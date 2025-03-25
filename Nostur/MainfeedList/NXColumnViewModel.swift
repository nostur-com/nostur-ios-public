//
//  ColumnViewModel.swift
//  Nosturix
//
//  Created by Fabian Lachman on 01/08/2024.
//

import SwiftUI
import Combine
import NostrEssentials

class NXColumnViewModel: ObservableObject {

#if DEBUG
    @ObservedObject public var speedTest = NXSpeedTest()
#endif

    // "Following-..." / "List-56D5EE90-17CB-4925" / ...
    public var id: String? { config?.id }
    public var config: NXColumnConfig?
    
    public let vmInner = NXColumnViewModelInner()
    
    @MainActor
    private func didFinish() {
        speedTest.didPutOnScreen()
        if !ConnectionPool.shared.anyConnected { // After finish we were never connected, watch for first connection to .load() again
            self.watchForFirstConnection = true
        }
    }
    
    @Published var viewState: ColumnViewState = .loading {
        didSet {
            if case .posts(let nrPosts) = viewState, nrPosts.isEmpty {
                if !vmInner.unreadIds.isEmpty {
                    vmInner.unreadIds = [:]
                    vmInner.updateIsAtTopSubject.send()
                }
            }
            else if case .loading = viewState {
                if !vmInner.unreadIds.isEmpty {
                    vmInner.unreadIds = [:]
                    vmInner.updateIsAtTopSubject.send()
                }
            }
        }
    }
   
    private var danglingIds: Set<NRPostID> = [] // posts that are transformed, but somehow not on screen (maybe not found on relays). either we put on on screen or not, dont transform over and over again.
    
    public var isVisible: Bool = false {
        didSet {
            guard let config else { return }
            if isVisible {

                speedTest.reset()
                speedTest.firstEmptyFeedVisibleFinished()
                
                if case .loading = viewState {
                    Task { @MainActor in
                        self.initialize(config)
                    }
                }
                else if case .posts(_) = viewState {
                    Task { @MainActor in
                        self.resume()
                    }
                }
            }
            else if !isPaused {
                Task { @MainActor in
                    self.pause()
                }
            }
        }
    }
    public var availableWidth: CGFloat? // Should set in NXColumnView.onAppear { } before .load()
    private var fetchFeedTimer: Timer? = nil
    private var newEventsInDatabaseSub: AnyCancellable?
    private var newPostSavedSub: AnyCancellable?
    private var newPostUndoSub: AnyCancellable?
    private var firstConnectionSub: AnyCancellable?
    private var reloadWhenNeededSub: AnyCancellable?
    private var lastDisconnectionSub: AnyCancellable?
    private var onAppearSubjectSub: AnyCancellable?
    public var watchForFirstConnection = false
    private var subscriptions = Set<AnyCancellable>()
    public var onAppearSubject = PassthroughSubject<Int64,Never>()
    
    @MainActor
    private var currentNRPostsOnScreen: [NRPost] {
        if case .posts(let nrPosts) = viewState {
            return nrPosts
        }
        return []
    }
    
    // Use feed.refreshedAt for filling gaps, because most recent on screen can be from local db from a different column, so different query and may be missing posts from earlier
    // We need to only update refreshed at after putting on screen from remote, not from local
    @MainActor
    public var refreshedAt: Int64 {
        get {
#if DEBUG
            
            if LESS_CACHE && IS_SIMULATOR { // Force to 6 hours ago for testing
                return (Int64(Date().timeIntervalSince1970) - 21_600)
            }
#endif
            
            guard let config else { // 2 days ago if config is somehow missing
                return (Int64(Date().timeIntervalSince1970) - 172_800)
            }
            
            switch config.columnType {
            case .following(let feed), .picture(let feed):
                if let refreshedAt = feed.refreshedAt, let mostRecentCreatedAt = self.mostRecentCreatedAt {
                    return min(Int64(refreshedAt.timeIntervalSince1970),Int64(mostRecentCreatedAt) - 300)
                }
                if let refreshedAt = feed.refreshedAt { // 5 minutes before last refreshedAt
                    return Int64(refreshedAt.timeIntervalSince1970) - 300
                }
                else if let mostRecentCreatedAt = self.mostRecentCreatedAt {
                   return Int64(mostRecentCreatedAt) // or most recent on screen
                }
            case .pubkeys(let feed):
                if let refreshedAt = feed.refreshedAt, let mostRecentCreatedAt = self.mostRecentCreatedAt {
                    return min(Int64(refreshedAt.timeIntervalSince1970),Int64(mostRecentCreatedAt) - 300)
                }
                if let refreshedAt = feed.refreshedAt { // 5 minutes before last refreshedAt
                    return Int64(refreshedAt.timeIntervalSince1970) - 300
                }
                else if let mostRecentCreatedAt = self.mostRecentCreatedAt {
                   return Int64(mostRecentCreatedAt) // or most recent on screen
                }
            case .relays(_): // 8 hours
                if let mostRecentCreatedAt = self.mostRecentCreatedAt {
                   return Int64(mostRecentCreatedAt) // or most recent on screen
                }
                return (Int64(Date().timeIntervalSince1970) - 28_800)
            default:
                if let mostRecentCreatedAt = self.mostRecentCreatedAt {
                   return Int64(mostRecentCreatedAt) // or most recent on screen
                }
                // else take 8 hours?
                return (Int64(Date().timeIntervalSince1970) - 28_800)
            }
            if let mostRecentCreatedAt = self.mostRecentCreatedAt {
               return Int64(mostRecentCreatedAt) // or most recent on screen
            }
            // else take 2 days
            return (Int64(Date().timeIntervalSince1970) - 172_800)
        }
        set {
            guard let config else { return }
            switch config.columnType {
            case .following(let feed), .picture(let feed):
                feed.refreshedAt = Date(timeIntervalSince1970: TimeInterval(newValue))
            case .pubkeys(let feed):
                feed.refreshedAt = Date(timeIntervalSince1970: TimeInterval(newValue))
            case .relays(let feed): // 8 hours
                feed.refreshedAt = Date(timeIntervalSince1970: TimeInterval(newValue))
            default:
                return
            }
        }
    }
    
    private var gapFiller: NXGapFiller?
    
    // For syncing .lastRead across devices
    public var feed: CloudFeed? = nil {
        didSet {
            syncFeedSubject
                .debounce(for: .seconds(5), scheduler: RunLoop.main)
                .sink { [weak self] _ in
                    guard let self, let feed else { return }
                    guard SettingsStore.shared.appWideSeenTracker && SettingsStore.shared.appWideSeenTrackeriCloud else { return }
                    
                    // Don't add duplicates to .lastRead but also keep the most recent one
                    // so remove new markAsReadSyncQueue from existing lastRead and then prepend markAsReadSyncQueue to lastRead (move existing ids to the front again)
                    // after that when we remove > 300 it is always less recent ones that are removed.
                    feed.lastRead.removeAll { self.markAsReadSyncQueue.contains($0) }
                    feed.lastRead.insert(contentsOf: self.markAsReadSyncQueue, at: 0)
                    
                    // if size of feed.lastRead is > 350, remove all beyond index 350
                    if feed.lastRead.count > 350 {
                        feed.lastRead = Array(feed.lastRead[..<350])
                    }
                    
                    self.markAsReadSyncQueue.removeAll()
                    viewContextSave()
                }
                .store(in: &subscriptions)
                
            feed?.objectWillChange
                .sink(receiveValue: { [weak self] in
                    guard let self, let feed else { return }
                    guard SettingsStore.shared.appWideSeenTracker && SettingsStore.shared.appWideSeenTrackeriCloud else { return }
                    
                    // Only the keys of self.unreadIds where self.unreadIds[key] > 0
                    let unreadIds: Set<String> = Set(
                        self.vmInner.unreadIds.filter({ $0.value > 0 })
                            .keys
                            .map { String($0.prefix(8)) } // just the prefix
                    )
                
                    // Only the unreadIds that are also in feedLastReadIds, using Set theory
                    let lastReadIdsToRemove: Set<String> = unreadIds.intersection(Set(feed.lastRead))
                    
                    guard !lastReadIdsToRemove.isEmpty else { return }
                    
                    if case .posts(let existingPosts) = self.viewState {
                        for key in vmInner.unreadIds.keys {
                            if lastReadIdsToRemove.contains(String(key.prefix(8))) {
                                vmInner.unreadIds[key] = nil
                                vmInner.updateIsAtTopSubject.send()
                            }
                        }

                        withAnimation { // withAnimation and not at top keeps scroll position
                            self.viewState = .posts(existingPosts.filter { !lastReadIdsToRemove.contains($0.shortId) })
                        }
                    }
                })
                .store(in: &subscriptions)
        }
    }
    
    private var markAsReadSyncQueue: Set<String> = []
    
    @MainActor
    public func markAsRead(_ shortPostId: String) {
        guard feed != nil else { return }
        guard SettingsStore.shared.appWideSeenTracker && SettingsStore.shared.appWideSeenTrackeriCloud else { return }
        markAsReadSyncQueue.insert(shortPostId)
        syncFeedSubject.send()
    }
    
    public func markAsRead(_ shortPostIds: [String]) {
        guard feed != nil else { return }
        guard SettingsStore.shared.appWideSeenTracker && SettingsStore.shared.appWideSeenTrackeriCloud else { return }
        markAsReadSyncQueue.formUnion(Set(shortPostIds))
        syncFeedSubject.send()
    }
    
    private var syncFeedSubject = PassthroughSubject<Void, Never>()
    private var loadLocalSubject = PassthroughSubject<(NXColumnConfig, Bool, (() -> Void)?), Never>()

    @MainActor
    public func initialize(_ config: NXColumnConfig) {
        self.subscriptions = Set<AnyCancellable>()
        self.config = config
        
        self.feed = config.feed
        
        // Set up loadLocal debouncer (somewhere there is a loadLocal -> loadRemote -> LoadLocal infinite loop, don't know where, this fixes that)
        // Could also setup for loadRemote but we never call loadRemote by itself so should not be necessary
        loadLocalSubject
            .debounce(for: .seconds(0.05), scheduler: RunLoop.main)
//            .throttle(for: .seconds(2.0), scheduler: RunLoop.main, latest: false) // <-- a 2 sec throttle here means our localLocal->loadRemote->loadLocal dance will always take longer than 2.0 seconds OR never finish... so remove it and find other solution
            .sink { [weak self] (config, older, completion) in
                self?._loadLocal(config, older: older, completion: completion)
            }
            .store(in: &subscriptions)
                
        
        // Set up gap filler, don't trigger yet here
        gapFiller = NXGapFiller(since: self.refreshedAt, windowSize: 4, timeout: 2.0, currentGap: 0, columnVM: self)
        guard isVisible else { return }
        startFetchFeedTimer()
        
//        // Change to loading if we were displaying posts before
//        if case .posts(_) = viewState {
//            viewState = .loading
//        }
        
        firstLoad(config)
        
        newPostSavedSub?.cancel()
        newPostSavedSub = nil
        listenForOwnNewPostSaved(config)
        
        newPostUndoSub?.cancel()
        newPostUndoSub = nil
        listenForOwnNewPostUndo(config)
        
        newEventsInDatabaseSub?.cancel()
        newEventsInDatabaseSub = nil
        listenForNewPosts(config)
        
        firstConnectionSub?.cancel()
        firstConnectionSub = nil
        listenForFirstConnection(config: config)
        
        onAppearSubjectSub?.cancel()
        onAppearSubjectSub = nil
        loadMoreWhenNearBottom(config)
        
        reloadWhenNeededSub?.cancel()
        reloadWhenNeededSub = nil
        reloadWhenNeeded(config)
        
        resumeFeedSub?.cancel()
        resumeFeedSub = nil
        listenForResumeFeed(config)
        
        pauseFeedSub?.cancel()
        pauseFeedSub = nil
        listenForPauseFeed(config)
        
        
        // if config.columnType is .following OR .picture
        switch config.columnType {
        case .following, .picture:
            followsChangedSub?.cancel()
            followsChangedSub = nil
            listenForFollowsChanged(config)
        default:
            break
        }
        
        
        blockListUpdatedSub?.cancel()
        blockListUpdatedSub = nil
        listenForBlockListUpdatedSub(config)
        
        muteListUpdatedSub?.cancel()
        muteListUpdatedSub = nil
        listenForMuteListUpdatedSub(config)
    }
    
