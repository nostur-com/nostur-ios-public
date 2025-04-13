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

let PROFILE_KINDS = Set([1,5,6,20,9802,34235])
let ARTICLE_KINDS = Set([30023])

// For profile view, try to load first 10 posts as fast as possible
// Then reload remaining later
class ProfilePostsViewModel: ObservableObject {
    
    enum ProfilePostsType {
        case posts
        case replies
        case articles
    }
    
    @Published var state: State
    private var backlog: Backlog
    public var type: ProfilePostsType
    private var pubkey: String
    private var didLoad = false
//    private static let POSTS_LIMIT = 300
    private var subscriptions = Set<AnyCancellable>()
    private var prefetchedIds = Set<String>()
        
    @Published var posts: [NRPost] = [] {
        didSet {
            guard !posts.isEmpty else { return }
            if state != .ready {
                self.state = .ready
            }
#if DEBUG
            L.og.debug("Profile posts feed loaded \(self.posts.count) items, pubkey: \(self.pubkey)")
#endif
        }
    }
    
    private var lastFetch: Date?
    
    public func timeout() {
        self.state = .timeout
    }
    
    public init(_ pubkey: String, type: ProfilePostsType) {
        self.type = type
        self.pubkey = pubkey
        self.state = .initializing
        self.backlog = Backlog(timeout: 8.0, auto: true)
        
        guard self.type != .articles else { return }
        
        receiveNotification(.newPostSaved)
            .sink { [weak self] notification in
                bg().perform {
                    let event = notification.object as! Event
                    guard event.pubkey == pubkey else { return }
                    guard (event.replyToId != nil && self?.type == .replies) || (event.replyToId == nil && self?.type == .posts) else { return }
                    
                    EventRelationsQueue.shared.addAwaitingEvent(event, debugInfo: "ProfilePostsViewModel.newPostSaved")
                    let nrPost = NRPost(event: event, cancellationId: event.cancellationId) // TODO: TEST UNDO SEND
                    DispatchQueue.main.async {
                        withAnimation {
                            self?.posts.insert(nrPost, at: 0)
                        }
                }
            }
        }
        .store(in: &subscriptions)
        
        receiveNotification(.unpublishedNRPost).sink { [weak self] notification in
            let nrPost = notification.object as! NRPost
            
            // Remove from view
            DispatchQueue.main.async {
                withAnimation {
                    self?.posts.removeAll(where: { $0.id == nrPost.id })
                }
            }
        }
        .store(in: &subscriptions)
        
    }
    
