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
    
    // "Following" / "List-56D5EE90-17CB-4925" / ...
    public var id: String? { config?.id }
    public var config: NXColumnConfig?
    private var account: CloudAccount?
    
    private var startTime: Date? {
        didSet {
            finishTime = nil
        }
    }
    @Published private var finishTime: Date?
    
    var loadTime: TimeInterval? {
        guard let startTime, let finishTime else { return nil }
        return finishTime.timeIntervalSince(startTime)
    }
    
    var formattedLoadTime: String {
        guard let loadTime else { return "-" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: loadTime)) ?? "-"
    }
    
    private func didFinish() {
        if finishTime == nil {
            finishTime = .now
        }
    }
    
    @Published var viewState: ColumnViewState = .loading {
        didSet {
            if case .posts(let nrPosts) = viewState, nrPosts.isEmpty {
                unreadIds = [:]
            }
        }
    }
    @Published var scrollToIndex: Int?
    
    // During scrolling, don't put new posts on screen, use Delayur helper
    private var delayur: NXDelayur?
    private var haltedProcessing: Bool {
        set {
            if newValue {
                if delayur == nil { delayur = NXDelayur() }
                delayur?.setDelayur(true, seconds: 2.5) { [weak self] in
                    self?.resumeProcessing()
                }
            }
            else {
                delayur?.setDelayur(false)
            }
        }
        get {
            delayur?.isDelaying ?? false
        }
    }
    
    @MainActor
    public func haltProcessing() {
        guard let config else { return }
#if DEBUG
        L.og.debug("☘️☘️ \(config.id) haltProcessing")
#endif
        haltedProcessing = true
    }
    
    private func resumeProcessing() {
        guard let config else { return }
#if DEBUG
        L.og.debug("☘️☘️ \(config.id) resumeProcessing")
#endif
        // Will trigger listenForNewPosts() with maybe subscriptionIds still in queue
        resumeSubject.send(Set())
    }
    
    @Published var unreadIds: [String: Int] = [:] { // Dict of [post id: posts count (post + parent posts)]
        didSet {
            if unreadCount == 0 {
                if !isAtTop {
                    isAtTop = true
                }
            }
        }
    }
    private var danglingIds: Set<NRPostID> = [] // posts that are transformed, but somehow not on screen (maybe not found on relays). either we put on on screen or not, dont transform over and over again.
    
    public var unreadCount: Int {
        unreadIds.reduce(0, { $0 + $1.value })
    }
    
    public var isVisible: Bool = false {
        didSet {
            guard let config else { return }
            if isVisible {
                if case .loading = viewState {
                    Task { @MainActor in
                        self.load(config)
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
    @Published public var isAtTop: Bool = true {
        didSet {
#if DEBUG
            guard let config else { return }
            L.og.debug("☘️☘️ \(config.id) isAtTop: \(self.isAtTop)")
#endif
        }
    }
    private var fetchFeedTimer: Timer? = nil
    private var newEventsInDatabaseSub: AnyCancellable?
    private var firstConnectionSub: AnyCancellable?
    private var lastDisconnectionSub: AnyCancellable?
    private var watchForFirstConnection = false
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
            guard let config else { // 7 days ago if config is somehow missing
                return (Int64(Date().timeIntervalSince1970) - (7 * 3600 * 24))
            }
            
            switch config.columnType {
            case .following(let feed):
                if let refreshedAt = feed.refreshedAt { // 5 minutes before last refreshedAt
                    return Int64(refreshedAt.timeIntervalSince1970) - (5 * 60)
                }
                else if let mostRecentCreatedAt = self.mostRecentCreatedAt {
                   return Int64(mostRecentCreatedAt) // or most recent on screen
                }
            case .pubkeys(let feed):
                if let refreshedAt = feed.refreshedAt { // 5 minutes before last refreshedAt
                    return Int64(refreshedAt.timeIntervalSince1970) - (5 * 60)
                }
                else if let mostRecentCreatedAt = self.mostRecentCreatedAt {
                   return Int64(mostRecentCreatedAt) // or most recent on screen
                }
            case .relays(_): // 8 hours
                if let mostRecentCreatedAt = self.mostRecentCreatedAt {
                   return Int64(mostRecentCreatedAt) // or most recent on screen
                }
                return (Int64(Date().timeIntervalSince1970) - (8 * 3600))
            default:
                if let mostRecentCreatedAt = self.mostRecentCreatedAt {
                   return Int64(mostRecentCreatedAt) // or most recent on screen
                }
                // else take 8 hours?
                return (Int64(Date().timeIntervalSince1970) - (8 * 3600))
            }
            if let mostRecentCreatedAt = self.mostRecentCreatedAt {
               return Int64(mostRecentCreatedAt) // or most recent on screen
            }
            // else take 7 days
            return (Int64(Date().timeIntervalSince1970) - (7 * 3600 * 24))
        }
        set {
            guard let config else { return }
            switch config.columnType {
            case .following(let feed):
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

    @MainActor
    public func load(_ config: NXColumnConfig) {
        self.config = config
        if !ConnectionPool.shared.anyConnected {
            self.watchForFirstConnection = true
        }
        guard isVisible || (config.id.starts(with: "Following-") && config.name != "Explore") else { return }
        gapFiller = NXGapFiller(since: self.refreshedAt, windowSize: 4, timeout: 2.0, currentGap: 0, columnVM: self)
        startTime = .now
        startFetchFeedTimer()
        loadLocal(config) { [weak self] in // <-- instant, and works offline
         // callback to load remote
            self?.loadRemote(config) // <--- fetch new posts (catch up)
        }
        listenForNewPosts(config: config) // <-- listen realtime for new posts  TODO: maybe do after 2 second delay?
        listenForFirstConnection(config: config)
        loadMoreWhenNearBottom(config)
    }
    
    public var isPaused: Bool { self.fetchFeedTimer == nil }
    
    @MainActor
    private func pause() {
        guard let config, !isPaused else { return }
#if DEBUG
        L.og.debug("☘️☘️ \(config.id) pause()")
#endif
        self.fetchFeedTimer?.invalidate()
        self.fetchFeedTimer = nil
        
        switch config.columnType {
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
    private func resume() {
        guard let config else { return }
#if DEBUG
        L.og.debug("☘️☘️ \(config.id) resume()")
#endif
        startTime = .now
        
        self.startFetchFeedTimer()
        self.fetchFeedTimerNextTick()
        
//        let fourHoursAgo = Int64(Date().timeIntervalSince1970) - (3600 * 4)  // 4 hours  ago
        
        self.listenForNewPosts(config: config)
        gapFiller?.fetchGap(since: self.refreshedAt, currentGap: 0)
    }
    
    private func fetchFeedTimerNextTick() {
        guard let config, !NRState.shared.appIsInBackground && (isVisible || (config.id.starts(with: "Following-") && config.name != "Explore")) else { return }
        bg().perform {
            guard !Importer.shared.isImporting else { return }
            setFirstTimeCompleted()

            Task { @MainActor in
                // TODO: Check if everthing is restored, .sendRealtimeReq is enough?
                self.sendRealtimeReq(config)
            }
        }
    }

    @MainActor
    public func loadLocal(_ config: NXColumnConfig, older: Bool = false, completion: (() -> Void)? = nil) {
        let allIdsSeen = self.allIdsSeen
        let currentIdsOnScreen = self.currentIdsOnScreen
        let currentNRPostsOnScreen = self.currentNRPostsOnScreen
//        let mostRecentCreatedAt = self.mostRecentCreatedAt ?? 0
        let wotEnabled = config.wotEnabled
        let repliesEnabled = config.repliesEnabled
  
        // Fetch since 5 minutes before most recent item on screen (since)
        // Or until oldest (bottom) item on screen (until)
        let (sinceTimestamp, untilTimestamp) = if case .posts(let nrPosts) = viewState {
            ((nrPosts.first?.created_at ?? (60 * 5)) - (60 * 5), (nrPosts.last?.created_at ?? Int64(Date().timeIntervalSince1970)))
        }
        else { // or if empty screen: 0 (since) or now (until)
            (0, Int64(Date().timeIntervalSince1970))
        }
        
        let sinceOrUntil = !older ? sinceTimestamp : untilTimestamp
        
        switch config.columnType {
        case .following(_):
#if DEBUG
            L.og.debug("☘️☘️ \(config.id) loadLocal(.following) \(older ? "older" : "")")
#endif
            guard let accountPubkey = config.accountPubkey, let account = NRState.shared.accounts.first(where: { $0.publicKey == accountPubkey }) else { return }
            self.account = account
            let followingPubkeys = account.followingPubkeys // TODO: Need to keep updated on changing .followingPubkeys
            let hashtagRegex: String? = makeHashtagRegex(account.followingHashtags)
            bg().perform { [weak self] in
                guard let self else { return }
                let fr = if !older {
                    Event.postsByPubkeys(followingPubkeys, lastAppearedCreatedAt: sinceTimestamp, hideReplies: !repliesEnabled, hashtagRegex: hashtagRegex)
                }
                else {
                    Event.postsByPubkeys(followingPubkeys, until: untilTimestamp, hideReplies: !repliesEnabled, hashtagRegex: hashtagRegex)
                }
                guard let events: [Event] = try? bg().fetch(fr) else { return }
                self.processToScreen(events, config: config, allIdsSeen: allIdsSeen, currentIdsOnScreen: currentIdsOnScreen, currentNRPostsOnScreen: currentNRPostsOnScreen, sinceOrUntil: Int(sinceOrUntil), older: older, wotEnabled: wotEnabled, repliesEnabled: repliesEnabled, completion: completion)
            }
        case .pubkeys(let feed):
#if DEBUG
            L.og.debug("☘️☘️ \(config.id) loadLocal(.pubkeys)\(older ? "older" : "")")
#endif
            let pubkeys = feed.contactPubkeys
            bg().perform { [weak self] in
                guard let self else { return }
                let fr = if !older {
                    Event.postsByPubkeys(pubkeys, lastAppearedCreatedAt: sinceTimestamp, hideReplies: !repliesEnabled)
                }
                else {
                    Event.postsByPubkeys(pubkeys, until: untilTimestamp, hideReplies: !repliesEnabled)
                }
                guard let events: [Event] = try? bg().fetch(fr) else { return }
                self.processToScreen(events, config: config, allIdsSeen: allIdsSeen, currentIdsOnScreen: currentIdsOnScreen, currentNRPostsOnScreen: currentNRPostsOnScreen, sinceOrUntil: Int(sinceOrUntil), older: older, wotEnabled: wotEnabled, repliesEnabled: repliesEnabled, completion: completion)
            }
        case .relays(let feed):
#if DEBUG
            L.og.debug("☘️☘️ \(config.id) loadLocal(.relays)\(older ? "older" : "")")
#endif
            let relaysData = feed.relaysData
            bg().perform { [weak self] in
                guard let self else { return }
                let fr = if !older {
                    Event.postsByRelays(relaysData, lastAppearedCreatedAt: sinceTimestamp, hideReplies: !repliesEnabled)
                }
                else {
                    Event.postsByRelays(relaysData, until: untilTimestamp, hideReplies: !repliesEnabled)
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
    private func loadRemote(_ config: NXColumnConfig) {
        switch config.columnType {
        case .following(_):
            guard let account else { return } // TODO: Need to handle hashtags
            loadRemote(account.followingPubkeys, config: config)
        case .pubkeys(let feed):
            loadRemote(feed.contactPubkeys, config: config)
        case .pubkey:
            viewState = .error("Not supported yet")
        case .relays(let feed):
            let relaysData = feed.relaysData
            guard !relaysData.isEmpty else {
                viewState = .error("No relays selected for this custom feed")
                return
            }
            loadRemote(relaysData, config: config)
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
        case .following(_):
            guard let account else { return }
            let pubkeys = account.followingPubkeys
            let hashtags = account.followingHashtags
            let filters = pubkeyOrHashtagReqFilters(pubkeys, hashtags: hashtags, since: NTimestamp(date: Date.now).timestamp)
            
            // TODO: Update "Following" to "Following-xxx" so we can have multiple following columns
            outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: config.id, filters: filters), activeSubscriptionId: config.id)
            
            fetchProfiles(pubkeys: pubkeys, subscriptionId: "Profiles-" + config.id)
        case .pubkeys(let feed):
            let pubkeys = feed.contactPubkeys
            let hashtags = feed.followingHashtags
            let filters = pubkeyOrHashtagReqFilters(pubkeys, hashtags: hashtags, since: NTimestamp(date: Date.now).timestamp)
            
            if let message = CM(type: .REQ, subscriptionId: config.id, filters: filters).json() {
                req(message, activeSubscriptionId: config.id)
                // TODO: Add toggle on .pubkeys custom feeds so we can also use outboxReq for non-"Following"
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
        case .following(_):
            guard let account else { return nil }
            let pubkeys = account.followingPubkeys
            let hashtags = account.followingHashtags
            let filters = pubkeyOrHashtagReqFilters(pubkeys, hashtags: hashtags, since: since, until: until)
            
            // TODO: Update "Following" to "Following-xxx" so we can have multiple following columns
            return (cmd: {
                outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: "RESUME-" + config.id, filters: filters))
            }, subId: "RESUME-" + config.id)
            
        case .pubkeys(let feed):
            let pubkeys = feed.contactPubkeys
            let hashtags = feed.followingHashtags
            let filters = pubkeyOrHashtagReqFilters(pubkeys, hashtags: hashtags, since: since, until: until)
            
            if let message = CM(type: .REQ, subscriptionId: "RESUME-" + config.id, filters: filters).json() {
                return (cmd: {
                    req(message)
                }, subId: "RESUME-" + config.id)
                // TODO: Add toggle on .pubkeys custom feeds so we can also use outboxReq for non-"Following"
            }
            return nil
        case .pubkey:
            return nil
        case .relays(let feed):
            let relaysData = feed.relaysData
            guard !relaysData.isEmpty else { return nil }
            
            let filters = globalFeedReqFilters(since: since, until: until)
            
            if let message = CM(type: .REQ, subscriptionId: "G-RESUME-" + config.id, filters: filters).json() {
                return (cmd: {
                    req(message)
                }, subId: "G-RESUME-" + config.id)
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
        switch config.columnType {
        case .following(_):
            guard let account else { return }
            let pubkeys = account.followingPubkeys
            let hashtags = account.followingHashtags
            let filters = pubkeyOrHashtagReqFilters(pubkeys, hashtags: hashtags, until: Int(until), limit: 100)
            
            // TODO: Update "Following" to "Following-xxx" so we can have multiple following columns
            outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: "PAGE-" + config.id, filters: filters))
            
        case .pubkeys(let feed):
            let pubkeys = feed.contactPubkeys
            let hashtags = feed.followingHashtags
            let filters = pubkeyOrHashtagReqFilters(pubkeys, hashtags: hashtags, until: Int(until), limit: 100)
            
            if let message = CM(type: .REQ, subscriptionId: "PAGE-" + config.id, filters: filters).json() {
                req(message)
                // TODO: Add toggle on .pubkeys custom feeds so we can also use outboxReq for non-"Following"
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
    
    private var allIdsSeen: Set<String> {
        get { SettingsStore.shared.appWideSeenTracker ? Deduplicator.shared.onScreenSeen : _allIdsSeen }
        set {
            if SettingsStore.shared.appWideSeenTracker {
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
    
    @MainActor
    private func listenForNewPosts(config: NXColumnConfig) {
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
                .sink { [weak self] subscriptionIds in
                    guard let self else { return }
                    guard !haltedProcessing && (isVisible) && !isPaused && !NRState.shared.appIsInBackground else {
                        queuedSubscriptionIds.add(subscriptionIds)
                        return
                    }
                    guard subscriptionIds.contains(config.id) else { return }
                    
#if DEBUG
                    L.og.debug("☘️☘️ \(config.id) listenForNewPosts.subscriptionIds \(subscriptionIds)")
#endif
                    Task { @MainActor in
                        self.loadLocal(config)
                    }
                }
        }
 
        self.sendRealtimeReq(config)
    }
    
    @MainActor
    private func listenForFirstConnection(config: NXColumnConfig) {
        guard firstConnectionSub == nil else { return }
        firstConnectionSub = receiveNotification(.firstConnection)
            .debounce(for: .seconds(0.1), scheduler: DispatchQueue.global())
            .sink { [weak self] _ in
                guard let self, watchForFirstConnection else { return }
#if DEBUG
                L.og.debug("☘️☘️ \(config.id) listenForFirstConnection")
#endif
                Task { @MainActor in
                    self.watchForFirstConnection = false
                    self.load(config)
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
                L.og.debug("☘️☘️ \(config.id) listenForLastDisconnection")
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
//                guard let self else { return }
                let danglerIds = danglers.compactMap { $0.replyToId }
                    .filter { postId in
                        Importer.shared.existingIds[postId] == nil && postId.range(of: ":") == nil // @TODO: <-- Workaround for aTag instead of e here, need to handle some other way
                    }
                
                if !danglerIds.isEmpty {
#if DEBUG
                    L.og.debug("☘️☘️ \(config.id) fetchParents: \(danglers.count.description), fetching....")
#endif
                    req(RM.getEvents(ids: danglerIds, subscriptionId: taskId)) // TODO: req or outboxReq?
                }
            },
            processResponseCommand: { [weak self] (taskId, _, _) in
                guard let self else { return }
                bg().perform { [weak self] in
                    guard let self else { return }
                    let danglingEvents = danglers.compactMap { $0.event }
#if DEBUG
                    L.og.debug("☘️☘️ \(config.id) fetchParents.processResponseCommand")
#endif
                    
                    // Need to go to main context again to get current screen state
                    Task { @MainActor in
                        let allIdsSeen = self.allIdsSeen
                        let currentIdsOnScreen = self.currentIdsOnScreen
//                        let mostRecentCreatedAt = self.mostRecentCreatedAt ?? 0
                        let wotEnabled = config.wotEnabled
                        let repliesEnabled = config.repliesEnabled
                        
                        // Then back to bg for processing
                        bg().perform {
                            self.processToScreen(danglingEvents, config: config, allIdsSeen: allIdsSeen, currentIdsOnScreen: currentIdsOnScreen, currentNRPostsOnScreen: currentNRPostsOnScreen, sinceOrUntil: sinceOrUntil, older: older, wotEnabled: wotEnabled, repliesEnabled: repliesEnabled)
                        }
                    }
                }
            },
            timeoutCommand: { [weak self] (taskId) in
                guard let self else { return }
                bg().perform { [weak self] in
                    guard let self else { return }
                    let danglingEvents: [Event] = danglers.compactMap { $0.event }
#if DEBUG
                    L.og.debug("☘️☘️ \(config.id) fetchParents.timeoutCommand")
#endif
                    
                    // Need to go to main context again to get current screen state
                    Task { @MainActor in
                        let allIdsSeen = self.allIdsSeen
                        let currentIdsOnScreen = self.currentIdsOnScreen
//                        let mostRecentCreatedAt = self.mostRecentCreatedAt ?? 0
                        let wotEnabled = config.wotEnabled
                        let repliesEnabled = config.repliesEnabled
                        
                        // Then back to bg for processing
                        bg().perform {
                            self.processToScreen(danglingEvents, config: config, allIdsSeen: allIdsSeen, currentIdsOnScreen: currentIdsOnScreen, currentNRPostsOnScreen: currentNRPostsOnScreen, sinceOrUntil: sinceOrUntil, older: older, wotEnabled: wotEnabled, repliesEnabled: repliesEnabled)
                        }
                    }

                }
            })

    //        DispatchQueue.main.async {
            self.backlog.add(danglingFetchTask)
    //        }
        danglingFetchTask.fetch()
    }
}

// -- MARK: POST RENDERING
extension NXColumnViewModel {
    
    // Primary function to put Events on screen
    private func processToScreen(_ events: [Event], config: NXColumnConfig, allIdsSeen: Set<String>, currentIdsOnScreen: Set<String>, currentNRPostsOnScreen: [NRPost] = [], sinceOrUntil: Int, older: Bool, wotEnabled: Bool, repliesEnabled: Bool, completion: (() -> Void)? = nil) {
        
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
            
#if DEBUG
        L.og.debug("☘️☘️ \(config.id) prepareEvents \(events.count.description)")
#endif
        
        let filteredEvents: [Event] = (wotEnabled ? applyWoT(events, config: config) : events) // Apply WoT filter or not
            .filter { // Apply (app wide) already-seen filter
                if $0.isRepost, let firstQuoteId = $0.firstQuoteId {
                    return !allIdsSeen.contains(firstQuoteId)
                }
                return !allIdsSeen.contains($0.id)
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
        L.og.debug("☘️☘️ \(config.id) prepareEvents newCount \(newCount.description)")
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
        
        guard WOT_FILTER_ENABLED() else { return events }  // Return all if globally disabled
        
        
        if case .relays(_) = config.columnType {
            // if we are here, type is .relays, only filter if the feed specific WoT filter is enabled
            return events.filter { $0.inWoT }
        }
                
        // TODO: handle other config.columnTypes
        
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
        L.og.debug("☘️☘️ \(config.id) transformToNRPosts currentIdsOnScreen: \(currentIdsOnScreen.count.description) transformedNrPosts: \(transformedNrPosts.count.description)")
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
                L.og.debug("☘️☘️ \(config.id) putOnScreen addedPosts (TOP) \(onlyNewAddedPosts.count.description) -> OLD FIRST: \((existingPosts.first?.content ?? "").prefix(150))")
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
                
                
                let addedAndExistingPostsTruncated = if isAtTop && notTooLittle && notTooMuch {
                    Array(addedAndExistingPosts.dropLast(dropCount))
                }
                else {
                    addedAndExistingPosts
                }
                
                allIdsSeen = allIdsSeen.union(getAllPostIds(addedAndExistingPostsTruncated))
                
                if isAtTop {
//                    haltProcessing() // TODO: Needed or not?
                    
                    let previousFirstPostId: String? = existingPosts.first?.id
                    
                    isAtTop = false
                    viewState = .posts(addedAndExistingPostsTruncated)
                    
                    // TODO: Should already start prefetching missing onlyNewAddedPosts pfp/kind 0 here

                    // Update unread count
                    for post in onlyNewAddedPosts {
                        if unreadIds[post.id] == nil {
                            unreadIds[post.id] = 1 + post.parentPosts.count
                        }
                    }
                    
                    if let previousFirstPostId, let restoreToIndex = addedAndExistingPostsTruncated.firstIndex(where: { $0.id == previousFirstPostId })  {
                        scrollToIndex = restoreToIndex
#if DEBUG
                L.og.debug("☘️☘️ \(config.id) putOnScreen restoreToIndex: \((addedAndExistingPostsTruncated[restoreToIndex].content ?? "").prefix(150))")
#endif
                    }
                }
                else {
                    withAnimation {
                        viewState = .posts(addedAndExistingPostsTruncated)
                        
                        // Update unread count
                        for post in onlyNewAddedPosts {
                            if unreadIds[post.id] == nil {
                                unreadIds[post.id] = 1 + post.parentPosts.count
                            }
                        }
                    }
                }
            }
            else { // add below
#if DEBUG
                L.og.debug("☘️☘️ \(config.id) putOnScreen addedPosts (AT END) \(onlyNewAddedPosts.count.description)")
#endif
                allIdsSeen = allIdsSeen.union(getAllPostIds(onlyNewAddedPosts))
                withAnimation {
                    self.viewState = .posts(existingPosts + onlyNewAddedPosts)
                }
                sendNextPageReq(config, until: existingPosts.last?.created_at ?? Int64(Date().timeIntervalSince1970))
            }
        }
        else { // Nothing on screen yet, put first posts on screen
            let uniqueAddedPosts = addedPosts.uniqued(on: { $0.id })
#if DEBUG
            L.og.debug("☘️☘️ \(config.id) putOnScreen addedPosts (💦FIRST💦) \(uniqueAddedPosts.count.description)")
#endif
            allIdsSeen = allIdsSeen.union(getAllPostIds(uniqueAddedPosts))
            if !isAtTop {
                isAtTop = true
            }
            withAnimation {
                viewState = .posts(uniqueAddedPosts)
            }
            sendNextPageReq(config, until: uniqueAddedPosts.last?.created_at ?? Int64(Date().timeIntervalSince1970))
        }
        
        completion?()
        didFinish()
    }
    
    // -- MARK: Helpers
    
    @MainActor
    private func getAllPostIds(_ nrPosts: [NRPost]) -> Set<String> {
        return nrPosts.reduce(Set<NRPostID>()) { partialResult, nrPost in
            if nrPost.isRepost, let firstPost = nrPost.firstQuote {
                // for repost add post + reposted post
                return partialResult.union(Set([nrPost.id, firstPost.id]))
            } else {
                return partialResult.union(Set([nrPost.id] + nrPost.parentPosts.map { $0.id }))
            }
        }
    }
    
    private func getAllEventIds(_ events: [Event]) -> Set<String> {
        return events.reduce(Set<String>()) { partialResult, event in
            if event.isRepost, let firstQuote = event.firstQuote_ {
                // for repost add post + reposted post
                return partialResult.union(Set([event.id, firstQuote.id]))
            }
            else {
                return partialResult.union(Set([event.id] + event.parentEvents.map { $0.id }))
            }
        }
    }
}

// -- MARK: PUBKEYS
extension NXColumnViewModel {
    
    @MainActor // // TODO: Need to handle hashtags. (probably replace instantFeed?, fixes hashtags and maybe also 50 limit)
    private func loadRemote(_ pubkeys: Set<String>, config: NXColumnConfig, older: Bool = false) {
#if DEBUG
        L.og.debug("☘️☘️ \(config.id) loadRemote(pubkeys)")
#endif
//        let instantFeed = InstantFeed()
//        self.instantFeed = instantFeed
//        let wotEnabled = config.wotEnabled
//        let repliesEnabled = config.repliesEnabled
        
        // Fetch since 5 minutes before most recent item on screen (since)
        // Or until oldest (bottom) item on screen (until)
        let (sinceTimestamp, untilTimestamp) = if case .posts(let nrPosts) = viewState {
            (self.refreshedAt, (nrPosts.last?.created_at ?? Int64(Date().timeIntervalSince1970)))
        }
        else { // or if empty screen: refreshedAt (since) or now (until)
            (0, Int64(Date().timeIntervalSince1970))
        }
        
        let sinceOrUntil = !older ? sinceTimestamp : untilTimestamp
        
        if !older {
            self.gapFiller?.fetchGap(since: sinceOrUntil, currentGap: 0)
        }
        else {
            // TODO: handler older
        }
        
//        bg().perform { [weak self] in
//            instantFeed.start(pubkeys, since: mostRecentCreatedAt) { [weak self] events in
//                guard let self, events.count > 0 else { return }
//#if DEBUG
//                L.og.debug("☘️☘️ \(config.id) loadRemote(pubkeys) instantFeed.onComplete events.count \(events.count.description)")
//#endif
//                
//                // Need to go to main context again to get current screen state
//                Task { @MainActor in
//                    let allIdsSeen = self.allIdsSeen
//                    let currentIdsOnScreen = self.currentIdsOnScreen
//                    let sinceOrUntil = !older ? (self.mostRecentCreatedAt ?? 0) : (self.oldestCreatedAt ?? Int(Date().timeIntervalSince1970))
//
//                    // Then back to bg for processing
//                    bg().perform {
//                        self.processToScreen(events, config: config, allIdsSeen: allIdsSeen, currentIdsOnScreen: currentIdsOnScreen, sinceOrUntil: sinceOrUntil, older: older, wotEnabled: wotEnabled, repliesEnabled: repliesEnabled)
//                    }
//                }
//            }
//        }
    }
}

// -- MARK: RELAYS
extension NXColumnViewModel {
    
    @MainActor
    public func loadRemote(_ relays: Set<RelayData>, config: NXColumnConfig, older: Bool = false) {
#if DEBUG
        L.og.debug("☘️☘️ \(config.id) loadRemote(relays)")
#endif
        let instantFeed = InstantFeed()
        self.instantFeed = instantFeed
        let mostRecentCreatedAt = self.mostRecentCreatedAt ?? 0
        let wotEnabled = config.wotEnabled
        let repliesEnabled = config.repliesEnabled
        
        bg().perform { [weak self] in
            instantFeed.start(relays, since: mostRecentCreatedAt) { [weak self] events in
                guard let self, events.count > 0 else { return }
                
                // TODO: We always only get max 50 event here, need to adjust fetch limit depending on situation
#if DEBUG
                L.og.debug("☘️☘️ \(config.id) loadRemote(relays) instantFeed.onComplete events.count \(events.count.description)")
#endif
                
                // Need to go to main context again to get current screen state
                Task { @MainActor in
                    let allIdsSeen = self.allIdsSeen
                    let currentIdsOnScreen = self.currentIdsOnScreen
//                    let mostRecentCreatedAt = self.mostRecentCreatedAt ?? 0
                    let sinceOrUntil = !older ? (self.mostRecentCreatedAt ?? 0) : (self.oldestCreatedAt ?? Int(Date().timeIntervalSince1970))
                    
                    // Then back to bg for processing
                    bg().perform {
                        self.processToScreen(events, config: config, allIdsSeen: allIdsSeen, currentIdsOnScreen: currentIdsOnScreen, sinceOrUntil: sinceOrUntil, older: older, wotEnabled: wotEnabled, repliesEnabled: repliesEnabled)
                    }
                }
            }
        }
    }
}

// -- MARK: SCROLLING
extension NXColumnViewModel {
    
    @MainActor
    public func scrollToFirstUnread() {
        if case .posts(let nrPosts) = viewState {
            for post in (nrPosts).reversed() {
                if let unreadCount = unreadIds[post.id], unreadCount > 0 {
                    if let firstUnreadIndex = nrPosts.firstIndex(where: { $0.id == post.id }) {
                        DispatchQueue.main.async {
                            self.objectWillChange.send()
                            self.scrollToIndex = firstUnreadIndex
                        }
                    }
                }
            }
        }
    }
    
    @MainActor
    public func scrollToTop() {
        DispatchQueue.main.async {
            self.objectWillChange.send()
            self.scrollToIndex = 0
        }
    }
    
    @MainActor
    public func loadMoreWhenNearBottom(_ config: NXColumnConfig) {
        onAppearSubject
            .debounce(for: 0.2, scheduler: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] lastCreatedAt in
                
#if DEBUG
                L.og.debug("☘️☘️ \(config.id) onAppearSubject lastCreatedAt \(lastCreatedAt)")
#endif
                // fetch older, can reuse NXDelayur?
                self?.loadLocal(config, older: true)
            }
            .store(in: &subscriptions)
    }
}

enum ColumnViewState {
    case loading
    case posts([NRPost]) // Posts
    case error(String)
}

let FETCH_FEED_INTERVAL = 9.0
let FEED_MAX_VISIBLE: Int = 20

func setFirstTimeCompleted() {
    if !UserDefaults.standard.bool(forKey: "firstTimeCompleted") {
        DispatchQueue.main.async {
            UserDefaults.standard.set(true, forKey: "firstTimeCompleted")
        }
    }
}

func pubkeyOrHashtagReqFilters(_ pubkeys: Set<String>, hashtags: Set<String>, since: Int? = nil, until: Int? = nil, limit: Int = 5000) -> [Filters] {
    guard !pubkeys.isEmpty || !hashtags.isEmpty else { return [] }
    
    var filters: [Filters] = []
    
    if !pubkeys.isEmpty {
        let followingContactsFilter = Filters(
            authors: pubkeys,
            kinds: FETCH_FOLLOWING_KINDS,
            since: since, until: until, limit: limit)
        
        filters.append(followingContactsFilter)
    }
    
    if !hashtags.isEmpty {
        let followingHashtagsFilter = Filters(
            kinds: FETCH_FOLLOWING_KINDS,
            tagFilter: TagFilter(tag: "t", values: Array(hashtags).map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }),
            since: since, until: until)
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


// TODO: loadSomeonesFeed()
// TODO: Still reusing old InstantFeed(), good or refactor/clean up?


func makeHashtagRegex(_ hashtags: Set<String>) -> String? {
    if !hashtags.isEmpty {
        let regex = ".*(" + hashtags.map {
            NSRegularExpression.escapedPattern(for: serializedT($0))
        }.joined(separator: "|") + ").*"
        return regex
    }
    
    return nil
}

// Catch up - resume feed
// Fetch posts since last time in X hour windows
// Wait Y seconds per window
// Can't know if fetch window has no posts or connection failure
// So before advancing to next window, make sure we have connection
// Note: don't use for "older"
class NXGapFiller {
    private var since: Int64
    private var windowSize: Int // Hours
    private var timeout: Double // Seconds
    private var currentGap: Int // used to calculate nextGapSince
    private weak var columnVM: NXColumnViewModel?
    private var backlog: Backlog
    
    private var windowStart: Int { // Depending on older or not we use start/end as since/until
        return Int(since) + (currentGap * 3600 * windowSize)
    }
    private var windowEnd: Int { // Depending on older or not we use start/end as since/until
        windowStart + (3600 * windowSize)
    }
    
    public init(since: Int64, windowSize: Int = 4, timeout: Double = 2, currentGap: Int = 0, columnVM: NXColumnViewModel) {
        self.since = since
        self.windowSize = windowSize
        self.timeout = timeout
        self.currentGap = currentGap
        self.columnVM = columnVM
        self.backlog = Backlog(timeout: timeout, auto: true)
    }
    
    @MainActor
    public func fetchGap(since: Int64, currentGap: Int) {
        guard let columnVM, let config = columnVM.config else { return }
        self.since = since
        self.currentGap = currentGap
        
        // Check connection?
        guard ConnectionPool.shared.anyConnected else {
            L.og.debug("☘️☘️⏭️🔴🔴 \(columnVM.id ?? "?") Not connected, skipping fetchGap")
            return
        }
        
        // Check if paused
        guard !columnVM.isPaused else {
            L.og.debug("☘️☘️🔴🔴 \(columnVM.id ?? "?") paused, skipping fetchGap")
            return
        }
                
        // send REQ
        if let (cmd, subId) = columnVM.getFillGapReqStatement(config, since: windowStart, until: windowEnd) {
            
            let reqTask = ReqTask(
//                prio: true,
//                debounceTime: ??,
                timeout: 15.0,
                subscriptionId: subId,
                reqCommand: { [weak self] _ in
                    guard let self else { return }
                    L.og.debug("☘️☘️⏭️ \(columnVM.id ?? "?") currentGap: \(self.currentGap) \(Date(timeIntervalSince1970: TimeInterval(self.windowStart)).formatted()) - \(Date(timeIntervalSince1970: TimeInterval(self.windowEnd)).formatted()) now=\(Date.now.formatted())")
                    cmd()
                },
                processResponseCommand: { [weak self] _, _, _ in
                    guard let self else { return }
                    self.columnVM?.refreshedAt = Int64(Date().timeIntervalSince1970)
                    self.columnVM?.loadLocal(config)
                    
                    if self.windowStart < Int(Date().timeIntervalSince1970) {
                        self.fetchGap(since: self.since, currentGap: self.currentGap + 1) // next gap (no since param)
                    }
                    else {
                        self.currentGap = 0
                    }
                },
                timeoutCommand: { subId in
                    L.og.debug("☘️☘️⏭️🔴🔴 \(columnVM.id ?? "?") timeout in fetchGap \(subId)")
                    Task { @MainActor in
                        self.columnVM?.loadLocal(config)
                    }
                })

            self.backlog.add(reqTask)
            reqTask.fetch()
        }
    }
}