    @MainActor
    private func firstLoad(_ config: NXColumnConfig) {

        speedTest.firstEmptyFeedVisibleFinished()
        
        // For SomeoneElses feed we need to fetch kind 3 first, before we can do loadLocal/loadRemote
        if case .someoneElses(let pubkey) = config.columnType {
            // Reset all posts already seen for SomeoneElses Feed
            allIdsSeen = []
            fetchKind3ForSomeoneElsesFeed(pubkey, config: config) { [weak self] updatedConfig in
                self?.config = updatedConfig
                self?.loadLocal(updatedConfig) { // <-- instant, and works offline
                    // callback to load remote
                    self?.loadRemote(updatedConfig) // <--- fetch new posts (with gap filler)
                }
            }
        }
        else { // Else we can start as normal with loadLocal
            loadLocal(config) { [weak self] in // <-- instant, and works offline
                // callback to load remote
                self?.loadRemote(config) // <--- fetch new posts (with gap filler)
            }
        }
    }
    
    private var muteListUpdatedSub: AnyCancellable?
    
    @MainActor
    private func listenForMuteListUpdatedSub(_ config: NXColumnConfig) {
        guard muteListUpdatedSub == nil else { return }
        muteListUpdatedSub =  receiveNotification(.muteListUpdated)
            .sink { [weak self] notification in
                guard let self else { return }
                if case .posts(let existingPosts) = viewState {
                    let mutedRootIds: Set<String> = notification.object as! Set<String>
                    
                    for nrPost in existingPosts where (mutedRootIds.contains(nrPost.id) || mutedRootIds.contains(nrPost.replyToRootId ?? "!")) {
                        vmInner.unreadIds[nrPost.id] = nil
                        vmInner.updateIsAtTopSubject.send()
                    }
                    
                    viewState = .posts(existingPosts.filter { nrPost in
                        return !mutedRootIds.contains(nrPost.id) && !mutedRootIds.contains(nrPost.replyToRootId ?? "!") // id not blocked
                            && !(nrPost.isRepost && mutedRootIds.contains(nrPost.firstQuoteId ?? "!")) // is not: repost + muted reposted id
                    })
                }
            }
    }
    
    private var blockListUpdatedSub: AnyCancellable?
    
    @MainActor
    private func listenForBlockListUpdatedSub(_ config: NXColumnConfig) {
        guard blockListUpdatedSub == nil else { return }
        blockListUpdatedSub =  receiveNotification(.blockListUpdated)
            .sink { [weak self] notification in
                guard let self else { return }
                if case .posts(let existingPosts) = viewState {
                    let blocks: Set<String> = notification.object as! Set<String>
                    
                    for nrPost in existingPosts where blocks.contains(nrPost.pubkey) {
                        vmInner.unreadIds[nrPost.id] = nil
                        vmInner.updateIsAtTopSubject.send()
                    }
                    
                    viewState = .posts(existingPosts.filter { nrPost in
                        return !blocks.contains(nrPost.pubkey) // pubkey not blocked
                            && !(nrPost.isRepost && blocks.contains(nrPost.firstQuote?.pubkey ?? "!")) // is not: repost + blocked reposted pubkey
                    })
                }
            }
    }
    
    private var followsChangedSub: AnyCancellable?
    
    @MainActor
    private func listenForFollowsChanged(_ config: NXColumnConfig) {
        guard followsChangedSub == nil else { return }
        followsChangedSub = receiveNotification(.followsChanged)
            .debounce(for: .seconds(2.0), scheduler: RunLoop.main)
            .throttle(for: .seconds(8.0), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                ConnectionPool.shared.closeSubscription(config.id)
                self?.sendRealtimeReq(config)
            }
    }
    
    @MainActor
    private func listenForOwnNewPostSaved(_ config: NXColumnConfig) {
        guard newPostSavedSub == nil else { return }
        newPostSavedSub = receiveNotification(.newPostSaved)
            .sink { [weak self] notification in
                guard let self else { return }

                let pubkeys: Set<String> = switch config.columnType {
                case .pubkeys(let feed):
                    feed.contactPubkeys
                case .following(_):
                    (config.account?.followingPubkeys ?? []).union(Set([config.accountPubkey ?? ""]))
                case .picture(_):
                    (config.account?.followingPubkeys ?? []).union(Set([config.accountPubkey ?? ""]))
                default:
                    []
                }

                let currentIdsOnScreen = self.currentIdsOnScreen
                let repliesEnabled = config.repliesEnabled
                
                let event = notification.object as! Event
                bg().perform { [weak self] in
                    
                    // Only kind 20 on picture-only feed
                    if case .picture(_) = config.columnType, event.kind != 20 {
                        return
                    }
                    
                    // No kind 20 on following feed
                    if case .following(_) = config.columnType, event.kind == 20 {
                        return
                    }
                    
                    
                    guard pubkeys.contains(event.pubkey), !currentIdsOnScreen.contains(event.id) else { return }
                    EventRelationsQueue.shared.addAwaitingEvent(event, debugInfo: "NXColumnViewModel.listenForOwnNewPostSaved")
                    // If we are not hiding replies, we render leafs + parents --> withParents: true
                    //     and we don't load replies (withReplies) because any reply we follow should already be its own leaf (PostOrThread)
                    // If we are hiding replies (view), we show mini pfp replies instead, for that we need reply info: withReplies: true
                    let newOwnPost = NRPost(event: event, withParents: repliesEnabled, withReplies: !repliesEnabled, withRepliesCount: true, cancellationId: event.cancellationId)
                    Task { @MainActor in
                        self?.putOnScreen([newOwnPost], config: config)
                    }
                }
            }
    }
    
    @MainActor
    private func listenForOwnNewPostUndo(_ config: NXColumnConfig) {
        guard newPostUndoSub == nil else { return }
        newPostUndoSub =  receiveNotification(.unpublishedNRPost)
            .sink { [weak self] notification in
                guard let self else { return }
                if case .posts(let existingPosts) = viewState {
                    let nrPost = notification.object as! NRPost
                    vmInner.unreadIds[nrPost.id] = nil
                    vmInner.updateIsAtTopSubject.send()
                    viewState = .posts(existingPosts.filter { $0.id != nrPost.id })
                }
            }
    }
    
    // Reload (after toggle replies enabled etc)
    @MainActor
    public func reload(_ config: NXColumnConfig) {
        viewState = .loading
        self.allIdsSeen = []
        startFetchFeedTimer()
        loadLocal(config)
    }
    
    public var isPaused: Bool { self.fetchFeedTimer == nil }
    
    @MainActor
    public func pause() {
        guard let config, !isPaused else { return }
        
        if IS_CATALYST { // Don't pause "Following" feed on macOS
            if config.id.starts(with: "Following-") {
                return
            }
        }
        
#if DEBUG
        L.og.debug("☘️☘️ \(config.name) pause()")
#endif
        self.fetchFeedTimer?.invalidate()
        self.fetchFeedTimer = nil
        self.realTimeReqTask?.cancel()
        
        switch config.columnType {
        case .picture(_):
            ConnectionPool.shared.closeSubscription(config.id) // List-...
        case .pubkeys(_):
            ConnectionPool.shared.closeSubscription(config.id) // List-...
        case .pubkey:
            ConnectionPool.shared.closeSubscription(config.id) // List-...
        case .relays(_):
            ConnectionPool.shared.closeSubscription(config.id) // List-...
        case .hashtags:
            ConnectionPool.shared.closeSubscription(config.id) // List-...
            
        default:
            let _: String? = nil
        }
    }
    
    private func startFetchFeedTimer() {
        self.fetchFeedTimer?.invalidate()
        self.fetchFeedTimer = Timer.scheduledTimer(withTimeInterval: FETCH_FEED_INTERVAL, repeats: true) { [weak self] _ in
            self?.fetchFeedTimerNextTick()
        }
        self.fetchFeedTimer?.tolerance = 2.0
    }
    
    @MainActor
    public func resume() {
        guard let config else { return }
#if DEBUG
        L.og.debug("☘️☘️ \(config.name) resume() isAtTop: \(self.vmInner.isAtTop)")
#endif
        speedTest.reset()
        speedTest.firstEmptyFeedVisibleFinished()

        
        self.startFetchFeedTimer()
        self.fetchFeedTimerNextTick()
        self.listenForNewPosts(config)
//        L.og.debug("☘️☘️ \(config.name) resume().loadLocal()")
        self.loadLocal(config) { [weak self] in
//            L.og.debug("☘️☘️ \(config.name) resume().loadRemote()")
            self?.loadRemote(config)
//            L.og.debug("☘️☘️ \(config.name) resume().fetchGap: since: \(self.refreshedAt.description) currentGap: 0")
//            gapFiller?.fetchGap(since: self.refreshedAt, currentGap: 0)
        }
    }
    
    private func fetchFeedTimerNextTick() {
        guard let config, !AppState.shared.appIsInBackground && (isVisible || (config.id.starts(with: "Following-") && config.name != "Explore")) else { return }
        bg().perform { [weak self] in
            guard !Importer.shared.isImporting else { return }
            setFirstTimeCompleted()

            Task { @MainActor [weak self] in
                self?.sendRealtimeReq(config)
            }
        }
    }
    
    public func loadLocal(_ config: NXColumnConfig, older: Bool = false, completion: (() -> Void)? = nil) {
        if !isVisible || isPaused || AppState.shared.appIsInBackground {
            #if DEBUG
            L.og.debug("☘️☘️ \(config.name) loadLocal - 👹👹 halted. isVisible: \(self.isVisible) isPaused: \(self.isPaused)")
            #endif
            return
        }
#if DEBUG
L.og.debug("☘️☘️ \(config.name) loadLocal (request, debounced and throttled first)")
#endif
        loadLocalSubject.send((config, older, completion))
    }

    @MainActor
    public func _loadLocal(_ config: NXColumnConfig, older: Bool = false, completion: (() -> Void)? = nil) {
        
        let currentNRPostsOnScreen = self.currentNRPostsOnScreen
        
        if !currentNRPostsOnScreen.isEmpty, let feed = config.feed { // if we don't check if screen is empty we can have permanent spinner at first run
            self.allIdsSeen = self.allIdsSeen.union(Set(feed.lastRead))
        }
        
        let allIdsSeen = self.allIdsSeen
        let currentIdsOnScreen = self.currentIdsOnScreen
        let wotEnabled = config.wotEnabled
        let repliesEnabled = config.repliesEnabled
  
        // Fetch since 5 minutes before most recent item on screen (since)
        // Or until oldest (bottom) item on screen (until)
        let (sinceTimestamp, untilTimestamp) = if case .posts(let nrPosts) = viewState {
            ((nrPosts.first?.created_at ?? 300) - 300, (nrPosts.last?.created_at ?? Int64(Date().timeIntervalSince1970)))
        }
        else { // or if empty screen: 0 (since) or now (until)
            (0, Int64(Date().timeIntervalSince1970))
        }
        
        let sinceOrUntil = !older ? sinceTimestamp : untilTimestamp
        
        switch config.columnType {
        case .following(let feed):
            
            let followingPubkeys: Set<String> = if let account = feed.account {
                account.followingPubkeys.union(Set([account.publicKey]))
                    .union(account.privateFollowingPubkeys)
            }
            else if feed.accountPubkey == EXPLORER_PUBKEY {
                AppState.shared.rawExplorePubkeys.subtracting(AppState.shared.bgAppState.blockedPubkeys)
            }
            else {
                []
            }
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) loadLocal(.following) \(older ? "older" : "") \(followingPubkeys.count) pubkeys")
#endif
            
            let hashtagRegex: String? = if let account = feed.account {
                makeHashtagRegex(account.followingHashtags)
            }
            else { nil }
            
            let kinds = if UserDefaults.standard.bool(forKey: "enable_picture_feed") {
                QUERY_FOLLOWING_KINDS.subtracting([20])
            } else { QUERY_FOLLOWING_KINDS }
            
            bg().perform { [weak self] in
                guard let self else { return }
                let fr = if !older {
                    Event.postsByPubkeys(followingPubkeys, lastAppearedCreatedAt: sinceTimestamp, hideReplies: !repliesEnabled, hashtagRegex: hashtagRegex, kinds: kinds)
                }
                else {
                    Event.postsByPubkeys(followingPubkeys, until: untilTimestamp, hideReplies: !repliesEnabled, hashtagRegex: hashtagRegex, kinds: kinds)
                }
                guard let events: [Event] = try? bg().fetch(fr) else { return }
                self.processToScreen(events, config: config, allIdsSeen: allIdsSeen, currentIdsOnScreen: currentIdsOnScreen, currentNRPostsOnScreen: currentNRPostsOnScreen, sinceOrUntil: Int(sinceOrUntil), older: older, wotEnabled: wotEnabled, repliesEnabled: repliesEnabled, completion: completion)
            }
        case .picture(let feed):
            
            let followingPubkeys: Set<String> = if let account = feed.account {
                account.followingPubkeys.union(Set([account.publicKey]))
                    .union(account.privateFollowingPubkeys)
            }
            else {
                []
            }
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) loadLocal(.picture) \(older ? "older" : "") \(followingPubkeys.count) pubkeys")
#endif
            
