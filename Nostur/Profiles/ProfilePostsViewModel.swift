//
//  ProfilePostsViewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/09/2023.
//

import SwiftUI
import NostrEssentials
import CoreData
import Combine

// For profile view, try to load first 10 posts as fast as possible
// Then reload remaining later
class ProfilePostsViewModel: ObservableObject {
    
    static let PROFILE_KINDS = Set([1,6,9802,30023])
    
    @Published var state:State
    private var backlog:Backlog
    private var pubkey:String
    private var didLoad = false
//    private static let POSTS_LIMIT = 300
    private var subscriptions = Set<AnyCancellable>()
    private var prefetchedIds = Set<String>()
        
    @Published var posts:[NRPost] = [] {
        didSet {
            guard !posts.isEmpty else { return }
            L.og.info("Profile posts feed loaded \(self.posts.count) items")
        }
    }
    
    private var lastFetch:Date?
    
    public func timeout() {
        self.state = .timeout
    }
    
    public init(_ pubkey:String) {
        self.pubkey = pubkey
        self.state = .initializing
        self.backlog = Backlog(timeout: 8.0, auto: true)
        
        receiveNotification(.newPostSaved)
            .sink { notification in
                bg().perform {
                    let event = notification.object as! Event
                    guard event.pubkey == pubkey else { return }
                    EventRelationsQueue.shared.addAwaitingEvent(event, debugInfo: "ProfilePostsViewModel.newPostSaved")
                    let nrPost = NRPost(event: event, cancellationId: event.cancellationId) // TODO: TEST UNDO SEND
                    DispatchQueue.main.async {
                        self.posts.insert(nrPost, at: 0)
                }
            }
        }
        .store(in: &subscriptions)
        
        receiveNotification(.unpublishedNRPost).sink { notification in
            let nrPost = notification.object as! NRPost
            
            // Remove from view
            DispatchQueue.main.async {
                self.posts.removeAll(where: { $0.id == nrPost.id })
            }
            
//            // Remove from database
//            bg().perform {
//                bg().delete(nrPost.event)
//                DataProvider.shared().bgSave()
//            }
        }
        .store(in: &subscriptions)
        
    }
    
    // STEP 1: FETCH POSTS FROM RELAYS
    private func fetchPostsFromRelays(_ onComplete: (() -> ())? = nil) {
        let reqTask = ReqTask(
            debounceTime: 0.1,
            subscriptionId: "PROFILEPOSTS",
            reqCommand: { taskId in
                if let cm = NostrEssentials
                            .ClientMessage(type: .REQ,
                                           subscriptionId: taskId,
                                           filters: [
                                            Filters(
                                                authors: Set([self.pubkey]),
                                                kinds: Self.PROFILE_KINDS,
                                                limit: 10
                                            )
                                           ]
                            ).json() {
                    req(cm)
                    self.lastFetch = Date.now
                }
                else {
                    L.og.error("Profile posts feed: Problem generating request")
                }
            },
            processResponseCommand: { taskId, relayMessage, _ in
                self.backlog.clear()
                self.fetchPostsFromDB(onComplete)

                L.og.info("Profile posts feed: ready to process relay response")
            },
            timeoutCommand: { taskId in
                self.backlog.clear()
                self.fetchPostsFromDB(onComplete)
                L.og.info("Profile posts feed: timeout ")
            })

        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    // STEP 2: FETCH RECEIVED POSTS FROM DB
    private func fetchPostsFromDB(_ onComplete: (() -> ())? = nil) {
        
        let cancellationIds:[String:UUID] = Dictionary(uniqueKeysWithValues: Unpublisher.shared.queue.map { ($0.nEvent.id, $0.cancellationId) })
        
        bg().perform {
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "pubkey == %@ AND kind IN %@", self.pubkey, Self.PROFILE_KINDS)
            fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            fr.fetchOffset = 0
            fr.fetchLimit = 10
            
            var posts:[NRPost] = []
            guard let events = try? bg().fetch(fr) else { return }

            for event in events {
                posts.append(NRPost(event: event, cancellationId: cancellationIds[event.id] ?? event.cancellationId))
            }
            
            DispatchQueue.main.async {
                onComplete?()
                self.posts = posts
                self.state = .ready
            }
            
            guard !posts.isEmpty else { return }
            guard SettingsStore.shared.fetchCounts else { return }
            for post in posts.prefix(5) {
                EventRelationsQueue.shared.addAwaitingEvent(post.event)
            }
            let eventIds = posts.prefix(5).map { $0.id }
            L.fetching.info("🔢 Fetching counts for \(eventIds.count) posts")
            fetchStuffForLastAddedNotes(ids: eventIds)
            self.prefetchedIds = self.prefetchedIds.union(Set(eventIds))
        }
    }
    
