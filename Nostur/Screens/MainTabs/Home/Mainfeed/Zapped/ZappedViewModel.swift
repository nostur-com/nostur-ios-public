//
//  ZappedViewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/03/2025.
//

import SwiftUI
import NostrEssentials
import Combine

typealias ZapStats = (Double, Int) // (Total value, Amount of zaps)


// Most zapped feed
// Fetch all zaps from your follows in the last 24/12/8/4/2 hours
// Sort posts by most value zapped
class ZappedViewModel: ObservableObject {
    private var speedTest: NXSpeedTest?
    @Published var state: FeedState
    private var posts: [PostID: ZapStats]
    private var backlog: Backlog
    private var follows: Set<Pubkey>
    private var didLoad = false
    private static let POSTS_LIMIT = 75
    private static let REQ_IDS_LIMIT = 500 // (strfry default)
    private static let ZAPPED_KINDS: Set<Int64> = Set([1,1222,20,9802,30032,34235])
    private var subscriptions = Set<AnyCancellable>()
    private var prefetchedIds = Set<String>()
    
    // From DB we always fetch the maximum time frame selected
    private var agoTimestamp: Int {
        return Int(Date.now.addingTimeInterval(Double(ago) * -3600).timeIntervalSince1970)
    }
    
    // From relays we fetch maximum at first, and then from since the last fetch, but not if its outside of time frame
    private var agoFetchTimestamp: Int {
        if let lastFetch, Int(lastFetch.timeIntervalSince1970) < agoTimestamp {
            return Int(lastFetch.timeIntervalSince1970)
        }
        return agoTimestamp
    }
    private var lastFetch: Date?
    
    @Published var zappedPosts: [NRPost] = [] {
        didSet {
            guard !zappedPosts.isEmpty else { return }
            L.og.info("Zapped feed: loaded \(self.zappedPosts.count) posts")
        }
    }
    
    @AppStorage("feed_zapped_ago") var ago: Int = 12 {
        didSet {
            logAction("Zapped feed time frame changed to \(self.ago)h")
            backlog.timeout = max(Double(ago / 4), 5.0)
            if ago < oldValue {
                self.state  = .loading
                self.follows = Nostur.follows()
                self.fetchPostsFromDB {
                    Task { @MainActor in
                        self.speedTest?.loadingBarViewState = .finalLoad
                        if self.zappedPosts.isEmpty == true {
#if DEBUG
                            L.og.debug("Zapped feed: timeout")
#endif
                            self.timeout()
                        }
                    }
                }
            }
            else {
                self.state  = .loading
                lastFetch = nil // need to fetch further back, so remove lastFetch
                self.follows = Nostur.follows()
                self.fetchZapsFromRelays {
                    Task { @MainActor in
                        self.speedTest?.loadingBarViewState = .finalLoad
                        if self.zappedPosts.isEmpty == true {
#if DEBUG
                            L.og.debug("Zapped feed: timeout")
#endif
                            self.timeout()
                        }
                    }
                }
            }
        }
    }
    
    var timeoutSeconds: Int { // 12 sec timeout for 1st 8hrs + 1 sec for every 4h after
        max(12, Int(ceil(Double(12 + ((ago-8)/4)))))
    }
    
    public func timeout() {
        speedTest?.loadingBarViewState = .timeout
        self.state = .timeout
    }
    
    public init() {
        self.state = .initializing
        self.posts = [PostID: ZapStats]()
        self.backlog = Backlog(timeout: 5.0, auto: true, backlogDebugName: "ZappedViewModel")
        self.follows = Nostur.follows()
        
        receiveNotification(.blockListUpdated)
            .sink { [weak self] notification in
                guard let self else { return }
                let blockedPubkeys = notification.object as! Set<String>
                self.zappedPosts = self.zappedPosts.filter { !blockedPubkeys.contains($0.pubkey)  }
            }
            .store(in: &self.subscriptions)
        
        receiveNotification(.muteListUpdated)
            .sink { [weak self] notification in
                guard let self else { return }
                let mutedRootIds = notification.object as! Set<String>
                self.zappedPosts = self.zappedPosts.filter { nrPost in
                    return !mutedRootIds.contains(nrPost.id) && !mutedRootIds.contains(nrPost.replyToRootId ?? "!") // id not blocked
                        && !(nrPost.isRepost && mutedRootIds.contains(nrPost.firstQuoteId ?? "!")) // is not: repost + muted reposted id
                }
            }
            .store(in: &self.subscriptions)
    }
    
