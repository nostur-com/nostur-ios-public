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
typealias RecommendedBy = Set
typealias Pubkey = String


// Popular/Hot feed
// Fetch all likes and reposts from your follows in the last 24/12/8/4/2 hours
// Sort posts by unique (pubkey) likes/reposts
class HotViewModel: ObservableObject {
    
    @Published var state: FeedState
    private var posts: [PostID: RecommendedBy<Pubkey>]
    private var backlog: Backlog
    private var follows: Set<Pubkey>
    private var didLoad = false
    private static let POSTS_LIMIT = 75
    private static let REQ_IDS_LIMIT = 500 // (strfry default)
    private static let HOT_KINDS: Set<Int64> = Set([1,20,9802,30032,34235])
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
                self.follows = Nostur.follows()
                self.fetchPostsFromDB()
            }
            else {
                self.state  = .loading
                lastFetch = nil // need to fetch further back, so remove lastFetch
                self.follows = Nostur.follows()
                self.fetchLikesAndRepostsFromRelays()
            }
        }
    }
    
    var timeoutSeconds:Int { // 12 sec timeout for 1st 8hrs + 1 sec for every 4h after
        max(12, Int(ceil(Double(12 + ((ago-8)/4)))))
    }
    
    public func timeout() {
        self.state = .timeout
    }
    
    public init() {
        self.state = .initializing
        self.posts = [PostID: RecommendedBy<Pubkey>]()
        self.backlog = Backlog(timeout: 5.0, auto: true)
        self.follows = Nostur.follows()
        
        receiveNotification(.blockListUpdated)
            .sink { [weak self] notification in
                guard let self else { return }
                let blockedPubkeys = notification.object as! Set<String>
                self.hotPosts = self.hotPosts.filter { !blockedPubkeys.contains($0.pubkey)  }
            }
            .store(in: &self.subscriptions)
        
        receiveNotification(.muteListUpdated)
            .sink { [weak self] notification in
                guard let self else { return }
                let mutedRootIds = notification.object as! Set<String>
                self.hotPosts = self.hotPosts.filter { nrPost in
                    return !mutedRootIds.contains(nrPost.id) && !mutedRootIds.contains(nrPost.replyToRootId ?? "!") // id not blocked
                        && !(nrPost.isRepost && mutedRootIds.contains(nrPost.firstQuoteId ?? "!")) // is not: repost + muted reposted id
                }
            }
            .store(in: &self.subscriptions)
    }
    
    // STEP 1: FETCH LIKES AND REPOSTS FROM FOLLOWS FROM RELAYS
    private func fetchLikesAndRepostsFromRelays(_ onComplete: (() -> ())? = nil) {
        let reqTask = ReqTask(
            debounceTime: 0.5,
            subscriptionId: "HOT",
            reqCommand: { [weak self] taskId in
                guard let self else { return }
                if let cm = NostrEssentials
                            .ClientMessage(type: .REQ,
                                           subscriptionId: taskId,
                                           filters: [
                                            Filters(
                                                authors: self.follows,
                                                kinds: Set([6,7]),
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
            processResponseCommand: { [weak self] taskId, relayMessage, _ in
                guard let self else { return }
                self.backlog.clear()
                self.fetchLikesAndRepostsFromDB(onComplete)

                L.og.info("Hot feed: ready to process relay response")
            },
            timeoutCommand: { [weak self] taskId in
                guard let self else { return }
                self.backlog.clear()
                self.fetchLikesAndRepostsFromDB(onComplete)
                L.og.info("Hot feed: timeout ")
            })

        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    // STEP 2: FETCH RECEIVED LIKES/REPOSTS FROM DB, SORT MOST LIKED/REPOSTED POSTS (WE ONLY HAVE IDs HERE)
    private func fetchLikesAndRepostsFromDB(_ onComplete: (() -> ())? = nil) {
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "created_at > %i AND kind IN {6,7} AND pubkey IN %@", agoTimestamp, follows)
        bg().perform { [weak self] in
            guard let self else { return }
            guard let likesOrReposts = try? bg().fetch(fr) else { return }
            for item in likesOrReposts {
                switch item.kind {
                case 6:
                    guard let firstQuoteId = item.firstQuoteId else { continue }
                    if self.posts[firstQuoteId] != nil {
                        self.posts[firstQuoteId]!.insert(item.pubkey)
                    }
                    else {
                        self.posts[firstQuoteId] = RecommendedBy([item.pubkey])
                    }
                case 7:
                    guard let reactionToId = item.reactionToId else { continue }
                    if self.posts[reactionToId] != nil {
                        self.posts[reactionToId]!.insert(item.pubkey)
                    }
                    else {
                        self.posts[reactionToId] = RecommendedBy([item.pubkey])
                    }
                default:
                    continue
                }
                
            }
            
            self.fetchPostsFromRelays(onComplete)
        }
    }
    
    // STEP 3: FETCH MOST LIKED/REPOSTED POSTS FROM RELAYS
    private func fetchPostsFromRelays(_ onComplete: (() -> ())? = nil) {
        
        // Skip ids we already have, so we can fit more into the default 500 limit
        let posts = self.posts
        bg().perform { [weak self] in
            let onlyNewIds = posts.keys
                .filter { postId in
                    Importer.shared.existingIds[postId] == nil
                }
            
            let sortedByLikesAndReposts = posts
                .filter({ el in
                    onlyNewIds.contains(el.key)
                })
                .sorted(by: { $0.value.count > $1.value.count })
                .prefix(Self.REQ_IDS_LIMIT)
        
            let ids = Set(sortedByLikesAndReposts.map { (postId, likedOrRepostedBy) in postId })

            guard !ids.isEmpty else {
                L.og.debug("Hot feed: fetchPostsFromRelays: empty ids")
                if (posts.count > 0) {
                    L.og.debug("Hot feed: but we can render the duplicates")
                    DispatchQueue.main.async { [weak self] in
                        self?.fetchPostsFromDB(onComplete)
                        self?.backlog.clear()
                    }
                }
                else {
                    onComplete?()
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
                    }
                    else {
                        L.og.error("Hot feed: Problem generating posts request")
                    }
                },
                processResponseCommand: { [weak self] taskId, relayMessage, _ in
                    self?.fetchPostsFromDB(onComplete)
                    self?.backlog.clear()
                    L.og.info("Hot feed: ready to process relay response")
                },
                timeoutCommand: { [weak self] taskId in
                    self?.fetchPostsFromDB(onComplete)
                    self?.backlog.clear()
                    L.og.info("Hot feed: timeout ")
                })

            self?.backlog.add(reqTask)
            reqTask.fetch()
           
        }
    }
    
    // STEP 4: FETCH RECEIVED POSTS FROM DB, SORT BY MOST LIKED/REPOSTED AND PUT ON SCREEN
    private func fetchPostsFromDB(_ onComplete: (() -> ())? = nil) {
        let ids = Set(self.posts.keys)
        guard !ids.isEmpty else {
            L.og.debug("fetchPostsFromDB: empty ids")
            onComplete?()
            return
        }
        let blockedPubkeys = blocks()
        bg().perform { [weak self] in
            guard let self else { return }
            let sortedByLikesAndReposts = self.posts
                .sorted(by: { $0.value.count > $1.value.count })
                .prefix(Self.POSTS_LIMIT)
            
            var nrPosts:[NRPost] = []
            for (postId, likesAndReposts) in sortedByLikesAndReposts {
                #if DEBUG
                if (likesAndReposts.count > 3) {
                    L.og.debug("🔝🔝 id:\(postId): \(likesAndReposts.count) -[LOG]-")
                }
                #endif
                if let event = Event.fetchEvent(id: postId, context: bg()) {
                    guard Self.HOT_KINDS.contains(event.kind) else { continue } // not DMs or other weird stuff
                    guard !blockedPubkeys.contains(event.pubkey) else { continue } // no blocked accounts
                    guard event.replyToId == nil && event.replyToRootId == nil else { continue } // no replies
                    guard event.created_at > self.agoTimestamp else { continue } // post itself should be within timeframe also
                    
                    // withReplies for miniPFPs
                    nrPosts.append(NRPost(event: event, withParents: true, withReplies: true))
                }
            }
            
            DispatchQueue.main.async { [weak self] in
                onComplete?()
                self?.hotPosts = nrPosts
                self?.state = .ready
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
        guard let index = self.hotPosts.firstIndex(of: post) else { return }
        guard index % 5 == 0 else { return }
        
        let nextIds = self.hotPosts.dropFirst(max(0,index - 1)).prefix(5).map { $0.id }
        guard !nextIds.isEmpty else { return }
        L.fetching.info("🔢 Fetching counts for \(nextIds.count) posts")
        fetchStuffForLastAddedNotes(ids: nextIds)
        self.prefetchedIds = self.prefetchedIds.union(Set(nextIds))
    }
    
    public func load() {
        guard shouldReload else { return }
        L.og.info("Hot feed: load()")
        self.follows = Nostur.follows()
        self.state = .loading
        self.hotPosts = []
        self.fetchLikesAndRepostsFromRelays()
    }
    
    // for after account change
    public func reload() {
        self.state = .loading
        self.lastFetch = nil
        self.posts = [PostID: RecommendedBy<Pubkey>]()
        self.backlog.clear()
        self.follows = Nostur.follows()
        self.hotPosts = []
        self.fetchLikesAndRepostsFromRelays()
    }
    
    // pull to refresh
    public func refresh() async {
        self.lastFetch = nil
        self.posts = [PostID: RecommendedBy<Pubkey>]()
        self.backlog.clear()
        self.follows = Nostur.follows()
        
        await withCheckedContinuation { continuation in
            self.fetchLikesAndRepostsFromRelays {
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
