//
//  ColumnViewModel.swift
//  Nosturix
//
//  Created by Fabian Lachman on 01/08/2024.
//

import SwiftUI
import Combine
import NostrEssentials

final class NXSeenReconciliationScheduler {
    private var task: Task<Void, Never>?

    @MainActor
    func schedule(
        isBusy: @escaping @MainActor () -> Bool,
        apply: @escaping @MainActor () -> Void
    ) {
        task?.cancel()
        task = Task { @MainActor [weak self] in
            while isBusy() {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled else { return }
            }

            // Do not mutate the List on the first idle frame. UIKit can briefly report idle
            // between a drag and deceleration or while a prepared restore starts scrolling.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            guard !isBusy() else {
                self?.schedule(isBusy: isBusy, apply: apply)
                return
            }

            self?.task = nil
            apply()
        }
    }

    @MainActor
    func cancel() {
        task?.cancel()
        task = nil
    }
}

class NXColumnViewModel: ObservableObject {
    public let columnVMid = UUID()
#if DEBUG
    var feedActionDebugRecord: ((String) -> Void)?
#endif
    /// Hides the List while a remember-on restore jumps from offset 0 to the saved post.
    @Published var isHidingFeedForRestore = false
    /// Prepend landed while the restore cover was up; lift the cover after settle.
    var delayRestoreRevealUntilPrependSettles = false
    @Published private(set) var alreadySeenNewerCount = 0
    @Published private(set) var isShowingAlreadySeenNewerPosts = false
    private var alreadySeenNewerCandidates: [String: NXAlreadySeenNewerPostCandidate] = [:]

    private func attachRestoreCoverIfNeeded() {
        guard vmInner.onRestoreCoverChange == nil else { return }
        vmInner.onRestoreCoverChange = { [weak self] hiding in
            guard let self, self.isHidingFeedForRestore != hiding else { return }
            self.isHidingFeedForRestore = hiding
#if DEBUG
            Task { @MainActor [weak self] in
                self?.recordFeedAction(hiding ? "RESTORE hide list" : "RESTORE reveal list")
            }
#endif
        }
    }
    
    public var speedTest: NXSpeedTest?

    // "Following-..." / "List-56D5EE90-17CB-4925" / ...
    public var id: String? { config?.id }
    public var config: NXColumnConfig?
    
    public var collectionView: UICollectionView?
    public var collectionPrefetcher: NXPostsFeedPrefetcher?
    
    public var tableView: UITableView?
    public var tablePrefetcher: NXPostsFeedTablePrefetcher?

#if DEBUG
    @MainActor
    var feedActionDebugPostCount: Int {
        currentNRPostsOnScreen.count
    }

    @MainActor
    func feedActionDebugState() -> String {
        let posts = currentNRPostsOnScreen
        let scrollView: UIScrollView? = collectionView ?? tableView
        let motion: String
        if scrollView?.isDragging == true || scrollView?.isTracking == true {
            motion = "dragging"
        } else if scrollView?.isDecelerating == true {
            motion = "decelerating"
        } else {
            motion = "idle"
        }
        let offset = scrollView.map { String(format: "%.1f", $0.contentOffset.y) } ?? "?"
        let reading = (vmInner.readingPostID ?? vmInner.pendingScrollToPostID).map(shortDebugID) ?? "none"
        let first = posts.first.map { shortDebugID($0.id) } ?? "none"
        let last = posts.last.map { shortDebugID($0.id) } ?? "none"
        return "\(posts.count) posts · y \(offset) · \(motion) · top \(vmInner.isAtTop) · anchor \(reading) · ids \(first)…\(last) · \(feedActionDebugViewport())"
    }

    @MainActor
    func feedActionDebugViewport() -> String {
        let postCount = currentNRPostsOnScreen.count
        guard let scrollView = collectionView ?? tableView else {
            return "size ? · remain ? · estRow ? · win 0"
        }
        let y = scrollView.contentOffset.y
        let insetTop = scrollView.adjustedContentInset.top
        let boundsHeight = scrollView.bounds.height
        let contentHeight = scrollView.contentSize.height
        let visibleBottom = y + boundsHeight - scrollView.adjustedContentInset.bottom
        let remaining = max(0, contentHeight - visibleBottom)
        let prefetch = max(1_200, boundsHeight * 2.5)
        let estimatedRow = postCount > 0 ? contentHeight / CGFloat(postCount) : 0
        let atTop = NXFeedViewport.isOffsetAtTop(contentOffsetY: y, insetTop: insetTop)
        return String(
            format: "size %.0f · remain %.0f/%.0f · estRow %.0f · visualTop %d · win %d",
            contentHeight,
            remaining,
            prefetch,
            estimatedRow,
            atTop ? 1 : 0,
            scrollView.window != nil ? 1 : 0
        )
    }

    @MainActor
    func recordFeedAction(_ message: String) {
        feedActionDebugRecord?(message)
    }

    nonisolated private func recordFeedActionFromBackground(_ message: String) {
        Task { @MainActor [weak self] in
            self?.recordFeedAction(message)
        }
    }

    nonisolated private func debugSeconds(since date: Date) -> String {
        String(format: "%.3fs", max(0, Date().timeIntervalSince(date)))
    }

    nonisolated private func debugSeconds(from start: Date, to end: Date) -> String {
        String(format: "%.3fs", max(0, end.timeIntervalSince(start)))
    }

    private func shortDebugID(_ id: String) -> String {
        String(id.prefix(8))
    }
#endif

    @MainActor
    private var isFeedActivelyScrolling: Bool {
        collectionView?.isDragging == true
            || collectionView?.isDecelerating == true
            || collectionView?.isTracking == true
            || tableView?.isDragging == true
            || tableView?.isDecelerating == true
            || tableView?.isTracking == true
    }

    @MainActor
    private var shouldDeferSeenReconciliation: Bool {
        isFeedActivelyScrolling
            || vmInner.isPerformingScroll
            || vmInner.isPerformingScrollToFirstUnread
            || vmInner.isPreparingForScrollRestore
    }

    @MainActor
    private var isFeedActuallyAtTop: Bool {
        let scrollView: UIScrollView? = collectionView ?? tableView
        let hasLiveScrollView = scrollView?.window != nil
        return NXFeedViewport.isActuallyAtTop(
            hasLiveScrollView: hasLiveScrollView,
            contentOffsetY: scrollView?.contentOffset.y ?? 0,
            insetTop: scrollView?.adjustedContentInset.top ?? 0,
            isPreparingRestore: vmInner.isPreparingForScrollRestore && (vmInner.pendingScrollToIndex ?? 0) > 0,
            restoreExpired: vmInner.isPreparedScrollRestoreExpired,
            fallbackIsAtTop: vmInner.isAtTop
        )
    }

    @MainActor
    private func shouldAbortLatePreparedRestoreFromViewModel() -> Bool {
        guard vmInner.isPreparingForScrollRestore,
              vmInner.isPreparedScrollRestoreExpired else { return false }
        return isFeedActuallyAtTop
    }

    /// Incoming prepends must not complete a pending jump to a saved mid-feed
    /// post if the user is already looking at the painted top.
    @MainActor
    private func isVisuallyAtTopForIncomingPosts() -> Bool {
        if isFeedActuallyAtTop { return true }
        let scrollView: UIScrollView? = collectionView ?? tableView
        guard vmInner.isPreparingForScrollRestore,
              let scrollView, scrollView.window != nil,
              NXFeedViewport.isOffsetAtTop(
                contentOffsetY: scrollView.contentOffset.y,
                insetTop: scrollView.adjustedContentInset.top
              ) else {
            return false
        }
        vmInner.abortPreparedScrollRestore()
        return true
    }

    /// `withAnimation` is intentional for ordinary updates where SwiftUI owns positioning.
    /// Off-top updates use the feed's explicit stable-ID/viewport-offset anchor and must remain
    /// unanimated; combining both mechanisms can apply two offset corrections and move the row.
    /// During an active drag/deceleration UIKit also owns the scroll position, so updates are
    /// deferred by the anchor coordinator until scrolling finishes.
    @MainActor
    private func setPosts(_ posts: [NRPost], animated: Bool = true) {
        // Pin whenever newer rows land above the reading post. That includes
        // autoScroll-off at the visual top: keep the current first post instead
        // of a hide-and-scrollTo restore. Auto-scroll at top still lets SwiftUI
        // move to the newest post.
        let pinInsertAbove = shouldPinFeedUpdate(to: posts)
            && (!isFeedActuallyAtTop || !SettingsStore.shared.autoScroll)
        if pinInsertAbove,
           let performAnchoredFeedUpdate = vmInner.performAnchoredFeedUpdate {
            let oldPosts = currentNRPostsOnScreen
            let oldIDs = Set(oldPosts.map(\.id))
            let requestedNewCount = posts.count { !oldIDs.contains($0.id) }
            performAnchoredFeedUpdate(NXFeedViewport.prependCoverReason) { [weak self] in
                guard let self else { return [] }
                let currentPosts = self.currentNRPostsOnScreen
                let desiredIDs = Set(posts.map(\.id))
                let preservedWhileWaiting = currentPosts.count {
                    !oldIDs.contains($0.id) && !desiredIDs.contains($0.id)
                }
                let rebasedPosts = NXFeedUpdateRebaser.rebase(
                    old: oldPosts,
                    desired: posts,
                    current: currentPosts,
                    id: \.id
                )
                withTransaction(Transaction(animation: nil)) {
                    self.viewState = .posts(rebasedPosts)
                }
#if DEBUG
                let preservedSuffix = preservedWhileWaiting > 0
                    ? " · preserved \(preservedWhileWaiting) older appended while queued"
                    : ""
                self.recordFeedAction(
                    "inserted \(requestedNewCount) newer at top · \(currentPosts.count)→\(rebasedPosts.count)\(preservedSuffix) · \(self.feedActionDebugViewport())"
                )
#endif
                return rebasedPosts.map(\.id)
            }
            return
        }

        if animated && !isFeedActivelyScrolling {
            withAnimation {
                viewState = .posts(posts)
            }
        } else {
            withTransaction(Transaction(animation: nil)) {
                viewState = .posts(posts)
            }
        }
    }

    @MainActor
    private func shouldPinFeedUpdate(to posts: [NRPost]) -> Bool {
        guard case .posts(let existing) = viewState else { return false }
        let oldIDs = existing.map(\.id)
        let newIDs = posts.map(\.id)
        let anchorID = vmInner.readingPostID
            ?? vmInner.pendingScrollToPostID
            ?? oldIDs.first(where: { newIDs.contains($0) })
        guard let anchorID else { return false }
        return NXFeedIndexMapping.itemsInsertedAbove(oldIDs: oldIDs, newIDs: newIDs, anchorID: anchorID)
    }
    