    // STEP 1: FETCH ZAPS FROM FOLLOWS FROM RELAYS
    private func fetchZapsFromRelays(_ onComplete: (() -> ())? = nil) {
        Task { @MainActor [weak self] in
            
            self?.state = .fetchingFromFollows
            
            if !ConnectionPool.shared.anyConnected {
                self?.speedTest?.loadingBarViewState = .connecting
            }
            else {
                self?.speedTest?.loadingBarViewState = .fetching
            }
        }
        
        let reqTask = ReqTask(
            debounceTime: 0.5,
            subscriptionId: "ZAPPED",
            reqCommand: { [weak self] taskId in
                guard let self else { return }
                let follows = self.follows.count <= 1950 ? self.follows : Set(self.follows.shuffled().prefix(1950))
                if let cm = NostrEssentials
                            .ClientMessage(type: .REQ,
                                           subscriptionId: taskId,
                                           filters: [
                                            Filters(
                                                kinds: Set([9735]),
                                                tagFilter: TagFilter(tag: "P", values: follows),
                                                since: self.agoFetchTimestamp,
                                                limit: 9999
                                            )
                                           ]
                            ).json() {
                    req(cm)
                    self.lastFetch = Date.now
                }
                else {
#if DEBUG
                    L.og.error("Zapped feed: Problem generating request")
#endif
                }
            },
            processResponseCommand: { [weak self] taskId, relayMessage, _ in
                guard let self else { return }
                self.backlog.clear()
                self.fetchZapsFromDB(onComplete)
#if DEBUG
                L.og.debug("Zapped feed: ready to process relay response")
#endif
            },
            timeoutCommand: { [weak self] taskId in
                guard let self else { return }
                self.backlog.clear()
                self.fetchZapsFromDB(onComplete)
#if DEBUG
                L.og.debug("Zapped feed: timeout ")
#endif
            })

        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    // STEP 2: FETCH RECEIVED LIKES/REPOSTS FROM DB, SORT MOST LIKED/REPOSTED POSTS (WE ONLY HAVE IDs HERE)
    private func fetchZapsFromDB(_ onComplete: (() -> ())? = nil) {
        Task { @MainActor in
            speedTest?.loadingBarViewState = .earlyLoad
        }
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "created_at > %i AND kind = 9735 AND fromPubkey IN %@", agoTimestamp, follows)
        bg().perform { [weak self] in
            guard let self else { return }
            guard let zaps = try? bg().fetch(fr) else {
                onComplete?()
                return
            }
            for item in zaps {
                guard let zappedEventId = item.zappedEventId, !zappedEventId.contains(":") else {
                    // Skip param replaceable events
                    continue
                }
                if self.posts[zappedEventId] != nil {
                    self.posts[zappedEventId]! = (self.posts[zappedEventId]!.0 + item.naiveSats, self.posts[zappedEventId]!.1 + 1)
                }
                else {
                    self.posts[zappedEventId] = (item.naiveSats, 1)
                }
            }
            
            self.fetchPostsFromRelays(onComplete)
        }
    }
    
    // STEP 3: FETCH MOST LIKED/REPOSTED POSTS FROM RELAYS
    private func fetchPostsFromRelays(_ onComplete: (() -> ())? = nil) {
        Task { @MainActor in
            speedTest?.loadingBarViewState = .secondFetching
        }
        // Skip ids we already have, so we can fit more into the default 500 limit
        let posts = self.posts
        bg().perform { [weak self] in
            let onlyNewIds = posts.keys
                .filter { postId in
                    Importer.shared.existingIds[postId] == nil
                }
            
            let sortedByZappedValue = posts
                .filter({ el in
                    onlyNewIds.contains(el.key)
                })
                .sorted(by: { $0.value > $1.value })
                .prefix(Self.REQ_IDS_LIMIT)
        
            let ids = Set(sortedByZappedValue.map { (postId, totalZappedValue) in postId })

            guard !ids.isEmpty else {
                L.og.debug("Zapped feed: fetchPostsFromRelays: empty ids")
                if (posts.count > 0) {
                    L.og.debug("Zapped feed: but we can render the duplicates")
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
            
            L.og.debug("Zapped feed: fetching \(ids.count) posts, skipped \(posts.count - ids.count) duplicates")
            
            let reqTask = ReqTask(
                debounceTime: 0.5,
                subscriptionId: "ZAPPED-POSTS",
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
#if DEBUG
                        L.og.error("Zapped feed: Problem generating posts request")
#endif
                    }
                },
                processResponseCommand: { [weak self] taskId, relayMessage, _ in
                    self?.fetchPostsFromDB(onComplete)
                    self?.backlog.clear()
#if DEBUG
                    L.og.debug("Zapped feed: ready to process relay response")
#endif
                },
                timeoutCommand: { [weak self] taskId in
                    self?.fetchPostsFromDB(onComplete)
                    self?.backlog.clear()
#if DEBUG
                    L.og.debug("Zapped feed: timeout ")
#endif
                })

            self?.backlog.add(reqTask)
            reqTask.fetch()
           
        }
    }
    
