//
//  NewPostsVM.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/12/2023.
//

import SwiftUI
import NostrEssentials
import Combine

class NewPostsVM: ObservableObject {
    
    @Published var state: FeedState
    @Published var posts: [NRPost] = []
    
    private var backlog: Backlog
    private var pubkeys: Set<Pubkey>
    private var since: Int64
    private var didLoad = false
    private static let POSTS_LIMIT = 75
    private var prefetchedIds = Set<String>()
    
    
    
    public func timeout() {
        self.state = .timeout
        didLoad = false
    }
    
    public init(pubkeys: Set<String>? = nil, since:Int64 = 0) {
        self.state = .initializing
        self.since = since > 0 ? since : Int64(Date.now.timeIntervalSince1970 - (24 * 3600 * 14)) // 2 weeks ago should be enough
        self.backlog = Backlog(timeout: 1.5, auto: true)
        self.pubkeys = pubkeys ?? NewPostNotifier.shared.enabledPubkeys
    }
    
    private func fetchPostsFromRelays(_ onComplete: (() -> ())? = nil) {
        bg().perform { [weak self] in
            let reqTask = ReqTask(
                debounceTime: 0.1,
                subscriptionId: "NEWPOSTS",
                reqCommand: { taskId in
                    guard let self else { return }
                    if let cm = NostrEssentials
                        .ClientMessage(type: .REQ,
                                       subscriptionId: taskId,
                                       filters: [
                                        Filters(
                                            authors: self.pubkeys,
                                            kinds: PROFILE_KINDS.subtracting(Set([6])), // not reposts
                                            since: self.since != 0 ? Int(self.since) : nil,
                                            limit: 150
                                        )
                                       ]
                        ).json() {
                        req(cm)
                    }
                    else {
                        L.og.info("New Posts feed: unable to create REQ")
                    }
                },
                processResponseCommand: { taskId, relayMessage, _ in
                    guard let self else { return }
                    self.fetchPostsFromDB(onComplete)
                    self.backlog.clear()
                    L.og.info("New Posts feed: ready to process relay response")
                },
                timeoutCommand: { taskId in
                    guard let self else { return }
                    self.fetchPostsFromDB(onComplete)
                    self.backlog.clear()
                    L.og.info("New Posts feed: timeout ")
                })
            
            self?.backlog.add(reqTask)
            guard self != nil else { return }
            reqTask.fetch()
            
        }
    }
    
    private func fetchPostsFromDB(_ onComplete: (() -> ())? = nil) {
        bg().perform { [weak self] in
            guard let self else { return }
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "created_at >= %i AND pubkey IN %@ AND kind IN %@ AND flags != \"is_update\"", self.since, self.pubkeys, PROFILE_KINDS.subtracting(Set([6]))) // not reposts
            fr.fetchLimit = 75
            fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
            guard let events = try? bg().fetch(fr) else { return }
            
            let nrPosts = events
                .map { NRPost(event: $0, withReplyTo: true, withParents: false, withReplies: true) }
            
            DispatchQueue.main.async { [weak self] in
                onComplete?()
                self?.posts = nrPosts
                self?.state = .ready
                self?.didLoad = true
            }
            
            guard !nrPosts.isEmpty else { return }
            
            guard SettingsStore.shared.fetchCounts && SettingsStore.shared.rowFooterEnabled else { return }
            for nrPost in nrPosts.prefix(5) {
                EventRelationsQueue.shared.addAwaitingEvent(nrPost.event)
            }
            let eventIds = nrPosts.prefix(5).map { $0.id }
            L.fetching.info("🔢 Fetching counts for \(eventIds.count) posts")
            fetchStuffForLastAddedNotes(ids: eventIds)
            self.prefetchedIds = self.prefetchedIds.union(Set(eventIds))
        }
    }
    
    public func prefetch(_ post:NRPost) {
        guard SettingsStore.shared.fetchCounts && SettingsStore.shared.rowFooterEnabled else { return }
        guard !self.prefetchedIds.contains(post.id) else { return }
        guard let index = self.posts.firstIndex(of: post) else { return }
        guard index % 5 == 0 else { return }
        
        let nextIds = self.posts.dropFirst(max(0,index - 1)).prefix(5).map { $0.id }
        guard !nextIds.isEmpty else { return }
        L.fetching.info("🔢 Fetching counts for \(nextIds.count) posts")
        fetchStuffForLastAddedNotes(ids: nextIds)
        self.prefetchedIds = self.prefetchedIds.union(Set(nextIds))
    }
    
    public func load() {
        guard !didLoad else { return }
        self.state = .loading
        self.posts = []
//        self.fetchPostsFromRelays()
        self.fetchPostsFromDB()
    }
    
    public enum FeedState {
        case initializing
        case loading
        case ready
        case timeout
    }
}