    public let vmInner = NXColumnViewModelInner()
    private var newestMarkedAsReadSaveTask: Task<Void, Never>?
    public var newestMarkedAsRead: Date? {
        didSet {
            guard newestMarkedAsRead != oldValue else { return }
            let newestMarkedAsRead = newestMarkedAsRead
            newestMarkedAsReadSaveTask?.cancel()
            newestMarkedAsReadSaveTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self, let feed = self.config?.feed else { return }
                    guard feed.newestMarkedReadAt != newestMarkedAsRead else { return }
                    feed.newestMarkedReadAt = newestMarkedAsRead
                    DataProvider.shared().saveToDiskNow(.viewContext)
                }
            }
        }
    }
    
    private var didLoadFirstLocalState = false
    
    @MainActor
    func handleAppearOnce(nrPost: NRPost) -> Bool {
        // Don't run if onPostAppearOnce is happening because of scrollToIndex (hidden scroll to keep scroll position)
        // Only run if it is actual user based scroll
        guard !vmInner.isPerformingScroll else { return false }
        // Animated unread navigation can bring several lazy rows through the appearance threshold.
        // The selected indexed target is marked explicitly when the scroll finishes.
        guard !vmInner.isPerformingScrollToFirstUnread else { return false }
        // The restored list paints from offset 0 before it jumps to the saved post.
        // Those newest rows must not mark the unread stack as read.
        if vmInner.isPreparingForScrollRestore {
            if shouldAbortLatePreparedRestoreFromViewModel() {
                vmInner.abortPreparedScrollRestore()
            } else {
                return false
            }
        }
        let scrollView: UIScrollView? = collectionView ?? tableView
        if scrollView?.isDragging == true || scrollView?.isTracking == true {
            vmInner.holdUnreadAboveReadingPost = false
        }
        if vmInner.holdUnreadAboveReadingPost,
           let readingID = vmInner.readingPostID,
           case .posts(let posts) = viewState,
           let readingIndex = posts.firstIndex(where: { $0.id == readingID }),
           let appearedIndex = posts.firstIndex(where: { $0.id == nrPost.id }),
           appearedIndex < readingIndex {
            return false
        }
        let visibleIds = currentVisiblePostIds()
        if !visibleIds.isEmpty && !visibleIds.contains(nrPost.id) {
            return false
        }
    #if DEBUG
        L.og.debug("☘️☘️ \(self.config?.name ?? "?") NXPostsFeed.onPostAppearOnce() -> updateIsAtTop() BEFORE: \(self.vmInner.isAtTop) -[LOG]-")
    #endif
        
        // Batch async operations to avoid blocking the main thread
        Task.detached(priority: .userInitiated) {
            await self.prefetch(nrPost)
            await self.saveLocalFeedState()
        }
        
        vmInner.updateIsAtTopSubject.send()
     
        // Optimize ID collection operations
        performIDCollectionUpdates(for: nrPost, vm: self)
        
        // Optimize unread marking operations
        performUnreadMarkingUpdates(for: nrPost, vm: self)
        
        return true
    }
    
    @MainActor
    private func didFinish() {
        if !ConnectionPool.shared.anyConnected { // After finish we were never connected, watch for first connection to .load() again
            self.watchForFirstConnection = true
        }

        if let speedTest, speedTest.loadingBarViewState != .finished, !speedTest.relaysFinishedAt.isEmpty {
#if DEBUG
            L.og.debug("🏁🏁 NXColumnViewModel.didFinish loadingBarViewState = .finalLoad")
#endif
            speedTest.loadingBarViewState = .finalLoad
        }
    }
    
    @Published var viewState: ColumnViewState = .loading {
        didSet {
            if case .posts(let nrPosts) = viewState {
                refreshAlreadySeenNewerPosts(for: nrPosts)
                if nrPosts.isEmpty, !vmInner.unreadIds.isEmpty {
                    vmInner.unreadIds = [:]
                    vmInner.updateIsAtTopSubject.send()
                }
            }
            else if case .loading = viewState {
                isViewPaused = false
                if !vmInner.unreadIds.isEmpty {
                    vmInner.unreadIds = [:]
                    vmInner.updateIsAtTopSubject.send()
                }
            }
        }
    }
   
    private var danglingIds: Set<NRPostID> = [] // posts that are transformed, but somehow not on screen (maybe not found on relays). either we put on on screen or not, dont transform over and over again.
    
    // isVisible should actually be isActiveTab (can still be not visible on navigate to detail)
    public var isVisible: Bool = false {
        didSet {
            guard let config, let speedTest else { return }
            guard isVisible != oldValue else { return }
            if isVisible {
                if case .loading = viewState {
                    Task { @MainActor in
                        self.initialize(config, speedTest: speedTest)
                    }
                }
                else if case .posts(_) = viewState {
                    Task { @MainActor in
                        FeedsCoordinator.shared.registerColumn(self)
                        self.resume()
                    }
                }
            }
            else if !isPaused {
                Task { @MainActor in
                    FeedsCoordinator.shared.unregisterColumn(self)
                    self.pause()
                }
            }
        }
    }
    
    private var paused = true
    private var lastResumeStartedAt: Date?
    private var lastBecameInactiveAt: Date?
    private var newEventsInDatabaseSub: AnyCancellable?
    private var pageEventsInDatabaseSub: AnyCancellable?
    private var newPostSavedSub: AnyCancellable?
    private var newSingleRelayPostSavedSub: AnyCancellable?
    private var newPostUndoSub: AnyCancellable?
    private var firstConnectionSub: AnyCancellable?
    private var reloadWhenNeededSub: AnyCancellable?
    private var lastDisconnectionSub: AnyCancellable?
    private var onAppearSubjectSub: AnyCancellable?
    private var onScreenSeenInsertedSub: AnyCancellable?
    private var cloudSeenInsertedSub: AnyCancellable?
    public var watchForFirstConnection = false
    public var saveLocalStateSub: AnyCancellable?
    private var subscriptions = Set<AnyCancellable>()
    private let seenReconciliationScheduler = NXSeenReconciliationScheduler()
    private var pendingSyncedSeenIds: Set<String> = []
    private var initialMediaTimeoutTask: Task<Void, Never>?
    private var autoExploreRelaysAfterWoTTimeout = false
    private var mediaDiscoverySubscriptionId: String?
    private var mediaDiscoveryTracker: BoundedRelayRequestCompletionTracker?
    private var mediaDiscoveryImportTask: Task<Void, Never>?
    private var lateMediaEventSub: AnyCancellable?
    private var selectedRelayAutoRetryAttempted = false
    private var selectedRelayRecoveryTask: Task<Void, Never>?
    @Published private(set) var mediaSearchTimedOut = false
    @Published private(set) var mediaUpdatesAvailable = false

    @MainActor
    var activeMediaFeedSource: MediaFeedSource? {
        config?.mediaFeedSourceSnapshot
    }

    @MainActor
    var canExploreMore: Bool {
        guard let config else { return false }
        switch config.mediaFeedSourceSnapshot {
        case .follows:
            return !WebOfTrust.shared.allowedPubkeysSnapshot().isEmpty || !config.mediaRelaysSnapshot.isEmpty
        case .webOfTrust:
            return !config.mediaRelaysSnapshot.isEmpty
        default:
            return false
        }
    }
    public var onAppearSubject = PassthroughSubject<Int64,Never>()
    private var lastPaginationRequest: (until: Int64, requestedAt: Date)?
    /// Oldest event inspected by older-page reads, including events filtered
    /// before rendering. The visible tail cannot be the sole cursor: a page of
    /// seen/muted/reply events adds no rows and would otherwise be requested
    /// forever.
    private var olderPaginationScanCursor: Int64?
    private var paginationRetryNotBefore: Date?
    private var paginationRetryTask: Task<Void, Never>?
    
    @MainActor
    public var currentNRPostsOnScreen: [NRPost] {
        if case .posts(let nrPosts) = viewState {
            return nrPosts
        }
        return []
    }
    
    // Use for filling gaps. Notes:
    // - most recent on screen can be from local db from a different column, so different query and may be missing posts from earlier
    // - use newest of either: feed.newestMarkedReadAt (iCloud synced) or feed.lastLocalFetchAt (UserDefaults)
    // - if lastLocalFetchAt is newer than newestMarkedReadAt, then use that so we don't fetch the same posts over and over
    // - loadRemote() is capped to not use since older than 24 hours ago (maxAgo)

    @MainActor
    public var nextFetchSince: Int64 {
#if DEBUG
            if LESS_CACHE && IS_SIMULATOR { // Force to 6 hours ago for testing
                return (Int64(Date().timeIntervalSince1970) - 21_600)
            }
#endif
            guard let config else { // 2 days ago if config is somehow missing
                return (Int64(Date().timeIntervalSince1970) - 172_800)
            }
            
            switch config.columnType {
            case .following(let feed), .picture(let feed), .vine(let feed), .yak(let feed), .pubkeys(let feed):
                return Int64(max((feed.newestMarkedReadAt ?? .distantPast).timeIntervalSince1970, (feed.lastLocalFetchAt ?? .distantPast).timeIntervalSince1970))
            case .relays(_): // 8 hours
                if let mostRecentCreatedAt = self.mostRecentCreatedAt {
                   return Int64(mostRecentCreatedAt) // or most recent on screen
                }
                return (Int64(Date().timeIntervalSince1970) - 28_800)
            default:
                if let mostRecentCreatedAt = self.mostRecentCreatedAt {
                   return Int64(mostRecentCreatedAt) // or most recent on screen
                }
                // else take 16 hours?
                return (Int64(Date().timeIntervalSince1970) - 57_600)
            }
        
        if let mostRecentCreatedAt = self.mostRecentCreatedAt {
           return Int64(mostRecentCreatedAt) // or most recent on screen
        }
        // else take 16 hours?
        return (Int64(Date().timeIntervalSince1970) - 57_600)
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
                    
                    let queuedReadIds = Array(self.markAsReadSyncQueue)
                    guard !queuedReadIds.isEmpty else { return }
                    
                    feed.managedObjectContext?.refresh(feed, mergeChanges: true)
                    
                    // Don't add duplicates to .lastRead but also keep the most recent one
                    // so remove new markAsReadSyncQueue from existing lastRead and then prepend markAsReadSyncQueue to lastRead (move existing ids to the front again)
                    // after that when we remove > 700 it is always less recent ones that are removed.
                    let queuedReadIdSet = Set(queuedReadIds)
                    var mergedLastRead = feed.lastRead
                    mergedLastRead.removeAll { queuedReadIdSet.contains($0) }
                    mergedLastRead.insert(contentsOf: queuedReadIds, at: 0)
                    
                    // if size of feed.lastRead is > 700, remove all beyond index 700
                    if mergedLastRead.count > 700 {
                        mergedLastRead = Array(mergedLastRead[..<700])
                    }
                    
                    feed.lastRead = mergedLastRead
                    self.markAsReadSyncQueue.subtract(queuedReadIdSet)
                    DataProvider.shared().saveToDiskNow(.viewContext)
                }
                .store(in: &subscriptions)
                
            FeedsCoordinator.shared.markedAsReadSubject
                .delay(for: .milliseconds(200), scheduler: RunLoop.main)
                .sink(receiveValue: { [weak self] (postId, columnVMid) in
                    guard let self, columnVMid != self.columnVMid else { return }
                    guard SettingsStore.shared.appWideSeenTracker else { return }

                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        // A row may represent a whole reply chain, so reconcile the
                        // exact component seen in the other column. Keep the row on
                        // screen: switching feeds must never drain an inactive feed.
                        var seenShortIds = Deduplicator.shared.onScreenSeen
                        seenShortIds.insert(String(postId.prefix(8)))
                        self.removeUnreadPostsAlreadyMarkedRead(seenShortIds)
                    }
                })
                .store(in: &subscriptions)
            
            feed?.objectWillChange
                .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
                .sink(receiveValue: { [weak self] in
                    Task { @MainActor [weak self] in
                        await Task.yield()
                        self?.scheduleAlreadySeenReconciliation()
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
    
    @MainActor
    public func markAsRead(_ shortPostIds: [String]) {
        guard feed != nil else { return }
        guard SettingsStore.shared.appWideSeenTracker && SettingsStore.shared.appWideSeenTrackeriCloud else { return }
        markAsReadSyncQueue.formUnion(Set(shortPostIds))
        syncFeedSubject.send()
    }
    
    @MainActor
    private func allShortIdsSeenMergingFeedLastRead(_ feed: CloudFeed?) -> Set<String> {
        guard let feed else { return allShortIdsSeen }
        return allShortIdsSeen.union(Set(feed.lastRead))
    }
    
    @MainActor
    private func mergeFeedLastReadIntoSeen(_ feed: CloudFeed?) {
        allShortIdsSeen = allShortIdsSeenMergingFeedLastRead(feed)
    }
    
    @MainActor
    private func scheduleAlreadySeenReconciliation() {
        scheduleAlreadySeenReconciliation(removingVisiblePostsFor: [])
    }

    @MainActor
    private func scheduleAlreadySeenReconciliation(removingVisiblePostsFor syncedSeenIds: Set<String>) {
        pendingSyncedSeenIds.formUnion(syncedSeenIds)
        seenReconciliationScheduler.schedule(
            isBusy: { [weak self] in
                self?.shouldDeferSeenReconciliation ?? false
            },
            apply: { [weak self] in
                guard let self else { return }
                let syncedSeenIds = self.pendingSyncedSeenIds
                self.pendingSyncedSeenIds.removeAll(keepingCapacity: true)
                var seenShortIds = Deduplicator.shared.onScreenSeen
                seenShortIds.formUnion(syncedSeenIds)
                if let feed = self.feed,
                   SettingsStore.shared.appWideSeenTrackeriCloud {
                    self.mergeFeedLastReadIntoSeen(feed)
                    seenShortIds.formUnion(feed.lastRead)
                }
                self.removeUnreadPostsAlreadyMarkedRead(seenShortIds)
            }
        )
    }

    @MainActor
    private func removeUnreadPostsAlreadyMarkedRead(_ seenShortIds: Set<String>) {
        guard SettingsStore.shared.appWideSeenTracker else { return }
        guard !seenShortIds.isEmpty else { return }
        guard case .posts(let existingPosts) = viewState else { return }

        let postIdsMarkedRead = Set(
            existingPosts
                .filter {
                    vmInner.unreadIds[$0.id, default: 0] > 0
                        && postContainsAnyShortId($0, in: seenShortIds)
                }
                .map(\.id)
        )
        guard !postIdsMarkedRead.isEmpty else { return }

        vmInner.updateUnreadIds { unreadIds in
            for postId in postIdsMarkedRead {
                unreadIds[postId] = nil
            }
        }
        vmInner.updateIsAtTopSubject.send()
#if DEBUG
        recordFeedAction(
            "seen reconciliation · marked \(postIdsMarkedRead.count) rows read · kept \(existingPosts.count) posts"
        )
#endif
    }

    @MainActor
    private func currentVisiblePostIds() -> Set<String> {
        guard case .posts(let posts) = viewState else { return [] }

        let indexPaths: [IndexPath]
        let sectionCounts: [Int]
        if let collectionView {
            indexPaths = collectionView.indexPathsForVisibleItems
            sectionCounts = (0..<collectionView.numberOfSections).map { collectionView.numberOfItems(inSection: $0) }
        } else if let tableView {
            indexPaths = tableView.indexPathsForVisibleRows ?? []
            sectionCounts = (0..<tableView.numberOfSections).map { tableView.numberOfRows(inSection: $0) }
        } else {
            return []
        }

        return Set(indexPaths.compactMap { indexPath in
            guard let itemIndex = NXFeedIndexMapping.itemIndex(
                for: indexPath,
                sectionCounts: sectionCounts,
                itemCount: posts.count
            ), posts.indices.contains(itemIndex) else { return nil }
            return posts[itemIndex].id
        })
    }

    private func postContainsAnyShortId(_ post: NRPost, in shortIds: Set<String>) -> Bool {
        if shortIds.contains(post.shortId) { return true }
        if post.kind == 6,
           let firstQuoteId = post.firstQuoteId,
           shortIds.contains(String(firstQuoteId.prefix(8))) {
            return true
        }
        return post.parentPosts.contains { shortIds.contains($0.shortId) }
    }

    private var syncFeedSubject = PassthroughSubject<Void, Never>()

    private struct LocalLoadRequest {
        let config: NXColumnConfig
        let older: Bool
        let sessionGeneration: UInt64
        let requestedAt: Date

        var key: String {
            "\(sessionGeneration):\(config.id):\(older ? "older" : "newer")"
        }
    }

    /// Local reads are serialized and equivalent pending reads are coalesced.
    /// Unlike Combine's `debounce`, every caller's completion is retained.
    @MainActor
    private lazy var localLoadCoordinator = NXLocalLoadCoordinator<LocalLoadRequest>(
        key: { $0.key },
        perform: { [weak self] request, finished in
            guard let self else {
                finished()
                return
            }
#if DEBUG
            let coordinatorWait = Date().timeIntervalSince(request.requestedAt)
            if coordinatorWait >= 0.05 {
                self.recordFeedAction(
                    "FETCH \(request.older ? "older" : "newer") · coordinator delayed \(self.debugSeconds(since: request.requestedAt))"
                )
            }
#endif
            self._loadLocal(
                request.config,
                older: request.older,
                sessionGeneration: request.sessionGeneration,
                requestedAt: request.requestedAt,
                completion: finished
            )
        }
    )

    /// Invalidates every asynchronous result produced for an older feed run.
    @MainActor private var feedSessionGeneration: UInt64 = 0
    
    private func resetCancellables() {
        newEventsInDatabaseSub?.cancel()
        pageEventsInDatabaseSub?.cancel()
        newPostSavedSub?.cancel()
        newSingleRelayPostSavedSub?.cancel()
        newPostUndoSub?.cancel()
        firstConnectionSub?.cancel()
        reloadWhenNeededSub?.cancel()
        lastDisconnectionSub?.cancel()
        onAppearSubjectSub?.cancel()
        onScreenSeenInsertedSub?.cancel()
        cloudSeenInsertedSub?.cancel()
        saveLocalStateSub?.cancel()
        muteListUpdatedSub?.cancel()
        mutedWordsChangedSub?.cancel()
        blockListUpdatedSub?.cancel()
        followsChangedSub?.cancel()
        resumeFeedSub?.cancel()
        pauseFeedSub?.cancel()
        saveFeedStateSub?.cancel()
        nextTickSub?.cancel()
    }

    @MainActor
    public func initialize(_ config: NXColumnConfig, speedTest: NXSpeedTest) {
        attachRestoreCoverIfNeeded()
        var config = config
        refreshMediaSnapshots(in: &config)
        stopMediaDiscoverySession()
        selectedRelayRecoveryTask?.cancel()
        selectedRelayRecoveryTask = nil
        mediaSearchTimedOut = false
        mediaUpdatesAvailable = false
        autoExploreRelaysAfterWoTTimeout = false
        selectedRelayAutoRetryAttempted = false
        clearLatestFeedSession()
        seenReconciliationScheduler.cancel()
        pendingSyncedSeenIds.removeAll(keepingCapacity: true)
        // get initial feed state from
        self.subscriptions.forEach { $0.cancel() }
        self.subscriptions.removeAll()
        self.config = config
        self.speedTest = speedTest
        listenForLateMediaUpdates(config)
        
        self.feed = config.feed
        
        // Set up gap filler, don't trigger yet here
        gapFiller = NXGapFiller(since: self.nextFetchSince, windowSize: 4, timeout: 2.0, currentGap: 0, columnVM: self)
        isViewPaused = false
        guard isVisible else { return }
        self.resetCancellables()
        paused = false
        FeedsCoordinator.shared.registerColumn(self)
        
//        // Change to loading if we were displaying posts before
//        if case .posts(_) = viewState {
//            viewState = .loading
//        }
        
        firstLoad(config)
        
        newPostSavedSub?.cancel()
        newPostSavedSub = nil
        listenForOwnNewPostSaved(config)
        
        newSingleRelayPostSavedSub?.cancel()
        newSingleRelayPostSavedSub = nil
        listenForOwnNewSingleRelayPostSaved(config)
        
        newPostUndoSub?.cancel()
        newPostUndoSub = nil
        listenForOwnNewPostUndo(config)
        
        newEventsInDatabaseSub?.cancel()
        newEventsInDatabaseSub = nil
        pageEventsInDatabaseSub?.cancel()
        pageEventsInDatabaseSub = nil
        listenForNewPosts(config)
        listenForPaginationImports(config)
        
        firstConnectionSub?.cancel()
        firstConnectionSub = nil
        listenForFirstConnection(config: config)
        
        onAppearSubjectSub?.cancel()
        onAppearSubjectSub = nil
        loadMoreWhenNearBottom(config)
        
        reloadWhenNeededSub?.cancel()
        reloadWhenNeededSub = nil
        reloadWhenNeeded(config)

        onScreenSeenInsertedSub?.cancel()
        onScreenSeenInsertedSub = nil
        cloudSeenInsertedSub?.cancel()
        cloudSeenInsertedSub = nil
        listenForOnScreenSeenInserted(config)

        resumeFeedSub?.cancel()
        resumeFeedSub = nil
        
        pauseFeedSub?.cancel()
        pauseFeedSub = nil
        listenForPauseFeed(config)
        
        saveFeedStateSub?.cancel()
        saveFeedStateSub = nil
        listenForSaveFeedStates(config)
        
        saveLocalStateSub?.cancel()
        saveLocalStateSub = nil
        listenForSaveLocalFeedState(config)
        
        
        // if config.columnType is .following / .picture / .vine / .yak
        switch config.columnType {
        case .following, .picture, .vine, .yak:
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
        
        mutedWordsChangedSub?.cancel()
        mutedWordsChangedSub = nil
        listenForMutedWordsChangedSub(config)
        
        nextTickSub?.cancel()
        nextTickSub = nil
        listenForNextTickSub(config)
    }
    
    @MainActor
    private func listenForOnScreenSeenInserted(_ config: NXColumnConfig) {
        guard onScreenSeenInsertedSub == nil else { return }
        guard SettingsStore.shared.appWideSeenTracker else { return }

        switch config.columnType {
        case .picture, .vine, .yak, .pubkeysPreview, .relayPreview:
            return
        default:
            break
        }

        onScreenSeenInsertedSub = Deduplicator.shared.onScreenSeenInsertedSubject
            .sink { [weak self] _ in
                self?.scheduleAlreadySeenReconciliation()
            }

        cloudSeenInsertedSub = Deduplicator.shared.cloudSeenInsertedSubject
            .sink { [weak self] syncedSeenIds in
                self?.scheduleAlreadySeenReconciliation(removingVisiblePostsFor: syncedSeenIds)
            }
    }

    private var nextTickSub: AnyCancellable?
    public func fetchFeedTimerNextTick() {
        nextTickSubject.send()
    }
    
    private var nextTickSubject = PassthroughSubject<Void, Never>()
    
#if DEBUG
    private func startFirstUnreadMeasurementIfNeeded(_ config: NXColumnConfig, reason: String) {
        guard shouldMeasureFirstUnread(config) else { return }
        vmInner.startFirstUnreadMeasurement(feedName: config.name, reason: reason)
    }
    
    private func shouldMeasureFirstUnread(_ config: NXColumnConfig) -> Bool {
        guard case .following = config.columnType else { return false }
        return config.name != "Explore"
    }
#endif
    
    @MainActor
    private func listenForNextTickSub(_ config: NXColumnConfig) {
        guard nextTickSub == nil else { return }
        nextTickSub = nextTickSubject
            .throttle(for: .seconds(9), scheduler: RunLoop.main, latest: false)
            .sink { [weak self] _ in
                self?._fetchFeedTimerNextTick()
            }
    }
    
    @MainActor
    private func firstLoad(_ config: NXColumnConfig) {
        let resumeWhereLeftOff = config.continue
        isViewPaused = false
#if DEBUG
        speedTest?.start(trigger: "firstLoad", feedName: config.name)
#else
        speedTest?.start()
#endif
        scheduleInitialMediaTimeout(for: config)
        scheduleSelectedRelayRecovery(for: config)
#if DEBUG
        startFirstUnreadMeasurementIfNeeded(config, reason: "firstLoad")
#endif
        
        // For SomeoneElses feed we need to fetch kind 3 first, before we can do loadLocal/loadRemote
        if case .someoneElses(let pubkey) = config.columnType {
            // Reset all posts already seen for SomeoneElses Feed
            allShortIdsSeen = []
            fetchKind3ForSomeoneElsesFeed(pubkey, config: config) { [weak self] updatedConfig in
                self?.config = updatedConfig
                self?.scheduleInitialRemoteFetch(updatedConfig)
            }
        }
        else { // Else we can start as normal with loadLocal
            if config.mediaFeedSourceSnapshot == .selectedRelays {
                switch config.columnType {
                case .picture, .vine, .yak:
                    for relayData in config.mediaRelaysSnapshot {
                        ConnectionPool.shared.addConnection(relayData) { connection in
                            connection.connect()
                        }
                    }
                default:
                    break
                }
            }
            
            // if relay feed, make sure relay is added to ConnectionPool
            if case .relays(let feed) = config.columnType {
                for relayData in feed.relaysData {
                    ConnectionPool.shared.addConnection(relayData) { conn in
                        conn.connect()
                    }
                }
                ConnectionPool.shared.queue.async(flags: .barrier) { [weak self] in
                    // ConnectionPool owns this queue; the config contains a
                    // main-context CloudFeed. Cross back before touching the
                    // view model or starting local feed restoration.
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if resumeWhereLeftOff {
                            // Start the relay request while the saved screen restores.
                            // The serialized local loader keeps imported results behind
                            // restoration, so they cannot overwrite each other.
                            self.loadLocal(config)
                            self.scheduleInitialRemoteFetch(config)
                        }
                        else {
                            self.scheduleInitialRemoteFetch(config)
                        }
                    }
                }
            }
            else if case .relayPreview(let relayData) = config.columnType {
                ConnectionPool.shared.addConnection(relayData) { [weak self] conn in
                    conn.connect()
                    
                    // Relay Preview without Resume-Where-Left
                    self?.scheduleInitialRemoteFetch(config)
                }
            }
            else {
                if resumeWhereLeftOff {
                    // Network and local restore can overlap. Waiting for all saved
                    // rows to render added about a second to every Mac column before
                    // its first-unread request even entered the scheduler.
                    loadLocal(config)
                    scheduleInitialRemoteFetch(config)
                }
                else {
                    scheduleInitialRemoteFetch(config)
                }
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
                    
                    let unreadIdsToRemove = existingPosts.compactMap { nrPost in
                        (mutedRootIds.contains(nrPost.id) || mutedRootIds.contains(nrPost.replyToRootId ?? "!"))
                            ? nrPost.id
                            : nil
                    }
                    vmInner.updateUnreadIds { unreadIds in
                        for id in unreadIdsToRemove {
                            unreadIds[id] = nil
                        }
                    }
                    if !unreadIdsToRemove.isEmpty {
                        vmInner.updateIsAtTopSubject.send()
                    }
                    
                    for nrPost in existingPosts {
                        nrPost.muted = mutedRootIds.contains(nrPost.id)
                            || mutedRootIds.contains(nrPost.replyToRootId ?? "!")
                            || (nrPost.isRepost && mutedRootIds.contains(nrPost.firstQuoteId ?? "!"))
                    }
                    viewState = .posts(existingPosts)
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
                    
                    let unreadIdsToRemove = existingPosts.compactMap { nrPost in
                        blocks.contains(nrPost.pubkey) ? nrPost.id : nil
                    }
                    vmInner.updateUnreadIds { unreadIds in
                        for id in unreadIdsToRemove {
                            unreadIds[id] = nil
                        }
                    }
                    if !unreadIdsToRemove.isEmpty {
                        vmInner.updateIsAtTopSubject.send()
                    }
                    
                    viewState = .posts(existingPosts.filter { nrPost in
                        return !blocks.contains(nrPost.pubkey) // pubkey not blocked
                            && !(nrPost.isRepost && blocks.contains(nrPost.firstQuote?.pubkey ?? "!")) // is not: repost + blocked reposted pubkey
                    })
                }
            }
    }
    
    private var mutedWordsChangedSub: AnyCancellable?
    
    @MainActor
    private func listenForMutedWordsChangedSub(_ config: NXColumnConfig) {
        guard mutedWordsChangedSub == nil else { return }
        mutedWordsChangedSub = receiveNotification(.mutedWordsChanged)
            .sink { [weak self] notification in
                guard let self else { return }
                guard case .posts(let existingPosts) = viewState else { return }
                let mutedWords = (notification.object as? [String]) ?? AppState.shared.bgAppState.mutedWords
                if mutedWords.isEmpty {
                    reload(config)
                    return
                }
                
                let unreadIdsToRemove = existingPosts.compactMap { nrPost in
                    !notMutedWords(in: nrPost.plainText, mutedWords: mutedWords)
                        ? nrPost.id
                        : nil
                }
                vmInner.updateUnreadIds { unreadIds in
                    for id in unreadIdsToRemove {
                        unreadIds[id] = nil
                    }
                }
                if !unreadIdsToRemove.isEmpty {
                    vmInner.updateIsAtTopSubject.send()
                }
                
                viewState = .posts(existingPosts.filter { nrPost in
                    notMutedWords(in: nrPost.plainText, mutedWords: mutedWords)
                })
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
                case .picture(_), .vine(_), .yak(_):
                    (config.account?.followingPubkeys ?? []).union(Set([config.accountPubkey ?? ""]))
                default:
                    []
                }

                let currentIdsOnScreen = self.currentIdsOnScreen
                let repliesEnabled = config.repliesEnabled
                
                let event = notification.object as! Event
                bg().perform { [weak self] in
                    // Make sure the post is not a reply or that replies are enabled for this feed
                    guard event.replyToId == nil || repliesEnabled else { return }
                    
                    // Only kind 1222/1244 on yak-only feed
                    if case .yak(_) = config.columnType, (event.kind != 1222 && event.kind != 1244) {
                        return
                    }
                    
                    // Only kind 34236 on picture-only feed
                    if case .vine(_) = config.columnType, event.kind != 34236 {
                        return
                    }
                    
                    // Only kind 20 on picture-only feed
                    if case .picture(_) = config.columnType, (event.kind != 20 && !(event.kind == 1 && event.kTag == 20)) {
                        return
                    }
                    
                    // No kind 20 on following feed
                    if case .following(_) = config.columnType, (event.kind == 20 || (event.kind == 1 && event.kTag == 20))  {
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
    private func listenForOwnNewSingleRelayPostSaved(_ config: NXColumnConfig) {
        guard newSingleRelayPostSavedSub == nil else { return }
        newSingleRelayPostSavedSub = receiveNotification(.newSingleRelayPostSaved)
            .sink { [weak self] notification in
                guard let self else { return }

                let currentIdsOnScreen = self.currentIdsOnScreen
                let repliesEnabled = config.repliesEnabled
                
                let (event, relayData) = notification.object as! (Event, RelayData)
                guard case .relays(let feed) = config.columnType else { return }
                guard feed.relaysData.contains(where: { $0.id == relayData.id }) else { return }
                
                bg().perform { [weak self] in
                    // Make sure the post is not a reply or that replies are enabled for this feed
                    guard event.replyToId == nil || repliesEnabled else { return }
                    
                    guard !currentIdsOnScreen.contains(event.id) else { return }
                    EventRelationsQueue.shared.addAwaitingEvent(event, debugInfo: "NXColumnViewModel.listenForOwnNewSingleRelayPostSaved")
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
                    vmInner.updateUnreadIds { unreadIds in
                        unreadIds[nrPost.id] = nil
                    }
                    vmInner.updateIsAtTopSubject.send()
                    viewState = .posts(existingPosts.filter { $0.id != nrPost.id })
                }
            }
    }
    
    // Reload (after toggle replies enabled etc)
    @MainActor
    public func reload(_ config: NXColumnConfig, refreshRemote: Bool = false) {
        var config = config
        refreshMediaSnapshots(in: &config)
        if config.mediaFeedSourceSnapshot == .selectedRelays,
           self.config?.mediaFeedSourceSnapshot != .selectedRelays {
            selectedRelayAutoRetryAttempted = false
        }
        let isExpandingMediaSource = self.config?.mediaFeedSourceSnapshot == .follows
            && config.mediaFeedSourceSnapshot == .webOfTrust
            && !currentNRPostsOnScreen.isEmpty
        mediaUpdatesAvailable = false
        self.config = config
        clearLatestFeedSession()
#if DEBUG
        speedTest?.start(trigger: "reload", feedName: config.name)
#else
        speedTest?.start()
#endif
        if case .timeout = viewState {
            viewState = .loading
            firstLoad(config)
        }
        else if case .error = viewState {
            viewState = .loading
            firstLoad(config)
        }
        else {
            // WoT is a superset of follows. Keep valid follow posts visible while
            // the broader local/network search adds results around them.
            if !isExpandingMediaSource {
                viewState = .loading
            }
            scheduleInitialMediaTimeout(for: config)
            scheduleSelectedRelayRecovery(for: config)
            if SettingsStore.shared.appWideSeenTracker {
                Deduplicator.shared.onScreenSeen = []
            }
            config.feed?.lastRead = []
            self.allShortIdsSeen = []
            paused = false
            FeedsCoordinator.shared.registerColumn(self)
            if config.continue {
                if refreshRemote, config.mediaFeedSourceSnapshot != nil {
                    // A source change replaces the current screen. Search all locally
                    // available history so older follow posts do not disappear merely
                    // because the normal initial query is limited to the last 8 hours.
                    loadAnyFlag = true
                }
                loadLocal(config) { [weak self] in
                    guard refreshRemote else { return }
                    Task { @MainActor in
                        if config.mediaFeedSourceSnapshot != nil {
                            // loadLocal consumes this flag. Restore it so the
                            // following relay request also asks for bounded history.
                            self?.loadAnyFlag = true
                        }
                        await self?.loadRemote(config)
                    }
                }
            }
            else {
                Task { [weak self] in
                    await self?.loadRemote(config)
                }
            }
        }
    }

    @MainActor
    private func refreshMediaSnapshots(in config: inout NXColumnConfig, sourceOverride: MediaFeedSource? = nil) {
        guard let feed = config.feed else {
            config.mediaFeedSourceSnapshot = nil
            config.mediaAllowedPubkeysSnapshot = []
            config.mediaRelaysSnapshot = []
            return
        }

        switch config.columnType {
        case .picture, .vine, .yak:
            let source = sourceOverride ?? feed.mediaFeedSource
            config.mediaFeedSourceSnapshot = source
            config.mediaRelaysSnapshot = feed.mediaDiscoveryRelays
            switch source {
            case .follows:
                if let account = feed.account {
                    config.mediaAllowedPubkeysSnapshot = account.followingPubkeys
                        .union(account.privateFollowingPubkeys)
                        .union([account.publicKey])
                }
                else {
                    config.mediaAllowedPubkeysSnapshot = []
                }
            case .webOfTrust:
                // "My WoT" is a broader source than "My follows". Keep that
                // relationship explicit even when the global WoT cache belongs to a
                // different main account or has not finished rebuilding yet.
                let feedAccountPubkeys: Set<String>
                if let account = feed.account {
                    feedAccountPubkeys = account.followingPubkeys
                        .union(account.privateFollowingPubkeys)
                        .union([account.publicKey])
                }
                else {
                    feedAccountPubkeys = []
                }
                config.mediaAllowedPubkeysSnapshot = WebOfTrust.shared.allowedPubkeysSnapshot()
                    .union(feedAccountPubkeys)
            case .selectedRelays:
                config.mediaAllowedPubkeysSnapshot = []
            }
        default:
            config.mediaFeedSourceSnapshot = nil
            config.mediaAllowedPubkeysSnapshot = []
            config.mediaRelaysSnapshot = []
        }
    }

    @MainActor
    private func scheduleInitialMediaTimeout(for config: NXColumnConfig) {
        initialMediaTimeoutTask?.cancel()
        switch config.columnType {
        case .picture, .vine, .yak:
            break
        default:
            return
        }

        let configId = config.id
        let timeoutNanoseconds: UInt64 = 12_000_000_000
        initialMediaTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            guard !Task.isCancelled else { return }
            guard let self, self.config?.id == configId else { return }
            guard self.mediaDiscoverySubscriptionId == nil else { return }
            guard case .loading = self.viewState else { return }
            if self.autoExploreRelaysAfterWoTTimeout,
               config.mediaFeedSourceSnapshot == .webOfTrust,
               !config.mediaRelaysSnapshot.isEmpty {
                self.autoExploreRelaysAfterWoTTimeout = false
                self.loadTemporaryMediaSource(.selectedRelays, from: config)
                return
            }
            if config.mediaFeedSourceSnapshot == .selectedRelays,
               !self.selectedRelayAutoRetryAttempted,
               !config.mediaRelaysSnapshot.isEmpty {
                // The first relay pass can import a bounded batch just after the
                // UI's outer deadline. Retry the now-connected relay and query all
                // history automatically; this is the same pass that previously
                // required the user to press Retry.
                self.selectedRelayAutoRetryAttempted = true
                self.mediaSearchTimedOut = false
                self.viewState = .loading
                self.loadAnyFlag = true
                self.firstLoad(config)
                return
            }
            self.mediaSearchTimedOut = false
            self.speedTest?.finishedWithoutResults()
            self.stopMediaDiscoverySession()
            self.viewState = .timeout
        }
    }

    @MainActor
    private func scheduleSelectedRelayRecovery(for config: NXColumnConfig) {
        selectedRelayRecoveryTask?.cancel()
        selectedRelayRecoveryTask = nil
        guard config.mediaFeedSourceSnapshot == .selectedRelays,
              !config.mediaRelaysSnapshot.isEmpty
        else { return }

        let configId = config.id
        selectedRelayRecoveryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            guard let self,
                  self.config?.id == configId,
                  self.config?.mediaFeedSourceSnapshot == .selectedRelays,
                  self.currentNRPostsOnScreen.isEmpty,
                  case .loading = self.viewState,
                  self.mediaDiscoverySubscriptionId == nil
            else { return }

            // Use the direct bounded discovery path once the selected socket has
            // had time to connect. This is equivalent to the formerly successful
            // manual Retry, but happens before an empty state can be shown.
            self.loadTemporaryMediaSource(.selectedRelays, from: config, attempt: 1)
        }
    }

    @MainActor
    func exploreMore(_ fallbackConfig: NXColumnConfig) {
        let currentConfig = config ?? fallbackConfig
        switch currentConfig.mediaFeedSourceSnapshot {
        case .follows:
            var wotConfig = currentConfig
            refreshMediaSnapshots(in: &wotConfig, sourceOverride: .webOfTrust)
            if wotConfig.mediaAllowedPubkeysSnapshot.isEmpty {
                guard !wotConfig.mediaRelaysSnapshot.isEmpty else { return }
                loadTemporaryMediaSource(.selectedRelays, from: wotConfig)
            }
            else {
                autoExploreRelaysAfterWoTTimeout = true
                loadTemporaryMediaSource(.webOfTrust, from: wotConfig)
            }
        case .webOfTrust:
            guard !currentConfig.mediaRelaysSnapshot.isEmpty else { return }
            autoExploreRelaysAfterWoTTimeout = false
            loadTemporaryMediaSource(.selectedRelays, from: currentConfig)
        default:
            break
        }
    }

    @MainActor
    private func loadTemporaryMediaSource(
        _ source: MediaFeedSource,
        from currentConfig: NXColumnConfig,
        attempt: Int = 0
    ) {
        stopMediaDiscoverySession()
#if DEBUG
        speedTest?.start(trigger: "mediaDiscover", feedName: currentConfig.name)
#else
        speedTest?.start()
#endif
        var temporaryConfig = currentConfig
        refreshMediaSnapshots(in: &temporaryConfig, sourceOverride: source)
        config = temporaryConfig
        mediaSearchTimedOut = false
        mediaUpdatesAvailable = false
        listenForLateMediaUpdates(temporaryConfig)
        viewState = .loading
        ConnectionPool.shared.closeSubscription(temporaryConfig.id)

        if source == .selectedRelays {
            for relay in temporaryConfig.mediaRelaysSnapshot {
                ConnectionPool.shared.addConnection(relay) { $0.connect() }
            }
        }

        let subscriptionId = "prio-MEDIA-DISC-" + String(UUID().uuidString.prefix(16))
        mediaDiscoverySubscriptionId = subscriptionId
        paused = false
        FeedsCoordinator.shared.registerColumn(self)
        loadLocal(temporaryConfig) { [weak self] in
            Task { @MainActor in
                guard let self, self.mediaDiscoverySubscriptionId == subscriptionId else { return }
                if source == .selectedRelays {
                    _ = await ConnectionPool.shared.waitForAnyConnectedRelay(
                        in: temporaryConfig.mediaRelaysSnapshot
                    )
                    guard self.mediaDiscoverySubscriptionId == subscriptionId else { return }
                }
                let targets = ConnectionPool.shared.requestTargetSnapshot(
                    relays: source == .selectedRelays ? temporaryConfig.mediaRelaysSnapshot : []
                )
                // Start completion timing only now: the preceding local fetch can
                // be delayed by other Core Data work and is not network wait time.
                self.startMediaDiscoveryTracker(
                    subscriptionId: subscriptionId,
                    targets: targets,
                    config: temporaryConfig,
                    attempt: attempt
                )
                self.speedTest?.requestStarted()
#if DEBUG
                FeedFetchDebug.shared.attach(
                    self.speedTest,
                    subscriptionId: subscriptionId,
                    summary: "\(temporaryConfig.name) media \(source.rawValue)",
                    seeds: ConnectionPool.shared.feedFetchDebugSeeds(
                        for: targets.relayIds,
                        outboxIds: targets.extraIds
                    ),
                    targetSnapshot: targets
                )
#endif
                self.sendBroadMediaReq(
                    temporaryConfig,
                    subscriptionId: subscriptionId,
                    limit: source == .selectedRelays ? 50 : 200
                )
            }
        }
    }

    @MainActor
    private func listenForLateMediaUpdates(_ config: NXColumnConfig) {
        lateMediaEventSub?.cancel()

        let kinds: Set<Int>
        switch config.columnType {
        case .vine:
            kinds = [34236]
        case .yak:
            kinds = [1222, 1244]
        case .picture:
            kinds = [20]
        default:
            return
        }

        let source = config.mediaFeedSourceSnapshot ?? .follows
        let configId = config.id
        let allowedPubkeys = config.mediaAllowedPubkeysSnapshot
        let selectedRelayIds = Set(config.mediaRelaysSnapshot.map(\.id))
        lateMediaEventSub = FeedsCoordinator.shared.notificationNeedsUpdateSubject
            .compactMap(\.event)
            .filter { event in
                guard kinds.contains(Int(event.kind)), !event.isMutedByWords else { return false }
                switch source {
                case .follows, .webOfTrust:
                    return allowedPubkeys.contains(event.pubkey)
                case .selectedRelays:
                    let receivedRelayIds = Set((event.relays ?? "")
                        .split(separator: " ")
                        .map { normalizeRelayUrl(String($0)) })
                    return !selectedRelayIds.isDisjoint(with: receivedRelayIds)
                }
            }
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self,
                          self.config?.id == configId,
                          self.config?.mediaFeedSourceSnapshot == source
                    else { return }
                    self.mediaUpdatesAvailable = true
                }
            }
    }

    @MainActor
    func showAvailableMediaUpdates(_ fallbackConfig: NXColumnConfig) {
        let activeConfig = config ?? fallbackConfig
        mediaUpdatesAvailable = false
        mediaSearchTimedOut = false
        viewState = .loading
        loadAnyFlag = true
        loadLocal(activeConfig)
    }

    @MainActor
    private func startMediaDiscoveryTracker(
        subscriptionId: String,
        targets: ConnectionPool.RequestTargetSnapshot,
        config: NXColumnConfig,
        attempt: Int
    ) {
        mediaDiscoveryTracker = BoundedRelayRequestCompletionTracker(
            subscriptionId: subscriptionId,
            targets: targets,
            onImport: { [weak self] in
                self?.scheduleMediaDiscoveryImport(subscriptionId: subscriptionId, config: config)
            },
            onCompletion: { [weak self] outcome in
                guard let self, self.mediaDiscoverySubscriptionId == subscriptionId else { return }
                switch outcome {
                case .finished:
                    self.scheduleMediaDiscoveryImport(
                        subscriptionId: subscriptionId,
                        config: config,
                        concludeAfterImport: true,
                        attempt: attempt
                    )
                case .timedOut:
                    if case .posts = self.viewState {
                        self.stopMediaDiscoverySession()
                        self.sendRealtimeReq(config)
                    }
                    else if self.autoExploreRelaysAfterWoTTimeout,
                            config.mediaFeedSourceSnapshot == .webOfTrust,
                            !config.mediaRelaysSnapshot.isEmpty {
                        self.autoExploreRelaysAfterWoTTimeout = false
                        self.loadTemporaryMediaSource(.selectedRelays, from: config)
                    }
                    else if config.mediaFeedSourceSnapshot == .selectedRelays,
                            attempt == 0,
                            !config.mediaRelaysSnapshot.isEmpty {
                        // A connection can become ready just after the first bounded
                        // request's deadline. Retry once transparently before making
                        // the user press Retry for a relay known to contain media.
                        self.loadTemporaryMediaSource(.selectedRelays, from: config, attempt: 1)
                    }
                    else {
                        self.mediaSearchTimedOut = true
                        self.speedTest?.finishedWithoutResults()
                        self.stopMediaDiscoverySession()
                        self.sendRealtimeReq(config)
                        self.viewState = .timeout
                    }
                }
            }
        )
        mediaDiscoveryTracker?.start()
    }

    @MainActor
    private func scheduleMediaDiscoveryImport(
        subscriptionId: String,
        config: NXColumnConfig,
        concludeAfterImport: Bool = false,
        attempt: Int = 0
    ) {
        let shouldConclude = concludeAfterImport
        mediaDiscoveryImportTask?.cancel()
        mediaDiscoveryImportTask = Task { [weak self] in
            if !shouldConclude {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard !Task.isCancelled else { return }
            guard let self, self.mediaDiscoverySubscriptionId == subscriptionId else { return }
            self.loadAnyFlag = true
            self.loadLocal(config) { [weak self] in
                guard let self, self.mediaDiscoverySubscriptionId == subscriptionId else { return }
                guard shouldConclude else { return }
                if self.currentNRPostsOnScreen.isEmpty {
                    self.confirmEmptyMediaDiscovery(
                        subscriptionId: subscriptionId,
                        config: config,
                        attempt: attempt
                    )
                }
                else {
                    self.stopMediaDiscoverySession()
                    self.sendRealtimeReq(config)
                }
            }
        }
    }

    @MainActor
    private func confirmEmptyMediaDiscovery(
        subscriptionId: String,
        config: NXColumnConfig,
        attempt: Int
    ) {
        // Priority imports are intentionally fast and can finish close to EOSE.
        // Flush the shared importer context, then enqueue one authoritative final
        // read before showing an empty result.
        DataProvider.shared().saveToDiskNow(.bgContext) { [weak self] in
            Task { @MainActor in
                guard let self, self.mediaDiscoverySubscriptionId == subscriptionId else { return }
                self.loadAnyFlag = true
                self.loadLocal(config) { [weak self] in
                    Task { @MainActor in
                        guard let self, self.mediaDiscoverySubscriptionId == subscriptionId else { return }
                        if self.currentNRPostsOnScreen.isEmpty {
                            self.finishEmptyMediaDiscovery(config: config, attempt: attempt)
                        }
                        else {
                            self.stopMediaDiscoverySession()
                            self.sendRealtimeReq(config)
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func finishEmptyMediaDiscovery(config: NXColumnConfig, attempt: Int) {
        if autoExploreRelaysAfterWoTTimeout,
           config.mediaFeedSourceSnapshot == .webOfTrust,
           !config.mediaRelaysSnapshot.isEmpty {
            autoExploreRelaysAfterWoTTimeout = false
            loadTemporaryMediaSource(.selectedRelays, from: config)
            return
        }
        if config.mediaFeedSourceSnapshot == .selectedRelays,
           attempt == 0,
           !config.mediaRelaysSnapshot.isEmpty {
            loadTemporaryMediaSource(.selectedRelays, from: config, attempt: 1)
            return
        }
        mediaSearchTimedOut = false
        speedTest?.finishedWithoutResults()
        stopMediaDiscoverySession()
        sendRealtimeReq(config)
        viewState = .timeout
    }

    @MainActor
    private func stopMediaDiscoverySession() {
        initialMediaTimeoutTask?.cancel()
        mediaDiscoveryImportTask?.cancel()
        mediaDiscoveryImportTask = nil
        mediaDiscoveryTracker?.cancel()
        mediaDiscoveryTracker = nil
        if let mediaDiscoverySubscriptionId {
            ConnectionPool.shared.closeSubscription(mediaDiscoverySubscriptionId)
        }
        mediaDiscoverySubscriptionId = nil
    }
    
    // for pausing fetching / loading
    public var isPaused: Bool { paused }
    
    // only for pausing view updates (to fix to detail and back withAnimation { } issue_
    public var isViewPaused: Bool = false
    
    @MainActor
    public func pauseViewUpdates() {
        if case .loading = viewState { return }
        isViewPaused = true
    }
    
    @MainActor
    public func resumeViewUpdates() {
        guard let config, isViewPaused else { return }
        isViewPaused = false
#if DEBUG
        recordFeedAction("RESUME view updates · \(feedActionDebugViewport())")
#endif
        self.loadLocal(config)
    }
    
    @MainActor
    public func pause() {
        guard let config, !isPaused else { return }
        
        if IS_CATALYST { // Don't pause "Following" feed on macOS
            if config.id.starts(with: "Following-") {
                return
            }
        }
        
#if DEBUG
        L.og.debug("☘️☘️ \(config.name) pause() -[LOG]-")
        recordFeedAction("PAUSE · \(feedActionDebugViewport())")
#endif
        paused = true
        self.lastResumeStartedAt = nil
        if lastBecameInactiveAt == nil {
            lastBecameInactiveAt = Date()
        }
        self.realTimeReqTask?.cancel()
        
        switch config.columnType {
        case .picture(_), .vine(_), .yak(_):
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
    
    @MainActor
    public func saveFeedState() {
        guard let config else { return }
        guard let feedId = config.feed?.id?.uuidString else { return }

        let onScreenIds: [String] = config.continue ? self.currentNRPostsOnScreen.map { $0.id } : []
        let parentIds: Set<String> = config.continue ? Set(currentNRPostsOnScreen.flatMap { $0.parentPosts.map {  $0.id } }) : []
        var scrollToId: String? = nil
        
        if config.continue {
            for post in self.currentNRPostsOnScreen {
                if vmInner.unreadIds[post.id] == nil {
                    scrollToId = post.id
                    break
                }
                else if let unreadCount = vmInner.unreadIds[post.id], unreadCount == 0 {
                    scrollToId = post.id
                    break
                }
            }
        }
        
        let feedState = LocalFeedState(
            cloudFeedId: feedId,
            onScreenIds: onScreenIds, // restore ids on screen and dont delete during maintenance
            parentIds: parentIds, // To render on with-replies feed, and so they don't get deleted during maintenance
            scrollToId: scrollToId
        )
        
        LocalFeedStateManager.shared.updateFeedState(feedState)
        
#if DEBUG
        L.og.debug("💾 Feed states: ☘️☘️ \(config.name) saveFeedState() \(feedId) - onScreenIds: \(onScreenIds.count) - parentIds: \(parentIds.count) - scrollToId: \(scrollToId ?? "") -[LOG]-")
#endif
    }
    
    private func scheduleInitialRemoteFetch(_ config: NXColumnConfig) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            FeedsCoordinator.shared.scheduleNetworkStart(id: self.columnVMid) { [weak self] in
                guard let self else { return }
                if FeedsCoordinator.shared.hasMultipleVisibleColumns {
                    self.fetchFeedTimerNextTick()
                }
                Task {
                    await self.loadRemote(config)
                }
            }
        }
    }
    
#if DEBUG
    @MainActor
    func debugFetchNow() {
        lastResumeStartedAt = nil
        lastBecameInactiveAt = Date().addingTimeInterval(-(LATEST_FEED_RESUME_REFRESH_AFTER + 1))
        resume()
    }
#endif

    @MainActor
    public func resume() {
        guard let config else { return }
        let now = Date()
        if let lastResumeStartedAt, now.timeIntervalSince(lastResumeStartedAt) < 2.0 {
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) resume() skipped, already resumed recently -[LOG]-")
            recordFeedAction("RESUME skip · already resumed <2s · \(feedActionDebugViewport())")
#endif
            return
        }
        lastResumeStartedAt = now
        // Scene phase often flickers .inactive and resets lastBecameInactiveAt.
        // lastBackgroundDuration is the real background interval (only valid
        // for a few seconds after foreground).
        let awayFor = max(
            lastBecameInactiveAt.map { now.timeIntervalSince($0) } ?? 0,
            AppState.shared.lastBackgroundDuration(now: now)
        )
        lastBecameInactiveAt = nil
#if DEBUG
        L.og.debug("☘️☘️ \(config.name) resume() isAtTop: \(self.vmInner.isAtTop) away: \(awayFor)s -[LOG]-")
        recordFeedAction(
            "RESUME · away \(String(format: "%.1f", awayFor))s · continue \(config.continue) · \(feedActionDebugViewport())"
        )
#endif
        paused = false
        isViewPaused = false
        FeedsCoordinator.shared.registerColumn(self)
        self.fetchFeedTimerNextTick()
        self.listenForNewPosts(config)
        self.listenForPaginationImports(config)

        if !config.continue,
           case .posts(let nrPosts) = viewState,
           awayFor < LATEST_FEED_RESUME_REFRESH_AFTER {
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) resume() Remember-off short away, fetch newer -[LOG]-")
            speedTest?.start(trigger: "resumeNewer", feedName: config.name)
#else
            speedTest?.start()
#endif
            let maxAgo = Int(Date().addingTimeInterval(-86_400).timeIntervalSince1970)
            let since = Int((nrPosts.first?.created_at ?? nextFetchSince) - 300)
            gapFiller?.fetchNewer(since: max(since, maxAgo), limit: 75)
            return
        }

#if DEBUG
        speedTest?.start(trigger: "resume", feedName: config.name)
        startFirstUnreadMeasurementIfNeeded(config, reason: "resume")
#else
        speedTest?.start()
#endif

        if config.continue {
            self.loadLocal(config) { [weak self] in
                Task {
                    await self?.loadRemote(config)
                }
            }
        }
        else {
            if case .posts = viewState {
#if DEBUG
                L.og.debug("☘️☘️ \(config.name) resume() Remember-off stale, start empty -[LOG]-")
#endif
                viewState = .loading
                isViewPaused = false
                vmInner.abortPreparedScrollRestore()
                clearLatestFeedSession()
                if SettingsStore.shared.appWideSeenTracker {
                    Deduplicator.shared.onScreenSeen = []
                }
                config.feed?.lastRead = []
                allShortIdsSeen = []
            }
            Task { [weak self] in
                await self?.loadRemote(config)
            }
        }
    }
    
    // Somehow sometimes there are 250+ subs, maybe from queued ticks from the timer? Now only call this throttled to be sure... see nextTickSub / listenForNextTickSub
    private func _fetchFeedTimerNextTick() {
        guard let config, (!AppState.shared.appIsInBackground || IS_CATALYST) && (isVisible || (config.id.starts(with: "Following-") && config.name != "Explore")) else { return }
        bg().perform { [weak self] in
            guard !Importer.shared.isImporting else { return }
            setFirstTimeCompleted()

            Task { @MainActor [weak self] in
                self?.sendRealtimeReq(config)
            }
        }
    }
    
    @MainActor
    public func loadLocal(_ config: NXColumnConfig, older: Bool = false, completion: (() -> Void)? = nil) {
        let latestReloadInFlight = latestFirstPaintMinimum != nil || latestBackfill
        if !isVisible || isPaused || (isViewPaused && !latestReloadInFlight) || (AppState.shared.appIsInBackground && !IS_CATALYST) {
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) loadLocal - 👹👹 halted. isVisible: \(self.isVisible) isPaused: \(self.isPaused) isViewPaused: \(self.isViewPaused) -[LOG]-")
#endif
            completion?()
            return
        }
#if DEBUG
        L.og.debug("☘️☘️ \(config.name) loadLocal (serialized request) -[LOG]-")
#endif
        let sessionGeneration = feedSessionGeneration
        let scopedCompletion = completion.map { completion in
            { [weak self] in
                guard self?.feedSessionGeneration == sessionGeneration else { return }
                completion()
            }
        }
        localLoadCoordinator.enqueue(
            LocalLoadRequest(
                config: config,
                older: older,
                sessionGeneration: sessionGeneration,
                requestedAt: Date()
            ),
            completion: scopedCompletion
        )
    }
    
    public var loadAnyFlag: Bool = false

    /// Remember-off: stay on `.loading` until this many posts are ready (10 iPhone / 6 Mac).
    var latestFirstPaintMinimum: Int? = nil
    /// Empty-screen `loadLocal` uses this `since` instead of the default 8h window.
    var latestLocalSinceOverride: Int64? = nil
    /// Ready posts while first-paint is held (viewState is still `.loading`).
    private(set) var latestHeldPostCount: Int = 0
    /// Remember-off latest session: use latest-first loading and pagination behavior.
    var latestBackfill = false
    /// Until fill finishes, keep the first screen still — no prepends or mid-list inserts.
    var latestSuppressPrepend = false
    /// First older append after first paint: keep the batch small so the list does not hitch.
    var latestQuietOlderAppend = false
    /// User scrolled to the bottom sentinel — older loads may exceed the initial screen cap.
    var latestUserLoadMore = false
    /// True while an older page (prefetch or scroll) is being transformed.
    var olderPageLoadInFlight = false
    /// Remember-off: we already kicked the first extra page after the initial screen.
    private var didPrefetchOlderPage = false
    private var prefetchOlderPageTask: Task<Void, Never>?
    private enum PaginationState {
        case idle
        case loadingLocal(cursor: Int64, sessionGeneration: UInt64)
        case loadingNetwork(cursor: Int64, subscriptionId: String, sessionGeneration: UInt64)
    }
    private var paginationState: PaginationState = .idle
    @Published private(set) var isLoadingOlderPage = false
    private var paginationTimeoutTask: Task<Void, Never>?
    /// A restored List briefly reports its temporary layout as near-bottom.
    /// Older work must not get ahead of the first newer query for Remember-on.
    private var suppressPaginationUntilRememberNewerLoad = false
    /// Remember-on: older pages wait until the user scrolls toward already-seen posts.
    private var userHasScrolledTowardOlder = false

    @MainActor
    func beginLatestFirstPaint() {
        advanceFeedSession()
        isViewPaused = false
        latestFirstPaintMinimum = LATEST_FEED_FIRST_PAINT_COUNT
        latestLocalSinceOverride = Int64(Date().addingTimeInterval(-LATEST_FEED_FILL_WINDOW).timeIntervalSince1970)
        latestHeldPostCount = 0
        latestBackfill = true
        latestSuppressPrepend = true
        latestQuietOlderAppend = false
        latestUserLoadMore = false
        olderPageLoadInFlight = false
        didPrefetchOlderPage = false
        prefetchOlderPageTask?.cancel()
        prefetchOlderPageTask = nil
        resetPaginationState()
        suppressPaginationUntilRememberNewerLoad = false
        userHasScrolledTowardOlder = false
    }

    func allowLatestFirstPaint() {
        latestFirstPaintMinimum = nil
    }

    func endLatestFirstPaintHold() {
        latestFirstPaintMinimum = nil
        latestLocalSinceOverride = nil
        latestHeldPostCount = 0
    }

    func allowLatestLivePrepend() {
        latestSuppressPrepend = false
    }

    @MainActor
    func clearLatestFeedSession() {
        advanceFeedSession()
        clearAlreadySeenNewerPosts()
        gapFiller?.cancelLatestSession()
        endLatestFirstPaintHold()
        latestBackfill = false
        latestSuppressPrepend = false
        latestQuietOlderAppend = false
        latestUserLoadMore = false
        olderPageLoadInFlight = false
        didPrefetchOlderPage = false
        prefetchOlderPageTask?.cancel()
        prefetchOlderPageTask = nil
        resetPaginationState()
        suppressPaginationUntilRememberNewerLoad = false
        userHasScrolledTowardOlder = false
    }

    @MainActor
    func beginLatestIncrementalFetch() {
        advanceFeedSession()
        latestQuietOlderAppend = false
        olderPageLoadInFlight = false
        latestUserLoadMore = false
    }

    @MainActor
    private func advanceFeedSession() {
        feedSessionGeneration &+= 1
        localLoadCoordinator.cancelAll()
        resetPaginationState()
    }

    @MainActor
    private func resetPaginationState() {
        paginationTimeoutTask?.cancel()
        paginationTimeoutTask = nil
        paginationRetryTask?.cancel()
        paginationRetryTask = nil
        olderPaginationScanCursor = nil
        paginationRetryNotBefore = nil
        lastPaginationRequest = nil
        if case .loadingNetwork(_, let subscriptionId, _) = paginationState {
            ConnectionPool.shared.closeSubscription(subscriptionId)
        }
        setPaginationState(.idle)
        olderPageLoadInFlight = false
        latestUserLoadMore = false
    }

    @MainActor
    private func setPaginationState(_ state: PaginationState) {
        paginationState = state
        if case .idle = state {
            isLoadingOlderPage = false
        } else {
            isLoadingOlderPage = true
        }
    }

    /// After the initial quiet append, start the next page so a fast scroll
    /// does not hit an empty tail. Sparse feeds may contain fewer than the
    /// first-paint target, so any visible root post is enough to paginate.
    func schedulePrefetchOlderPage() {
        guard latestBackfill, !didPrefetchOlderPage else { return }
        prefetchOlderPageTask?.cancel()
        prefetchOlderPageTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.prefetchOlderPageIfNeeded()
        }
    }

    @MainActor
    private func prefetchOlderPageIfNeeded() {
        guard latestBackfill, !didPrefetchOlderPage, !olderPageLoadInFlight else { return }
        guard !latestQuietOlderAppend else { return }
        guard let config else { return }
        let onScreen = currentNRPostsOnScreen.count
        if onScreen > LATEST_FEED_INITIAL_VISIBLE + 1 {
            didPrefetchOlderPage = true
            return
        }
        didPrefetchOlderPage = true
#if DEBUG
        if onScreen == 0 {
            recordFeedAction("initial fetch empty · requesting older history")
        }
#endif
        // Try local rows first, then continue to relays when local storage has
        // nothing older. With only a few visible posts the tail sentinel is
        // already on screen while the quiet append is active; it will not
        // re-appear later to trigger the network page by itself.
        loadOlderPage(config)
    }

    @MainActor
    func noteUserScrolledTowardOlder() {
        guard !userHasScrolledTowardOlder else { return }
        userHasScrolledTowardOlder = true
#if DEBUG
        recordFeedAction("PAGE arm · user scrolled toward older · \(feedActionDebugViewport())")
#endif
    }

    @MainActor
    private func loadOlderPage(_ config: NXColumnConfig, requestNetwork: Bool = true) {
        guard NXFeedViewport.shouldAllowRememberOnOlderFetch(
            continueEnabled: config.continue,
            userHasScrolledTowardOlder: userHasScrolledTowardOlder,
            visiblePostCount: currentNRPostsOnScreen.count
        ) else {
#if DEBUG
            recordFeedAction("PAGE skip · loadOlderPage · remember-on until scroll down")
#endif
            return
        }
        guard case .idle = paginationState else { return }
        let visibleCursor = Int64(oldestCreatedAt ?? Int(Date().timeIntervalSince1970))
        let cursor = min(visibleCursor, olderPaginationScanCursor ?? visibleCursor)
        let sessionGeneration = feedSessionGeneration
        let countBeforeLoad = currentNRPostsOnScreen.count
        setPaginationState(.loadingLocal(cursor: cursor, sessionGeneration: sessionGeneration))
        olderPageLoadInFlight = true
        latestUserLoadMore = true
        loadLocal(config, older: true) { [weak self] in
            guard let self else { return }
            guard self.feedSessionGeneration == sessionGeneration,
                  case .loadingLocal(let activeCursor, let activeGeneration) = self.paginationState,
                  activeCursor == cursor,
                  activeGeneration == sessionGeneration
            else { return }
            self.olderPageLoadInFlight = false
            self.latestUserLoadMore = false
            if !requestNetwork || self.currentNRPostsOnScreen.count > countBeforeLoad {
                self.clearPaginationRetryPause()
                self.setPaginationState(.idle)
                return
            }
            // Ask relays for the complete visible-tail window. The local scan
            // may have moved farther back, but relays can still have events the
            // local database did not. The imported follow-up read uses this
            // active network cursor before advancing the next page.
            self.startNextPageNetworkRequest(config, cursor: cursor, sessionGeneration: sessionGeneration)
        }
    }

    @MainActor
    private func noteOlderPaginationScan(_ oldestScannedCreatedAt: Int64?) {
        guard let oldestScannedCreatedAt else { return }
        olderPaginationScanCursor = min(
            olderPaginationScanCursor ?? oldestScannedCreatedAt,
            oldestScannedCreatedAt
        )
    }

    @MainActor
    private func clearPaginationRetryPause() {
        paginationRetryTask?.cancel()
        paginationRetryTask = nil
        paginationRetryNotBefore = nil
    }

    @MainActor
    private func pauseEmptyPaginationRetry(
        config: NXColumnConfig,
        requestedCursor: Int64,
        sessionGeneration: UInt64
    ) {
        // Empty initial feeds already transition to the explicit retry state.
        // Automatic pagination retry is only for an existing feed tail.
        guard !currentNRPostsOnScreen.isEmpty else { return }
        let resumeCursor = min(requestedCursor, olderPaginationScanCursor ?? requestedCursor)
        guard resumeCursor < requestedCursor else {
            paginationRetryTask?.cancel()
            paginationRetryTask = nil
            paginationRetryNotBefore = .distantFuture
#if DEBUG
            recordFeedAction(
                "older pagination stopped · no visible posts · cursor unchanged \(requestedCursor)"
            )
#endif
            return
        }
        let delay: TimeInterval = 5
        paginationRetryNotBefore = Date().addingTimeInterval(delay)
#if DEBUG
        recordFeedAction(
            "older page yielded no visible posts · advanced cursor \(requestedCursor)→\(resumeCursor) · retry in \(Int(delay))s"
        )
#endif
        paginationRetryTask?.cancel()
        paginationRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self,
                  self.feedSessionGeneration == sessionGeneration,
                  self.isVisible,
                  !self.isPaused,
                  !self.isViewPaused
            else { return }
            self.paginationRetryTask = nil
            self.paginationRetryNotBefore = nil
            self.loadOlderPage(config)
        }
    }

    @MainActor
    private func _loadLocal(
        _ config: NXColumnConfig,
        older: Bool = false,
        sessionGeneration: UInt64,
        requestedAt: Date,
        completion: (() -> Void)? = nil
    ) {
        let currentNRPostsOnScreen = self.currentNRPostsOnScreen
        
        if !currentNRPostsOnScreen.isEmpty { // if we don't check if screen is empty we can have permanent spinner at first run
            mergeFeedLastReadIntoSeen(config.feed)
        }
        
        let repliesEnabled = config.repliesEnabled
        
        if config.continue && !didLoadFirstLocalState && currentNRPostsOnScreen.isEmpty, let feedId = config.feed?.id?.uuidString { // very first load from local saved state
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) - First load from local state -[LOG]-")
#endif
            if let localFeedState = LocalFeedStateManager.shared.feedState(for: feedId) {
                let idsToPutInScreen: [String] = localFeedState.onScreenIds
                
                if !idsToPutInScreen.isEmpty {
                    suppressPaginationUntilRememberNewerLoad = true
                    
                    // Fetch events
                    bg().perform { [self] in
                        let fr = Event.fetchRequest()
                        fr.predicate = NSPredicate(format: "id IN %@", idsToPutInScreen)
                        let fetchedEvents = ((try? bg().fetch(fr)) ?? [])
                            .map {
                                $0.parentEvents = !repliesEnabled ? [] : Event.getParentEvents($0)
                                return $0
                            }
                        let events: [Event]
                        switch config.columnType {
                        case .picture, .vine, .yak:
                            events = self.applyMediaSource(fetchedEvents, config: config)
                        default:
                            events = fetchedEvents
                        }
                        
                        // transform Event to NRPost
                        var eventsMap: [String: NRPost] = [:]
                        for event in events {
                            guard !event.isMutedByWords else { continue }
                            eventsMap[event.id] = NRPost(event: event, withParents: repliesEnabled, withReplies: !repliesEnabled, withRepliesCount: true, cancellationId: event.cancellationId)
                        }
                        
                        // put on screen
                        let nrPosts = idsToPutInScreen.compactMap { eventsMap[$0] }
                        Task { @MainActor in
                            guard self.shouldAcceptResults(
                                for: config,
                                sessionGeneration: sessionGeneration
                            ) else {
                                completion?()
                                return
                            }
                            guard !nrPosts.isEmpty else {
                                // Saved IDs can belong to a previously selected
                                // media source. Fall back to the normal local query
                                // instead of restoring an empty screen late.
                                self.loadAnyFlag = true
                                self._loadLocal(
                                    config,
                                    sessionGeneration: sessionGeneration,
                                    requestedAt: requestedAt,
                                    completion: completion
                                )
                                return
                            }

                            if let scrollToId = localFeedState.scrollToId, let restoreToIndex = nrPosts.firstIndex(where: { $0.id == scrollToId }) {
                                
                                
                                // Restore unread count
                                vmInner.updateUnreadIds { unreadIds in
                                    for index in nrPosts.indices where index < restoreToIndex {
                                        let nrPost = nrPosts[index]
                                        if unreadIds[nrPost.id] == nil {
                                            unreadIds[nrPost.id] = 1 + nrPost.parentPosts.count
                                        }
                                    }
                                }
                                
                                // Pending only. Do not set readingPostID / isAtTop until
                                // the scroll actually lands — a leftover mid-feed id made
                                // later prepends jump away from the visible top post.
                                vmInner.beginPreparedScrollRestore(postID: scrollToId, index: restoreToIndex)
                                isHidingFeedForRestore = true
                                vmInner.holdUnreadAboveReadingPost = true
                                
                                // Update the view state without animation
                                withTransaction(Transaction(animation: nil)) {
                                    viewState = .posts(nrPosts)
                                }
                                
#if DEBUG
                                L.og.debug("☘️☘️ \(config.name) - First load from local state - restoreToIndex: \(restoreToIndex) - id: \(scrollToId) -[LOG]-")
#endif
                                
                                // After a very short delay, trigger the scroll
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    self.vmInner.requestScroll(to: restoreToIndex)
                                }
                            }
                            else {
                                self.viewState = .posts(nrPosts)
                            }

                            // CloudKit may have merged lastRead before the restored snapshot
                            // created its unread IDs. Reconcile once the snapshot exists, while
                            // deferring the List mutation until restore and scrolling are idle.
                            self.scheduleAlreadySeenReconciliation(
                                removingVisiblePostsFor: Deduplicator.shared.cloudSyncedSeen
                            )

#if DEBUG
                            // Remember-on restores bypass putOnScreen(), so emit
                            // the same 0→N marker used by fresh feeds. Without it
                            // every Mac column's first-render timer stays measuring.
                            self.recordFeedAction("restored feed · 0→\(nrPosts.count) posts")
#endif
//                            self.allIdsSeen = self.allIdsSeen.union(Set(idsToPutInScreen)) // TODO: remove top unread part if scroll restore
#if DEBUG
                            L.og.debug("☘️☘️ \(config.name) - Loaded \(nrPosts.count) from local state -[LOG]-")
                            self.recordFeedAction("restored feed · queued newer reconciliation")
#endif
                            // Restoring the remembered snapshot is only the first paint.
                            // Queue a normal local read behind this one so posts newer than
                            // the snapshot are either inserted (unseen) or offered by the
                            // already-seen banner. didLoadFirstLocalState is already true,
                            // so this request cannot restore the same snapshot again.
                            self.loadLocal(config)
                            completion?()
                        }
                    }
                }
                
                didLoadFirstLocalState = true
                if idsToPutInScreen.isEmpty {
                    completion?()
                }
                return
            }
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) - No local state found -[LOG]-")
#endif
        }
        
        let allShortIdsSeen = self.allShortIdsSeenMergingFeedLastRead(config.feed)
        let currentIdsOnScreen = self.currentIdsOnScreen
        let wotEnabled = config.wotEnabled
  
        // Fetch since 5 minutes before most recent item on screen (since)
        // Or until oldest (bottom) item on screen (until)
        let nowTs = Int64(Date().timeIntervalSince1970)
        let (sinceTimestamp, untilTimestamp): (Int64, Int64)
        if case .posts(let nrPosts) = viewState {
            sinceTimestamp = (nrPosts.first?.created_at ?? 300) - 300
            let visibleUntil = nrPosts.last?.created_at ?? nowTs
            let activeNetworkCursor: Int64? = if older,
                case .loadingNetwork(let cursor, _, _) = paginationState {
                cursor
            } else {
                nil
            }
            untilTimestamp = older
                ? min(visibleUntil, activeNetworkCursor ?? olderPaginationScanCursor ?? visibleUntil)
                : visibleUntil
        }
        else if loadAnyFlag {
            // Very early date but not zero because zero defaults back 8 hours
            sinceTimestamp = 1622888074
            untilTimestamp = nowTs
        }
        else if let latestLocalSinceOverride {
            sinceTimestamp = latestLocalSinceOverride
            untilTimestamp = nowTs
        }
        else { // empty screen: 0 (since) or now (until)
            sinceTimestamp = 0
            untilTimestamp = nowTs
        }
        
        if loadAnyFlag {
            self.loadAnyFlag = false
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
            L.og.debug("☘️☘️ \(config.name) loadLocal(.following) \(older ? "older" : "") \(followingPubkeys.count) pubkeys -[LOG]-")
#endif
            
            // Remove picture/yak/vine kinds from main following feed, but only if their seperate feeds are enabled and not desktop columns
            let removeSeperateFeedKinds: Set<Int> = [
                (!IS_DESKTOP_COLUMNS() && UserDefaults.standard.bool(forKey: "enable_picture_feed")) ? 20 : -1,
                (!IS_DESKTOP_COLUMNS() && UserDefaults.standard.bool(forKey: "enable_yak_feed")) ? 1222 : -1,
                (!IS_DESKTOP_COLUMNS() && UserDefaults.standard.bool(forKey: "enable_yak_feed")) ? 1244 : -1,
                (!IS_DESKTOP_COLUMNS() && UserDefaults.standard.bool(forKey: "enable_vine_feed")) ? 34236 : -1,
            ]
            
            let kinds = if !feed.kinds.isEmpty {
                feed.kinds.subtracting( !feed.repliesEnabled ? REPLY_KINDS : [])
            }
            else {
                QUERY_FOLLOWING_KINDS_WITH_REPLIES.subtracting(removeSeperateFeedKinds).subtracting( !feed.repliesEnabled ? REPLY_KINDS : [])
            }
            
            bg().perform { [weak self] in
                guard let self else { return }
                let queryStartedAt = Date()
                let fr = if !older {
                    Event.postsByPubkeys(followingPubkeys, lastAppearedCreatedAt: sinceTimestamp, hideReplies: !repliesEnabled, kinds: kinds)
                }
                else {
                    Event.postsByPubkeys(followingPubkeys, until: untilTimestamp, hideReplies: !repliesEnabled, kinds: kinds)
                }
                let events: [Event] = (try? bg().fetch(fr)) ?? []
#if DEBUG
                let dbSeconds = self.debugSeconds(since: queryStartedAt)
                self.recordFeedActionFromBackground(
                    "FETCH \(older ? "older" : "newer") · db \(events.count) in \(dbSeconds) · following"
                )
#endif
                self.processToScreen(events, config: config, allShortIdsSeen: allShortIdsSeen, currentIdsOnScreen: currentIdsOnScreen, currentNRPostsOnScreen: currentNRPostsOnScreen, sinceOrUntil: Int(sinceOrUntil), older: older, wotEnabled: wotEnabled, repliesEnabled: repliesEnabled, sessionGeneration: sessionGeneration, completion: completion)
            }
        case .picture, .vine, .yak:
            let source = config.mediaFeedSourceSnapshot ?? .follows
            let mediaRelays = config.mediaRelaysSnapshot
            
            let kinds: Set<Int> = switch config.columnType {
            case .vine:
                [34236]
            case .yak:
                [1222,1244]
            default: // .picture
                [20]
            }

#if DEBUG
            L.og.debug("☘️☘️ \(config.name) loadLocal(.picture/.vine/.yak) (\(kinds.description) \(older ? "older" : "") source: \(source.rawValue) - loadAnyFlag:\(self.loadAnyFlag) -[LOG]-")
#endif
            
            bg().perform { [weak self] in
                guard let self else { return }
                let events: [Event]
                if source == .selectedRelays {
                    let fr: NSFetchRequest<Event>
                    if !older {
                        fr = Event.postsByRelays(mediaRelays, lastAppearedCreatedAt: sinceTimestamp, hideReplies: !repliesEnabled, fetchLimit: QUERY_FETCH_LIMIT, kinds: kinds)
                    }
                    else {
                        fr = Event.postsByRelays(mediaRelays, until: untilTimestamp, hideReplies: !repliesEnabled, fetchLimit: QUERY_FETCH_LIMIT, kinds: kinds)
                    }
                    events = (try? bg().fetch(fr)) ?? []
                }
                else {
                    if !older {
                        events = Event.fetchMediaPosts(
                            by: config.mediaAllowedPubkeysSnapshot,
                            lastAppearedCreatedAt: sinceTimestamp,
                            hideReplies: !repliesEnabled,
                            kinds: kinds,
                            context: bg()
                        )
                    }
                    else {
                        events = Event.fetchMediaPosts(
                            by: config.mediaAllowedPubkeysSnapshot,
                            until: untilTimestamp,
                            hideReplies: !repliesEnabled,
                            kinds: kinds,
                            context: bg()
                        )
                    }
                }
                self.processToScreen(events, config: config, allShortIdsSeen: allShortIdsSeen, currentIdsOnScreen: currentIdsOnScreen, currentNRPostsOnScreen: currentNRPostsOnScreen, sinceOrUntil: Int(sinceOrUntil), older: older, wotEnabled: wotEnabled, repliesEnabled: repliesEnabled, sessionGeneration: sessionGeneration, completion: completion)
            }
        case .pubkeys(let feed), .followSet(let feed), .followPack(let feed): // The pubkeys are in the CloudFeed
            let pubkeys = feed.contactPubkeys
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) loadLocal(.pubkeys/.followSet/Pack)\(older ? "older" : "") \(pubkeys.count) pubkeys -[LOG]-")
#endif
            let kinds = if !feed.kinds.isEmpty {
                feed.kinds.subtracting( !feed.repliesEnabled ? REPLY_KINDS : [])
            }
            else {
                QUERY_FOLLOWING_KINDS_WITH_REPLIES.subtracting( !feed.repliesEnabled ? REPLY_KINDS : [])
            }

            bg().perform { [weak self] in
                guard let self else { return }
                let queryStartedAt = Date()
                let fr = if !older {
                    Event.postsByPubkeys(pubkeys, lastAppearedCreatedAt: sinceTimestamp, hideReplies: !repliesEnabled, kinds: kinds)
                }
                else {
                    Event.postsByPubkeys(pubkeys, until: untilTimestamp, hideReplies: !repliesEnabled, kinds: kinds)
                }
                let events: [Event] = (try? bg().fetch(fr)) ?? []
#if DEBUG
                let dbSeconds = self.debugSeconds(since: queryStartedAt)
                self.recordFeedActionFromBackground(
                    "FETCH \(older ? "older" : "newer") · db \(events.count) in \(dbSeconds) · pubkeys"
                )
#endif

                self.processToScreen(events, config: config, allShortIdsSeen: allShortIdsSeen, currentIdsOnScreen: currentIdsOnScreen, currentNRPostsOnScreen: currentNRPostsOnScreen, sinceOrUntil: Int(sinceOrUntil), older: older, wotEnabled: wotEnabled, repliesEnabled: repliesEnabled, sessionGeneration: sessionGeneration, completion: completion)
            }
        case .someoneElses(_):
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) loadLocal(.someoneElses)\(older ? "older" : "") -[LOG]-")
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
                let events: [Event] = (try? bg().fetch(fr)) ?? []
                self.processToScreen(events, config: config, allShortIdsSeen: allShortIdsSeen, currentIdsOnScreen: currentIdsOnScreen, currentNRPostsOnScreen: currentNRPostsOnScreen, sinceOrUntil: Int(sinceOrUntil), older: older, wotEnabled: wotEnabled, repliesEnabled: repliesEnabled, sessionGeneration: sessionGeneration, completion: completion)
            }
        case .pubkeysPreview(_): // The pubkeys are in the NXConfig
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) loadLocal(.pubkeysPreview)\(older ? "older" : "") -[LOG]-")
#endif
            bg().perform { [weak self] in
                guard let self else { return }
                let fr = if !older {
                    Event.postsByPubkeys(config.pubkeys, lastAppearedCreatedAt: sinceTimestamp, hideReplies: !repliesEnabled, kinds: QUERY_FOLLOWING_KINDS)
                }
                else {
                    Event.postsByPubkeys(config.pubkeys, until: untilTimestamp, hideReplies: !repliesEnabled, kinds: QUERY_FOLLOWING_KINDS)
                }
                let events: [Event] = (try? bg().fetch(fr)) ?? []
                self.processToScreen(events, config: config, allShortIdsSeen: [], currentIdsOnScreen: currentIdsOnScreen, currentNRPostsOnScreen: currentNRPostsOnScreen, sinceOrUntil: Int(sinceOrUntil), older: older, wotEnabled: wotEnabled, repliesEnabled: repliesEnabled, sessionGeneration: sessionGeneration, completion: completion)
            }
        case .relays(let feed):
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) loadLocal(.relays)\(older ? "older" : "") -[LOG]-")
#endif
            let relaysData = feed.relaysData
            let kinds = if !feed.kinds.isEmpty {
                feed.kinds.subtracting( !feed.repliesEnabled ? REPLY_KINDS : [])
            }
            else {
                QUERY_FOLLOWING_KINDS_WITH_REPLIES.subtracting( !feed.repliesEnabled ? REPLY_KINDS : [])
            }
            
            bg().perform { [weak self] in
                guard let self else { return }
                let queryStartedAt = Date()
                let fr = if !older {
                    Event.postsByRelays(relaysData, lastAppearedCreatedAt: sinceTimestamp, hideReplies: !repliesEnabled, kinds: kinds)
                }
                else {
                    Event.postsByRelays(relaysData, until: untilTimestamp, hideReplies: !repliesEnabled, kinds: kinds)
                }
                let events: [Event] = (try? bg().fetch(fr)) ?? []
#if DEBUG
                let dbSeconds = self.debugSeconds(since: queryStartedAt)
                self.recordFeedActionFromBackground(
                    "FETCH \(older ? "older" : "newer") · db \(events.count) in \(dbSeconds) · relays"
                )
#endif
                self.processToScreen(events, config: config, allShortIdsSeen: allShortIdsSeen, currentIdsOnScreen: currentIdsOnScreen, currentNRPostsOnScreen: currentNRPostsOnScreen, sinceOrUntil: Int(sinceOrUntil), older: older, wotEnabled: wotEnabled, repliesEnabled: repliesEnabled, sessionGeneration: sessionGeneration, completion: completion)
            }
        case .relayPreview(let relayData):
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) loadLocal(.relayPreview)\(older ? "older" : "") -[LOG]-")
#endif
            let relaysData: Set<RelayData> = [relayData]
            bg().perform { [weak self] in
                guard let self else { return }
                let fr = if !older {
                    Event.postsByRelays(relaysData, lastAppearedCreatedAt: sinceTimestamp, hideReplies: !repliesEnabled, kinds: QUERY_FOLLOWING_KINDS)
                }
                else {
                    Event.postsByRelays(relaysData, until: untilTimestamp, hideReplies: !repliesEnabled, kinds: QUERY_FOLLOWING_KINDS)
                }
                let events: [Event] = (try? bg().fetch(fr)) ?? []
                self.processToScreen(events, config: config, allShortIdsSeen: allShortIdsSeen, currentIdsOnScreen: currentIdsOnScreen, currentNRPostsOnScreen: currentNRPostsOnScreen, sinceOrUntil: Int(sinceOrUntil), older: older, wotEnabled: wotEnabled, repliesEnabled: repliesEnabled, sessionGeneration: sessionGeneration, completion: completion)
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
        switch config.columnType {
        case .following, .picture, .vine, .yak, .pubkeys, .followSet, .followPack,
             .someoneElses, .pubkeysPreview, .relays, .relayPreview:
            break
        default:
            completion?()
        }
    }
        
    private func broadMediaFilters(_ config: NXColumnConfig, since: Int? = nil, until: Int? = nil, limit: Int? = nil) -> [Filters] {
        switch config.columnType {
        case .vine:
            return [Filters(kinds: [34236], since: since, until: until, limit: limit)]
        case .yak:
            return [Filters(kinds: [1222, 1244], since: since, until: until, limit: limit)]
        case .picture:
            // Nostr limits apply per filter. Split the requested maximum across
            // the two ways a picture post can be represented.
            let perFilterLimit = limit.map { max(1, ($0 + 1) / 2) }
            return [
                Filters(kinds: [20], since: since, until: until, limit: perFilterLimit),
                Filters(kinds: [1], tagFilter: TagFilter(tag: "k", values: ["20"]), since: since, until: until, limit: perFilterLimit)
            ]
        default:
            return []
        }
    }

    @MainActor
    private func sendBroadMediaReq(_ config: NXColumnConfig, subscriptionId: String, since: Int? = nil, until: Int? = nil, limit: Int? = nil, isActiveSubscription: Bool = false) {
        let source = config.mediaFeedSourceSnapshot ?? .follows
        let relays = source == .selectedRelays ? config.mediaRelaysSnapshot : []
        guard source != .selectedRelays || !relays.isEmpty else { return }

        // WoT membership is applied locally after import. Request a bounded sample
        // from our read relays instead of sending a huge author list to outbox relays.
        let maximumResponse = source == .webOfTrust ? 200 : 50
        let requestedResponseLimit = min(limit ?? maximumResponse, maximumResponse)
        let responseLimit = if source == .webOfTrust {
            // A Nostr filter limit is per relay. Divide the network budget over
            // our read relays so one refresh imports roughly 200 events in total.
            Int(ceil(Double(requestedResponseLimit) / Double(max(1, ConnectionPool.shared.configuredReadRelayCount()))))
        }
        else if source == .selectedRelays {
            Int(ceil(Double(requestedResponseLimit) / Double(max(1, relays.count))))
        }
        else {
            requestedResponseLimit
        }
        let filters = broadMediaFilters(config, since: since, until: until, limit: responseLimit)
        guard !filters.isEmpty else { return }

        let clientMessage = NostrEssentials.ClientMessage(type: .REQ, subscriptionId: subscriptionId, filters: filters)
        if let message = clientMessage.json() {
            req(message, activeSubscriptionId: isActiveSubscription ? subscriptionId : nil, relays: relays)
        }
    }

    @MainActor
    private func sendRealtimeReq(_ config: NXColumnConfig) {
        switch config.columnType {
        case .following(let feed):
            // Make sure max pubkeys is < 2000 (relay limits)
            let followingPubkeys = (feed.account?.followingPubkeys ?? []).union(feed.account?.privateFollowingPubkeys ?? [])
            let ownPubkey: Set<String> = if let account = feed.account {
                Set([account.publicKey])
            }
            else {
                Set<String>()
            }
            
            let pubkeys = if feed.accountPubkey == EXPLORER_PUBKEY {
                AppState.shared.rawExplorePubkeys.subtracting(AppState.shared.bgAppState.blockedPubkeys)
            }
            else if followingPubkeys.count > 1999 { // Take random 1999 + own pubkey if filter is too large
                Set(followingPubkeys.shuffled().prefix(1999)).union(ownPubkey)
            }
            else {
                followingPubkeys.union(ownPubkey)
            }
            
            guard !pubkeys.isEmpty else { return }
            
            
            // Remove picture/yak/vine kinds from main following feed, but only if their seperate feeds are enabled and not desktop columns
            let removeSeperateFeedKinds: Set<Int> = [
                (!IS_DESKTOP_COLUMNS() && UserDefaults.standard.bool(forKey: "enable_picture_feed")) ? 20 : -1,
                (!IS_DESKTOP_COLUMNS() && UserDefaults.standard.bool(forKey: "enable_yak_feed")) ? 1222 : -1,
                (!IS_DESKTOP_COLUMNS() && UserDefaults.standard.bool(forKey: "enable_yak_feed")) ? 1244 : -1,
                (!IS_DESKTOP_COLUMNS() && UserDefaults.standard.bool(forKey: "enable_vine_feed")) ? 34236 : -1,
            ]
            
            let kinds = if !feed.kinds.isEmpty {
                feed.kinds.subtracting( !feed.repliesEnabled ? REPLY_KINDS : [])
            }
            else {
                QUERY_FOLLOWING_KINDS_WITH_REPLIES.subtracting(removeSeperateFeedKinds).subtracting( !feed.repliesEnabled ? REPLY_KINDS : [])
            }
            
            let filters = followingReqFilters(pubkeys, since: NTimestamp(date: Date.now).timestamp, kinds: kinds)
            
            outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: config.id, filters: filters), activeSubscriptionId: config.id)
        case .picture(let feed), .vine(let feed), .yak(let feed):
            if config.mediaFeedSourceSnapshot != .follows {
                sendBroadMediaReq(
                    config,
                    subscriptionId: config.id,
                    since: NTimestamp(date: .now).timestamp,
                    isActiveSubscription: true
                )
                return
            }

            // Make sure max pubkeys is < 2000 (relay limits)
            let followingPubkeys = (feed.account?.followingPubkeys ?? []).union(feed.account?.privateFollowingPubkeys ?? [])
            let ownPubkey: Set<String> = if let account = feed.account {
                Set([account.publicKey])
            }
            else {
                Set<String>()
            }
            
            let pubkeys = if feed.accountPubkey == EXPLORER_PUBKEY {
                AppState.shared.rawExplorePubkeys.subtracting(AppState.shared.bgAppState.blockedPubkeys)
            }
            else if followingPubkeys.count > 1999 { // Take random 1999 + own pubkey if filter is too large
                Set(followingPubkeys.shuffled().prefix(1999)).union(ownPubkey)
            }
            else {
                followingPubkeys.union(ownPubkey)
            }
            
            let followingHashtags: Set<String> = (feed.account?.followingHashtags ?? [])
            let hashtags: Set<String> = if (followingHashtags.count + pubkeys.count) <= 2000, let account = feed.account {
                account.followingHashtags
            }
            else { [] } // Skip hashtags if filter is too large
            
            guard pubkeys.count > 0 || hashtags.count > 0 else { return }
            
            let filters = switch config.columnType {
                case .vine(_):
                pubkeyOrHashtagReqFilters(pubkeys, hashtags: hashtags, since: NTimestamp(date: Date.now).timestamp, kinds: [34236,5])
                case .yak(_):
                pubkeyOrHashtagReqFilters(pubkeys, hashtags: hashtags, since: NTimestamp(date: Date.now).timestamp, kinds: [1222,1244,5])
                default: // .picture: // kind:20 + hashtags + kind:1-k20-tag
                pubkeyOrHashtagReqFilters(pubkeys, hashtags: hashtags, since: NTimestamp(date: Date.now).timestamp, kinds: [20,5]) + [Filters(
                    authors: pubkeys,
                    kinds: [1],
                    tagFilter: TagFilter(tag: "k", values: ["20"]),
                    since: NTimestamp(date: Date.now).timestamp
                )]
            }
            
            outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: config.id, filters: filters), activeSubscriptionId: config.id)
            
        case .pubkeys(let feed), .followSet(let feed), .followPack(let feed):
            let pubkeys = feed.contactPubkeys.count <= 2000 ? feed.contactPubkeys : Set(feed.contactPubkeys.shuffled().prefix(2000))
            guard pubkeys.count > 0 else { return }
            
            let kinds = if !feed.kinds.isEmpty {
                feed.kinds.subtracting( !feed.repliesEnabled ? REPLY_KINDS : [])
            }
            else {
                FETCH_FOLLOWING_FEED_KINDS_WITH_REPLIES.subtracting( !feed.repliesEnabled ? REPLY_KINDS : [])
            }
            
            let filters = Filters(
                authors: pubkeys,
                kinds: kinds,
                since: NTimestamp(date: Date.now).timestamp
            )
            
            nxReq(filters, subscriptionId: config.id, isActiveSubscription: true, useOutbox: feed.useOutbox)

        case .someoneElses(_):
            let pubkeys = config.pubkeys.count <= 2000 ? config.pubkeys : Set(config.pubkeys.shuffled().prefix(2000))
            let hashtags = pubkeys.count + config.hashtags.count <= 2000 ? config.hashtags : [] // no hashtags if filter too large
            
            guard pubkeys.count > 0 || hashtags.count > 0 else { return }
            let filters = pubkeyOrHashtagReqFilters(pubkeys, hashtags: hashtags, since: NTimestamp(date: Date.now).timestamp, kinds: FETCH_FOLLOWING_FEED_KINDS)
            
            if let message = CM(type: .REQ, subscriptionId: config.id, filters: filters).json() {
                req(message, activeSubscriptionId: config.id)
            }
        case .pubkeysPreview(_):
            let pubkeys = config.pubkeys.count <= 2000 ? config.pubkeys : Set(config.pubkeys.shuffled().prefix(2000))
            
            guard pubkeys.count > 0 else { return }
            let filters = pubkeyOrHashtagReqFilters(pubkeys, hashtags: [], since: NTimestamp(date: Date.now).timestamp, kinds: FETCH_FOLLOWING_FEED_KINDS)
            
            if let message = CM(type: .REQ, subscriptionId: config.id, filters: filters).json() {
                req(message, activeSubscriptionId: config.id) // TODO: Toggle for outboxReq or not?
            }
        case .pubkey:
            let _: String? = nil
        case .relays(let feed):
            let relaysData = feed.relaysData
            guard !relaysData.isEmpty else { return }
            
            let kinds = if !feed.kinds.isEmpty {
                feed.kinds.subtracting( !feed.repliesEnabled ? REPLY_KINDS : [])
            }
            else {
                FETCH_GLOBAL_KINDS_WITH_REPLIES.subtracting( !feed.repliesEnabled ? REPLY_KINDS : [])
            }
            
            nxReq(Filters(kinds: kinds, since: Int(Date.now.timeIntervalSince1970), limit: 100), subscriptionId: config.id, isActiveSubscription: true, relays: relaysData)
            
        case .relayPreview(let relayData):
            let relaysData: Set<RelayData> = [relayData]
            guard !relaysData.isEmpty else { return }
            nxReq(Filters(kinds: FETCH_GLOBAL_KINDS, since: Int(Date.now.timeIntervalSince1970), limit: 100), subscriptionId: config.id, isActiveSubscription: true, relays: relaysData)
            
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
    public func getFillGapReqStatement(
        _ config: NXColumnConfig,
        since: Int,
        until: Int? = nil,
        latestLimit: Int? = nil,
        includeOutbox: Bool? = nil
    ) -> (cmd: () -> Void, subId: String, targets: (() -> ConnectionPool.RequestTargetSnapshot)?)? {
        // loadAnyFlag: media "search all local history" may omit the window.
        // Remember-off (latest feed) must still send a recent since. Stripping
        // since/until sent 150 events per extra with no time bound.
        var until: Int? = self.loadAnyFlag ? nil : until
        var since: Int? = self.loadAnyFlag ? nil : since
        if !config.continue {
            let maxAgo = Int(Date().addingTimeInterval(-86_400).timeIntervalSince1970)
            if since == nil || since! < maxAgo {
                since = maxAgo
            }
            until = nil
        }
        let filterLimit = latestLimit ?? (!config.continue ? 150 : DEFAULT_REQ_LIMIT)
        switch config.columnType {
        case .following(let feed):
            
            // Make sure max pubkeys is < 2000 (relay limits)
            let followingPubkeys = (feed.account?.followingPubkeys ?? []).union(feed.account?.privateFollowingPubkeys ?? [])
            let ownPubkey: Set<String> = if let account = feed.account {
                Set([account.publicKey])
            }
            else {
                Set<String>()
            }
            
            let pubkeys = if feed.accountPubkey == EXPLORER_PUBKEY {
                AppState.shared.rawExplorePubkeys.subtracting(AppState.shared.bgAppState.blockedPubkeys)
            }
            else if followingPubkeys.count > 1999 { // Take random 1999 + own pubkey if filter is too large
                Set(followingPubkeys.shuffled().prefix(1999)).union(ownPubkey)
            }
            else {
                followingPubkeys.union(ownPubkey)
            }
            
            // Remove picture/yak/vine kinds from main following feed, but only if their seperate feeds are enabled and not desktop columns
            let removeSeperateFeedKinds: Set<Int> = [
                (!IS_DESKTOP_COLUMNS() && UserDefaults.standard.bool(forKey: "enable_picture_feed")) ? 20 : -1,
                (!IS_DESKTOP_COLUMNS() && UserDefaults.standard.bool(forKey: "enable_yak_feed")) ? 1222 : -1,
                (!IS_DESKTOP_COLUMNS() && UserDefaults.standard.bool(forKey: "enable_yak_feed")) ? 1244 : -1,
                (!IS_DESKTOP_COLUMNS() && UserDefaults.standard.bool(forKey: "enable_vine_feed")) ? 34236 : -1,
            ]
            
            let kinds = if !feed.kinds.isEmpty {
                feed.kinds.subtracting( !feed.repliesEnabled ? REPLY_KINDS : [])
                    .subtracting(since == nil ? [5] : [-1])
            }
            else {
               FETCH_FOLLOWING_FEED_KINDS_WITH_REPLIES.subtracting(removeSeperateFeedKinds)
                    .subtracting(since == nil ? [5] : [-1])
                    .subtracting( !feed.repliesEnabled ? REPLY_KINDS : [])
            }
            
            let filters = followingReqFilters(pubkeys, since: since, until: until, limit: filterLimit, kinds: kinds)
             
            let subId = "RESUME-" + config.id + "-" + (since?.description ?? "any")
            let clientMessage = NostrEssentials.ClientMessage(type: .REQ, subscriptionId: subId, filters: filters)
            let sendOutbox = includeOutbox ?? (feed.accountPubkey != EXPLORER_PUBKEY)
            return (cmd: {
                guard !pubkeys.isEmpty else {
                    L.og.debug("☘️☘️ cmd with empty pubkeys -[LOG]-")
                    return
                }
                if !sendOutbox {
                    if let cm = clientMessage.json() {
                        req(cm)
                    }
                }
                else {
                    outboxReq(clientMessage)
                }
            }, subId: subId, targets: {
                ConnectionPool.shared.requestTargetSnapshot(
                    for: clientMessage,
                    includeOutbox: sendOutbox
                )
            })

        case .picture(let feed), .vine(let feed), .yak(let feed):
            if config.mediaFeedSourceSnapshot != .follows {
                let subId = "prio-MEDIA-RESUME-" + config.id + "-" + (since?.description ?? "any")
                return (cmd: { [weak self] in
                    self?.sendBroadMediaReq(
                        config,
                        subscriptionId: subId,
                        since: since,
                        until: until,
                        limit: !config.continue ? 150 : nil
                    )
                }, subId: subId, targets: {
                    ConnectionPool.shared.requestTargetSnapshot(
                        relays: config.mediaFeedSourceSnapshot == .selectedRelays ? config.mediaRelaysSnapshot : []
                    )
                })
            }

            // Make sure max pubkeys is < 2000 (relay limits)
            let followingPubkeys = (feed.account?.followingPubkeys ?? []).union(feed.account?.privateFollowingPubkeys ?? [])
            let ownPubkey: Set<String> = if let account = feed.account {
                Set([account.publicKey])
            }
            else {
                Set<String>()
            }
            
            let pubkeys = if feed.accountPubkey == EXPLORER_PUBKEY {
                AppState.shared.rawExplorePubkeys.subtracting(AppState.shared.bgAppState.blockedPubkeys)
            }
            else if followingPubkeys.count > 1999 { // Take random 1999 + own pubkey if filter is too large
                Set(followingPubkeys.shuffled().prefix(1999)).union(ownPubkey)
            }
            else {
                followingPubkeys.union(ownPubkey)
            }
            
            let followingHashtags: Set<String> = (feed.account?.followingHashtags ?? [])
            let hashtags: Set<String> = if (followingHashtags.count + pubkeys.count) <= 2000, let account = feed.account {
                account.followingHashtags
            }
            else { [] } // Skip hashtags if filter is too large
            
            let removeKinds: Set<Int> = [
                since == nil ? 5 : -1
            ]
            let historyLimit: Int? = latestLimit ?? (since == nil ? 150 : filterLimit)
            
            let filters = switch config.columnType {
                case .vine(_):
                pubkeyOrHashtagReqFilters(pubkeys, hashtags: hashtags, since: since, until: until, limit: historyLimit, kinds: Set([34236,5]).subtracting(removeKinds))
                case .yak(_):
                pubkeyOrHashtagReqFilters(pubkeys, hashtags: hashtags, since: since, until: until, limit: historyLimit, kinds: Set([1222,1244,5]).subtracting(removeKinds))
                default: // .picture: // kind:20 + hashtags + kind:1-k20-tag
                pubkeyOrHashtagReqFilters(pubkeys, hashtags: hashtags, since: since, until: until, limit: historyLimit, kinds: Set([20,5]).subtracting(removeKinds)) + [Filters(
                    authors: pubkeys,
                    kinds: [1],
                    tagFilter: TagFilter(tag: "k", values: ["20"]),
                    since: since,
                    until: until,
                    limit: since == nil ? 75 : (!config.continue ? 75 : 300)
                )]
            }
            
            let subId = "prio-MEDIA-RESUME-" + config.id + "-" + (since?.description ?? "any")

            let clientMessage = NostrEssentials.ClientMessage(type: .REQ, subscriptionId: subId, filters: filters)
            return (cmd: {
                guard pubkeys.count > 0 || hashtags.count > 0 else {
                    L.og.debug("☘️☘️ cmd with empty pubkeys and hashtags -[LOG]-")
                    return
                }
                outboxReq(clientMessage)
                                
            }, subId: subId, targets: {
                ConnectionPool.shared.requestTargetSnapshot(for: clientMessage, includeOutbox: true)
            })
            
        case .pubkeys(let feed), .followSet(let feed), .followPack(let feed):
            let pubkeys = feed.contactPubkeys.count <= 2000 ? feed.contactPubkeys : Set(feed.contactPubkeys.shuffled().prefix(2000))
            
            guard pubkeys.count > 0 else {
                L.og.debug("☘️☘️ cmd with empty pubkeys -[LOG]-")
                return nil
            }
            
            let removeKinds: Set<Int> = [
                since == nil ? 5 : -1
            ]
            
            let kinds = if !feed.kinds.isEmpty {
                feed.kinds.subtracting( !feed.repliesEnabled ? REPLY_KINDS : [])
            }
            else {
                FETCH_FOLLOWING_FEED_KINDS_WITH_REPLIES.subtracting( !feed.repliesEnabled ? REPLY_KINDS : [])
            }
            
            let filters = Filters(
                authors: pubkeys,
                kinds: kinds.subtracting(removeKinds),
                since: since,
                until: until,
                limit: filterLimit
            )
            
            let subscriptionId = "RESUME-" + config.id + "-" + (since?.description ?? "any")
            
            return (cmd: {
                nxReq(filters, subscriptionId: subscriptionId, useOutbox: feed.useOutbox)
            }, subId: subscriptionId, targets: nil)
 
        case .someoneElses(_):
            let pubkeys = config.pubkeys.count <= 2000 ? config.pubkeys : Set(config.pubkeys.shuffled().prefix(2000))
            let hashtags = pubkeys.count + config.hashtags.count <= 2000 ? config.hashtags : [] // no hashtags if filter too large
            
            guard pubkeys.count > 0 || hashtags.count > 0 else {
                L.og.debug("☘️☘️ cmd with empty pubkeys and hashtags -[LOG]-")
                return nil
            }
            
            let removeKinds: Set<Int> = [
                since == nil ? 5 : -1
            ]
            
            let filters = pubkeyOrHashtagReqFilters(pubkeys, hashtags: hashtags, limit: 150, kinds: FETCH_FOLLOWING_FEED_KINDS.subtracting(removeKinds))
            
            if let message = CM(type: .REQ, subscriptionId: "RESUME-" + config.id + "-" + (since?.description ?? "any"), filters: filters).json() {
                return (cmd: {
                    req(message)
                }, subId: "RESUME-" + config.id + "-" + (since?.description ?? "any"), targets: nil)
            }
            return nil
            
        case .pubkeysPreview(_):
            let pubkeys = config.pubkeys.count <= 2000 ? config.pubkeys : Set(config.pubkeys.shuffled().prefix(2000))
            
            guard pubkeys.count > 0 else {
                L.og.debug("☘️☘️ cmd with empty pubkeys and hashtags -[LOG]-")
                return nil
            }
            
            let removeKinds: Set<Int> = [
                since == nil ? 5 : -1
            ]
            
            let filters = pubkeyOrHashtagReqFilters(pubkeys, hashtags: [], limit: 150, kinds: FETCH_FOLLOWING_FEED_KINDS.subtracting(removeKinds))
            
            if let message = CM(type: .REQ, subscriptionId: "RESUME-" + config.id + "-" + (since?.description ?? "any"), filters: filters).json() {
                return (cmd: {
                    req(message)
                }, subId: "RESUME-" + config.id + "-" + (since?.description ?? "any"), targets: nil)
            }
            return nil
        case .pubkey:
            return nil
        case .relays(let feed):
            let relaysData = feed.relaysData
            guard !relaysData.isEmpty else { return nil }
            
            let removeKinds: Set<Int> = [
                since == nil ? 5 : -1
            ]
            
            let kinds = if !feed.kinds.isEmpty {
                feed.kinds.subtracting( !feed.repliesEnabled ? REPLY_KINDS : []).subtracting(removeKinds)
            }
            else {
                FETCH_GLOBAL_KINDS_WITH_REPLIES.subtracting( !feed.repliesEnabled ? REPLY_KINDS : []).subtracting(removeKinds)
            }
            
            let filters = globalFeedReqFilters(kinds: kinds, since: since, until: until)
            
            if let message = CM(type: .REQ, subscriptionId: "G-RESUME-" + config.id + "-" + (since?.description ?? "any"), filters: filters).json() {
                return (cmd: {
                    req(message, activeSubscriptionId: "G-RESUME-" + config.id + "-" + (since?.description ?? "any"), relays: relaysData)
                }, subId: "G-RESUME-" + config.id + "-" + (since?.description ?? "any"), targets: nil)
            }
            return nil
        case .relayPreview(let relayData):
            let relaysData: Set<RelayData> = [relayData]
            guard !relaysData.isEmpty else { return nil }
            
            let removeKinds: Set<Int> = [
                since == nil ? 5 : -1
            ]
            
            let filters = globalFeedReqFilters(kinds: FETCH_GLOBAL_KINDS.subtracting(removeKinds), since: since, until: until)
            
            if let message = CM(type: .REQ, subscriptionId: "G-RESUME-" + config.id + "-" + (since?.description ?? "any"), filters: filters).json() {
                return (cmd: {
                    req(message, activeSubscriptionId: "G-RESUME-" + config.id + "-" + (since?.description ?? "any"), relays: relaysData)
                }, subId: "G-RESUME-" + config.id + "-" + (since?.description ?? "any"), targets: nil)
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
    private func startNextPageNetworkRequest(
        _ config: NXColumnConfig,
        cursor: Int64,
        sessionGeneration: UInt64
    ) {
        guard feedSessionGeneration == sessionGeneration else { return }
        let prefix: String = switch config.columnType {
        case .picture, .vine, .yak:
            config.mediaFeedSourceSnapshot == .follows ? "PAGE" : "MEDIA-PAGE"
        case .relays, .relayPreview:
            "G-PAGE"
        default:
            "PAGE"
        }
        let nonce = UUID().uuidString.prefix(8)
        let subscriptionId = "\(prefix)-\(config.id)-\(sessionGeneration)-\(cursor)-\(nonce)"
        setPaginationState(.loadingNetwork(
            cursor: cursor,
            subscriptionId: subscriptionId,
            sessionGeneration: sessionGeneration
        ))

        guard sendNextPageReq(config, until: cursor, subscriptionId: subscriptionId) else {
            setPaginationState(.idle)
            finishEmptyInitialPageIfNeeded()
            return
        }

        paginationTimeoutTask?.cancel()
        paginationTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled, let self,
                  case .loadingNetwork(_, let activeSubscriptionId, let activeGeneration) = self.paginationState,
                  activeSubscriptionId == subscriptionId,
                  activeGeneration == sessionGeneration
            else { return }
            ConnectionPool.shared.closeSubscription(subscriptionId)
            self.setPaginationState(.idle)
            self.pauseEmptyPaginationRetry(
                config: config,
                requestedCursor: cursor,
                sessionGeneration: sessionGeneration
            )
            self.finishEmptyInitialPageIfNeeded()
        }
    }

    @MainActor
    private func finishEmptyInitialPageIfNeeded() {
        guard currentNRPostsOnScreen.isEmpty, case .loading = viewState else { return }
#if DEBUG
        recordFeedAction("older history finished empty · showing retry")
#endif
        endLatestFirstPaintHold()
        didFinish()
        viewState = .timeout
    }

    @MainActor
    @discardableResult
    private func sendNextPageReq(_ config: NXColumnConfig, until: Int64, subscriptionId: String) -> Bool {
        var didSend = false

#if DEBUG
        L.og.debug("☘️☘️ \(config.name) sendNextPageReq() \(subscriptionId) until=\(until) -[LOG]-")
#endif
        switch config.columnType {
        case .following(let feed):
            // Make sure max pubkeys is < 2000 (relay limits)
            let followingPubkeys = (feed.account?.followingPubkeys ?? []).union(feed.account?.privateFollowingPubkeys ?? [])
            let ownPubkey: Set<String> = if let account = feed.account {
                Set([account.publicKey])
            }
            else {
                Set<String>()
            }
            
            let pubkeys = if feed.accountPubkey == EXPLORER_PUBKEY {
                AppState.shared.rawExplorePubkeys.subtracting(AppState.shared.bgAppState.blockedPubkeys)
            }
            else if followingPubkeys.count > 1999 { // Take random 1999 + own pubkey if filter is too large
                Set(followingPubkeys.shuffled().prefix(1999)).union(ownPubkey)
            }
            else {
                followingPubkeys.union(ownPubkey)
            }
            
            guard !pubkeys.isEmpty else { return false }
             
            // Remove picture/yak/vine kinds from main following feed, but only if their seperate feeds are enabled and not desktop columns
            let removeSeperateFeedKinds: Set<Int> = [
                (!IS_DESKTOP_COLUMNS() && UserDefaults.standard.bool(forKey: "enable_picture_feed")) ? 20 : -1,
                (!IS_DESKTOP_COLUMNS() && UserDefaults.standard.bool(forKey: "enable_yak_feed")) ? 1222 : -1,
                (!IS_DESKTOP_COLUMNS() && UserDefaults.standard.bool(forKey: "enable_yak_feed")) ? 1244 : -1,
                (!IS_DESKTOP_COLUMNS() && UserDefaults.standard.bool(forKey: "enable_vine_feed")) ? 34236 : -1,
            ]
            
            let kinds = if !feed.kinds.isEmpty {
                feed.kinds.subtracting( !feed.repliesEnabled ? REPLY_KINDS : [])
            }
            else {
                QUERY_FOLLOWING_KINDS_WITH_REPLIES.subtracting(removeSeperateFeedKinds).subtracting( !feed.repliesEnabled ? REPLY_KINDS : [])
            }
            
            let filters = followingReqFilters(pubkeys, until: Int(until), limit: 150, kinds: kinds)
            
            outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: subscriptionId, filters: filters))
            didSend = true
            
        case .picture(let feed), .vine(let feed), .yak(let feed):
            if config.mediaFeedSourceSnapshot != .follows {
                sendBroadMediaReq(
                    config,
                    subscriptionId: subscriptionId,
                    until: Int(until),
                    limit: 150
                )
                return true
            }

            // Make sure max pubkeys is < 2000 (relay limits)
            let followingPubkeys = (feed.account?.followingPubkeys ?? []).union(feed.account?.privateFollowingPubkeys ?? [])
            let ownPubkey: Set<String> = if let account = feed.account {
                Set([account.publicKey])
            }
            else {
                Set<String>()
            }
            
            let pubkeys = if feed.accountPubkey == EXPLORER_PUBKEY {
                AppState.shared.rawExplorePubkeys.subtracting(AppState.shared.bgAppState.blockedPubkeys)
            }
            else if followingPubkeys.count > 1999 { // Take random 1999 + own pubkey if filter is too large
                Set(followingPubkeys.shuffled().prefix(1999)).union(ownPubkey)
            }
            else {
                followingPubkeys.union(ownPubkey)
            }
            
            let followingHashtags: Set<String> = (feed.account?.followingHashtags ?? [])
            let hashtags: Set<String> = if (followingHashtags.count + pubkeys.count) <= 2000, let account = feed.account {
                account.followingHashtags
            }
            else { [] } // Skip hashtags if filter is too large
            
            guard pubkeys.count > 0 || hashtags.count > 0 else { return false }
            
            let filters = switch config.columnType {
                case .vine(_):
                pubkeyOrHashtagReqFilters(pubkeys, hashtags: hashtags, until: Int(until), limit: 150, kinds: [34236,5])
                case .yak(_):
                pubkeyOrHashtagReqFilters(pubkeys, hashtags: hashtags, until: Int(until), limit: 150, kinds: [1222,1244,5])
                default: // .picture: // kind:20 + hashtags + kind:1-k20-tag
                pubkeyOrHashtagReqFilters(pubkeys, hashtags: hashtags, until: Int(until), limit: 150, kinds: [20,5]) + [Filters(
                    authors: pubkeys,
                    kinds: [1],
                    tagFilter: TagFilter(tag: "k", values: ["20"]),
                    until: Int(until),
                    limit: 150
                )]
            }
            
            outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: subscriptionId, filters: filters))
            didSend = true
            
        case .pubkeys(let feed), .followSet(let feed), .followPack(let feed):
            let pubkeys = feed.contactPubkeys.count <= 2000 ? feed.contactPubkeys : Set(feed.contactPubkeys.shuffled().prefix(2000))
            
            guard pubkeys.count > 0 else { return false }
            
            let kinds = if !feed.kinds.isEmpty {
                feed.kinds.subtracting( !feed.repliesEnabled ? REPLY_KINDS : [])
            }
            else {
                FETCH_FOLLOWING_FEED_KINDS_WITH_REPLIES.subtracting( !feed.repliesEnabled ? REPLY_KINDS : [])
            }
            
            let filters = Filters(
                authors: pubkeys,
                kinds: kinds,
                until: Int(until),
                limit: 100
            )
            
            nxReq(filters, subscriptionId: subscriptionId, useOutbox: feed.useOutbox)
            didSend = true
            
        case .someoneElses(_):
            let pubkeys = config.pubkeys.count <= 2000 ? config.pubkeys : Set(config.pubkeys.shuffled().prefix(2000))
            let hashtags = pubkeys.count + config.hashtags.count <= 2000 ? config.hashtags : [] // no hashtags if filter too large
            
            guard pubkeys.count > 0 || hashtags.count > 0 else { return false }
            let filters = pubkeyOrHashtagReqFilters(pubkeys, hashtags: hashtags, until: Int(until), limit: 100, kinds: FETCH_FOLLOWING_FEED_KINDS)
            
            if let message = CM(type: .REQ, subscriptionId: subscriptionId, filters: filters).json() {
                req(message)
                didSend = true
            }
            
        case .pubkeysPreview(_):
            let pubkeys = config.pubkeys.count <= 2000 ? config.pubkeys : Set(config.pubkeys.shuffled().prefix(2000))
            guard pubkeys.count > 0 else { return false }
            let filters = pubkeyOrHashtagReqFilters(pubkeys, hashtags: [], until: Int(until), limit: 100, kinds: FETCH_FOLLOWING_FEED_KINDS)
            
            if let message = CM(type: .REQ, subscriptionId: subscriptionId, filters: filters).json() {
                req(message)
                didSend = true
            }
            
        case .pubkey:
            let _: String? = nil
        case .relays(let feed):
            let relaysData = feed.relaysData
            guard !relaysData.isEmpty else { return false }
            
            let kinds = if !feed.kinds.isEmpty {
                feed.kinds.subtracting( !feed.repliesEnabled ? REPLY_KINDS : [])
            }
            else {
                FETCH_GLOBAL_KINDS_WITH_REPLIES.subtracting( !feed.repliesEnabled ? REPLY_KINDS : [])
            }
            
            nxReq(Filters(kinds: kinds, until: Int(until), limit: 100), subscriptionId: subscriptionId, relays: relaysData)
            didSend = true
        
        case .relayPreview(let relayData):
            let relaysData: Set<RelayData> = [relayData]
            guard !relaysData.isEmpty else { return false }
            nxReq(Filters(kinds: FETCH_GLOBAL_KINDS, until: Int(until), limit: 100), subscriptionId: subscriptionId, relays: relaysData)
            didSend = true
            
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
        return didSend
    }
    
    private var backlog = Backlog(auto: true)
    
    // prefix / .shortId only
    public var allShortIdsSeen: Set<String> {
        get {
            if case .picture(_) = config?.columnType {
                return _allShortIdsSeen
            }
            else if case .vine(_) = config?.columnType {
                return _allShortIdsSeen
            }
            else if case .yak(_) = config?.columnType {
                return _allShortIdsSeen
            }
            else {
                return SettingsStore.shared.appWideSeenTracker ? Deduplicator.shared.onScreenSeen : _allShortIdsSeen
            }
        }
        set {
            if case .pubkeysPreview(_) = config?.columnType {
                return
            }
            else if case .relayPreview(_) = config?.columnType {
                return
            }
            else if case .picture(_) = config?.columnType {
                _allShortIdsSeen = newValue
            }
            else if case .vine(_) = config?.columnType {
                _allShortIdsSeen = newValue
            }
            else if case .yak(_) = config?.columnType {
                _allShortIdsSeen = newValue
            }
            else if SettingsStore.shared.appWideSeenTracker {
                Deduplicator.shared.onScreenSeen = newValue
            }
            else {
                _allShortIdsSeen = newValue
            }
        }
    }
    
    public func markShortIdSeen(_ shortId: String) {
        if case .pubkeysPreview(_) = config?.columnType {
            return
        }
        else if case .relayPreview(_) = config?.columnType {
            return
        }
        else if case .picture(_) = config?.columnType {
            _allShortIdsSeen.insert(shortId)
        }
        else if case .vine(_) = config?.columnType {
            _allShortIdsSeen.insert(shortId)
        }
        else if case .yak(_) = config?.columnType {
            _allShortIdsSeen.insert(shortId)
        }
        else if SettingsStore.shared.appWideSeenTracker {
            Deduplicator.shared.insertOnScreenSeen(shortId)
        }
        else {
            _allShortIdsSeen.insert(shortId)
        }
    }
    
    public func markShortIdsSeen(_ shortIds: Set<String>) {
        if case .pubkeysPreview(_) = config?.columnType {
            return
        }
        else if case .relayPreview(_) = config?.columnType {
            return
        }
        else if case .picture(_) = config?.columnType {
            _allShortIdsSeen.formUnion(shortIds)
        }
        else if case .vine(_) = config?.columnType {
            _allShortIdsSeen.formUnion(shortIds)
        }
        else if case .yak(_) = config?.columnType {
            _allShortIdsSeen.formUnion(shortIds)
        }
        else if SettingsStore.shared.appWideSeenTracker {
            Deduplicator.shared.formUnionOnScreenSeen(shortIds)
        }
        else {
            _allShortIdsSeen.formUnion(shortIds)
        }
    }
    
    // Only shortIds: String(id.prefix(8))
    private var _allShortIdsSeen: Set<String> = []

    @MainActor
    private func recordAlreadySeenNewerCandidates(_ candidates: [NXAlreadySeenNewerPostCandidate]) {
        guard !candidates.isEmpty else { return }
        for candidate in candidates {
            alreadySeenNewerCandidates[candidate.id] = candidate
        }
        refreshAlreadySeenNewerPosts(for: currentNRPostsOnScreen)
    }

    private func refreshAlreadySeenNewerPosts(for posts: [NRPost]) {
        let visibleCreatedAt = posts.map(\.created_at)
        let candidateIDs = NXAlreadySeenNewerPosts.candidateIDs(
            from: Array(alreadySeenNewerCandidates.values),
            visibleCreatedAt: visibleCreatedAt
        )
        if alreadySeenNewerCount != candidateIDs.count {
            alreadySeenNewerCount = candidateIDs.count
        }
    }

    @MainActor
    private func clearAlreadySeenNewerPosts() {
        alreadySeenNewerCandidates = [:]
        alreadySeenNewerCount = 0
        isShowingAlreadySeenNewerPosts = false
    }

    @MainActor
    func showAlreadySeenNewerPosts() {
        guard !isShowingAlreadySeenNewerPosts,
              let config,
              !alreadySeenNewerCandidates.isEmpty
        else { return }

        let ids = NXAlreadySeenNewerPosts.candidateIDs(
            from: Array(alreadySeenNewerCandidates.values),
            visibleCreatedAt: currentNRPostsOnScreen.map(\.created_at)
        )
        guard !ids.isEmpty else {
            clearAlreadySeenNewerPosts()
            return
        }

        isShowingAlreadySeenNewerPosts = true
        let currentIdsOnScreen = self.currentIdsOnScreen
        let currentPosts = currentNRPostsOnScreen
        let since = currentPosts.map(\.created_at).max() ?? 0
        let sessionGeneration = feedSessionGeneration
        let wotEnabled = config.wotEnabled
        let repliesEnabled = config.repliesEnabled

        bg().perform { [weak self] in
            guard let self else { return }
            let request = Event.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@", ids)
            let events = (try? bg().fetch(request)) ?? []

            self.processToScreen(
                events,
                config: config,
                allShortIdsSeen: [],
                currentIdsOnScreen: currentIdsOnScreen,
                currentNRPostsOnScreen: currentPosts,
                sinceOrUntil: Int(since),
                older: false,
                wotEnabled: wotEnabled,
                repliesEnabled: repliesEnabled,
                revealAtTop: true,
                sessionGeneration: sessionGeneration
            ) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.feedSessionGeneration == sessionGeneration else { return }
                    self.isShowingAlreadySeenNewerPosts = false
                    if !Set(ids).isDisjoint(with: self.currentIdsOnScreen) {
                        self.clearAlreadySeenNewerPosts()
                    }
                    else {
#if DEBUG
                        self.recordFeedAction("SHOW AGAIN produced no visible candidate")
#endif
                    }
                }
            }
        }
    }
    
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
    public func saveLocalFeedState() {
        saveLocalFeedStateSubject.send()
    }
    
    private var saveLocalFeedStateSubject = PassthroughSubject<Void, Never>()
    
    @MainActor
    private func listenForSaveLocalFeedState(_ config: NXColumnConfig) {
        guard saveLocalStateSub == nil else { return }
        saveLocalStateSub = saveLocalFeedStateSubject
            .throttle(for: .seconds(5), scheduler: RunLoop.main, latest: true)
            .debounce(for: .seconds(5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                // Normally this is triggered via FeedsCoordinator to save all feed states and then also to disk
                // But here we just request to save this (not all) states and then we need to save manually here also
                self?.saveFeedState()
                // so save manually here
                LocalFeedStateManager.shared.saveToDisk()
            }
    }
    
    private var saveFeedStateSub: AnyCancellable?
    
    @MainActor
    private func listenForSaveFeedStates(_ config: NXColumnConfig) {
        guard saveFeedStateSub == nil else { return }
        saveFeedStateSub = FeedsCoordinator.shared.saveFeedStatesSubject
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.saveFeedState()
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
                    let activeConfig = self.config ?? config
                    guard isVisible && !isPaused && (!AppState.shared.appIsInBackground || IS_CATALYST) else {
                        queuedSubscriptionIds.add(subscriptionIds)
                        return
                    }
                    guard subscriptionIds.contains(activeConfig.id) else { return }
                    
#if DEBUG
                    L.og.debug("☘️☘️ \(config.name) listenForNewPosts.subscriptionIds \(subscriptionIds) -[LOG]-")
                    self.recordFeedAction("FETCH newer · listenForNewPosts / import · \(self.feedActionDebugViewport())")
#endif
                    
                    self.loadLocal(activeConfig)
                }
        }

        // Multi-column refresh is rotated by FeedFetchScheduler. The delayed
        // REQ is only needed when this is the single live column (iPhone/iPad).
        if !FeedsCoordinator.shared.hasMultipleVisibleColumns {
            realTimeReqTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self?.sendRealtimeReq(config)
            }
        }
    }

    /// PAGE- / MEDIA-PAGE- / G-PAGE- imports are older than the last row. The
    /// realtime listener ignores those ids and throttles 5s, so the user hit
    /// the tail and waited ~10s for a sudden dump that jumped the list.
    @MainActor
    private func listenForPaginationImports(_ config: NXColumnConfig) {
        guard pageEventsInDatabaseSub == nil else { return }
        let configId = config.id
        pageEventsInDatabaseSub = Importer.shared.importedMessagesFromSubscriptionIds
            .filter { ids in
                ids.contains { Self.isPaginationSubscription($0, configId: configId) }
            }
            .debounce(for: .seconds(0.15), scheduler: DispatchQueue.main)
            .sink { [weak self] importedIds in
                guard let self else { return }
                let activeConfig = self.config ?? config
                guard self.isVisible && !self.isPaused else { return }
                guard case .loadingNetwork(let cursor, let subscriptionId, let sessionGeneration) = self.paginationState,
                      self.feedSessionGeneration == sessionGeneration
                else { return }
                guard importedIds.contains(subscriptionId) else { return }

                let countBeforeLoad = self.currentNRPostsOnScreen.count
                self.latestUserLoadMore = true
                self.loadLocal(activeConfig, older: true) { [weak self] in
                    guard let self else { return }
                    self.latestUserLoadMore = false
                    guard self.feedSessionGeneration == sessionGeneration,
                          case .loadingNetwork(let activeCursor, let activeSubscriptionId, let activeGeneration) = self.paginationState,
                          activeCursor == cursor,
                          activeSubscriptionId == subscriptionId,
                          activeGeneration == sessionGeneration
                    else { return }
                    // Imported rows can all be filtered (already seen, muted, or
                    // replies). They still prove that the page request responded;
                    // leaving it alive until the six-second timeout only occupies
                    // relay slots and makes the footer look stuck.
                    self.paginationTimeoutTask?.cancel()
                    self.paginationTimeoutTask = nil
                    ConnectionPool.shared.closeSubscription(subscriptionId)
                    self.setPaginationState(.idle)
                    if self.currentNRPostsOnScreen.count > countBeforeLoad {
                        self.clearPaginationRetryPause()
                    } else {
                        self.pauseEmptyPaginationRetry(
                            config: activeConfig,
                            requestedCursor: cursor,
                            sessionGeneration: sessionGeneration
                        )
                    }
                    self.finishEmptyInitialPageIfNeeded()
                }
            }
    }

    private static func isPaginationSubscription(_ subscriptionId: String, configId: String) -> Bool {
        subscriptionId.hasPrefix("PAGE-" + configId + "-")
            || subscriptionId.hasPrefix("MEDIA-PAGE-" + configId + "-")
            || subscriptionId.hasPrefix("G-PAGE-" + configId + "-")
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
                L.og.debug("☘️☘️ \(config.name) listenForFirstConnection.load(config) -[LOG]-")
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
                    L.og.debug("☘️☘️ \(config.name) 🟠 reloadWhenNeeded feed.repliesEnabled changed from \(oldValue) to \(newValue) -[LOG]-")
#endif
                    self?.reload(config)
                }
            }
        
        feed.publisher(for: \.kinds_)
            .scan((feed.kinds_, feed.kinds_)) { (previous, current) in
                return (previous.1, current)
            }
            .dropFirst()  // Skip the initial value to avoid unnecessary reload on setup
            .sink { [weak self] oldValue, newValue in
                if oldValue != newValue {
#if DEBUG
                    L.og.debug("☘️☘️ \(config.name) 🟠 reloadWhenNeeded feed.kinds_ changed from \(oldValue) to \(newValue) -[LOG]-")
#endif
                    self?.reload(config)
                }
            }
            .store(in: &subscriptions)

        receiveNotification(.mediaFeedConfigurationChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let changedFeedId = notification.object as? UUID,
                      changedFeedId == feed.id
                else { return }
                ConnectionPool.shared.closeSubscription(config.id)
                self?.reload(config, refreshRemote: true)
            }
            .store(in: &subscriptions)
    }
    
    @MainActor
    private func listenForLastDisconnection(config: NXColumnConfig) {
        guard lastDisconnectionSub == nil else { return }
        lastDisconnectionSub = receiveNotification(.lastDisconnection)
            .debounce(for: .seconds(0.1), scheduler: DispatchQueue.global())
            .sink { [weak self] _ in
                guard let self else { return }
#if DEBUG
                L.og.debug("☘️☘️ \(config.name) listenForLastDisconnection -[LOG]-")
#endif
                Task { @MainActor in
                    self.watchForFirstConnection = true
                }
            }
        
    }
    
    private func fetchParents(_ danglers: [NRPost], config: NXColumnConfig, allShortIdsSeen: Set<String>, currentIdsOnScreen: Set<String>, currentNRPostsOnScreen: [NRPost] = [], sinceOrUntil: Int, older: Bool = false, sessionGeneration: UInt64? = nil) {
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
                let danglerIds = danglers
                    // less than 2 days ago
                    .filter { $0.createdAt.timeIntervalSince1970 > (Date.now.timeIntervalSince1970 - 172_800) }
                    .compactMap { $0.replyToId }
                    .filter { postId in
                        Importer.shared.existingIds[postId] == nil && postId.range(of: ":") == nil
                    }
                
//                let danglerATags = danglers
//                    .filter { $0.createdAt.timeIntervalSince1970 > (Date.now.timeIntervalSince1970 - 172_800) }
//                    .compactMap { $0.replyToId }
//                    .filter { postId in
//                        Importer.shared.existingIds[postId] == nil && postId.range(of: ":") != nil
//                    }
                
                if !danglerIds.isEmpty {
#if DEBUG
                    L.og.debug("☘️☘️ \(config.name) fetchParents: \(danglers.count.description), fetching.... -[LOG]-")
#endif
                    req(RM.getEvents(ids: danglerIds, subscriptionId: taskId)) // TODO: req or outboxReq?
                }
//                for aTagString in danglerATags {
//                    guard let aTag = try? ATag(aTagString) else { continue }
//                    req(RM.getArticle(pubkey: aTag.pubkey, kind: Int(aTag.kind), definition: aTag.definition, subscriptionId: taskId))
//                }
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
                        self.mergeFeedLastReadIntoSeen(config.feed)
                        let allShortIdsSeen = self.allShortIdsSeen
                        let currentIdsOnScreen = self.currentIdsOnScreen
                        let wotEnabled = config.wotEnabled
                        let repliesEnabled = config.repliesEnabled
                        
                        // Then back to bg for processing
                        bg().perform { [weak self] in
                            guard let self else { return }
#if DEBUG
                            L.og.debug("☘️☘️ \(config.name) fetchParents(.pubkeys)\(older ? "older" : "").processToScreen -[LOG]-")
#endif
                            self.processToScreen(danglingEvents, config: config, allShortIdsSeen: allShortIdsSeen, currentIdsOnScreen: currentIdsOnScreen, currentNRPostsOnScreen: currentNRPostsOnScreen, sinceOrUntil: sinceOrUntil, older: older, wotEnabled: wotEnabled, repliesEnabled: repliesEnabled, sessionGeneration: sessionGeneration)
                        }
                    }
                }
            },
            timeoutCommand: { (taskId) in
                bg().perform { [weak self]  in
                    let danglingEvents: [Event] = danglers
                    // less than 2 days ago
                        .filter { $0.createdAt.timeIntervalSince1970 > (Date.now.timeIntervalSince1970 - 172_800) }
                        .compactMap { $0.event }
#if DEBUG
                    L.og.debug("☘️☘️ \(config.name) fetchParents.timeoutCommand -[LOG]-")
#endif
                    
                    // Need to go to main context again to get current screen state
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.mergeFeedLastReadIntoSeen(config.feed)
                        let allShortIdsSeen = self.allShortIdsSeen
                        let currentIdsOnScreen = self.currentIdsOnScreen
                        let wotEnabled = config.wotEnabled
                        let repliesEnabled = config.repliesEnabled
                        
                        // Then back to bg for processing
                        bg().perform { [weak self] in
                            guard let self else { return }
#if DEBUG
                            L.og.debug("☘️☘️ \(config.name) fetchParents(.pubkeys)\(older ? "older" : "").processToScreen (timeoutCommand) -[LOG]-")
#endif
                            self.processToScreen(danglingEvents, config: config, allShortIdsSeen: allShortIdsSeen, currentIdsOnScreen: currentIdsOnScreen, currentNRPostsOnScreen: currentNRPostsOnScreen, sinceOrUntil: sinceOrUntil, older: older, wotEnabled: wotEnabled, repliesEnabled: repliesEnabled, sessionGeneration: sessionGeneration)
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
        guard !post.ownPostAttributes.isGoingToSend else { return } // don't prefetch unsent
        
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
    
    deinit {
        initialMediaTimeoutTask?.cancel()
        mediaDiscoveryImportTask?.cancel()
        lateMediaEventSub?.cancel()
#if DEBUG
        if let config {
            let configId = config.id
            Task { @MainActor in
                ConnectionPool.shared.closeSubscription(configId)
            }
            L.og.debug("☘️☘️ \(config.name) deinit  -[LOG]-")
        }
#endif
        
        // Cancel all subscriptions
        newEventsInDatabaseSub?.cancel()
        pageEventsInDatabaseSub?.cancel()
        newPostSavedSub?.cancel()
        newSingleRelayPostSavedSub?.cancel()
        newPostUndoSub?.cancel()
        firstConnectionSub?.cancel()
        reloadWhenNeededSub?.cancel()
        lastDisconnectionSub?.cancel()
        onAppearSubjectSub?.cancel()
        resumeFeedSub?.cancel()
        pauseFeedSub?.cancel()
        saveFeedStateSub?.cancel()
        followsChangedSub?.cancel()
        blockListUpdatedSub?.cancel()
        muteListUpdatedSub?.cancel()
        
        let scheduleId = columnVMid
        Task { @MainActor in
            FeedsCoordinator.shared.unregisterColumn(id: scheduleId)
        }
        
        // Cancel task
        realTimeReqTask?.cancel()
    }
}

enum NXFeedUpdateRebaser {
    /// Applies a snapshot-style update to the latest feed contents. Rows inserted
    /// or appended after `old` was captured are retained, while intentional
    /// removals from `desired` still take effect.
    static func rebase<Item, ID: Hashable>(
        old: [Item],
        desired: [Item],
        current: [Item],
        id: (Item) -> ID
    ) -> [Item] {
        let oldIDs = Set(old.map(id))
        let desiredIDs = Set(desired.map(id))
        let inserted = desired.filter { !oldIDs.contains(id($0)) }
        let insertedIDs = Set(inserted.map(id))
        let removedIDs = oldIDs.subtracting(desiredIDs)
        return inserted + current.filter {
            let itemID = id($0)
            return !insertedIDs.contains(itemID) && !removedIDs.contains(itemID)
        }
    }
}

// -- MARK: POST RENDERING
extension NXColumnViewModel {
    
    // Primary function to put Events on screen
    // allIdsSeen must be prefix / .shortId format
    private func processToScreen(_ events: [Event], config: NXColumnConfig, allShortIdsSeen: Set<String>, currentIdsOnScreen: Set<String>, currentNRPostsOnScreen: [NRPost] = [], sinceOrUntil: Int, older: Bool, wotEnabled: Bool, repliesEnabled: Bool, revealAtTop: Bool = false, sessionGeneration: UInt64? = nil, completion: (() -> Void)? = nil) {
#if DEBUG
        let transformStartedAt = Date()
        L.og.debug("☘️☘️ \(config.name) processToScreen() -[LOG]-")
#endif
        // Capture this while on the Event context. It must be retained even if
        // every fetched event is filtered and produces no NRPost.
        let oldestScannedCreatedAt = older ? events.map(\.created_at).min() : nil
        // Apply WoT filter, remove already on screen
        let preparation = prepareEvents(events, config: config, allShortIdsSeen: allShortIdsSeen, currentIdsOnScreen: currentIdsOnScreen, currentNRPostsOnScreen: currentNRPostsOnScreen, sinceOrUntil: sinceOrUntil, older: older, wotEnabled: wotEnabled, repliesEnabled: repliesEnabled)
        let preparedEvents = preparation.events
#if DEBUG
        let preparedAt = Date()
#endif
        // Transform from Event to NRPost (only not already on screen by prev statement)
        let nrPosts: [NRPost] = self.transformToNRPosts(preparedEvents, config: config, currentIdsOnScreen: currentIdsOnScreen, currentNRPostsOnScreen: currentNRPostsOnScreen, repliesEnabled: repliesEnabled)
#if DEBUG
        let nrPostsAt = Date()
#endif
        // Turn loose NRPost replies into partial threads / leafs
        let partialThreads: [NRPost] = self.transformToPartialThreads(nrPosts, currentIdsOnScreen: currentIdsOnScreen)
        
        let (danglers, partialThreadsWithParent) = extractDanglingReplies(partialThreads)
        
#if DEBUG
        let threadsAt = Date()
        recordFeedActionFromBackground(
            "FETCH \(older ? "older" : "newer") · \(events.count)→\(preparedEvents.count)→\(partialThreadsWithParent.count) · prepare \(debugSeconds(from: transformStartedAt, to: preparedAt)) · NR \(debugSeconds(from: preparedAt, to: nrPostsAt)) · threads \(debugSeconds(from: nrPostsAt, to: threadsAt))"
        )
        let proxy = ScrollOffset.proxy(.top, id: self.columnVMid)
        L.og.debug("☘️☘️ \(config.name) processToScreen() danglers: \(danglers.count) partialThreadsWithParent: \(partialThreadsWithParent.count) offset: \(proxy.offset) -[LOG]-")
#endif
        
        let newDanglers = danglers.filter { !self.danglingIds.contains($0.id) }
        if !newDanglers.isEmpty && repliesEnabled {
            danglingIds = danglingIds.union(newDanglers.map { $0.id })
            fetchParents(newDanglers, config: config, allShortIdsSeen: allShortIdsSeen, currentIdsOnScreen: currentIdsOnScreen, currentNRPostsOnScreen: currentNRPostsOnScreen, sinceOrUntil: sinceOrUntil, older: older, sessionGeneration: sessionGeneration)
        }
        
        guard !partialThreadsWithParent.isEmpty else {
            Task { @MainActor in
                guard self.shouldAcceptResults(for: config, sessionGeneration: sessionGeneration) else {
                    completion?()
                    return
                }
                self.noteOlderPaginationScan(oldestScannedCreatedAt)
                if !older {
                    self.suppressPaginationUntilRememberNewerLoad = false
                    self.recordAlreadySeenNewerCandidates(preparation.alreadySeenCandidates)
                }
                if latestFirstPaintMinimum == nil,
                   let speedTest, !speedTest.relaysFinishedAt.isEmpty {
#if DEBUG
                    L.og.debug("🏁🏁 \(config.name) processToScreen loadingBarViewState = .finalLoad -[LOG]-")
#endif
                    if speedTest.loadingBarViewState != .finished && speedTest.loadingBarViewState != .finalLoad {
                        speedTest.loadingBarViewState = .finalLoad
                    }
                }
                completion?()
                if !older {
                    self.recoverSparseRememberOnFeedIfNeeded(config)
                }
            }
            return
        }
        
        Task { @MainActor in
            guard self.shouldAcceptResults(for: config, sessionGeneration: sessionGeneration) else {
                completion?()
                return
            }
            self.noteOlderPaginationScan(oldestScannedCreatedAt)
            if !older {
                self.suppressPaginationUntilRememberNewerLoad = false
                self.recordAlreadySeenNewerCandidates(preparation.alreadySeenCandidates)
            }
            self.putOnScreen(
                partialThreadsWithParent,
                config: config,
                insertAtEnd: older,
                revealAtTop: revealAtTop,
                completion: {
                    completion?()
                    if !older {
                        self.recoverSparseRememberOnFeedIfNeeded(config)
                    }
                }
            )
        }
    }

    @MainActor
    private func recoverSparseRememberOnFeedIfNeeded(_ config: NXColumnConfig) {
        guard config.continue,
              currentNRPostsOnScreen.count < 6,
              let oldest = currentNRPostsOnScreen.last
        else { return }
#if DEBUG
        recordFeedAction(
            "PAGE recover sparse restore · \(currentNRPostsOnScreen.count) posts · \(feedActionDebugViewport())"
        )
#endif
        requestNextPageIfNeeded(until: oldest.created_at, trigger: "sparse restore")
    }

    @MainActor
    private func shouldAcceptResults(for incomingConfig: NXColumnConfig, sessionGeneration: UInt64? = nil) -> Bool {
        if let sessionGeneration, sessionGeneration != feedSessionGeneration {
            return false
        }
        guard incomingConfig.mediaFeedSourceSnapshot != nil else { return true }
        guard config?.id == incomingConfig.id,
              config?.mediaFeedSourceSnapshot == incomingConfig.mediaFeedSourceSnapshot
        else { return false }
        if case .timeout = viewState { return false }
        return true
    }
    
    // -- MARK: Subfunctions used by processToScreen():
    
    // Prepare events: apply WoT filter, remove already on screen, load .parentEvents
    private func prepareEvents(_ events: [Event], config: NXColumnConfig, allShortIdsSeen: Set<String>, currentIdsOnScreen: Set<String>, currentNRPostsOnScreen: [NRPost], sinceOrUntil: Int, older: Bool, wotEnabled: Bool, repliesEnabled: Bool) -> (events: [Event], alreadySeenCandidates: [NXAlreadySeenNewerPostCandidate]) {
        shouldBeBg()
        let isMediaFeed: Bool = switch config.columnType {
        case .picture, .vine, .yak: true
        default: false
        }
        let isSeen: (Event) -> Bool = {
            if allShortIdsSeen.contains($0.shortId) { return true }
            if $0.kind == 6,
               let firstQuoteId = $0.firstQuoteId,
               allShortIdsSeen.contains(String(firstQuoteId.prefix(8))) {
                return true
            }
            return false
        }

        // Apply the time window before WoT and parent/thread work. The initial
        // latest screen normally prefers unseen events. If fewer than a full
        // screen are unseen, however, use the newest eligible events instead of
        // repeatedly querying the same 50 rows and eventually revealing one
        // stale unseen post (common in Explore).
        let timeFilteredEvents: [Event] = events.filter {
                if !older {
                    return $0.created_at > Int64(sinceOrUntil) // skip all older than first on screen (check LEAFS only)
                }
                else {
                    return Int64(sinceOrUntil) > $0.created_at // skip all newer than last on screen (check LEAFS only)
                }
            }
        let wotFilteredEvents: [Event] = ((wotEnabled || isMediaFeed)
            ? applyWoT(timeFilteredEvents, config: config)
            : timeFilteredEvents)
        let alreadySeenCandidates = older ? [] : wotFilteredEvents
            .filter(isSeen)
            .map { NXAlreadySeenNewerPostCandidate(id: $0.id, createdAt: $0.created_at) }
        let unseenEvents = wotFilteredEvents.filter { !isSeen($0) }
        let isHeldFirstPaint = !older
            && latestFirstPaintMinimum != nil
            && currentNRPostsOnScreen.isEmpty
        let candidateEvents = if isHeldFirstPaint,
                                 unseenEvents.count < LATEST_FEED_FIRST_PAINT_COUNT {
            wotFilteredEvents
        }
        else {
            unseenEvents
        }
        // First paint only needs a screenful. Building parent threads for
        // the whole firehose is what pushed p1 past 3s with 50+ extras.
        let eventsToRender = firstPaintEventCap(
            from: candidateEvents,
            older: older,
            onScreenCount: currentNRPostsOnScreen.count
        )
        let newUnrenderedEvents: [Event] = eventsToRender
            .map {
                $0.parentEvents = !repliesEnabled ? [] : Event.getParentEvents($0)
                return $0
            }

        let newEventIds = getAllEventIds(newUnrenderedEvents)
        let newCount = newEventIds.subtracting(currentIdsOnScreen).count

        guard newCount > 0 else {
            // First paint / empty latest feed: show newest local posts even if
            // they were already seen. Remember-off after 2 minutes is "latest now".
            if case .loading = viewState {
                let fallbackCandidates = ((wotEnabled || isMediaFeed)
                    ? applyWoT(events, config: config)
                    : events)
                let fallbackEvents = firstPaintEventCap(from: fallbackCandidates, older: false)
                    .map {
                        $0.parentEvents = !repliesEnabled ? [] : Event.getParentEvents($0)
                        return $0
                    }
#if DEBUG
                L.og.debug("☘️☘️ \(config.name) prepareEvents newCount \(fallbackEvents.count) (first load, ignore seen) -[LOG]-")
#endif
                return (fallbackEvents, alreadySeenCandidates)
            }

            return ([], alreadySeenCandidates)
        }
        
#if DEBUG
        L.og.debug("☘️☘️ \(config.name) prepareEvents newCount \(newCount.description) -[LOG]-")
#endif
        
        return (newUnrenderedEvents, alreadySeenCandidates)
    }

    private func firstPaintEventCap(from events: [Event], older: Bool, onScreenCount: Int = 0) -> [Event] {
        let remainingInitial = max(0, LATEST_FEED_INITIAL_VISIBLE - onScreenCount)
        let cap = if older && latestBackfill && !latestUserLoadMore {
            min(
                latestQuietOlderAppend ? LATEST_FEED_QUIET_OLDER_CAP : remainingInitial,
                remainingInitial
            )
        }
        else if older && latestBackfill {
            LATEST_FEED_INITIAL_VISIBLE
        }
        else if !older, latestFirstPaintMinimum != nil, case .loading = viewState {
            LATEST_FEED_FIRST_PAINT_EVENT_CAP
        }
        else {
            events.count
        }
        guard events.count > cap else { return events }
        return Array(events.sorted { $0.created_at > $1.created_at }.prefix(cap))
    }
    
    private func applyWoT(_ events: [Event], config: NXColumnConfig) -> [Event] {
        // if pubkeys feed, always show all the pubkeys
        if case .pubkeys(_) = config.columnType {
            return events
        }
        
        // if following feed, always show all the pubkeys
        if case .following = config.columnType {
            return events
        }
        
        switch config.columnType {
        case .picture, .vine, .yak:
            return applyMediaSource(events, config: config)
        default:
            break
        }
        
        guard WOT_FILTER_ENABLED() else { return events }  // Return all if globally disabled
        
        if case .relays(_) = config.columnType {
            // if we are here, type is .relays, only filter if the feed specific WoT filter is enabled
            return events.filter { $0.inWoT }
        }
                
        return events
    }

    private func applyMediaSource(_ events: [Event], config: NXColumnConfig) -> [Event] {
        switch config.mediaFeedSourceSnapshot ?? .follows {
        case .follows, .webOfTrust:
            return events.filter { config.mediaAllowedPubkeysSnapshot.contains($0.pubkey) }
        case .selectedRelays:
            let selectedRelayIds = Set(config.mediaRelaysSnapshot.map(\.id))
            guard !selectedRelayIds.isEmpty else { return [] }
            return events.filter { event in
                let receivedRelayIds = Set((event.relays ?? "")
                    .split(separator: " ")
                    .map { normalizeRelayUrl(String($0)) })
                return !selectedRelayIds.isDisjoint(with: receivedRelayIds)
            }
        }
    }
    
    private func transformToNRPosts(_ events: [Event], config: NXColumnConfig, older: Bool = false, currentIdsOnScreen: Set<String>, currentNRPostsOnScreen: [NRPost], repliesEnabled: Bool) -> [NRPost] { // call from bg
        shouldBeBg()

        let transformedNrPosts = events
            // Don't transform again what is already on screen
            .filter { !currentIdsOnScreen.contains($0.id) }
            // Skip spam-filtered events (includes muted words)
            .filter { !$0.isMutedByWords }
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
    public func putOnScreen(_ addedPosts: [NRPost], config: NXColumnConfig, insertAtEnd: Bool = false, revealAtTop: Bool = false, completion: (() -> Void)? = nil) {

        if !addedPosts.isEmpty {
            mediaUpdatesAvailable = false
        }

        if case .posts(let existingPosts) = viewState { // There are already posts on screen
            
            
            // Only the ids of self.unreadIds where unreadIds[key] > 0
            let currentUnreadIdsOnScreen: Set<String> = Set(
                self.vmInner.unreadIds.filter({ $0.value > 0 }).keys
            )
            
            // Somehow we still have duplicates here that should have been filtered in prev steps (bug?) so filter duplicates again here
            let currentIdsOnScreen = Set(existingPosts.map { $0.id }).union(currentUnreadIdsOnScreen)
            
            
            let onlyNewAddedPosts = addedPosts
                .filter {
                    // if it is a repost, check reposted-id also
                    if $0.kind == 6, let firstQuoteId = $0.firstQuoteId, currentIdsOnScreen.contains(firstQuoteId) {
                        return false
                    }
                    // else just check the normal id
                    return !currentIdsOnScreen.contains($0.id)
                }
                .uniqued(on: { $0.id }) // <--- need last line?
#if DEBUG
            FeedFetchDebug.shared.noteAccepted(speedTest, count: onlyNewAddedPosts.count)
#endif
            
            if !insertAtEnd && latestSuppressPrepend {
#if DEBUG
                L.og.debug("☘️☘️ \(config.name) putOnScreen skip prepend until latest fill finishes -[LOG]-")
#endif
                completion?()
                return
            }

            if !insertAtEnd { // add on top
                let isAtTop = isVisuallyAtTopForIncomingPosts()
                if vmInner.isAtTop != isAtTop {
                    vmInner.isAtTop = isAtTop
                }
#if DEBUG
                L.og.debug("☘️☘️ \(config.name) putOnScreen isAtTop: \(isAtTop) addedPosts (TOP) \(onlyNewAddedPosts.count.description) -> OLD FIRST: \((existingPosts.first?.content ?? "").prefix(150))  -[LOG]-")
                recordFeedAction(
                    "PREPEND decide · visualTop \(isAtTop) · added \(onlyNewAddedPosts.count) · existing \(existingPosts.count) · reading \((vmInner.readingPostID ?? vmInner.pendingScrollToPostID).map(shortDebugID) ?? "none") · \(feedActionDebugViewport())"
                )
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
                
                // Update unread count
                vmInner.updateUnreadIds { unreadIds in
                    for post in onlyNewAddedPosts {
                        if unreadIds[post.id] == nil {
                            unreadIds[post.id] = 1 + post.parentPosts.count
                        }
                    }
                }
                
                if revealAtTop {
                    // This update was explicitly requested by the user. Do not preserve
                    // the old first row: that would insert the post above the viewport
                    // and make the button appear to have done nothing.
                    vmInner.abortPreparedScrollRestore()
                    vmInner.cancelPendingFeedSettle?()
                    vmInner.holdUnreadAboveReadingPost = false
                    vmInner.readingPostID = nil
                    vmInner.unreadIds = [:]
                    vmInner.isAtTop = true
                    vmInner.updateIsAtTopSubject.send()
                    withTransaction(Transaction(animation: nil)) {
                        viewState = .posts(addedAndExistingPostsTruncated)
                    }
                    if let firstRevealedPostID = onlyNewAddedPosts.first?.id {
                        vmInner.requestScroll(to: 0, postID: firstRevealedPostID)
                    }
#if DEBUG
                    recordFeedAction(
                        "revealed \(onlyNewAddedPosts.count) already-seen at top · \(existingPosts.count)→\(addedAndExistingPostsTruncated.count) · \(feedActionDebugViewport())"
                    )
#endif
                }
                else if isAtTop {
                    // Visually at top: pin to the on-screen first post. A leftover
                    // readingPostID from an unfinished restore is further down the list
                    // and would yank the user away from the post they just started reading.
                    let previousFirstPostId = existingPosts.first?.id
                    
                    // TODO: Should already start prefetching missing onlyNewAddedPosts pfp/kind 0 here

                    if SettingsStore.shared.autoScroll {
                        // withAnimation intentionally lets a stationary feed move to the newest post.
                        setPosts(addedAndExistingPostsTruncated)
#if DEBUG
                        recordFeedAction(
                            "inserted \(onlyNewAddedPosts.count) newer at top · \(existingPosts.count)→\(addedAndExistingPostsTruncated.count) · auto-scroll · \(feedActionDebugViewport())"
                        )
#endif
                    }
                    else {
                        // Same snapshot pin as a mid-feed prepend. hide+scrollTo
                        // "restore first post" flashed a second restore cover.
                        if vmInner.readingPostID == nil {
                            vmInner.readingPostID = previousFirstPostId
                                ?? vmInner.pendingScrollToPostID
                        }
                        vmInner.holdUnreadAboveReadingPost = true
                        setPosts(addedAndExistingPostsTruncated)
                    }
                }
                else {
#if DEBUG
                    L.og.debug("☘️☘️📜 \(config.name) putOnScreen isAtTop: \(self.vmInner.isAtTop) pin visible post + not at top, to keep scroll pos -[LOG]-")
#endif
                    // Keep the reading identity so a remounted List or a delayed restore
                    // scroll can still find the same post after rows are inserted above it.
                    if vmInner.readingPostID == nil {
                        vmInner.readingPostID = vmInner.pendingScrollToPostID
                    }
                    setPosts(addedAndExistingPostsTruncated)
                }
            }
            else { // add below
                let postsToAppend = if latestBackfill && !latestUserLoadMore {
                    Array(onlyNewAddedPosts.prefix(max(0, LATEST_FEED_INITIAL_VISIBLE - existingPosts.count)))
                }
                else {
                    onlyNewAddedPosts
                }
#if DEBUG
                L.og.debug("☘️☘️ \(config.name) putOnScreen addedPosts (AT END) \(postsToAppend.count.description) -[LOG]-")
#endif
                guard !postsToAppend.isEmpty else {
                    completion?()
                    return
                }
                // SwiftUI List can reconcile self-sizing rows against estimated heights
                // when its identity changes during drag/deceleration, moving the viewport
                // backward. Queue the append until idle, but do not manually correct it.
#if DEBUG
                recordFeedAction(
                    "APPEND decide · +\(postsToAppend.count) · will cancel settle · \(feedActionDebugViewport())"
                )
#endif
                vmInner.abortPreparedScrollRestore()
                vmInner.cancelPendingFeedSettle?()
                let applyAppend = { [weak self] () -> [String] in
                    guard let self else {
                        completion?()
                        return []
                    }
                    let currentPosts = self.currentNRPostsOnScreen
                    let currentIDs = Set(currentPosts.map(\.id))
                    let actualPostsToAppend = postsToAppend.filter { !currentIDs.contains($0.id) }
                    guard !actualPostsToAppend.isEmpty else {
                        completion?()
                        self.didFinish()
                        return currentPosts.map(\.id)
                    }
                    let appendedPosts = currentPosts + actualPostsToAppend
                    withTransaction(Transaction(animation: nil)) {
                        self.viewState = .posts(appendedPosts)
                    }
#if DEBUG
                    self.recordFeedAction(
                        "appended \(actualPostsToAppend.count) older at end after idle · \(currentPosts.count)→\(appendedPosts.count) · \(self.feedActionDebugViewport())"
                    )
#endif
                    // Pagination uses the visible count change to decide whether local data
                    // satisfied this page or a relay PAGE request is needed. Complete only
                    // after the deferred append is real, and keep the request single-flight
                    // while we wait for scroll idle.
                    completion?()
                    self.didFinish()
                    return appendedPosts.map(\.id)
                }
                if let performAnchoredFeedUpdate = vmInner.performAnchoredFeedUpdate {
                    performAnchoredFeedUpdate("older posts append", applyAppend)
                } else {
                    _ = applyAppend()
                }
                return
            }
        }
        else { // Nothing on screen yet, put first posts on screen
            let uniqueAddedPosts = addedPosts.uniqued(on: { $0.id })
                .sorted(by: { $0.created_at > $1.created_at })
            if let min = latestFirstPaintMinimum {
                if uniqueAddedPosts.count < min {
                    latestHeldPostCount = uniqueAddedPosts.count
#if DEBUG
                    L.og.debug("☘️☘️ \(config.name) putOnScreen holding first paint \(uniqueAddedPosts.count)/\(min) -[LOG]-")
#endif
                    completion?()
                    return
                }
                latestHeldPostCount = 0
                let firstScreen = Array(uniqueAddedPosts.prefix(min))
#if DEBUG
                L.og.debug("☘️☘️ \(config.name) putOnScreen first paint \(firstScreen.count)/\(uniqueAddedPosts.count) -[LOG]-")
                FeedFetchDebug.shared.noteAccepted(speedTest, count: firstScreen.count)
#endif
                if !vmInner.isAtTop {
                    vmInner.isAtTop = true
                }
                vmInner.abortPreparedScrollRestore()
                setPosts(firstScreen, animated: false)
#if DEBUG
                recordFeedAction("first paint · 0→\(firstScreen.count) posts")
#endif
                completion?()
                didFinish()
                return
            }
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) putOnScreen addedPosts (💦FIRST💦) \(uniqueAddedPosts.count.description) - \((uniqueAddedPosts.first?.content ?? "").prefix(150)) -[LOG]-")
            FeedFetchDebug.shared.noteAccepted(speedTest, count: uniqueAddedPosts.count)
#endif
            if !vmInner.isAtTop {
                vmInner.isAtTop = true
            }
            vmInner.abortPreparedScrollRestore()
            latestHeldPostCount = 0
            setPosts(uniqueAddedPosts)
#if DEBUG
            recordFeedAction("initial feed · 0→\(uniqueAddedPosts.count) posts")
#endif
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
            if event.kind == 6, let firstQuoteId = event.firstQuoteId {
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
    private func loadRemote(_ config: NXColumnConfig) async {
        // Cold launch can schedule the same Remember-off feed through both the
        // initial appearance and the app-wide resume pass. Starting the second
        // request cancels phase one and queues an identical Core Data read, so
        // the otherwise-ready first result is discarded. Keep the active latest
        // session; explicit reload/resume paths cancel it before coming here.
        if !config.continue, gapFiller?.hasActiveLatestRequest == true {
#if DEBUG
            recordFeedAction("remote fetch coalesced · latest request already active")
#endif
            return
        }
#if DEBUG
        L.og.debug("☘️☘️ \(config.name) loadRemote(config) -[LOG]-")
        recordFeedAction("remote fetch started · first-paint target \(LATEST_FEED_FIRST_PAINT_COUNT)")
#endif
        
        switch config.columnType {
        case .relays(let feed):
            let relays = feed.relaysData
            guard !relays.isEmpty else {
                self.didFinish()
                viewState = .error("No relays selected for this custom feed")
                return
            }

            let mostRecentCreatedAt = self.mostRecentCreatedAt ?? 0
            let wotEnabled = config.wotEnabled
            let repliesEnabled = config.repliesEnabled
            
            let fetchKinds = if !feed.kinds.isEmpty {
                feed.kinds.subtracting( !feed.repliesEnabled ? REPLY_KINDS : [])
            }
            else {
                FETCH_GLOBAL_KINDS_WITH_REPLIES.subtracting( !feed.repliesEnabled ? REPLY_KINDS : [])
            }
            
            // Fetch from relays
            speedTest?.requestStarted()
            let resumeSubId = "RESUME-" + config.id
#if DEBUG
            FeedFetchDebug.shared.attach(
                speedTest,
                subscriptionId: resumeSubId,
                summary: "\(config.name) relay feed kinds=\(fetchKinds.count)",
                seeds: ConnectionPool.shared.feedFetchDebugSeeds(for: Set(relays.map(\.id)))
            )
#endif
            _ = try? await relayReq(Filters(kinds: fetchKinds, limit: 250), timeout: 5.5, relays: relays, subscriptionId: resumeSubId)
            
            let queryKinds = if !feed.kinds.isEmpty {
                feed.kinds.subtracting( !feed.repliesEnabled ? REPLY_KINDS : [])
            }
            else {
                QUERY_FOLLOWING_KINDS_WITH_REPLIES.subtracting( !feed.repliesEnabled ? REPLY_KINDS : [])
            }
                              
            // Fetch from DB
            let postsByRelays: [Event] = await withBgContext { _ in
                let fr = Event.postsByRelays(relays, lastAppearedCreatedAt: Int64(mostRecentCreatedAt), fetchLimit: 150, kinds: queryKinds)
                return (try? bg().fetch(fr)) ?? []
            }
            
            if postsByRelays.isEmpty && self.currentNRPostsOnScreen.count == 0 {
                self.speedTest?.relayTimedout()
                Task { @MainActor in
                    if case .loading = self.viewState {
                        self.didFinish()
                        self.viewState = .timeout
                    }
                }
            }
            else {
                speedTest?.relayFinished()
                
                // TODO: Check if we still hit .fetchLimit problem here
#if DEBUG
                L.og.debug("☘️☘️ \(config.name) loadRemoteRelays() relayFinished events.count \(postsByRelays.count.description) -[LOG]-")
#endif
                
                // Need to go to main context again to get current screen state
                Task { @MainActor in
                    self.mergeFeedLastReadIntoSeen(feed)
                    let allShortIdsSeen = self.allShortIdsSeen
                    let currentIdsOnScreen = self.currentIdsOnScreen
                    let since = (self.mostRecentCreatedAt ?? 0)
                    
                    // Then back to bg for processing
                    bg().perform { [weak self] in
                        self?.processToScreen(postsByRelays, config: config, allShortIdsSeen: allShortIdsSeen, currentIdsOnScreen: currentIdsOnScreen, sinceOrUntil: since, older: false, wotEnabled: wotEnabled, repliesEnabled: repliesEnabled) {
                            // completion runs in @MainActor
                            // if still nothing is on screen, run again without already-seen id filter
                            if self?.currentIdsOnScreen.count == 0 {
                                bg().perform { [weak self] in
                                    self?.processToScreen(postsByRelays, config: config, allShortIdsSeen: [], currentIdsOnScreen: currentIdsOnScreen, sinceOrUntil: since, older: false, wotEnabled: wotEnabled, repliesEnabled: repliesEnabled)
                                }
                            }
                        }
                    }
                }
            }
        default:
            // Fetch since 5 minutes before most recent item on screen (since) or .refeshedAt
            let sinceTimestamp = if case .posts(let nrPosts) = viewState {
                (nrPosts.first?.created_at ?? self.nextFetchSince) - Int64(300)
            }
            else { // or if empty screen: nextFetchSince (since)
                self.nextFetchSince
            }
            // Don't go older than 24 hrs ago
            let maxAgo = Int64(Date().addingTimeInterval(-86_400).timeIntervalSince1970)
            
            
            if config.continue {
                self.gapFiller?.fetchGap(since: max(sinceTimestamp, maxAgo), currentGap: 0)
            }
            else {
                self.gapFiller?.fetchSimple(limit: 75)
            }
            
            // Media feeds resolve profiles lazily for displayed posts. Proactively
            // requesting metadata for the whole follow list can enqueue thousands
            // of unrelated events and delay the actual media imports past EOSE.
            let isMediaFeed: Bool = switch config.columnType {
            case .picture, .vine, .yak: true
            default: false
            }
            if !isMediaFeed,
               let feed = config.feed,
               feed.profilesFetchedAt == nil || (feed.profilesFetchedAt?.timeIntervalSinceNow ?? 0) < -900 {
                fetchProfiles(config)
            }
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
        
        var pubkeys: Set<String>
        
        switch config.columnType {
        case .following(let feed), .picture(let feed), .vine(let feed), .yak(let feed):
                // Make sure max pubkeys is < 2000 (relay limits)
                let followingPubkeys = (feed.account?.followingPubkeys ?? []).union(feed.account?.privateFollowingPubkeys ?? [])
                let ownPubkey: Set<String> = if let account = feed.account {
                    Set([account.publicKey])
                }
                else {
                    Set<String>()
                }
                
                pubkeys = if feed.accountPubkey == EXPLORER_PUBKEY {
                    AppState.shared.rawExplorePubkeys.subtracting(AppState.shared.bgAppState.blockedPubkeys)
                }
                else if followingPubkeys.count > 1999 { // Take random 1999 + own pubkey if filter is too large
                    Set(followingPubkeys.shuffled().prefix(1999)).union(ownPubkey)
                }
                else {
                    followingPubkeys.union(ownPubkey)
                }
            
            case .pubkeys(let feed), .followSet(let feed), .followPack(let feed):
                pubkeys = feed.contactPubkeys.count <= 2000 ? feed.contactPubkeys : Set(feed.contactPubkeys.shuffled().prefix(2000))
            
            case .someoneElses(_), .pubkeysPreview(_):
                pubkeys = config.pubkeys.count <= 2000 ? config.pubkeys : Set(config.pubkeys.shuffled().prefix(2000))
            
            default:
                pubkeys = []
                break
            
        }

        
        guard !pubkeys.isEmpty else {
#if DEBUG
            L.fetching.debug("☘️☘️ \(config.name) not checking profiles, pubkeys isEmpty")
#endif
            return
        }
        
#if DEBUG
        L.fetching.debug("☘️☘️ \(config.name) checking profiles since: \(since?.description ?? "") -[LOG]-")
#endif
        
        let subscriptionId = "Profiles-" + feed.subscriptionId
        let filters = Filters(authors: pubkeys, kinds: FETCH_FOLLOWING_PROFILE_KINDS, since: since)
        
        if case .following(_) = config.columnType {
            outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: subscriptionId, filters: [filters]))
        }
        else if case .picture(_) = config.columnType {
            outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: subscriptionId, filters: [filters]))
        }
        else if case .vine(_) = config.columnType {
            outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: subscriptionId, filters: [filters]))
        }
        else if case .yak(_) = config.columnType {
            outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: subscriptionId, filters: [filters]))
        }
        else {
            nxReq(filters, subscriptionId: subscriptionId, useOutbox: feed.useOutbox)
        }
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
#if DEBUG
                L.og.debug("☘️☘️ \(config.name) 🟪 Fetching clEvent from relays")