            let hashtagRegex: String? = if let account = feed.account {
                makeHashtagRegex(account.followingHashtags)
            }
            else { nil }
            
            bg().perform { [weak self] in
                guard let self else { return }
                let fr = if !older {
                    Event.postsByPubkeys(followingPubkeys, lastAppearedCreatedAt: sinceTimestamp, hideReplies: !repliesEnabled, hashtagRegex: hashtagRegex, kinds: [20])
                }
                else {
                    Event.postsByPubkeys(followingPubkeys, until: untilTimestamp, hideReplies: !repliesEnabled, hashtagRegex: hashtagRegex, kinds: [20])
                }
                guard let events: [Event] = try? bg().fetch(fr) else { return }
                self.processToScreen(events, config: config, allIdsSeen: allIdsSeen, currentIdsOnScreen: currentIdsOnScreen, currentNRPostsOnScreen: currentNRPostsOnScreen, sinceOrUntil: Int(sinceOrUntil), older: older, wotEnabled: wotEnabled, repliesEnabled: repliesEnabled, completion: completion)
            }
        case .pubkeys(let feed):
            let pubkeys = feed.contactPubkeys
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) loadLocal(.pubkeys)\(older ? "older" : "") \(pubkeys.count) pubkeys")
#endif

            bg().perform { [weak self] in
                guard let self else { return }
                let fr = if !older {
                    Event.postsByPubkeys(pubkeys, lastAppearedCreatedAt: sinceTimestamp, hideReplies: !repliesEnabled, kinds: QUERY_FOLLOWING_KINDS)
                }
                else {
                    Event.postsByPubkeys(pubkeys, until: untilTimestamp, hideReplies: !repliesEnabled, kinds: QUERY_FOLLOWING_KINDS)
                }
                guard let events: [Event] = try? bg().fetch(fr) else { return }

                self.processToScreen(events, config: config, allIdsSeen: allIdsSeen, currentIdsOnScreen: currentIdsOnScreen, currentNRPostsOnScreen: currentNRPostsOnScreen, sinceOrUntil: Int(sinceOrUntil), older: older, wotEnabled: wotEnabled, repliesEnabled: repliesEnabled, completion: completion)
            }
        case .someoneElses(_):
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) loadLocal(.someoneElses)\(older ? "older" : "")")
#endif
            // pubkeys and hashtags coming from loadLocal(_:pubkeys: hashtags:) not from config
            let hashtagRegex: String? = !config.hashtags.isEmpty ? makeHashtagRegex(config.hashtags) : nil
            bg().perform { [weak self] in
                guard let self else { return }
                let fr = if !older {
                    Event.postsByPubkeys(config.pubkeys, lastAppearedCreatedAt: sinceTimestamp, hideReplies: !repliesEnabled, hashtagRegex: hashtagRegex, kinds: QUERY_FOLLOWING_KINDS)
                }
                else {
                    Event.postsByPubkeys(config.pubkeys, until: untilTimestamp, hideReplies: !repliesEnabled, hashtagRegex: hashtagRegex, kinds: QUERY_FOLLOWING_KINDS)
                }
                guard let events: [Event] = try? bg().fetch(fr) else { return }
                self.processToScreen(events, config: config, allIdsSeen: allIdsSeen, currentIdsOnScreen: currentIdsOnScreen, currentNRPostsOnScreen: currentNRPostsOnScreen, sinceOrUntil: Int(sinceOrUntil), older: older, wotEnabled: wotEnabled, repliesEnabled: repliesEnabled, completion: completion)
            }
        case .relays(let feed):
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) loadLocal(.relays)\(older ? "older" : "")")
#endif
            let relaysData = feed.relaysData
            bg().perform { [weak self] in
                guard let self else { return }
                let fr = if !older {
                    Event.postsByRelays(relaysData, lastAppearedCreatedAt: sinceTimestamp, hideReplies: !repliesEnabled, kinds: QUERY_FOLLOWING_KINDS)
                }
                else {
                    Event.postsByRelays(relaysData, until: untilTimestamp, hideReplies: !repliesEnabled, kinds: QUERY_FOLLOWING_KINDS)
                }
                guard let events: [Event] = try? bg().fetch(fr) else { return }
                self.processToScreen(events, config: config, allIdsSeen: allIdsSeen, currentIdsOnScreen: currentIdsOnScreen, currentNRPostsOnScreen: currentNRPostsOnScreen, sinceOrUntil: Int(sinceOrUntil), older: older, wotEnabled: wotEnabled, repliesEnabled: repliesEnabled, completion: completion)
            }
        case .pubkey:
            viewState = .error("Not supported yet")
        case .hashtags:
            viewState = .error("Not supported yet")
        case .mentions:
            viewState = .error("Not supported yet")
        case .newPosts:
            viewState = .error("Not supported yet")
        case .reactions:
            viewState = .error("Not supported yet")
        case .reposts:
            viewState = .error("Not supported yet")
        case .zaps:
            viewState = .error("Not supported yet")
        case .newFollowers:
            viewState = .error("Not supported yet")
        case .search:
            viewState = .error("Not supported yet")
        case .bookmarks:
            viewState = .error("Not supported yet")
        case .privateNotes:
            viewState = .error("Not supported yet")
        case .DMs:
            viewState = .error("Not supported yet")
        case .hot:
            viewState = .error("Not supported yet")
        case .discover:
            viewState = .error("Not supported yet")
        case .gallery:
            viewState = .error("Not supported yet")
        case .explore:
            viewState = .error("Not supported yet")
        case .articles:
            viewState = .error("Not supported yet")
        case .none:
            viewState = .error("Missing column type")
        }
    }
        
    @MainActor
    private func sendRealtimeReq(_ config: NXColumnConfig) {
        switch config.columnType {
        case .following(let feed):
            let pubkeys: Set<String> = if let account = feed.account {
                account.followingPubkeys.union(Set([account.publicKey]))
                    .union(account.privateFollowingPubkeys)
            }
            else if feed.accountPubkey == EXPLORER_PUBKEY {
                AppState.shared.rawExplorePubkeys.subtracting(AppState.shared.bgAppState.blockedPubkeys)
            }
            else { [] }
            
            let hashtags: Set<String> = if let account = feed.account {
                account.followingHashtags
            }
            else { [] }
            
            guard pubkeys.count > 0 || hashtags.count > 0 else { return }
            
            let kinds = if UserDefaults.standard.bool(forKey: "enable_picture_feed") {
                FETCH_FOLLOWING_KINDS.subtracting([20])
            } else {
                FETCH_FOLLOWING_KINDS
            }
            
            let filters = pubkeyOrHashtagReqFilters(pubkeys, hashtags: hashtags, since: NTimestamp(date: Date.now).timestamp, kinds: kinds)
            
            outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: config.id, filters: filters), activeSubscriptionId: config.id)
        case .picture(let feed):
            let pubkeys: Set<String> = if let account = feed.account {
                account.followingPubkeys.union(Set([account.publicKey]))
                    .union(account.privateFollowingPubkeys)
            }
            else { [] }
            
            let hashtags: Set<String> = if let account = feed.account {
                account.followingHashtags
            }
            else { [] }
            
            guard pubkeys.count > 0 || hashtags.count > 0 else { return }
            
            let filters = pubkeyOrHashtagReqFilters(pubkeys, hashtags: hashtags, since: NTimestamp(date: Date.now).timestamp, kinds: [20,5])
            
            outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: config.id, filters: filters), activeSubscriptionId: config.id)
        case .pubkeys(let feed):
            let pubkeys = feed.contactPubkeys
            let hashtags = feed.followingHashtags
            guard pubkeys.count > 0 || hashtags.count > 0 else { return }
            let filters = pubkeyOrHashtagReqFilters(pubkeys, hashtags: hashtags, since: NTimestamp(date: Date.now).timestamp, kinds: FETCH_FOLLOWING_KINDS)
            
            if let message = CM(type: .REQ, subscriptionId: config.id, filters: filters).json() {
                req(message, activeSubscriptionId: config.id)
                // TODO: Add toggle on .pubkeys custom feeds so we can also use outboxReq for non-"Following"
            }
        case .someoneElses(_):
            guard config.pubkeys.count > 0 || config.hashtags.count > 0 else { return }
            let filters = pubkeyOrHashtagReqFilters(config.pubkeys, hashtags: config.hashtags, since: NTimestamp(date: Date.now).timestamp, kinds: FETCH_FOLLOWING_KINDS)
            
            if let message = CM(type: .REQ, subscriptionId: config.id, filters: filters).json() {
                req(message, activeSubscriptionId: config.id)
            }
        case .pubkey:
            let _: String? = nil
        case .relays(let feed):
            let relaysData = feed.relaysData
            guard !relaysData.isEmpty else { return }
            let now = NTimestamp(date: Date.now)
            req(RM.getGlobalFeedEvents(subscriptionId: config.id, since: now), activeSubscriptionId: config.id, relays: relaysData)
        case .hashtags:
            let _: String? = nil
        case .mentions:
            let _: String? = nil
        case .newPosts:
            let _: String? = nil
        case .reactions:
            let _: String? = nil
        case .reposts:
            let _: String? = nil
        case .zaps:
            let _: String? = nil
        case .newFollowers:
            let _: String? = nil
        case .search:
            let _: String? = nil
        case .bookmarks:
            let _: String? = nil
        case .privateNotes:
            let _: String? = nil
        case .DMs:
            let _: String? = nil
        case .hot:
            let _: String? = nil
        case .discover:
            let _: String? = nil
        case .gallery:
            let _: String? = nil
        case .explore:
            let _: String? = nil
        case .articles:
            let _: String? = nil
        case .none:
            let _: String? = nil
        }
    }
    
    @MainActor
    public func getFillGapReqStatement(_ config: NXColumnConfig, since: Int, until: Int? = nil) -> (cmd: () -> Void, subId: String)? {
        switch config.columnType {
        case .following(let feed):
            let pubkeys: Set<String> = if let account = feed.account {
                account.followingPubkeys.union(Set([account.publicKey]))
                    .union(account.privateFollowingPubkeys)
            }
            else if feed.accountPubkey == EXPLORER_PUBKEY {
                AppState.shared.rawExplorePubkeys.subtracting(AppState.shared.bgAppState.blockedPubkeys)
            }
            else { [] }
            
            let hashtags: Set<String> = if let account = feed.account {
                account.followingHashtags
            }
            else { [] }
            
            let kinds = if UserDefaults.standard.bool(forKey: "enable_picture_feed") {
                FETCH_FOLLOWING_KINDS.subtracting([20])
            } else {
                FETCH_FOLLOWING_KINDS
            }
            
            let filters = pubkeyOrHashtagReqFilters(pubkeys, hashtags: hashtags, since: since, until: until, kinds: kinds)
             
            return (cmd: {
                guard pubkeys.count > 0 || hashtags.count > 0 else {
                    L.og.debug("☘️☘️ cmd with empty pubkeys and hashtags")
                    return
                }
                if feed.accountPubkey == EXPLORER_PUBKEY {
                    if let cm = NostrEssentials
                        .ClientMessage(type: .REQ,
                                       subscriptionId: "RESUME-" + config.id + "-" + since.description,
                                       filters: filters
                        ).json() {
                        req(cm)
                    }
                }
                else {
                    outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: "RESUME-" + config.id + "-" + since.description, filters: filters))
                }
            }, subId: "RESUME-" + config.id + "-" + since.description)

        case .picture(let feed):
            let pubkeys: Set<String> = if let account = feed.account {
                account.followingPubkeys.union(Set([account.publicKey]))
                    .union(account.privateFollowingPubkeys)
            }
            else { [] }
            
            let hashtags: Set<String> = if let account = feed.account {
                account.followingHashtags
            }
            else { [] }
            
            let filters = pubkeyOrHashtagReqFilters(pubkeys, hashtags: hashtags, since: since, until: until, kinds: [20,5])
             
            return (cmd: {
                guard pubkeys.count > 0 || hashtags.count > 0 else {
                    L.og.debug("☘️☘️ cmd with empty pubkeys and hashtags")
                    return
                }
                outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: "RESUME-" + config.id + "-" + since.description, filters: filters))
            }, subId: "RESUME-" + config.id + "-" + since.description)
            
        case .pubkeys(let feed):
            let pubkeys = feed.contactPubkeys
            let hashtags = feed.followingHashtags
            guard pubkeys.count > 0 || hashtags.count > 0 else {
                L.og.debug("☘️☘️ cmd with empty pubkeys and hashtags")
                return nil
            }
            let filters = pubkeyOrHashtagReqFilters(pubkeys, hashtags: hashtags, since: since, until: until, kinds: FETCH_FOLLOWING_KINDS)
            
            if let message = CM(type: .REQ, subscriptionId: "RESUME-" + config.id + "-" + since.description, filters: filters).json() {
                return (cmd: {
                    req(message)
                }, subId: "RESUME-" + config.id + "-" + since.description)
                // TODO: Add toggle on .pubkeys custom feeds so we can also use outboxReq for non-"Following"
            }
            return nil
        case .someoneElses(_):
            guard config.pubkeys.count > 0 || config.hashtags.count > 0 else {
                L.og.debug("☘️☘️ cmd with empty pubkeys and hashtags")
                return nil
            }
            let filters = pubkeyOrHashtagReqFilters(config.pubkeys, hashtags: config.hashtags, since: since, until: until, kinds: FETCH_FOLLOWING_KINDS)
            
            if let message = CM(type: .REQ, subscriptionId: "RESUME-" + config.id + "-" + since.description, filters: filters).json() {
                return (cmd: {
                    req(message)
                }, subId: "RESUME-" + config.id + "-" + since.description)
            }
            return nil
        case .pubkey:
            return nil
        case .relays(let feed):
            let relaysData = feed.relaysData
            guard !relaysData.isEmpty else { return nil }
            
            let filters = globalFeedReqFilters(since: since, until: until)
            
            if let message = CM(type: .REQ, subscriptionId: "G-RESUME-" + config.id + "-" + since.description, filters: filters).json() {
                return (cmd: {
                    req(message, activeSubscriptionId: "G-RESUME-" + config.id + "-" + since.description, relays: relaysData)
                }, subId: "G-RESUME-" + config.id + "-" + since.description)
            }
            return nil
        case .hashtags:
            return nil
        case .mentions:
            return nil
        case .newPosts:
            return nil
        case .reactions:
            return nil
        case .reposts:
            return nil
        case .zaps:
            return nil
        case .newFollowers:
            return nil
        case .search:
            return nil
        case .bookmarks:
            return nil
        case .privateNotes:
            return nil
        case .DMs:
            return nil
        case .hot:
            return nil
        case .discover:
            return nil
        case .gallery:
            return nil
        case .explore:
            return nil
        case .articles:
            return nil
        case .none:
            return nil
        }
    }
    
    @MainActor
    private func sendNextPageReq(_ config: NXColumnConfig, until: Int64) {
#if DEBUG
        L.og.debug("☘️☘️ \(config.name) sendNextPageReq()")
#endif
        switch config.columnType {
        case .following(let feed):
            let pubkeys: Set<String> = if let account = feed.account {
                account.followingPubkeys.union(Set([account.publicKey]))
                    .union(account.privateFollowingPubkeys)
            }
            else if feed.accountPubkey == EXPLORER_PUBKEY {
                AppState.shared.rawExplorePubkeys.subtracting(AppState.shared.bgAppState.blockedPubkeys)
            }
            else { [] }
            
            let hashtags: Set<String> = if let account = feed.account {
                account.followingHashtags
            }
            else { [] }
            
            guard pubkeys.count > 0 || hashtags.count > 0 else { return }
            
            let kinds = if UserDefaults.standard.bool(forKey: "enable_picture_feed") {
                FETCH_FOLLOWING_KINDS.subtracting([20])
            } else {
                FETCH_FOLLOWING_KINDS
            }
            
            let filters = pubkeyOrHashtagReqFilters(pubkeys, hashtags: hashtags, until: Int(until), limit: 150, kinds: kinds)
            
            outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: "PAGE-" + config.id, filters: filters))
            
        case .picture(let feed):
            let pubkeys: Set<String> = if let account = feed.account {
                account.followingPubkeys.union(Set([account.publicKey]))
                    .union(account.privateFollowingPubkeys)
            }
            else { [] }
            
            let hashtags: Set<String> = if let account = feed.account {
                account.followingHashtags
            }
            else { [] }
            
            guard pubkeys.count > 0 || hashtags.count > 0 else { return }
            
            let filters = pubkeyOrHashtagReqFilters(pubkeys, hashtags: hashtags, until: Int(until), limit: 150, kinds: [20,5])
            
            outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: "PAGE-" + config.id, filters: filters))
            
        case .pubkeys(let feed):
            let pubkeys = feed.contactPubkeys
            let hashtags = feed.followingHashtags
            
            guard pubkeys.count > 0 || hashtags.count > 0 else { return }
            
            let filters = pubkeyOrHashtagReqFilters(pubkeys, hashtags: hashtags, until: Int(until), limit: 100, kinds: FETCH_FOLLOWING_KINDS)
            
            if let message = CM(type: .REQ, subscriptionId: "PAGE-" + config.id, filters: filters).json() {
                req(message)
                // TODO: Add toggle on .pubkeys custom feeds so we can also use outboxReq for non-"Following"
            }
            
        case .someoneElses(_):
            guard config.pubkeys.count > 0 || config.hashtags.count > 0 else { return }
            let filters = pubkeyOrHashtagReqFilters(config.pubkeys, hashtags: config.hashtags, until: Int(until), limit: 100, kinds: FETCH_FOLLOWING_KINDS)
            
            if let message = CM(type: .REQ, subscriptionId: "PAGE-" + config.id, filters: filters).json() {
                req(message)
            }
        case .pubkey:
            let _: String? = nil
        case .relays(let feed):
            let relaysData = feed.relaysData
            guard !relaysData.isEmpty else { return }
            req(RM.getGlobalFeedEvents(limit: 100, subscriptionId: "G-PAGE-" + config.id, until: NTimestamp(timestamp: Int(until))), relays: relaysData)
            
        case .hashtags:
            let _: String? = nil
        case .mentions:
            let _: String? = nil
        case .newPosts:
            let _: String? = nil
        case .reactions:
            let _: String? = nil
        case .reposts:
            let _: String? = nil
        case .zaps:
            let _: String? = nil
        case .newFollowers:
            let _: String? = nil
        case .search:
            let _: String? = nil
        case .bookmarks:
            let _: String? = nil
        case .privateNotes:
            let _: String? = nil
        case .DMs:
            let _: String? = nil
        case .hot:
            let _: String? = nil
        case .discover:
            let _: String? = nil
        case .gallery:
            let _: String? = nil
        case .explore:
            let _: String? = nil
        case .articles:
            let _: String? = nil
        case .none:
            let _: String? = nil
        }
    }
    
    private var instantFeed: InstantFeed?
    private var backlog = Backlog(auto: true)
    
    // prefix / .shortId only
    public var allIdsSeen: Set<String> {
        get {
            if case .picture(_) = config?.columnType {
                return _allIdsSeen
            }
            else {
                return SettingsStore.shared.appWideSeenTracker ? Deduplicator.shared.onScreenSeen : _allIdsSeen
            }
        }
        set {
            if case .picture(_) = config?.columnType {
                _allIdsSeen = newValue
            }
            else if SettingsStore.shared.appWideSeenTracker {
                Deduplicator.shared.onScreenSeen = newValue
            }
            else {
                _allIdsSeen = newValue
            }
        }
    }
    private var _allIdsSeen: Set<String> = []
    
    @MainActor // all ids, leaf ids, parent ids, reposted ids, but only what is on screen NOW
    private var currentIdsOnScreen: Set<String> {
        let onScreenIds: Set<String> = if case .posts(let nrPosts) = viewState {
            self.getAllPostIds(nrPosts)
        }
        else {
            []
        }
        return onScreenIds
    }
    
    @MainActor // most recent .created_at on screen (for use in req filters -> since:)
    private var mostRecentCreatedAt: Int? {
        guard case .posts(let nrPosts) = viewState else { return nil }
        if let mostRecent = nrPosts.max(by: { $0.createdAt < $1.createdAt }) {
            return Int(mostRecent.created_at)
        }
        return nil
    }
    
    @MainActor // most recent .created_at on screen (for use in req filters -> since:)
    private var oldestCreatedAt: Int? {
        guard case .posts(let nrPosts) = viewState else { return nil }
        if let oldest = nrPosts.min(by: { $0.createdAt < $1.createdAt }) {
            return Int(oldest.created_at)
        }
        return nil
    }
    
    private var resumeSubject = PassthroughSubject<Set<String>, Never>()
    private let queuedSubscriptionIds = NXQueuedSubscriptionIds()
    
    private var resumeFeedSub: AnyCancellable?

    @MainActor
    private func listenForResumeFeed(_ config: NXColumnConfig) {
        guard resumeFeedSub == nil else { return }
        resumeFeedSub = FeedsCoordinator.shared.resumeFeedsSubject
            .debounce(for: .seconds(0.15), scheduler: RunLoop.main)
//            .throttle(for: .seconds(10.0), scheduler: RunLoop.main, latest: false)
            .sink { [weak self] _ in
                guard let self, !AppState.shared.appIsInBackground && isVisible else { return }
                self.resume()
            }
    }
    
    private var pauseFeedSub: AnyCancellable?

    @MainActor
    private func listenForPauseFeed(_ config: NXColumnConfig) {
        guard pauseFeedSub == nil else { return }
        pauseFeedSub = FeedsCoordinator.shared.pauseFeedsSubject
            .debounce(for: .seconds(0.1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.pause()
            }
    }
    
    @MainActor
    private func listenForNewPosts(_ config: NXColumnConfig) {
        if newEventsInDatabaseSub == nil {
            // Merge the imported messages publisher with the custom subject
               let mergedPublisher = Importer.shared.importedMessagesFromSubscriptionIds
                   .merge(with: resumeSubject)
                   .subscribe(on: DispatchQueue.global())
            
            newEventsInDatabaseSub = mergedPublisher
            
                .handleEvents(receiveOutput: { [weak self] ids in
                    self?.queuedSubscriptionIds.add(ids)
                })
            
                .debounce(for: .seconds(0.1), scheduler: DispatchQueue.global())
                .throttle(for: .seconds(5.0), scheduler: DispatchQueue.global(), latest: true)
            
                .map { [weak self] _ in self?.queuedSubscriptionIds.getAndClear() ?? [] }
                .filter { !$0.isEmpty }
                .receive(on: RunLoop.main) // main because .haltedProcessing must access .isDelaying on main
                .sink { [weak self] subscriptionIds in
                    guard let self else { return }
                    guard isVisible && !isPaused && !AppState.shared.appIsInBackground else {
                        queuedSubscriptionIds.add(subscriptionIds)
                        return
                    }
                    guard subscriptionIds.contains(config.id) else { return }
                    
#if DEBUG
                    L.og.debug("☘️☘️ \(config.name) listenForNewPosts.subscriptionIds \(subscriptionIds)")
#endif
                    
                    self.loadLocal(config)
                }
        }
 
        realTimeReqTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self?.sendRealtimeReq(config)
        }
    }
    
    private var realTimeReqTask: Task<Void, Never>?
    
    @MainActor
    private func listenForFirstConnection(config: NXColumnConfig) {
        guard firstConnectionSub == nil else { return }
        firstConnectionSub = receiveNotification(.firstConnection)
            .debounce(for: .seconds(0.1), scheduler: DispatchQueue.global())
            .sink { [weak self] _ in
                guard let self, watchForFirstConnection else { return }
#if DEBUG
                L.og.debug("☘️☘️ \(config.name) listenForFirstConnection.load(config)")
#endif
                Task { @MainActor in
                    self.watchForFirstConnection = false
                    self.firstLoad(config)
                }
            }
        
    }
    
    @MainActor
    private func reloadWhenNeeded(_ config: NXColumnConfig) {
        guard reloadWhenNeededSub == nil, let feed = config.feed else { return }

        reloadWhenNeededSub = feed.publisher(for: \.repliesEnabled)
            .scan((feed.repliesEnabled, feed.repliesEnabled)) { (previous, current) in
                return (previous.1, current)
            }
            .dropFirst()  // Skip the initial value to avoid unnecessary reload on setup
            .sink { [weak self] oldValue, newValue in
                if oldValue != newValue {
#if DEBUG
                    L.og.debug("☘️☘️ \(config.name) 🟠 reloadWhenNeeded feed.repliesEnabled changed from \(oldValue) to \(newValue)")
#endif
                    self?.reload(config)
                }
            }
    }
    
    @MainActor
    private func listenForLastDisconnection(config: NXColumnConfig) {
        guard lastDisconnectionSub == nil else { return }
        lastDisconnectionSub = receiveNotification(.lastDisconnection)
            .debounce(for: .seconds(0.1), scheduler: DispatchQueue.global())
            .sink { [weak self] _ in
                guard let self else { return }
#if DEBUG
                L.og.debug("☘️☘️ \(config.name) listenForLastDisconnection")
#endif
                Task { @MainActor in
                    self.watchForFirstConnection = true
                }
            }
        
    }
    
    private func fetchParents(_ danglers: [NRPost], config: NXColumnConfig, allIdsSeen: Set<String>, currentIdsOnScreen: Set<String>, currentNRPostsOnScreen: [NRPost] = [], sinceOrUntil: Int, older: Bool = false) {
        for nrPost in danglers {
            EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "CVM.001")
        }

        // TODO: PROBLEM/BUG: During first load of feed with 1 contact, we have some recent events + some old events from a single person,
        // First render: some events are put on screen, most recent is 12h ago, at top of feed.
        // Some events are replies but the parent is missing, after fetching replies, they are rendered in second pass
        // they are put on top (as if new events), but they are old replies (30 days ago), so should be bottom!
        // Solutions?
        // - Only put events on top, within last 1-3 days, ignore others
        // - Maybe just always only fetch dangling events only from newer than 1-2 days ago, never older, because they will always come in at top on second pass because they are fetched later, so expectation is NEW events, not old.
        let danglingFetchTask = ReqTask(
            debounceTime: 1.0, // getting all missing replyTo's in 1 req, so can debounce a bit longer
            timeout: 6.0,
            reqCommand: { (taskId) in
                let danglerIds = danglers.compactMap { $0.replyToId }
                    .filter { postId in
                        Importer.shared.existingIds[postId] == nil && postId.range(of: ":") == nil // @TODO: <-- Workaround for aTag instead of e here, need to handle some other way
                    }
                
                if !danglerIds.isEmpty {
#if DEBUG
                    L.og.debug("☘️☘️ \(config.name) fetchParents: \(danglers.count.description), fetching.... -[LOG]-")
#endif
                    req(RM.getEvents(ids: danglerIds, subscriptionId: taskId)) // TODO: req or outboxReq?
                }
            },
            processResponseCommand: { (taskId, _, _) in
                bg().perform { [weak self] in
                    let danglingEvents = danglers.compactMap { $0.event }
#if DEBUG
                    L.og.debug("☘️☘️ \(config.name) fetchParents.processResponseCommand -[LOG]-")
#endif
                    
                    // Need to go to main context again to get current screen state
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let allIdsSeen = self.allIdsSeen
                        let currentIdsOnScreen = self.currentIdsOnScreen
                        let wotEnabled = config.wotEnabled
                        let repliesEnabled = config.repliesEnabled
                        
                        // Then back to bg for processing
                        bg().perform { [weak self] in
                            guard let self else { return }
#if DEBUG
                            L.og.debug("☘️☘️ \(config.name) fetchParents(.pubkeys)\(older ? "older" : "").processToScreen -[LOG]-")
#endif
                            self.processToScreen(danglingEvents, config: config, allIdsSeen: allIdsSeen, currentIdsOnScreen: currentIdsOnScreen, currentNRPostsOnScreen: currentNRPostsOnScreen, sinceOrUntil: sinceOrUntil, older: older, wotEnabled: wotEnabled, repliesEnabled: repliesEnabled)
                        }
                    }
                }
            },
            timeoutCommand: { (taskId) in
                bg().perform { [weak self]  in
                    let danglingEvents: [Event] = danglers.compactMap { $0.event }
#if DEBUG
                    L.og.debug("☘️☘️ \(config.name) fetchParents.timeoutCommand")
#endif
                    
                    // Need to go to main context again to get current screen state
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let allIdsSeen = self.allIdsSeen
                        let currentIdsOnScreen = self.currentIdsOnScreen
                        let wotEnabled = config.wotEnabled
                        let repliesEnabled = config.repliesEnabled
                        
                        // Then back to bg for processing
                        bg().perform { [weak self] in
                            guard let self else { return }
#if DEBUG
                            L.og.debug("☘️☘️ \(config.name) fetchParents(.pubkeys)\(older ? "older" : "").processToScreen (timeoutCommand)")
#endif
                            self.processToScreen(danglingEvents, config: config, allIdsSeen: allIdsSeen, currentIdsOnScreen: currentIdsOnScreen, currentNRPostsOnScreen: currentNRPostsOnScreen, sinceOrUntil: sinceOrUntil, older: older, wotEnabled: wotEnabled, repliesEnabled: repliesEnabled)
                        }
                    }

                }
            })

            self.backlog.add(danglingFetchTask)
            danglingFetchTask.fetch()
    }
    
    private var prefetchedIds: Set<String> = []
    
    // TODO: Add Debounce/Throttle here!
    @MainActor
    public func prefetch(_ post: NRPost) {
        guard SettingsStore.shared.fetchCounts && SettingsStore.shared.rowFooterEnabled else { return }
        
        if case .posts(let nrPosts) = viewState {
            guard let index = nrPosts.firstIndex(of: post) else { return }
            let before = max(index - 2, 0)
            let after = min(index + 2, nrPosts.count - 1)

            let rangeOfPostsIds = Array(nrPosts[before...after]).compactMap { post in
                if post.kind == 6 {
                    return post.firstQuoteId
                }
                return post.id
            }
            
            guard !rangeOfPostsIds.isEmpty else { return }
            
            let unfetchedIds = rangeOfPostsIds.filter { !self.prefetchedIds.contains($0) }
              
            guard !unfetchedIds.isEmpty else { return }
            fetchStuffForLastAddedNotes(ids: unfetchedIds)
            self.prefetchedIds = self.prefetchedIds.union(Set(unfetchedIds)) // TODO: need to LRU self.prefetchedIds
        }
    }
}