    // STEP 1: FETCH POSTS FROM RELAYS
    private func fetchPostsFromRelays(_ onComplete: (() -> ())? = nil) {
        let reqTask = ReqTask(
            debounceTime: 0.1,
            subscriptionId: String("PROFILEPOSTS" + UUID().uuidString.suffix(11)),
            reqCommand: { [weak self] taskId in
                guard let self else { return }
                outboxReq(NostrEssentials
                    .ClientMessage(type: .REQ,
                                   subscriptionId: taskId,
                                   filters: [
                                    Filters(
                                        authors: Set([self.pubkey]),
                                        kinds: self.type == .articles ? ARTICLE_KINDS : PROFILE_KINDS,
                                        limit: 25
                                    )
                                   ]
                    ))
                self.lastFetch = Date.now
            },
            processResponseCommand: { [weak self] taskId, relayMessage, _ in
                guard let self else { return }
                self.backlog.clear()
                self.fetchPostsFromDB(onComplete)

#if DEBUG
                L.og.debug("Profile posts feed: ready to process relay response \(taskId), pubkey: \(self.pubkey)")
#endif
            },
            timeoutCommand: { [weak self] taskId in
                guard let self else { return }
                self.backlog.clear()
                self.fetchPostsFromDB(onComplete)
#if DEBUG
                L.og.debug("Profile posts feed: timeout \(taskId), pubkey: \(self.pubkey)")
#endif
            })

        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    // STEP 2: FETCH RECEIVED POSTS FROM DB
    private func fetchPostsFromDB(_ onComplete: (() -> ())? = nil) {
        
        let cancellationIds: [String:UUID] = Dictionary(uniqueKeysWithValues: Unpublisher.shared.queue.map { ($0.nEvent.id, $0.cancellationId) })
        
        bg().perform { [weak self] in
            guard let self else { return }
            let fr = Event.fetchRequest()
            if self.type == .articles {
                fr.predicate = NSPredicate(format: "pubkey == %@ AND kind IN %@ AND flags != \"is_update\" AND replyToId == nil AND replyToRootId == nil", self.pubkey, ARTICLE_KINDS)
            }
            else if self.type == .posts {
                fr.predicate = NSPredicate(format: "pubkey == %@ AND kind IN %@ AND replyToId == nil AND replyToRootId == nil", self.pubkey, PROFILE_KINDS.subtracting([5]))
            }
            else {
                fr.predicate = NSPredicate(format: "pubkey == %@ AND kind IN %@ AND (replyToId != nil OR replyToRootId != nil)", self.pubkey, PROFILE_KINDS.subtracting([5]))
            }
            fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            fr.fetchOffset = 0
            fr.fetchLimit = 10
            
            var posts: [NRPost] = []
            guard let events = try? bg().fetch(fr) else { return }

            for event in events {
                posts.append(NRPost(event: event, cancellationId: cancellationIds[event.id] ?? event.cancellationId))
            }
            
            DispatchQueue.main.async { [weak self] in
                onComplete?()
                withAnimation {
                    self?.posts = posts
                    self?.state = .ready
                }
            }
            
            guard !posts.isEmpty else { return }
            guard SettingsStore.shared.fetchCounts && SettingsStore.shared.rowFooterEnabled else { return }
            for post in posts.prefix(5) {
                EventRelationsQueue.shared.addAwaitingEvent(post.event)
            }
            let eventIds = posts.prefix(5).map { $0.id }
#if DEBUG
            L.fetching.debug("🔢 Fetching counts for \(eventIds.count) posts, pubkey: \(self.pubkey)")
#endif
            fetchStuffForLastAddedNotes(ids: eventIds)
            self.prefetchedIds = self.prefetchedIds.union(Set(eventIds))
        }
    }
    
    // Fetch post stats (if enabled)
    // And: after user scrolls we prefetch the next 50 posts
    // We detect this by using .onBecomingVisible on the 6th post
    public func prefetch(_ post: NRPost) {
        guard let index = self.posts.firstIndex(of: post) else { return }
        
        if index == 5 {
            self.prefetchOnSixthPost()
        }
        
        self.fetchPostStats(index, postId:post.id)
    }
    
    private func prefetchOnSixthPost() {
        guard let oldestPostDate = self.posts.last?.createdAt else { return }
        outboxReq(NostrEssentials
                    .ClientMessage(type: .REQ,
                                   filters: [
                                    Filters(
                                        authors: Set([self.pubkey]),
                                        kinds: self.type == .articles ? ARTICLE_KINDS : PROFILE_KINDS,
                                        until: Int(oldestPostDate.timeIntervalSince1970),
                                        limit: 50
                                    )
                                   ]
        ))
    }
    
    private func fetchPostStats(_ index:Int, postId:String) {
        guard SettingsStore.shared.fetchCounts && SettingsStore.shared.rowFooterEnabled else { return }
        guard !self.prefetchedIds.contains(postId) else { return }
        
        guard index % 5 == 0 else { return }
        
        let nextIds = self.posts.dropFirst(max(0,index - 1)).prefix(5).map { $0.id }
        guard !nextIds.isEmpty else { return }
#if DEBUG
        L.fetching.debug("🔢 Fetching counts for \(nextIds.count) posts, pubkey: \(self.pubkey)")
#endif
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

        if (Date.now.timeIntervalSince1970 - lastFetch.timeIntervalSince1970) > 600 {
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
        
        bg().perform { [weak self] in
            guard let self else { return }
            let fr = Event.fetchRequest()
            if self.type == .articles {
                fr.predicate = NSPredicate(format: "pubkey == %@ AND kind IN %@ AND flags != \"is_update\" AND replyToRootId == nil AND replyToId == nil AND created_at <= %i", self.pubkey, ARTICLE_KINDS, Int(firstPostCreatedAt))
            }
            else if self.type == .posts {
                fr.predicate = NSPredicate(format: "pubkey == %@ AND kind IN %@ AND replyToRootId == nil AND replyToId == nil AND created_at <= %i", self.pubkey, PROFILE_KINDS.subtracting([5]), Int(firstPostCreatedAt))
            }
            else {
                fr.predicate = NSPredicate(format: "pubkey == %@ AND kind IN %@ AND (replyToRootId != nil OR replyToId != nil) AND created_at <= %i", self.pubkey, PROFILE_KINDS.subtracting([5]), Int(firstPostCreatedAt))
            }
            fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            fr.fetchOffset = offset
            fr.fetchLimit = amount
            
            var posts: [NRPost] = []
            guard let events = try? bg().fetch(fr) else { return }

            for event in events {
                guard !currentVisibleIds.contains(event.id) else { continue }
                posts.append(NRPost(event: event, cancellationId: cancellationIds[event.id] ?? event.cancellationId))
            }
            
            guard !posts.isEmpty else { return }
            
            DispatchQueue.main.async { [weak self] in
                withAnimation {
                    self?.posts.append(contentsOf: posts)
                }
            }
            
            guard SettingsStore.shared.fetchCounts && SettingsStore.shared.rowFooterEnabled else { return }
            for post in posts.prefix(5) {
                EventRelationsQueue.shared.addAwaitingEvent(post.event)
            }
            let eventIds = posts.prefix(5).map { $0.id }
#if DEBUG
            L.fetching.debug("🔢 Fetching counts for \(eventIds.count) posts, pubkey: \(self.pubkey)")
#endif
            fetchStuffForLastAddedNotes(ids: eventIds)
            self.prefetchedIds = self.prefetchedIds.union(Set(eventIds))
        }
    }
    
    public func fetchMore(after: NRPost, amount: Int) {
        outboxReq(NostrEssentials
                    .ClientMessage(type: .REQ,
                                   filters: [
                                    Filters(
                                        authors: Set([self.pubkey]),
                                        kinds: self.type == .articles ? ARTICLE_KINDS : PROFILE_KINDS,
                                        until: Int(after.created_at),
                                        limit: amount
                                    )
                                   ]
                    ))
    }
    
    public enum State {
        case initializing
        case loading
        case ready
        case timeout
    }
}
