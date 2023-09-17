//
//  HotViewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/09/2023.
//

import SwiftUI
import NostrEssentials
import Combine

typealias PostID = String
typealias LikedBy = Set
typealias Pubkey = String


// Popular/Hot feed
// Fetch all likes from your follows in the last 24/12/8/4/2 hours
// Sort posts by unique (pubkey) likes
class HotViewModel: ObservableObject {
    
    @Published var state:FeedState
    private var posts:[PostID: LikedBy<Pubkey>]
    private var backlog:Backlog
    private var follows:Set<Pubkey>
    private var didLoad = false
    private static let POSTS_LIMIT = 75
    private static let REQ_IDS_LIMIT = 500 // (strfry default)
    private var subscriptions = Set<AnyCancellable>()
    private var prefetchedIds = Set<String>()
    
    // From DB we always fetch the maximum time frame selected
    private var agoTimestamp:Int {
        return Int(Date.now.addingTimeInterval(-1 * Double(ago) * 3600).timeIntervalSince1970)
    }
    
    // From relays we fetch maximum at first, and then from since the last fetch, but not if its outside of time frame
    private var agoFetchTimestamp:Int {
        if let lastFetch, Int(lastFetch.timeIntervalSince1970) < agoTimestamp {
            return Int(lastFetch.timeIntervalSince1970)
        }
        return agoTimestamp
    }
    private var lastFetch:Date?
    
    @Published var hotPosts:[NRPost] = [] {
        didSet {
            guard !hotPosts.isEmpty else { return }
            L.og.info("Hot feed: loaded \(self.hotPosts.count) posts")
        }
    }
    
    @AppStorage("feed_hot_ago") var ago:Int = 12 {
        didSet {
            logAction("Hot feed time frame changed to \(self.ago)h")
            backlog.timeout = max(Double(ago / 4), 5.0)
            if ago < oldValue {
                self.state  = .loading
                self.fetchPostsFromDB()
            }
            else {
                self.state  = .loading
                lastFetch = nil // need to fetch further back, so remove lastFetch
                self.fetchLikesFromRelays()
            }
        }
    }
    
    var timeoutSeconds:Int { // 10 sec timeout for 1st 8hrs + 1 sec for every 4h after
        max(10, Int(ceil(Double(10 + ((ago-8)/4)))))
    }
    
    public func timeout() {
        self.state = .timeout
    }
    
    public init() {
        self.state = .initializing
        self.posts = [PostID: LikedBy<Pubkey>]()
        self.backlog = Backlog(timeout: 5.0, auto: true)
        self.follows = NosturState.shared.followingPublicKeys
        
        receiveNotification(.blockListUpdated)
            .sink { [weak self] notification in
                guard let self else { return }
                let blockedPubkeys = notification.object as! [String]
                self.hotPosts = self.hotPosts.filter { !blockedPubkeys.contains($0.pubkey)  }
            }
            .store(in: &self.subscriptions)
    }
    
    // STEP 1: FETCH LIKES FROM FOLLOWS FROM RELAYS
    private func fetchLikesFromRelays(_ onComplete: (() -> ())? = nil) {
        let reqTask = ReqTask(
            debounceTime: 0.5,
            subscriptionId: "HOT",
            reqCommand: { taskId in
                if let cm = NostrEssentials
                            .ClientMessage(type: .REQ,
                                           subscriptionId: taskId,
                                           filters: [
                                            Filters(
                                                authors: self.follows,
                                                kinds: Set([7]),
                                                since: self.agoFetchTimestamp,
                                                limit: 9999
                                            )
                                           ]
                            ).json() {
                    req(cm)
                    self.lastFetch = Date.now
                }
                else {
                    L.og.error("Hot feed: Problem generating request")
                }
            },
            processResponseCommand: { taskId, relayMessage in
                self.backlog.clear()
                self.fetchLikesFromDB(onComplete)

                L.og.info("Hot feed: ready to process relay response")
            },
            timeoutCommand: { taskId in
                self.backlog.clear()
                self.fetchLikesFromDB(onComplete)
                L.og.info("Hot feed: timeout ")
            })

        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    // STEP 2: FETCH RECEIVED LIKES FROM DB, SORT MOST LIKED POSTS (WE ONLY HAVE IDs HERE)
    private func fetchLikesFromDB(_ onComplete: (() -> ())? = nil) {
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "created_at > %i AND kind == 7 AND pubkey IN %@", agoTimestamp, follows)
        bg().perform {
            guard let likes = try? bg().fetch(fr) else { return }
            for like in likes {
                guard let reactionToId = like.reactionToId else { continue }
                if self.posts[reactionToId] != nil {
                    self.posts[reactionToId]!.insert(like.pubkey)
                }
                else {
                    self.posts[reactionToId] = LikedBy([like.pubkey])
                }
            }
            
            self.fetchPostsFromRelays()
        }
    }
    