// -- MARK: POST RENDERING
extension NXColumnViewModel {
    
    // Primary function to put Events on screen
    // allIdsSeen must be prefix / .shortId format
    private func processToScreen(_ events: [Event], config: NXColumnConfig, allIdsSeen: Set<String>, currentIdsOnScreen: Set<String>, currentNRPostsOnScreen: [NRPost] = [], sinceOrUntil: Int, older: Bool, wotEnabled: Bool, repliesEnabled: Bool, completion: (() -> Void)? = nil) {
#if DEBUG
        L.og.debug("☘️☘️ \(config.name) processToScreen() -[LOG]-")
#endif
        // Apply WoT filter, remove already on screen
        let preparedEvents = prepareEvents(events, config: config, allIdsSeen: allIdsSeen, currentIdsOnScreen: currentIdsOnScreen, sinceOrUntil: sinceOrUntil, older: older, wotEnabled: wotEnabled, repliesEnabled: repliesEnabled)
        
        // Transform from Event to NRPost (only not already on screen by prev statement)
        let nrPosts: [NRPost] = self.transformToNRPosts(preparedEvents, config: config, currentIdsOnScreen: currentIdsOnScreen, currentNRPostsOnScreen: currentNRPostsOnScreen, repliesEnabled: repliesEnabled)
        
        // Turn loose NRPost replies into partial threads / leafs
        let partialThreads: [NRPost] = self.transformToPartialThreads(nrPosts, currentIdsOnScreen: currentIdsOnScreen)
        
        let (danglers, partialThreadsWithParent) = extractDanglingReplies(partialThreads)
        
        let newDanglers = danglers.filter { !self.danglingIds.contains($0.id) }
        if !newDanglers.isEmpty && repliesEnabled {
            danglingIds = danglingIds.union(newDanglers.map { $0.id })
            fetchParents(newDanglers, config: config, allIdsSeen: allIdsSeen, currentIdsOnScreen: currentIdsOnScreen, currentNRPostsOnScreen: currentNRPostsOnScreen, sinceOrUntil: sinceOrUntil, older: older)
        }
        
        guard !partialThreadsWithParent.isEmpty else {
            Task { @MainActor in
                if case .loading = viewState {
                    if speedTest.loadingBarViewState == .earlyLoad {
                        viewState = .timeout
                    }
                }
                completion?()
            }
            return
        }
        
        Task { @MainActor in
            self.putOnScreen(partialThreadsWithParent, config: config, insertAtEnd: older, completion: completion)
            
            #if DEBUG
            if availableWidth == nil {
                fatalError("availableWidth was never set, pls check")
            }
            #endif
        }
    }
    