#endif
                self.speedTest?.requestStarted()
                req(RM.getAuthorContactsList(pubkey: pubkey, subscriptionId: taskId))
            },
            processResponseCommand: { taskId, _, clEvent in
                bg().perform {
#if DEBUG
                    L.og.debug("☘️☘️ \(config.name) 🟪 Processing clEvent response from relays")
#endif
                    var updatedConfig = config
                    if let clEvent = clEvent, clEvent.pubkey == pubkey && clEvent.kind == 3 {
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
    public func requestNextPageIfNeeded(until: Int64, trigger: String = "near tail") {
        guard isVisible,
              !isPaused,
              !isViewPaused,
              !AppState.shared.appIsInBackground || IS_CATALYST
        else {
#if DEBUG
            recordPageSkipIfNeeded(trigger: trigger, reason: "paused/hidden/background")
#endif
            return
        }

        if !NXFeedViewport.shouldAllowRememberOnOlderFetch(
            continueEnabled: config?.continue == true,
            userHasScrolledTowardOlder: userHasScrolledTowardOlder,
            visiblePostCount: currentNRPostsOnScreen.count
        ) {
#if DEBUG
            recordPageSkipIfNeeded(trigger: trigger, reason: "remember-on until scroll down")
#endif
            return
        }

        // Quiet first-paint append owns the first older batch. Don't start a
        // second transform while the initial posts just appeared.
        if suppressPaginationUntilRememberNewerLoad
            || vmInner.isPreparingForScrollRestore
            || latestQuietOlderAppend
            || olderPageLoadInFlight {
#if DEBUG
            let reason = [
                suppressPaginationUntilRememberNewerLoad ? "remember-newer" : nil,
                vmInner.isPreparingForScrollRestore ? "restore" : nil,
                latestQuietOlderAppend ? "quiet-append" : nil,
                olderPageLoadInFlight ? "in-flight" : nil
            ].compactMap { $0 }.joined(separator: "+")
            recordPageSkipIfNeeded(trigger: trigger, reason: reason)
#endif
            return
        }

        if let paginationRetryNotBefore, Date() < paginationRetryNotBefore {
#if DEBUG
            recordPageSkipIfNeeded(trigger: trigger, reason: "retry-wait")
#endif
            return
        }

        let effectiveUntil = min(until, olderPaginationScanCursor ?? until)

        let now = Date()
        if let previousRequest = lastPaginationRequest,
           previousRequest.until == effectiveUntil,
           now.timeIntervalSince(previousRequest.requestedAt) < 0.4 {
#if DEBUG
            recordPageSkipIfNeeded(trigger: trigger, reason: "debounce")
#endif
            return
        }

        lastPaginationRequest = (effectiveUntil, now)
        didPrefetchOlderPage = true
#if DEBUG
        recordFeedAction(
            "PAGE request · \(trigger) · cursor \(effectiveUntil) · \(feedActionDebugViewport())"
        )
#endif
        onAppearSubject.send(effectiveUntil)
    }

#if DEBUG
    @MainActor
    private func recordPageSkipIfNeeded(trigger: String, reason: String) {
        // Lead/tail appear-skips are constant while scrolling. The false
        // near-tail hypothesis is the 2.5-screen path, so only log that.
        guard trigger == "2.5-screen threshold" else { return }
        recordFeedAction("PAGE skip · \(trigger) · \(reason) · \(feedActionDebugViewport())")
    }
#endif
    
    @MainActor
    public func scrollToFirstUnread() {
        if case .posts(let nrPosts) = viewState {
            for post in (nrPosts).reversed() {
                if let unreadCount = vmInner.unreadIds[post.id], unreadCount > 0 {
                    if let firstUnreadIndex = nrPosts.firstIndex(where: { $0.id == post.id }) {
                        DispatchQueue.main.async {
                            self.vmInner.requestScroll(to: firstUnreadIndex)
                        }
                    }
                }
            }
        }
    }
    
    @MainActor
    public func scrollToTop() {
        DispatchQueue.main.async {
            self.vmInner.requestScroll(to: 0)
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
                L.og.debug("☘️☘️ \(config.name) loadMoreWhenNearBottom.onAppearSubject lastCreatedAt \(lastCreatedAt) -[LOG]-")
#endif
                self?.loadOlderPage(config)
            }
    }
}

enum ColumnViewState {
    case loading
    case posts([NRPost]) // Posts
    case timeout
    case error(String)
}

/// Serializes asynchronous local feed reads without losing completion handlers.
/// If equivalent work is already pending, callers share that read; a notification
/// received while the same read is running queues one follow-up snapshot.
@MainActor
final class NXLocalLoadCoordinator<Request> {
    typealias Work = (Request, @escaping () -> Void) -> Void

    private struct Pending {
        let id = UUID()
        let key: String
        let request: Request
        var completions: [() -> Void]
    }

    private let makeKey: (Request) -> String
    private let perform: Work
    private var pending: [Pending] = []
    private var active: Pending?

    init(key: @escaping (Request) -> String, perform: @escaping Work) {
        self.makeKey = key
        self.perform = perform
    }

    func enqueue(_ request: Request, completion: (() -> Void)? = nil) {
        let key = makeKey(request)
        if let index = pending.firstIndex(where: { $0.key == key }) {
            if let completion {
                pending[index].completions.append(completion)
            }
            return
        }

        pending.append(Pending(
            key: key,
            request: request,
            completions: completion.map { [$0] } ?? []
        ))
        drain()
    }

    /// All work belongs to an invalidated feed generation. The underlying
    /// active read cannot be cancelled once Core Data has accepted it, but it
    /// must not keep the new feed waiting for its coordinator slot.
    func cancelAll() {
        let completions = (active?.completions ?? []) + pending.flatMap(\.completions)
        active = nil
        pending.removeAll()
        completions.forEach { $0() }
    }

    private func drain() {
        guard active == nil, !pending.isEmpty else { return }
        let next = pending.removeFirst()
        active = next
        perform(next.request) { [weak self] in
            guard let self, self.active?.id == next.id else { return }
            self.active = nil
            next.completions.forEach { $0() }
            self.drain()
        }
    }
}

@MainActor
extension NXColumnViewModel: FeedColumnScheduling {
    var columnScheduleId: UUID { columnVMid }
    
    var prefersFirstInRotation: Bool {
        guard let config else { return false }
        return config.id.hasPrefix("Following-") && config.name != "Explore"
    }
    
    var isPausedForScheduling: Bool { isPaused }
    
    func scheduledResume() {
        resume()
    }
    
    func scheduledFetchTick() {
        fetchFeedTimerNextTick()
    }
}

let FETCH_FEED_INTERVAL = 9.0
let FEED_MAX_VISIBLE: Int = 20
let DEFAULT_REQ_LIMIT: Int? = 500

// MARK: Remember-off "latest now" (CloudFeed.continue == false)
//
// Goal: first screen feels like "latest now" (10 iPhone / 6 Mac), bar finishes
// at first paint, fill imports into the DB without dumping 20–40 NRPosts on
// the list, older rows load as the user scrolls.
//
// Phases (NXGapFiller):
//   1. firstPaint — outbox REQ, 8h, limit 20. Hold `.loading` until COUNT posts.
//   2. fill       — 24h, limit 75. Import only; do not putOnScreen a big older batch.
//   3. newer      — under 2 min away: keep the list, prepend like Remember-on.
//
// Resume: away >= RESUME_REFRESH_AFTER (120s) wipes to empty and runs firstPaint.
// Under 2 min calls fetchNewer. lastBackgroundDuration() is needed because
// lastBecameInactiveAt is often reset by a brief .inactive flicker.
//
// Known remaining issues:
// - DEBUG overlay + 50-relay outbox still hitch after first paint (Release on
//   device is much better). Do not assume a hang is "too many NRPosts" until
//   the overlay is off (`feed_fetch_debug_overlay` lives in the *app* container
//   plist, not `defaults write` on the Mac host).
// - Fill still starts late after background (~6s connecting deadline).
// - A locally exhausted tail can still wait up to the bounded PAGE timeout.
//   PAGE requests have per-session IDs so late imports cannot satisfy a newer page.
// - Bottom append is a raw `existing + older` assign. Do not run the prepend
//   pin/settle on that path — it scrollToItem's a stale reading post.
// Remember-on fetchGap is intentionally unchanged.
let LATEST_FEED_FIRST_PAINT_COUNT = 6
let LATEST_FEED_FIRST_PAINT_EVENT_CAP = LATEST_FEED_FIRST_PAINT_COUNT + 2
let LATEST_FEED_FIRST_PAINT_LIMIT = 20
/// Sparse feeds can be force-revealed below the first-paint target and must still load older pages.
/// First older batch after first paint. 20 parent-heavy NRPosts hitch the list for seconds.
let LATEST_FEED_QUIET_OLDER_CAP = 8
/// Remember-off: keep this many posts on screen, then load more as the user scrolls.
let LATEST_FEED_INITIAL_VISIBLE = 12
let LATEST_FEED_FIRST_PAINT_WINDOW: TimeInterval = 8 * 3600
let LATEST_FEED_FILL_WINDOW: TimeInterval = 24 * 3600
/// Remember-off: skip a full latest refetch after a short app switch / tab hide.
let LATEST_FEED_RESUME_REFRESH_AFTER: TimeInterval = 120

func followingReqFilters(_ pubkeys: Set<String>, since: Int? = nil, until: Int? = nil, limit: Int? = nil, kinds: Set<Int>) -> [Filters] {
    guard !pubkeys.isEmpty else { return [] }
    return [Filters(authors: pubkeys, kinds: kinds, since: since, until: until, limit: limit)]
}

func pubkeyOrHashtagReqFilters(_ pubkeys: Set<String>, hashtags: Set<String>, since: Int? = nil, until: Int? = nil, limit: Int? = nil, kinds: Set<Int>) -> [Filters] {
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

func globalFeedReqFilters(kinds: Set<Int>, since: Int? = nil, until: Int? = nil, limit: Int = 250) -> [Filters] {
    return [Filters(kinds: kinds,
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

let FETCH_GLOBAL_KINDS: Set<Int> = [1,1222,6,20,9802,30023,34235,34236] // removed kind 5 because relays send back only 5's?? and alot? hit limit and no other kinds come back

let FETCH_GLOBAL_KINDS_WITH_REPLIES: Set<Int> = [1,1111,1222,1244,6,20,9802,30023,34235,34236] // removed kind 5 because relays send back only 5's?? and alot? hit limit and no other kinds come back

let FETCH_FOLLOWING_FEED_KINDS: Set<Int> = [1,1222,5,6,20,9802,30023,34235,34236,30311]

let FETCH_FOLLOWING_FEED_KINDS_WITH_REPLIES: Set<Int> = [1,1111,1222,1244,5,6,20,9802,30023,34235,34236,30311]

let FETCH_FOLLOWING_PROFILE_KINDS: Set<Int> = [0,10002,10050,10063]

let QUERY_FOLLOWING_KINDS: Set<Int> = [1,1222,6,20,9802,30023,34235,34236]

let QUERY_FOLLOWING_KINDS_WITH_REPLIES: Set<Int> = [1,1111,1222,1244,6,20,9802,30023,34235,34236]

let REPLY_KINDS: Set<Int> = [1111,1244] // substract these is replies toggle is off

let QUERY_FETCH_LIMIT = 50 // Was 25 before, but seems we are missing posts, maybe too much non WoT-hashtag coming back. Increase limit or split query? or could be the time cutoff is too short/strict


import CoreData

// LVM pubkeys
extension Event {
    
    // TODO: Optimize tagsSerialized / hashtags matching
    // GET NEWER
    static func postsByPubkeys(_ pubkeys: Set<String>, lastAppearedCreatedAt: Int64 = 0, hideReplies: Bool = false, hashtagRegex: String? = nil, kinds: Set<Int>) -> NSFetchRequest<Event> {
        let blockedPubkeys = blocks()
        let hoursAgo = Int64(Date.now.timeIntervalSince1970) - 28_800 // 8 hours ago
        
        // Take oldest timestamp: 8 hours ago OR lastAppearedCreatedAt
        // if we don't have lastAppearedCreatedAt. Take 8 hours ago
        let cutOffPoint = lastAppearedCreatedAt == 0 ? hoursAgo : min(lastAppearedCreatedAt, hoursAgo)
        let cutOffNotInFuture: Int64 = min(cutOffPoint, Int64(Date().timeIntervalSince1970) + 10800) // Never show posts too far into the future (fake timestamp)
        let threeHoursFromNow: Int64 = Int64(Date().timeIntervalSince1970) + 10800 // Never show posts too far into the future (fake timestamp)
        
        // get 15 events before lastAppearedCreatedAt (or 8 hours ago, if we dont have it)
        let frBefore = Event.fetchRequest()
        frBefore.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        frBefore.fetchLimit = QUERY_FETCH_LIMIT
        
        
        
        if let hashtagRegex = hashtagRegex {
            var predicate = "created_at <= %i"
            
            if kinds.contains(20) {
                predicate += " AND (kind IN %@ OR (kind = 1 AND kTag = 20))"
            }
            else {
                predicate += " AND kind IN %@"
            }
            
            predicate += " AND NOT pubkey IN %@ AND (pubkey IN %@ OR tagsSerialized MATCHES %@)"
            
            if hideReplies {
                predicate += " AND replyToRootId == nil AND replyToId == nil"
            }
            
            predicate += " AND flags != \"is_update\""
            
            frBefore.predicate = NSPredicate(format: predicate, cutOffNotInFuture, kinds, blockedPubkeys, pubkeys, hashtagRegex)
        }
        else {
            var predicate = "created_at <= %i AND pubkey IN %@"
            if kinds.contains(20) {
                predicate += " AND (kind IN %@ OR (kind = 1 AND kTag = 20))"
            }
            else {
                predicate += " AND kind IN %@"
            }
            
            if hideReplies {
                predicate += " AND replyToRootId == nil AND replyToId == nil"
            }
            
            predicate += " AND flags != \"is_update\" AND NOT pubkey IN %@"
            
            frBefore.predicate = NSPredicate(format: predicate, cutOffNotInFuture, pubkeys, kinds, blockedPubkeys)
        }
        
        let newFirstEvent = try? bg().fetch(frBefore).last
        
        let newCutOffPoint = newFirstEvent != nil ? newFirstEvent!.created_at : cutOffNotInFuture
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        fr.fetchLimit = QUERY_FETCH_LIMIT
        
        var predicate = "created_at >= %i AND created_at < %i AND pubkey IN %@"
        
        if kinds.contains(20) {
            predicate += " AND (kind IN %@ OR (kind = 1 AND kTag = 20))"
        }
        else {
            predicate += " AND kind IN %@"
        }
        
        if hideReplies {
            predicate += " AND replyToRootId == nil AND replyToId == nil"
        }
        
        predicate += " AND flags != \"is_update\" AND NOT pubkey IN %@"
        
        fr.predicate = NSPredicate(format: predicate, newCutOffPoint, threeHoursFromNow, pubkeys, kinds, blockedPubkeys)
        return fr
    }
    
    
    // GET OLDER
    static func postsByPubkeys(_ pubkeys: Set<String>, until cutOffPoint: Int64 = Int64(Date().timeIntervalSince1970), hideReplies: Bool = false, hashtagRegex: String? = nil, kinds: Set<Int>) -> NSFetchRequest<Event> {
        let blockedPubkeys = blocks()
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        fr.fetchLimit = QUERY_FETCH_LIMIT
        
        let cutOffNotInFuture: Int64 = min(cutOffPoint, Int64(Date().timeIntervalSince1970) + 10800) // Never show posts too far into the future (fake timestamp)
        
        if let hashtagRegex = hashtagRegex {
            
            let after = cutOffPoint - 28_800 // we need just 25 posts, so don't scan too far back, the regex match on tagsSerialized seems slow
            
            var predicate = "created_at > %i AND created_at <= %i"
            
            if kinds.contains(20) {
                predicate += " AND (kind IN %@ OR (kind = 1 AND kTag = 20))"
            }
            else {
                predicate += " AND kind IN %@"
            }
            
            predicate += " AND NOT pubkey IN %@ AND (pubkey IN %@ OR tagsSerialized MATCHES %@)"
            
            if hideReplies {
                predicate += " AND replyToRootId == nil AND replyToId == nil"
            }
            
            predicate += " AND flags != \"is_update\""
            
            fr.predicate = NSPredicate(format: predicate, after, cutOffNotInFuture, kinds, blockedPubkeys, pubkeys, hashtagRegex)
        }
        else {
            
            var predicate = "created_at <= %i AND pubkey IN %@"
            
            if kinds.contains(20) {
                predicate += " AND (kind IN %@ OR (kind = 1 AND kTag = 20))"
            }
            else {
                predicate += " AND kind IN %@"
            }
            
            if hideReplies {
                predicate += " AND replyToRootId == nil AND replyToId == nil"
            }
            
            predicate += " AND flags != \"is_update\" AND NOT pubkey IN %@"
            
            fr.predicate = NSPredicate(format: predicate, cutOffNotInFuture, pubkeys, kinds, blockedPubkeys)
        }
        return fr
    }
}

// Broad local media fetches used by WoT feeds. Fetching by kind first avoids
// putting a potentially very large WoT pubkey set into a Core Data predicate.
extension Event {
    /// Core Data/SQLite cannot reliably execute one `IN` predicate containing a
    /// full WoT (often tens of thousands of authors). Query bounded author sets
    /// through the pubkey index and merge the newest unique events.
    static func fetchMediaPosts(
        by pubkeys: Set<String>,
        lastAppearedCreatedAt: Int64 = 0,
        hideReplies: Bool = false,
        kinds: Set<Int>,
        context: NSManagedObjectContext
    ) -> [Event] {
        fetchMediaPostsInBatches(pubkeys: pubkeys, context: context) { batch in
            mediaPosts(
                by: batch,
                lastAppearedCreatedAt: lastAppearedCreatedAt,
                hideReplies: hideReplies,
                kinds: kinds
            )
        }
    }

    static func fetchMediaPosts(
        by pubkeys: Set<String>,
        until cutOffPoint: Int64,
        hideReplies: Bool = false,
        kinds: Set<Int>,
        context: NSManagedObjectContext
    ) -> [Event] {
        fetchMediaPostsInBatches(pubkeys: pubkeys, context: context) { batch in
            mediaPosts(
                by: batch,
                until: cutOffPoint,
                hideReplies: hideReplies,
                kinds: kinds
            )
        }
    }

    private static func fetchMediaPostsInBatches(
        pubkeys: Set<String>,
        context: NSManagedObjectContext,
        request: (Set<String>) -> NSFetchRequest<Event>
    ) -> [Event] {
        guard !pubkeys.isEmpty else { return [] }

        let authors = Array(pubkeys)
        var eventsById: [String: Event] = [:]
        let batchSize = 500

        for start in stride(from: 0, to: authors.count, by: batchSize) {
            let end = min(start + batchSize, authors.count)
            let batch = Set(authors[start..<end])
            do {
                for event in try context.fetch(request(batch)) {
                    eventsById[event.id] = event
                }
            }
            catch {
                L.og.error("Media feed local batch fetch failed: \(error.localizedDescription)")
            }
        }

        return Array(eventsById.values)
            .sorted { $0.created_at > $1.created_at }
            .prefix(100)
            .map { $0 }
    }

    static func mediaPosts(
        by pubkeys: Set<String>,
        lastAppearedCreatedAt: Int64 = 0,
        hideReplies: Bool = false,
        kinds: Set<Int>
    ) -> NSFetchRequest<Event> {
        let blockedPubkeys = blocks()
        let eightHoursAgo = Int64(Date.now.timeIntervalSince1970) - 28_800
        let lowerBound = lastAppearedCreatedAt == 0 ? eightHoursAgo : min(lastAppearedCreatedAt, eightHoursAgo)
        let upperBound = Int64(Date.now.timeIntervalSince1970) + 10_800

        let request = Event.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        request.fetchLimit = 100

        var predicate = "created_at >= %i AND created_at < %i AND pubkey IN %@"
        predicate += kinds.contains(20)
            ? " AND (kind IN %@ OR (kind = 1 AND kTag = 20))"
            : " AND kind IN %@"
        if hideReplies {
            predicate += " AND replyToRootId == nil AND replyToId == nil"
        }
        predicate += " AND flags != \"is_update\" AND NOT pubkey IN %@"
        request.predicate = NSPredicate(format: predicate, lowerBound, upperBound, pubkeys, kinds, blockedPubkeys)
        return request
    }

    static func mediaPosts(
        by pubkeys: Set<String>,
        until cutOffPoint: Int64,
        hideReplies: Bool = false,
        kinds: Set<Int>
    ) -> NSFetchRequest<Event> {
        let blockedPubkeys = blocks()
        let cutOffNotInFuture = min(cutOffPoint, Int64(Date.now.timeIntervalSince1970) + 10_800)

        let request = Event.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        request.fetchLimit = 100

        var predicate = "created_at <= %i AND pubkey IN %@"
        predicate += kinds.contains(20)
            ? " AND (kind IN %@ OR (kind = 1 AND kTag = 20))"
            : " AND kind IN %@"
        if hideReplies {
            predicate += " AND replyToRootId == nil AND replyToId == nil"
        }
        predicate += " AND flags != \"is_update\" AND NOT pubkey IN %@"
        request.predicate = NSPredicate(format: predicate, cutOffNotInFuture, pubkeys, kinds, blockedPubkeys)
        return request
    }
}

// LVM relays
extension Event {
    private static func relayTokenRegex(_ relays: Set<RelayData>) -> String {
        let escapedRelayUrls = relays.compactMap { relay in
            let url = relay.url
            return url.isEmpty ? nil : NSRegularExpression.escapedPattern(for: url)
        }

        guard !escapedRelayUrls.isEmpty else { return "$^" }

        // relays is a space-separated field, match selected relay URLs as whole tokens.
        return ".*(^|\\s)(" + escapedRelayUrls.joined(separator: "|") + ")(\\s|$).*"
    }

    static func postsByRelays(_ relays: Set<RelayData>, lastAppearedCreatedAt: Int64 = 0, hideReplies: Bool = false, fetchLimit: Int = 50, force: Bool = false, kinds: Set<Int>) -> NSFetchRequest<Event> {
        let blockedPubkeys = blocks()
        let regex = relayTokenRegex(relays)
        let kindClause = kinds.contains(20) ? "(kind IN %@ OR (kind = 1 AND kTag = 20))" : "kind IN %@"
        let hoursAgo = Int64(Date.now.timeIntervalSince1970) - 28_800 // 8 hours ago
        
        // Take oldest timestamp: 8 hours ago OR lastAppearedCreatedAt
        // if we don't have lastAppearedCreatedAt. Take 8 hours ago
        let cutOffPoint = lastAppearedCreatedAt == 0 ? hoursAgo : min(lastAppearedCreatedAt, hoursAgo)
        let cutOffNotInFuture: Int64 = min(cutOffPoint, Int64(Date().timeIntervalSince1970) + 10800) // Never show posts too far into the future (fake timestamp)
        
        // get 50 events before lastAppearedCreatedAt (or 8 hours ago, if we dont have it)
        let frBefore = Event.fetchRequest()
        frBefore.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        
        // Increased fetchLimit for Relays feed so there are enough events after applying inWoT filter
        frBefore.fetchLimit = fetchLimit // TODO: Should apply WoT on message parser / receive, before adding to adding to database
        
        if hideReplies {
            frBefore.predicate = NSPredicate(format: "created_at <= %i AND \(kindClause) AND NOT pubkey IN %@ AND relays MATCHES %@ AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\"", cutOffNotInFuture, kinds, blockedPubkeys, regex)
        }
        else {
            frBefore.predicate = NSPredicate(format: "created_at <= %i AND \(kindClause) AND NOT pubkey IN %@ AND relays MATCHES %@ AND flags != \"is_update\"", cutOffNotInFuture, kinds, blockedPubkeys, regex)
        }
        
        let newFirstEvent = try? bg().fetch(frBefore).last
        
        let newCutOffPoint = newFirstEvent != nil ? newFirstEvent!.created_at : cutOffNotInFuture
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        
        // Increased fetchLimit for Relays feed so there are enough events after applying inWoT filter
        fr.fetchLimit = fetchLimit // TODO: Should apply WoT on message parser / receive, before adding to adding to database
        
        let threeHoursFromNow: Int64 = Int64(Date().timeIntervalSince1970) + 10800 // Never show posts too far into the future (fake timestamp)
        
        if hideReplies {
            fr.predicate = !force
                ? NSPredicate(format: "created_at >= %i AND created_at < %i AND \(kindClause) AND relays MATCHES %@ AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\"", newCutOffPoint, threeHoursFromNow, kinds, regex)
                : NSPredicate(format: "\(kindClause) AND relays MATCHES %@ AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\"", kinds, regex)
        }
        else {
            fr.predicate = !force
                ? NSPredicate(format: "created_at >= %i AND created_at < %i AND \(kindClause) AND relays MATCHES %@ AND flags != \"is_update\"", newCutOffPoint, threeHoursFromNow, kinds, regex)
                : NSPredicate(format: "\(kindClause) AND relays MATCHES %@ AND flags != \"is_update\"", kinds, regex)
        }
        return fr
    }
    
    
    static func postsByRelays(_ relays: Set<RelayData>, until cutOffPoint: Int64 = Int64(Date().timeIntervalSince1970), hideReplies: Bool = false, fetchLimit: Int = 50, kinds: Set<Int>) -> NSFetchRequest<Event> {
        let blockedPubkeys = blocks()
        let regex = relayTokenRegex(relays)
        let kindClause = kinds.contains(20) ? "(kind IN %@ OR (kind = 1 AND kTag = 20))" : "kind IN %@"
        
        let cutOffNotInFuture: Int64 = min(cutOffPoint, Int64(Date().timeIntervalSince1970) + 10800) // Never show posts too far into the future (fake timestamp)
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]

        // Increased fetchLimit for Relays feed so there are enough events after applying inWoT filter
        fr.fetchLimit = fetchLimit // TODO: Should apply WoT on message parser / receive, before adding to adding to database
        
        if hideReplies {
            fr.predicate = NSPredicate(format: "created_at <= %i AND \(kindClause) AND relays MATCHES %@ AND replyToRootId == nil AND replyToId == nil AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffNotInFuture, kinds, regex, blockedPubkeys)
        }
        else {
            fr.predicate = NSPredicate(format: "created_at <= %i AND \(kindClause) AND relays MATCHES %@ AND flags != \"is_update\" AND NOT pubkey IN %@", cutOffNotInFuture, kinds, regex, blockedPubkeys)
        }
        return fr
    }
}

func notMutedWords(in text: String, mutedWords: [String]) -> Bool {
    guard !mutedWords.isEmpty else { return true }
    guard !text.isEmpty else { return true }
    let textLower = text.lowercased()
    return mutedWords.first(where: { textLower.contains($0) }) == nil
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