    // STEP 3: FETCH MOST LIKED POSTS FROM RELAYS
    private func fetchPostsFromRelays(onComplete: (() -> ())? = nil) {
        
        // Skip ids we already have, so we can fit more into the default 500 limit
        let posts = self.posts
        bg().perform {
            let onlyNewIds = posts.keys
                .filter { postId in
                    Importer.shared.existingIds[postId] == nil
                }
            
            let sortedByLikes = posts
                .filter({ el in
                    onlyNewIds.contains(el.key)
                })
                .sorted(by: { $0.value.count > $1.value.count })
                .prefix(Self.REQ_IDS_LIMIT)
        
            let ids = Set(sortedByLikes.map { (postId, likedBy) in postId })

            guard !ids.isEmpty else {
                L.og.debug("Hot feed: fetchPostsFromRelays: empty ids")
                if (posts.count > 0) {
                    L.og.debug("Hot feed: but we can render the duplicates")
                    DispatchQueue.main.async {
                        self.fetchPostsFromDB(onComplete)
                        self.backlog.clear()
                    }
                }
                return
            }
            
            L.og.debug("Hot feed: fetching \(ids.count) posts, skipped \(posts.count - ids.count) duplicates")
            
            let reqTask = ReqTask(
                debounceTime: 0.5,
                subscriptionId: "HOT-POSTS",
                reqCommand: { taskId in
                    if let cm = NostrEssentials
                                .ClientMessage(type: .REQ,
                                               subscriptionId: taskId,
                                               filters: [
                                                Filters(
                                                    ids: ids,
                                                    limit: 9999
                                                )
                                               ]
                                ).json() {
                        req(cm)
    //                    self.lastFetch = Date.now
                    }
                    else {
                        L.og.error("Hot feed: Problem generating posts request")
                    }
                },
                processResponseCommand: { taskId, relayMessage in
                    self.fetchPostsFromDB(onComplete)
                    self.backlog.clear()
                    L.og.info("Hot feed: ready to process relay response")
                },
                timeoutCommand: { taskId in
                    self.fetchPostsFromDB(onComplete)
                    self.backlog.clear()
                    L.og.info("Hot feed: timeout ")
                })

            self.backlog.add(reqTask)
            reqTask.fetch()
           
        }
    }
    
    // STEP 4: FETCH RECEIVED POSTS FROM DB, SORT BY MOST LIKED AND PUT ON SCREEN
    private func fetchPostsFromDB(_ onComplete: (() -> ())? = nil) {
        let ids = Set(self.posts.keys)
        guard !ids.isEmpty else {
            L.og.debug("fetchPostsFromDB: empty ids")
            return
        }
        let blockedPubkeys = NosturState.shared.account?.blockedPubkeys_ ?? []
        bg().perform {
            let sortedByLikes = self.posts
                .sorted(by: { $0.value.count > $1.value.count })
                .prefix(Self.POSTS_LIMIT)
            
            var nrPosts:[NRPost] = []
            for (postId, likes) in sortedByLikes {
                if (likes.count > 3) {
                    L.og.debug("🔝🔝 id:\(postId): \(likes.count)")
                }
                if let event = try? Event.fetchEvent(id: postId, context: bg()) {
                    guard !blockedPubkeys.contains(event.pubkey) else { continue } // no blocked accoutns
                    guard event.replyToId == nil && event.replyToRootId == nil else { continue } // no replies
                    guard event.created_at > self.agoTimestamp else { continue } // post itself should be within timeframe also
                    
                    // withReplies for miniPFPs
                    nrPosts.append(NRPost(event: event, withParents: true, withReplies: true))
                }
            }
            
            DispatchQueue.main.async {
                onComplete?()
                self.hotPosts = nrPosts
                self.state = .ready
            }
            
            guard !nrPosts.isEmpty else { return }
            guard SettingsStore.shared.fetchCounts else { return }
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
        guard SettingsStore.shared.fetchCounts else { return }
        guard !self.prefetchedIds.contains(post.id) else { return }
        guard let index = self.hotPosts.firstIndex(of: post) else { return }
        guard index % 5 == 0 else { return }
        
        let nextIds = self.hotPosts.dropFirst(index - 1).prefix(5).map { $0.id }
        guard !nextIds.isEmpty else { return }
        L.fetching.info("🔢 Fetching counts for \(nextIds.count) posts")
        fetchStuffForLastAddedNotes(ids: nextIds)
        self.prefetchedIds = self.prefetchedIds.union(Set(nextIds))
    }
    
    public func load() {
        guard shouldReload else { return }
        self.state = .loading
        self.hotPosts = []
        self.fetchLikesFromRelays()
    }
    
    // for after acocunt change
    public func reload() {
        self.state = .loading
        self.lastFetch = nil
        self.posts = [PostID: LikedBy<Pubkey>]()
        self.backlog.clear()
        self.follows = NosturState.shared.followingPublicKeys
        self.hotPosts = []
        self.fetchLikesFromRelays()
    }
    
    // pull to refresh
    public func refresh() async {
        self.state = .loading
        self.lastFetch = nil
        self.posts = [PostID: LikedBy<Pubkey>]()
        self.backlog.clear()
        self.follows = NosturState.shared.followingPublicKeys
        
        await withCheckedContinuation { continuation in
            self.fetchLikesFromRelays {
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
    
    public enum FeedState {
        case initializing
        case loading
        case ready
        case timeout
    }
}