    // -- MARK: Subfunctions used by processToScreen():
    
    // Prepare events: apply WoT filter, remove already on screen, load .parentEvents
    private func prepareEvents(_ events: [Event], config: NXColumnConfig, allIdsSeen: Set<String>, currentIdsOnScreen: Set<String>, sinceOrUntil: Int, older: Bool, wotEnabled: Bool, repliesEnabled: Bool) -> [Event] {
        shouldBeBg()
        let filteredEvents: [Event] = (wotEnabled ? applyWoT(events, config: config) : events) // Apply WoT filter or not
            .filter { // Apply (app wide) already-seen filter
                if $0.isRepost, let firstQuoteId = $0.firstQuoteId {
                    return !allIdsSeen.contains(String(firstQuoteId.prefix(8)))
                }
                return !allIdsSeen.contains($0.shortId)
            }
        
        let newUnrenderedEvents: [Event] = filteredEvents
            .filter { 
                if !older {
                    return $0.created_at > Int64(sinceOrUntil) // skip all older than first on screen (check LEAFS only)
                }
                else {
                    return Int64(sinceOrUntil) > $0.created_at // skip all newer than last on screen (check LEAFS only)
                }
            }
            .map {
                $0.parentEvents = !repliesEnabled ? [] : Event.getParentEvents($0, fixRelations: true)
                if repliesEnabled {
                    _ = $0.replyTo__
                }
                return $0
            }

        let newEventIds = getAllEventIds(newUnrenderedEvents)
        let newCount = newEventIds.subtracting(currentIdsOnScreen).count
        
        guard newCount > 0 else { return [] }
        
#if DEBUG
        L.og.debug("☘️☘️ \(config.name) prepareEvents newCount \(newCount.description) -[LOG]-")
#endif
        
        return newUnrenderedEvents
    }
    
    private func applyWoT(_ events: [Event], config: NXColumnConfig) -> [Event] {
        // if pubkeys feed, always show all the pubkeys
        if case .pubkeys(_) = config.columnType {
            return events
        }
        
        // if following feed, always show all the pubkeys
        if case .following(_) = config.columnType {
            return events // no need, hashtags are already filtered in RelayMessage.parseRelayMessage()
        }
        
        // if picture feed, always show all the pubkeys
        if case .picture(_) = config.columnType {
            return events // no need, hashtags are already filtered in RelayMessage.parseRelayMessage()
        }
        
        guard WOT_FILTER_ENABLED() else { return events }  // Return all if globally disabled
        
        if case .relays(_) = config.columnType {
            // if we are here, type is .relays, only filter if the feed specific WoT filter is enabled
            return events.filter { $0.inWoT }
        }
                
        return events
    }
    