    // STEP 4: FETCH RECEIVED POSTS FROM DB, SORT BY MOST LIKED/REPOSTED AND PUT ON SCREEN
    private func fetchPostsFromDB(_ onComplete: (() -> ())? = nil) {
        let ids = Set(self.posts.keys)
        guard !ids.isEmpty else {
#if DEBUG
            L.og.debug("fetchPostsFromDB: empty ids")
#endif
            onComplete?()
            return
        }
        let blockedPubkeys = blocks()
        bg().perform { [weak self] in
            guard let self else { return }
            let sortedByZappedValue = self.posts
                .sorted(by: { $0.value > $1.value })
                .prefix(Self.POSTS_LIMIT)
            
            var nrPosts: [NRPost] = []
            for (postId, zapStats) in sortedByZappedValue {
                if let event = Event.fetchEvent(id: postId, context: bg()) {
                    guard Self.ZAPPED_KINDS.contains(event.kind) else { continue } // not DMs or other weird stuff
                    guard !blockedPubkeys.contains(event.pubkey) else { continue } // no blocked accounts
                    guard event.replyToId == nil && event.replyToRootId == nil else { continue } // no replies
                    guard event.created_at > self.agoTimestamp else { continue } // post itself should be within timeframe also
                    
                    // fix tally
                    event.zapsCount = Int64(zapStats.1) < event.zapsCount ? Int64(zapStats.1) : event.zapsCount
                    event.zapTally = Int64(zapStats.0) < event.zapTally ? Int64(zapStats.0) : event.zapTally
                    
                    // withReplies for miniPFPs
                    nrPosts.append(NRPost(event: event, withParents: true, withReplies: true))
                }
            }
            
            DispatchQueue.main.async { [weak self] in
                onComplete?()
                self?.zappedPosts = nrPosts
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
        guard let index = self.zappedPosts.firstIndex(of: post) else { return }
        guard index % 5 == 0 else { return }
        
        let nextIds = self.zappedPosts.dropFirst(max(0,index - 1)).prefix(5).map { $0.id }
        guard !nextIds.isEmpty else { return }
#if DEBUG
        L.fetching.debug("🔢 Fetching counts for \(nextIds.count) posts")
#endif
        fetchStuffForLastAddedNotes(ids: nextIds)
        self.prefetchedIds = self.prefetchedIds.union(Set(nextIds))
    }
    
    public func load(speedTest: NXSpeedTest) {
        self.speedTest = speedTest
        guard shouldReload else { return }

#if DEBUG
        L.og.debug("Zapped feed: load()")
#endif
        self.follows = Nostur.follows()
        self.state = .loading
        self.zappedPosts = []
        self.speedTest?.start()
        self.fetchZapsFromRelays {
            Task { @MainActor in
                self.speedTest?.loadingBarViewState = .finalLoad
                if self.zappedPosts.isEmpty == true {
#if DEBUG
                    L.og.debug("Zapped feed: timeout")
#endif
                    self.timeout()
                }
            }
        }
    }
    
    // for after account change
    public func reload() {
        self.state = .loading
        self.lastFetch = nil
        self.posts = [PostID: ZapStats]()
        self.backlog.clear()
        self.follows = Nostur.follows()
        self.zappedPosts = []
        self.speedTest?.start()
        self.fetchZapsFromRelays {
            Task { @MainActor in
                self.speedTest?.loadingBarViewState = .finalLoad
                if self.zappedPosts.isEmpty == true {
#if DEBUG
                    L.og.debug("Zapped feed: timeout")
#endif
                    self.timeout()
                }
            }
        }
    }
    
    // pull to refresh
    public func refresh() async {
        self.lastFetch = nil
        self.posts = [PostID: ZapStats]()
        self.backlog.clear()
        self.follows = Nostur.follows()
        
        self.speedTest?.start()
        await withCheckedContinuation { continuation in
            self.fetchZapsFromRelays {
                Task { @MainActor in
                    self.speedTest?.loadingBarViewState = .finalLoad
                    if self.zappedPosts.isEmpty == true {
#if DEBUG
                        L.og.debug("Zapped feed: timeout")
#endif
                        self.timeout()
                    }
                }
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
    
    public enum FeedState {
        case initializing
        case loading
        case fetchingFromFollows
        case ready
        case timeout
    }
}