    // Fetch post stats (if enabled)
    // And: after user scrolls we prefetch the next 50 posts
    // We detect this by using .onBecomingVisible on the 6th post
    public func prefetch(_ post:NRPost) {
        guard let index = self.posts.firstIndex(of: post) else { return }
        
        if index == 5 {
            self.prefetchOnSixthPost()
        }
        
        self.fetchPostStats(index, postId:post.id)
    }
    
    private func prefetchOnSixthPost() {
        guard let oldestPostDate = self.posts.last?.createdAt else { return }
        if let cm = NostrEssentials
                    .ClientMessage(type: .REQ,
                                   filters: [
                                    Filters(
                                        authors: Set([self.pubkey]),
                                        kinds: Self.PROFILE_KINDS,
                                        until: Int(oldestPostDate.timeIntervalSince1970),
                                        limit: 50
                                    )
                                   ]
                    ).json() {
            req(cm)
        }
        else {
            L.og.error("Profile posts feed: Problem generating request")
        }
    }
    
    private func fetchPostStats(_ index:Int, postId:String) {
        guard SettingsStore.shared.fetchCounts else { return }
        guard !self.prefetchedIds.contains(postId) else { return }
        
        guard index % 5 == 0 else { return }
        
        let nextIds = self.posts.dropFirst(max(0,index - 1)).prefix(5).map { $0.id }
        guard !nextIds.isEmpty else { return }
        L.fetching.info("🔢 Fetching counts for \(nextIds.count) posts")
        fetchStuffForLastAddedNotes(ids: nextIds)
        self.prefetchedIds = self.prefetchedIds.union(Set(nextIds))
    }
    
    public func load() {
        guard shouldReload else { return }
        self.state = .loading
        self.posts = []
        self.fetchPostsFromRelays()
    }
    
    // for after acocunt change
    public func reload() {
        self.state = .loading
        self.backlog.clear()
        self.posts = []
        self.fetchPostsFromRelays()
    }
    
    // pull to refresh
    public func refresh() async {
        self.state = .loading
        self.backlog.clear()
        await withCheckedContinuation { continuation in
            self.fetchPostsFromRelays {
                continuation.resume()
            }
        }
    }
    
    public var shouldReload: Bool {
        // Should only refetch since last fetch, if last fetch is more than 10 mins ago
        guard let lastFetch else { return true }

        if (Date.now.timeIntervalSince1970 - lastFetch.timeIntervalSince1970) > 60 * 10 {
            return true
        }
        return false
    }
    
    public func loadMore(after: NRPost, amount: Int) {
        let cancellationIds:[String:UUID] = Dictionary(uniqueKeysWithValues: Unpublisher.shared.queue.map { ($0.nEvent.id, $0.cancellationId) })
        
        let offset = self.posts.count
        let currentVisibleIds = Set(self.posts.map { $0.id })
        
        // Always use offset from this post, else pagination will be messed up if a new post comes in
        guard let firstPostCreatedAt = self.posts.first?.created_at else { return }
        
        bg().perform {
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "pubkey == %@ AND kind IN %@ AND created_at <= %i", self.pubkey, Self.PROFILE_KINDS, Int(firstPostCreatedAt))
            fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            fr.fetchOffset = offset
            fr.fetchLimit = amount
            
            var posts:[NRPost] = []
            guard let events = try? bg().fetch(fr) else { return }

            for event in events {
                guard !currentVisibleIds.contains(event.id) else { continue }
                posts.append(NRPost(event: event, cancellationId: cancellationIds[event.id] ?? event.cancellationId))
            }
            
            guard !posts.isEmpty else { return }
            
            DispatchQueue.main.async {
                self.posts.append(contentsOf: posts)
            }
            
            guard SettingsStore.shared.fetchCounts else { return }
            for post in posts.prefix(5) {
                EventRelationsQueue.shared.addAwaitingEvent(post.event)
            }
            let eventIds = posts.prefix(5).map { $0.id }
            L.fetching.info("🔢 Fetching counts for \(eventIds.count) posts")
            fetchStuffForLastAddedNotes(ids: eventIds)
            self.prefetchedIds = self.prefetchedIds.union(Set(eventIds))
        }
    }
    
    public func fetchMore(after: NRPost, amount: Int) {
        if let cm = NostrEssentials
                    .ClientMessage(type: .REQ,
                                   filters: [
                                    Filters(
                                        authors: Set([self.pubkey]),
                                        kinds: Self.PROFILE_KINDS,
                                        until: Int(after.created_at),
                                        limit: amount
                                    )
                                   ]
                    ).json() {
            req(cm)
        }
        else {
            L.og.error("Profile posts feed: Problem generating .fetchMore request")
        }
    }
    
    public enum State {
        case initializing
        case loading
        case ready
        case timeout
    }
}