    private func transformToNRPosts(_ events: [Event], config: NXColumnConfig, older: Bool = false, currentIdsOnScreen: Set<String>, currentNRPostsOnScreen: [NRPost], repliesEnabled: Bool) -> [NRPost] { // call from bg
        shouldBeBg()

        let transformedNrPosts = events
            // Don't transform again what is already on screen
            .filter { !currentIdsOnScreen.contains($0.id) }
            // transform Event to NRPost
            .map {
                NRPost(event: $0, withParents: repliesEnabled, withReplies: !repliesEnabled, withRepliesCount: true, cancellationId: $0.cancellationId)
            }
        
#if DEBUG
        L.og.debug("☘️☘️ \(config.name) transformToNRPosts currentIdsOnScreen: \(currentIdsOnScreen.count.description) transformedNrPosts: \(transformedNrPosts.count.description) -[LOG]-")
#endif
        
        return transformedNrPosts
    }
    
    private func transformToPartialThreads(_ nrPosts: [NRPost], currentIdsOnScreen: Set<String>) -> [NRPost] {
        shouldBeBg()
        
        let sortedByLongest = nrPosts.sorted(by: { $0.parentPosts.count > $1.parentPosts.count })

        var renderedIds = [String]()
        var renderedPosts = [NRPost]()
        for post in sortedByLongest {
            if post.isRepost && post.firstQuoteId != nil && renderedIds.contains(post.firstQuoteId!) {
                // Reposted post already on screen
                continue
            }
            guard !renderedIds.contains(post.id) else { continue } // Post is already on screen
            
            guard !post.isRepost else {
                // Render a repost, but track firstQuoteId instead of .id in renderedIds
                if let firstQuoteId = post.firstQuoteId {
                    renderedIds.append(firstQuoteId)
                    renderedIds.append(post.id)
                    renderedPosts.append(post)
                }
                continue
            }
            
            guard !post.parentPosts.isEmpty else {
                // Render a root post, that has no parents
                renderedIds.append(post.id)
                renderedPosts.append(post)
                continue
            }
            // render thread, truncated
            let truncatedPost = post
            // structure is: parentPosts: [root, reply, reply, reply, replyTo] post: ThisPost
            if let replyTo = post.parentPosts.last {
                // always keep at least 1 parent (replyTo)
                
                // keep parents until we have already seen one, don't traverse further
                var parentsKeep: [NRPost] = []
                
                // dropLast because we always add at least 1 reply back with: + [replyTo]
                for parent in post.parentPosts.dropLast(1).reversed() {
                    if !renderedIds.contains(parent.id) && !currentIdsOnScreen.contains(parent.id) {
                        parentsKeep.insert(parent, at: 0)
                    }
                    else {
                        break
                    }
                }
                // parentsKeep is now parentPosts with parents we have seen and older removed
                // so we don't have gaps like before when using just .filter { }
                
                truncatedPost.parentPosts = (parentsKeep + [replyTo]) // add back the replyTo, so we don't have dangling replies.
            }
            truncatedPost.threadPostsCount = 1 + truncatedPost.parentPosts.count
            truncatedPost.isTruncated = post.parentPosts.count > truncatedPost.parentPosts.count
            renderedIds.append(contentsOf: [truncatedPost.id] + truncatedPost.parentPosts.map { $0.id })
            renderedPosts.append(truncatedPost)
        }
        return renderedPosts
            .sorted(by: { $0.created_at > $1.created_at })
    }
    
    @MainActor
    public func putOnScreen(_ addedPosts: [NRPost], config: NXColumnConfig, insertAtEnd: Bool = false, completion: (() -> Void)? = nil) {
        
        if case .posts(let existingPosts) = viewState { // There are already posts on screen
            
            // Somehow we still have duplicates here that should have been filtered in prev steps (bug?) so filter duplicates again here
            let currentIdsOnScreen = existingPosts.map { $0.id }
            let onlyNewAddedPosts = addedPosts
                .filter { !currentIdsOnScreen.contains($0.id) }
                .uniqued(on: { $0.id }) // <--- need last line?
            
            if !insertAtEnd { // add on top
#if DEBUG
                L.og.debug("☘️☘️ \(config.name) putOnScreen isAtTop: \(self.vmInner.isAtTop) addedPosts (TOP) \(onlyNewAddedPosts.count.description) -> OLD FIRST: \((existingPosts.first?.content ?? "").prefix(150))")
#endif
   
                let addedAndExistingPosts = onlyNewAddedPosts + existingPosts
                
                // Truncate if needed (only if posts are inerted at the top)
                let dropCount = max(0, addedAndExistingPosts.count - FEED_MAX_VISIBLE) // Drop any above FEED_MAX_VISIBLE
                // But never drop the current first 10 so we can
                // - Add new at top, but keep scroll position by staying on current first (can't do that if its removed, we end up  scrolled to top bug)
                // - Also still make possible to scroll down a bit
                
                // So we need to keep: onlyNew+10, make sure when we .dropLast() it does not become less than that
                let notTooMuch = (addedAndExistingPosts.count - dropCount) > (onlyNewAddedPosts.count + 10)
                
                // also don't drop too little for performance
                let notTooLittle = dropCount > 5
                
                
                let addedAndExistingPostsTruncated = if vmInner.isAtTop && notTooLittle && notTooMuch {
                    Array(addedAndExistingPosts.dropLast(dropCount))
                }
                else {
                    addedAndExistingPosts
                }
                
                // Update unread count
                for post in onlyNewAddedPosts {
                    if vmInner.unreadIds[post.id] == nil {
                        vmInner.unreadIds[post.id] = 1 + post.parentPosts.count
                    }
                }
                
                if vmInner.isAtTop {
                    let previousFirstPostId: String? = existingPosts.first?.id
                    
                    // TODO: Should already start prefetching missing onlyNewAddedPosts pfp/kind 0 here

                    if SettingsStore.shared.autoScroll {
                        withAnimation { // withAnimation won't keep scroll position and scrolls to newest post
                            viewState = .posts(addedAndExistingPostsTruncated)
                        }
                    }
                    else {
                        #if DEBUG
                        L.og.debug("☘️☘️📜 \(config.name) putOnScreen isAtTop: \(self.vmInner.isAtTop) - should restore using scrollToIndex, if we were not at top ")
                        #endif
                        
                        // ANTI-FLICKER:
                        if let previousFirstPostId, let restoreToIndex = addedAndExistingPostsTruncated.firstIndex(where: { $0.id == previousFirstPostId })  {
                            // Signal that we're about to update with new posts that will need scroll restoration
                            vmInner.isPreparingForScrollRestore = true
                            
                            // Store the target index for later use
                            vmInner.pendingScrollToIndex = restoreToIndex
                            
                            // Update the view state without animation
                            viewState = .posts(addedAndExistingPostsTruncated)
                            
                            // Set isAtTop to false since we'll be scrolling to a non-top position
                            vmInner.isAtTop = false
                            
                            #if DEBUG
                            L.og.debug("☘️☘️ \(config.name) putOnScreen restoreToIndex: \((addedAndExistingPostsTruncated[restoreToIndex].content ?? "").prefix(150))")
                            #endif
                            
                            // After a very short delay, trigger the scroll
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                                self.vmInner.scrollToIndex = restoreToIndex
                                
                                // Reset the preparation flag after a delay
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    self.vmInner.isPreparingForScrollRestore = false
                                    self.vmInner.pendingScrollToIndex = nil
                                }
                            }
                        }
                        else {
                            self.vmInner.isPreparingForScrollRestore = false
                            self.vmInner.pendingScrollToIndex = nil
                            // No previous post to restore to, just update the view
                            viewState = .posts(addedAndExistingPostsTruncated)
                        }
                    }
                }
                else {
                    self.vmInner.isPreparingForScrollRestore = false
                    self.vmInner.pendingScrollToIndex = nil
                    #if DEBUG
                    L.og.debug("☘️☘️📜 \(config.name) putOnScreen isAtTop: \(self.vmInner.isAtTop) withAnimation { }  + not at top, to keep scroll pos ")
                    #endif
                    withAnimation { // withAnimation and not at top keeps scroll position
                        viewState = .posts(addedAndExistingPostsTruncated)
                    }
                }
            }
            else { // add below
#if DEBUG
                L.og.debug("☘️☘️ \(config.name) putOnScreen addedPosts (AT END) \(onlyNewAddedPosts.count.description)")
#endif
                
                self.vmInner.isPreparingForScrollRestore = false
                self.vmInner.pendingScrollToIndex = nil
                
                // No withAnimation { } at bottom or it will jump?
                self.viewState = .posts(existingPosts + onlyNewAddedPosts)
            }
        }
        else { // Nothing on screen yet, put first posts on screen
            let uniqueAddedPosts = addedPosts.uniqued(on: { $0.id })
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) putOnScreen addedPosts (💦FIRST💦) \(uniqueAddedPosts.count.description) - \((uniqueAddedPosts.first?.content ?? "").prefix(150))")
#endif
            if !vmInner.isAtTop {
                vmInner.isAtTop = true
            }
            vmInner.isPreparingForScrollRestore = false
            vmInner.pendingScrollToIndex = nil
            withAnimation {
                viewState = .posts(uniqueAddedPosts)
            }
        }
        
        completion?()
        didFinish()
    }
    
    // -- MARK: Helpers
    
    @MainActor
    private func getAllPostIds(_ nrPosts: [NRPost], prefixOnly: Bool = false) -> Set<String> {
        return nrPosts.reduce(Set<NRPostID>()) { partialResult, nrPost in
            if nrPost.isRepost, let firstQuoteId = nrPost.firstQuoteId {
                // for repost add post + reposted post
                return prefixOnly
                    ? partialResult.union(Set([nrPost.shortId, String(firstQuoteId.prefix(8))]))
                    : partialResult.union(Set([nrPost.id, firstQuoteId]))
            } else {
                return prefixOnly
                        ? partialResult.union(Set([nrPost.shortId] + nrPost.parentPosts.map { $0.shortId }))
                        : partialResult.union(Set([nrPost.id] + nrPost.parentPosts.map { $0.id }))
            }
        }
    }
    
    private func getAllEventIds(_ events: [Event]) -> Set<String> {
        return events.reduce(Set<String>()) { partialResult, event in
            if event.isRepost, let firstQuoteId = event.firstQuoteId {
                // for repost add post + reposted post
                return partialResult.union(Set([event.id, firstQuoteId]))
            }
            else {
                return partialResult.union(Set([event.id] + event.parentEvents.map { $0.id }))
            }
        }
    }
}

// -- MARK: PUBKEYS
extension NXColumnViewModel {
    
    @MainActor
    private func loadRemote(_ config: NXColumnConfig) {
        
        speedTest.firstFetchStarted()
        
        #if DEBUG
        L.og.debug("☘️☘️ \(config.name) loadRemote(config)")
        #endif
        
        switch config.columnType {
        case .relays(let feed):
            let relays = feed.relaysData
            guard !relays.isEmpty else {
                viewState = .error("No relays selected for this custom feed")
                return
            }
            let instantFeed = InstantFeed()
            self.instantFeed = instantFeed
            let mostRecentCreatedAt = self.mostRecentCreatedAt ?? 0
            let wotEnabled = config.wotEnabled
            let repliesEnabled = config.repliesEnabled
            
            bg().perform { [weak self] in
                instantFeed.start(relays, since: mostRecentCreatedAt) { [weak self] events in
                    guard let self, events.count > 0 else {
                        self?.speedTest.relayTimedout()
                        Task { @MainActor in
                            if case .loading = self?.viewState {
                                self?.viewState = .timeout
                            }
                        }
                        return
                    }
                    
                    speedTest.relayFinished()
                    
                    // TODO: Check if we still hit .fetchLimit problem here
#if DEBUG
                    L.og.debug("☘️☘️ \(config.name) loadRemoteRelays() instantFeed.onComplete events.count \(events.count.description)")
#endif
                    
                    // Need to go to main context again to get current screen state
                    Task { @MainActor in
                        self.allIdsSeen = self.allIdsSeen.union(Set(feed.lastRead))
                        let allIdsSeen = self.allIdsSeen
                        let currentIdsOnScreen = self.currentIdsOnScreen
                        let since = (self.mostRecentCreatedAt ?? 0)
                        
                        // Then back to bg for processing
                        bg().perform { [weak self] in
                            self?.processToScreen(events, config: config, allIdsSeen: allIdsSeen, currentIdsOnScreen: currentIdsOnScreen, sinceOrUntil: since, older: false, wotEnabled: wotEnabled, repliesEnabled: repliesEnabled)
                        }
                    }
                }
            }
        default:
            // Fetch since 5 minutes before most recent item on screen (since) or .refeshedAt
            let sinceTimestamp = if case .posts(let nrPosts) = viewState {
                (nrPosts.first?.created_at ?? self.refreshedAt) - Int64(300)
            }
            else { // or if empty screen: refreshedAt (since)
                self.refreshedAt
            }
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) loadRemote.fetchGap: since: \(sinceTimestamp) currentGap: 0 -[LOG]-")
#endif
            // Don't go older than 24 hrs ago
            let maxAgo = Int64(Date().addingTimeInterval(-86_400).timeIntervalSince1970)
            
            self.gapFiller?.fetchGap(since: max(sinceTimestamp, maxAgo), currentGap: 0)
            
//            fetchProfiles(config) // No need? we already fetch kind 0 with 1,5,6 etc...
        }
    }
    
    private func fetchProfiles(_ config: NXColumnConfig) {
        guard let feed = config.feed else { return }
        let since: Int? = if let profilesFetchedAt = feed.profilesFetchedAt {
            Int(profilesFetchedAt.timeIntervalSince1970)
        }
        else {
            nil
        }
        
        let pubkeys: Set<String> = switch config.columnType {
        case .following(let feed), .picture(let feed):
            (feed.account?.followingPubkeys
                .union(Set([feed.account!.publicKey]))
                .union(feed.account!.privateFollowingPubkeys)) ?? []
        case .pubkeys(let feed):
            feed.contactPubkeys
        case .someoneElses(_):
            config.pubkeys
        default:
            []
        }
        
        guard !pubkeys.isEmpty else {
            L.fetching.debug("not checking profiles, pubkeys isEmpty")
            return
        }
        
        L.fetching.info("checking profiles since: \(since?.description ?? "")")
        
        let subscriptionId = "Profiles-" + feed.subscriptionId
        ConnectionPool.shared
            .sendMessage(
                NosturClientMessage(
                    clientMessage: NostrEssentials.ClientMessage(
                        type: .REQ,
                        subscriptionId: subscriptionId,
                        filters: [Filters(authors: pubkeys, kinds: [0], since: since)]
                    ),
                    relayType: .READ
                ),
                subscriptionId: subscriptionId
            )
        feed.profilesFetchedAt = .now
    }
}

// -- MARK: SOMEONE ELSES FEED
extension NXColumnViewModel {
    @MainActor
    public func fetchKind3ForSomeoneElsesFeed(_ pubkey: String, config: NXColumnConfig, completion: @escaping (NXColumnConfig) -> Void) {
        let getContactListTask = ReqTask(
            prio: true,
            reqCommand: { taskId in
                L.og.notice("🟪 Fetching clEvent from relays")
                req(RM.getAuthorContactsList(pubkey: pubkey, subscriptionId: taskId))
            },
            processResponseCommand: { taskId, _, clEvent in
                bg().perform {
                    L.og.notice("🟪 Processing clEvent response from relays")
                    var updatedConfig = config
                    if let clEvent = clEvent {
                        updatedConfig.setPubkeys(Set(clEvent.fastPs.map { $0.1 }.filter { isValidPubkey($0) }))
                        
                        updatedConfig.setHashtags(Set(clEvent.fastTs.map { $0.1.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }))
    
                        Task { @MainActor in
                            completion(updatedConfig)
                        }
                    }
                    else if let clEvent = Event.fetchReplacableEvent(3, pubkey: pubkey, context: bg()) {
                        updatedConfig.setPubkeys(Set(clEvent.fastPs.map { $0.1 }.filter { isValidPubkey($0) }))
                        
                        updatedConfig.setHashtags(Set(clEvent.fastTs.map { $0.1.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }))
    
                        Task { @MainActor in
                            completion(updatedConfig)
                        }
                    }
                }
            },
            timeoutCommand: { taskId in
                bg().perform {
                    if let clEvent = Event.fetchReplacableEvent(3, pubkey: pubkey, context: bg()) {
                        var updatedConfig = config
                        updatedConfig.setPubkeys(Set(clEvent.fastPs.map { $0.1 }.filter { isValidPubkey($0) }))
                        
                        updatedConfig.setHashtags(Set(clEvent.fastTs.map { $0.1.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }))
    
                        Task { @MainActor in
                            completion(updatedConfig)
                        }
                    }
                }
            }
        )
        Backlog.shared.add(getContactListTask)
        getContactListTask.fetch()
    }
}

// -- MARK: SCROLLING
extension NXColumnViewModel {
    
    @MainActor
    public func scrollToFirstUnread() {
        if case .posts(let nrPosts) = viewState {
            for post in (nrPosts).reversed() {
                if let unreadCount = vmInner.unreadIds[post.id], unreadCount > 0 {
                    if let firstUnreadIndex = nrPosts.firstIndex(where: { $0.id == post.id }) {
                        DispatchQueue.main.async {
                            self.vmInner.objectWillChange.send()
                            self.vmInner.scrollToIndex = firstUnreadIndex
                        }
                    }
                }
            }
        }
    }
    
    @MainActor
    public func scrollToTop() {
        DispatchQueue.main.async {
            self.vmInner.objectWillChange.send()
            self.vmInner.scrollToIndex = 0
        }
    }
    
    @MainActor
    public func loadMoreWhenNearBottom(_ config: NXColumnConfig) {
        guard onAppearSubjectSub == nil else { return }
        onAppearSubjectSub = onAppearSubject
            .debounce(for: 0.2, scheduler: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] lastCreatedAt in
                
#if DEBUG
                L.og.debug("☘️☘️ \(config.name) loadMoreWhenNearBottom.onAppearSubject lastCreatedAt \(lastCreatedAt)")
#endif
                self?.loadLocal(config, older: true) {
                    self?.sendNextPageReq(config, until: Int64(self?.oldestCreatedAt ?? Int(Date().timeIntervalSince1970)))
                }
            }
    }
}

enum ColumnViewState {
    case loading
    case posts([NRPost]) // Posts
    case timeout
    case error(String)
}

let FETCH_FEED_INTERVAL = 9.0
let FEED_MAX_VISIBLE: Int = 20

func fetchFollowingFeedKinds() -> Set<Int> {
    if UserDefaults.standard.bool(forKey: "enable_picture_feed") {
        return FETCH_FOLLOWING_KINDS.subtracting([20])
    }
    return FETCH_FOLLOWING_KINDS
}

func pubkeyOrHashtagReqFilters(_ pubkeys: Set<String>, hashtags: Set<String>, since: Int? = nil, until: Int? = nil, limit: Int = 5000, kinds: Set<Int>) -> [Filters] {
    guard !pubkeys.isEmpty || !hashtags.isEmpty else { return [] }
    
    var filters: [Filters] = []
    
    if !pubkeys.isEmpty {
        let followingContactsFilter = Filters(
            authors: pubkeys,
            kinds: kinds,
            since: since, until: until, limit: limit)
        
        filters.append(followingContactsFilter)
    }
    
    if !hashtags.isEmpty {
        let followingHashtagsFilter = Filters(
            kinds: kinds,
            tagFilter: TagFilter(tag: "t", values: Array(hashtags).map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }),
            since: since, until: until, limit: limit)
        filters.append(followingHashtagsFilter)
    }
    
    return filters
}

func globalFeedReqFilters(since: Int? = nil, until: Int? = nil, limit: Int = 5000) -> [Filters] {
    return [Filters(kinds: FETCH_GLOBAL_KINDS,
                    since: since, until: until, limit: limit )]
}

// Return replies without parents seperataly
func extractDanglingReplies(_ nrPosts: [NRPost]) -> (danglers: [NRPost], threads: [NRPost]) {
    shouldBeBg()
    var danglers: [NRPost] = []
    var threads: [NRPost] = []
    nrPosts.forEach { nrPost in
        if (nrPost.replyToRootId != nil || nrPost.replyToId != nil) && nrPost.parentPosts.isEmpty {
            danglers.append(nrPost)
        }
        else {
            threads.append(nrPost)
        }
    }
    return (danglers: danglers, threads: threads)
}

func makeHashtagRegex(_ hashtags: Set<String>) -> String? {
    if !hashtags.isEmpty {
        let regex = ".*(" + hashtags.map {
            NSRegularExpression.escapedPattern(for: serializedT($0))
        }.joined(separator: "|") + ").*"
        return regex
    }
    
    return nil
}


// From old LVM code, need to refactor:

typealias CM = NostrEssentials.ClientMessage

let FETCH_GLOBAL_KINDS: Set<Int> = [1,5,6,20,9802,30023,34235]
let FETCH_FOLLOWING_KINDS: Set<Int> = [0,1,5,6,20,9802,30023,34235,30311,10002]
let QUERY_FOLLOWING_KINDS: Set<Int> = [1,6,20,9802,30023,34235]
let QUERY_FETCH_LIMIT = 50 // Was 25 before, but seems we are missing posts, maybe too much non WoT-hashtag coming back. Increase limit or split query? or could be the time cutoff is too short/strict


import CoreData

// LVM pubkeys
extension Event {
    
    // TODO: Optimize tagsSerialized / hashtags matching
    static func postsByPubkeys(_ pubkeys: Set<String>, mostRecent: Event, hideReplies: Bool = false, hashtagRegex:String? = nil, kinds: Set<Int>) -> NSFetchRequest<Event> {
        let blockedPubkeys = blocks()
        let cutOffPoint = mostRecent.created_at - 900
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        fr.fetchLimit = QUERY_FETCH_LIMIT
        if let hashtagRegex = hashtagRegex {
            if hideReplies {
                fr.predicate = NSPredicate(format: "created_at >= %i AND kind IN %@ AND NOT pubkey IN %@ AND (pubkey IN %@ OR tagsSerialized MATCHES %@) AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\"", cutOffPoint, kinds, blockedPubkeys, pubkeys, hashtagRegex)
            }
            else {
                fr.predicate = NSPredicate(format: "created_at >= %i AND kind IN %@ AND NOT pubkey IN %@ AND (pubkey IN %@ OR tagsSerialized MATCHES %@) AND flags != \"is_update\"", cutOffPoint, kinds, blockedPubkeys, pubkeys, hashtagRegex)
            }
        }
        else {
            if hideReplies {
                fr.predicate = NSPredicate(format: "created_at >= %i AND pubkey IN %@ AND kind IN %@ AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffPoint,  pubkeys, kinds, blockedPubkeys)
            }
            else {
                fr.predicate = NSPredicate(format: "created_at >= %i AND pubkey IN %@ AND kind IN %@ AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffPoint, pubkeys, kinds, blockedPubkeys)
            }
        }
        return fr
    }
    
    
    static func postsByPubkeys(_ pubkeys: Set<String>, until: Event, hideReplies: Bool = false, hashtagRegex: String? = nil, kinds: Set<Int>) -> NSFetchRequest<Event> {
        let blockedPubkeys = blocks()
        let cutOffPoint = until.created_at + 60
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        fr.fetchLimit = QUERY_FETCH_LIMIT
        if let hashtagRegex = hashtagRegex {
            
            let after = until.created_at - 28_800 // we need just 25 posts, so don't scan too far back, the regex match on tagsSerialized seems slow
            
            if hideReplies {
                fr.predicate = NSPredicate(format: "created_at > %i AND created_at <= %i AND kind IN %@ AND NOT pubkey IN %@ AND (pubkey IN %@ OR tagsSerialized MATCHES %@) AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\"", after, cutOffPoint, kinds, blockedPubkeys, pubkeys, hashtagRegex)
            }
            else {
                fr.predicate = NSPredicate(format: "created_at > %i AND created_at <= %i AND kind IN %@ AND NOT pubkey IN %@ AND (pubkey IN %@ OR tagsSerialized MATCHES %@) AND flags != \"is_update\"", after, cutOffPoint, kinds, blockedPubkeys, pubkeys, hashtagRegex)
            }
        }
        else {
            if hideReplies {
                fr.predicate = NSPredicate(format: "created_at <= %i AND pubkey IN %@ AND kind IN %@ AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffPoint, pubkeys, kinds, blockedPubkeys)
            }
            else {
                fr.predicate = NSPredicate(format: "created_at <= %i AND pubkey IN %@ AND kind IN %@ AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffPoint, pubkeys, kinds, blockedPubkeys)
            }
        }
        return fr
    }
    
    static func postsByPubkeys(_ pubkeys: Set<String>, lastAppearedCreatedAt: Int64 = 0, hideReplies: Bool = false, hashtagRegex: String? = nil, kinds: Set<Int>) -> NSFetchRequest<Event> {
        let blockedPubkeys = blocks()
        let hoursAgo = Int64(Date.now.timeIntervalSince1970) - 28_800 // 8 hours ago
        
        // Take oldest timestamp: 8 hours ago OR lastAppearedCreatedAt
        // if we don't have lastAppearedCreatedAt. Take 8 hours ago
        let cutOffPoint = lastAppearedCreatedAt == 0 ? hoursAgo : min(lastAppearedCreatedAt, hoursAgo)
        
        // get 15 events before lastAppearedCreatedAt (or 8 hours ago, if we dont have it)
        let frBefore = Event.fetchRequest()
        frBefore.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        frBefore.fetchLimit = QUERY_FETCH_LIMIT
        if let hashtagRegex = hashtagRegex {
            if hideReplies {
                frBefore.predicate = NSPredicate(format: "created_at <= %i AND kind IN %@ AND NOT pubkey IN %@ AND (pubkey IN %@ OR tagsSerialized MATCHES %@) AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\"", cutOffPoint, kinds, blockedPubkeys, pubkeys, hashtagRegex)
            }
            else {
                frBefore.predicate = NSPredicate(format: "created_at <= %i AND kind IN %@ AND NOT pubkey IN %@ AND (pubkey IN %@ OR tagsSerialized MATCHES %@) AND flags != \"is_update\"", cutOffPoint, kinds, blockedPubkeys, pubkeys, hashtagRegex)
            }
        }
        else {
            if hideReplies {
                frBefore.predicate = NSPredicate(format: "created_at <= %i AND pubkey IN %@ AND kind IN %@ AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffPoint, pubkeys, kinds, blockedPubkeys)
            }
            else {
                frBefore.predicate = NSPredicate(format: "created_at <= %i AND pubkey IN %@ AND kind IN %@ AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffPoint, pubkeys, kinds, blockedPubkeys)
            }
        }
        
        let newFirstEvent = try? bg().fetch(frBefore).last
        
        let newCutOffPoint = newFirstEvent != nil ? newFirstEvent!.created_at : cutOffPoint
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        fr.fetchLimit = QUERY_FETCH_LIMIT
        if hideReplies {
            fr.predicate = NSPredicate(format: "created_at >= %i AND pubkey IN %@ AND kind IN %@ AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\" AND NOT pubkey IN %@", newCutOffPoint, pubkeys, kinds, blockedPubkeys)
        }
        else {
            fr.predicate = NSPredicate(format: "created_at >= %i AND pubkey IN %@ AND kind IN %@ AND flags != \"is_update\" AND NOT pubkey IN %@", newCutOffPoint,  pubkeys, kinds, blockedPubkeys)
        }
        return fr
    }
    
    static func postsByPubkeys(_ pubkeys: Set<String>, until cutOffPoint: Int64 = Int64(Date().timeIntervalSince1970), hideReplies: Bool = false, hashtagRegex: String? = nil, kinds: Set<Int>) -> NSFetchRequest<Event> {
        let blockedPubkeys = blocks()
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        fr.fetchLimit = QUERY_FETCH_LIMIT
        if let hashtagRegex = hashtagRegex {
            
            let after = cutOffPoint - 28_800 // we need just 25 posts, so don't scan too far back, the regex match on tagsSerialized seems slow
            
            if hideReplies {
                fr.predicate = NSPredicate(format: "created_at > %i AND created_at <= %i AND kind IN %@ AND NOT pubkey IN %@ AND (pubkey IN %@ OR tagsSerialized MATCHES %@) AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\"", after, cutOffPoint, kinds, blockedPubkeys, pubkeys, hashtagRegex)
            }
            else {
                fr.predicate = NSPredicate(format: "created_at > %i AND created_at <= %i AND kind IN %@ AND NOT pubkey IN %@ AND (pubkey IN %@ OR tagsSerialized MATCHES %@) AND flags != \"is_update\"", after, cutOffPoint, kinds, blockedPubkeys, pubkeys, hashtagRegex)
            }
        }
        else {
            if hideReplies {
                fr.predicate = NSPredicate(format: "created_at <= %i AND pubkey IN %@ AND kind IN %@ AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffPoint, pubkeys, kinds, blockedPubkeys)
            }
            else {
                fr.predicate = NSPredicate(format: "created_at <= %i AND pubkey IN %@ AND kind IN %@ AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffPoint, pubkeys, kinds, blockedPubkeys)
            }
        }
        return fr
    }
}

// LVM relays
extension Event {
    
    static func postsByRelays(_ relays: Set<RelayData>, mostRecent: Event, hideReplies: Bool = false, fetchLimit: Int = 50, kinds: Set<Int>) -> NSFetchRequest<Event> {
        let blockedPubkeys = blocks()
        let regex = "(" + relays.compactMap { $0.url }.map {
            NSRegularExpression.escapedPattern(for: $0)
        }.joined(separator: "|") + ")"
        let cutOffPoint = mostRecent.created_at - 900
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        
        // Increased fetchLimit for Relays feed so there are enough events after applying inWoT filter
        fr.fetchLimit = fetchLimit // TODO: Should apply WoT on message parser / receive, before adding to adding to database
        if hideReplies {
            fr.predicate = NSPredicate(format: "created_at >= %i AND kind IN %@ AND relays MATCHES %@ AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffPoint, kinds, regex, blockedPubkeys)
        }
        else {
            fr.predicate = NSPredicate(format: "created_at >= %i AND kind IN %@ AND relays MATCHES %@ AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffPoint, kinds, regex, blockedPubkeys)
        }
        return fr
    }
    
    
    static func postsByRelays(_ relays: Set<RelayData>, until: Event, hideReplies: Bool = false, fetchLimit: Int = 50, kinds: Set<Int>) -> NSFetchRequest<Event> {
        let blockedPubkeys = blocks()
        let regex = "(" + relays.compactMap { $0.url }.map {
            NSRegularExpression.escapedPattern(for: $0)
        }.joined(separator: "|") + ")"
        let cutOffPoint = until.created_at + 60
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]

        // Increased fetchLimit for Relays feed so there are enough events after applying inWoT filter
        fr.fetchLimit = fetchLimit // TODO: Should apply WoT on message parser / receive, before adding to adding to database
        
        if hideReplies {
            fr.predicate = NSPredicate(format: "created_at <= %i AND kind IN %@ AND relays MATCHES %@ AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffPoint, kinds, regex, blockedPubkeys)
        }
        else {
            fr.predicate = NSPredicate(format: "created_at <= %i AND kind IN %@ AND relays MATCHES %@ AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffPoint, kinds, regex, blockedPubkeys)
        }
        return fr
    }
    
    static func postsByRelays(_ relays: Set<RelayData>, lastAppearedCreatedAt: Int64 = 0, hideReplies: Bool = false, fetchLimit: Int = 50, force: Bool = false, kinds: Set<Int>) -> NSFetchRequest<Event> {
        let blockedPubkeys = blocks()
        let regex = "(" + relays.compactMap { $0.url }.map {
            NSRegularExpression.escapedPattern(for: $0)
        }.joined(separator: "|") + ")"
        let hoursAgo = Int64(Date.now.timeIntervalSince1970) - 28_800 // 8 hours ago
        
        // Take oldest timestamp: 8 hours ago OR lastAppearedCreatedAt
        // if we don't have lastAppearedCreatedAt. Take 8 hours ago
        let cutOffPoint = lastAppearedCreatedAt == 0 ? hoursAgo : min(lastAppearedCreatedAt, hoursAgo)
        
        // get 50 events before lastAppearedCreatedAt (or 8 hours ago, if we dont have it)
        let frBefore = Event.fetchRequest()
        frBefore.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        
        // Increased fetchLimit for Relays feed so there are enough events after applying inWoT filter
        frBefore.fetchLimit = fetchLimit // TODO: Should apply WoT on message parser / receive, before adding to adding to database
        
        if hideReplies {
            frBefore.predicate = NSPredicate(format: "created_at <= %i AND kind IN %@ AND NOT pubkey IN %@ AND relays MATCHES %@ AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\"", cutOffPoint, kinds, blockedPubkeys, regex)
        }
        else {
            frBefore.predicate = NSPredicate(format: "created_at <= %i AND kind IN %@ AND NOT pubkey IN %@ AND relays MATCHES %@ AND flags != \"is_update\"", cutOffPoint, kinds, blockedPubkeys, regex)
        }
        
        let newFirstEvent = try? bg().fetch(frBefore).last
        
        let newCutOffPoint = newFirstEvent != nil ? newFirstEvent!.created_at : cutOffPoint
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        
        // Increased fetchLimit for Relays feed so there are enough events after applying inWoT filter
        fr.fetchLimit = fetchLimit // TODO: Should apply WoT on message parser / receive, before adding to adding to database
        
        if hideReplies {
            fr.predicate = !force
                ? NSPredicate(format: "created_at >= %i AND kind IN %@ AND relays MATCHES %@ AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\"", newCutOffPoint, kinds, regex)
                : NSPredicate(format: "kind IN %@ AND relays MATCHES %@ AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\"", kinds, regex)
        }
        else {
            fr.predicate = !force
                ? NSPredicate(format: "created_at >= %i AND kind IN %@ AND relays MATCHES %@ AND flags != \"is_update\"", newCutOffPoint, kinds, regex)
                : NSPredicate(format: "kind IN %@ AND relays MATCHES %@ AND flags != \"is_update\"", kinds, regex)
        }
        return fr
    }
    
    
    static func postsByRelays(_ relays: Set<RelayData>, until cutOffPoint: Int64 = Int64(Date().timeIntervalSince1970), hideReplies: Bool = false, fetchLimit: Int = 50, kinds: Set<Int>) -> NSFetchRequest<Event> {
        let blockedPubkeys = blocks()
        let regex = "(" + relays.compactMap { $0.url }.map {
            NSRegularExpression.escapedPattern(for: $0)
        }.joined(separator: "|") + ")"
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]

        // Increased fetchLimit for Relays feed so there are enough events after applying inWoT filter
        fr.fetchLimit = fetchLimit // TODO: Should apply WoT on message parser / receive, before adding to adding to database
        
        if hideReplies {
            fr.predicate = NSPredicate(format: "created_at <= %i AND kind IN %@ AND relays MATCHES %@ AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffPoint, kinds, regex, blockedPubkeys)
        }
        else {
            fr.predicate = NSPredicate(format: "created_at <= %i AND kind IN %@ AND relays MATCHES %@ AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffPoint, kinds, regex, blockedPubkeys)
        }
        return fr
    }
}

func notMutedWords(in text: String, mutedWords: [String]) -> Bool {
    return mutedWords.first(where: { text.localizedCaseInsensitiveContains($0) }) == nil
}

func notMuted(_ nrPost: NRPost) -> Bool {
    let mutedRootIds: Set<String> = CloudBlocked.mutedRootIds()
    return !mutedRootIds.contains(nrPost.id) && !mutedRootIds.contains(nrPost.replyToRootId ?? "NIL") && !mutedRootIds.contains(nrPost.replyToId ?? "NIL")
}



func threadCount(_ nrPosts: [NRPost]) -> Int {
    nrPosts.reduce(0) { partialResult, nrPost in
        (partialResult + nrPost.threadPostsCount) //  Data race in Nostur.NRPost.threadPostsCount.setter : Swift.Int at 0x10fbe9680 - thread 1
    }
}

struct NewPubkeysForList {
    var subscriptionId: String
    var pubkeys: Set<String>
}

struct NewRelaysForList {
    var subscriptionId: String
    var relays: Set<RelayData>
    var wotEnabled: Bool
}
