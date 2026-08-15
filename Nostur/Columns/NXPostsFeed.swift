//
//  NXPostsFeed.swift
//  Nosturix
//
//  Created by Fabian Lachman on 01/08/2024.
//

import SwiftUI
import QuartzCore
@_spi(Advanced) import SwiftUIIntrospect
import Combine

private struct NXFeedLayoutStabilizerKey: EnvironmentKey {
    static let defaultValue: NXFeedLayoutStabilizer? = nil
}

extension EnvironmentValues {
    var feedLayoutStabilizer: NXFeedLayoutStabilizer? {
        get { self[NXFeedLayoutStabilizerKey.self] }
        set { self[NXFeedLayoutStabilizerKey.self] = newValue }
    }
}

/// Applies asynchronous row-height changes without moving the post the user is reading.
/// Updates are deferred during drag/deceleration, then the first visible row is restored to
/// the same viewport position after self-sizing layout completes.
@MainActor
final class NXFeedLayoutStabilizer: ObservableObject {
    private weak var scrollView: UIScrollView?
    private var itemIDs: [String] = []
    private var pendingUpdates: [() -> Void] = []
    private var pendingPinByIdentity = false
    private var flushTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var isProgrammaticScrollInProgress = false
    private var isSuspended = false
    private var lastKnownAnchor: (id: String, visibleTopOffset: CGFloat)?
    private var suspendedAnchor: (id: String, visibleTopOffset: CGFloat)?
    private var pendingRestoreAnchor: (id: String, visibleTopOffset: CGFloat)?
    private var anchorGeneration = 0
    private var lastContentOffsetY: CGFloat = 0
    private var lastInsetTop: CGFloat = 0
    private var lastUserScrollAt: CFTimeInterval = 0
    private var scrollObservations: [NSKeyValueObservation] = []

    var isProgrammaticScrollPending: Bool {
        isProgrammaticScrollInProgress
    }

    func attach(to scrollView: UIScrollView) {
        let replaced = self.scrollView !== scrollView
        self.scrollView = scrollView
        if replaced {
            observeScrollGeometry(of: scrollView)
        }
        guard replaced, !isSuspended, let anchor = pendingRestoreAnchor else { return }
        pendingRestoreAnchor = nil
        startSettling(anchor: anchor, pinByIdentity: true)
    }

    func updateItemIDs(_ itemIDs: [String]) {
        self.itemIDs = itemIDs
    }

    func rememberAnchor(id: String, visibleTopOffset: CGFloat = 0) {
        lastKnownAnchor = (id, visibleTopOffset)
        if let scrollView {
            lastContentOffsetY = scrollView.contentOffset.y
            lastInsetTop = scrollView.adjustedContentInset.top
        }
    }

    func visiblePostID() -> String? {
        guard let scrollView, scrollView.window != nil else { return lastKnownAnchor?.id }
        return visibleAnchor(in: scrollView)?.id ?? lastKnownAnchor?.id
    }

    /// Preserve reading position across tab/detail navigation. Row content can finish resolving
    /// while its List is hidden, when UIKit's visible-cell anchoring is not reliable.
    func suspendPositionTracking() {
        if let scrollView {
            suspendedAnchor = visibleAnchor(in: scrollView) ?? lastKnownAnchor ?? suspendedAnchor
        } else {
            suspendedAnchor = lastKnownAnchor ?? suspendedAnchor
        }
        isSuspended = true
        cancelPendingWork()

        let updates = pendingUpdates
        pendingUpdates.removeAll()
        pendingPinByIdentity = false
        updates.forEach { $0() }
    }

    func resumePositionTracking() {
        isSuspended = false
        guard let anchor = suspendedAnchor else { return }
        suspendedAnchor = nil
        lastKnownAnchor = anchor
        startSettling(anchor: anchor, pinByIdentity: true)
    }

    func beginProgrammaticScroll() {
        isProgrammaticScrollInProgress = true
        settleTask?.cancel()
        settleTask = nil
        anchorGeneration += 1
    }

    func cancelProgrammaticScroll() {
        isProgrammaticScrollInProgress = false
        scheduleFlush()
    }

    func finishProgrammaticScroll(finalPosition: () -> Void) async {
        flushTask?.cancel()
        flushTask = nil

        guard let scrollView else {
            let updates = pendingUpdates
            pendingUpdates.removeAll()
            pendingPinByIdentity = false
            updates.forEach { $0() }
            finalPosition()
            isProgrammaticScrollInProgress = false
            return
        }

        let updates = pendingUpdates
        pendingUpdates.removeAll()
        pendingPinByIdentity = false

        // Keep programmatic-scroll blocking until after the final pin so a row-height
        // change applied here cannot start a competing settle (visible as a jump).

        // Most unread jumps do not have a pending row-height change. In that common case a
        // snapshot only causes a visible one-frame flash, so settle the final position directly.
        guard !updates.isEmpty else {
            scrollView.layoutIfNeeded()
            finalPosition()
            scrollView.layoutIfNeeded()
            isProgrammaticScrollInProgress = false
            return
        }

        // SwiftUI reconciles the resolved repost and UIKit corrects the self-sized row on
        // separate layout passes. Cover those passes with the already-rendered viewport so the
        // user never sees the temporary wrong offset between resize and final positioning.
        let snapshot = scrollView.snapshotView(afterScreenUpdates: false)
        if let snapshot, let superview = scrollView.superview {
            snapshot.frame = scrollView.frame
            snapshot.isUserInteractionEnabled = false
            superview.addSubview(snapshot)
        }

        updates.forEach { $0() }

        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)
        scrollView.layoutIfNeeded()
        finalPosition()
        scrollView.layoutIfNeeded()

        snapshot?.removeFromSuperview()
        isProgrammaticScrollInProgress = false
    }

    /// Pins `id` to the visible top. No-ops when it is already there so an unread
    /// animation that landed correctly is not followed by a second scrollToItem jump.
    func pinItemToVisibleTop(id: String) {
        guard let scrollView, scrollView.window != nil else {
            rememberAnchor(id: id, visibleTopOffset: 0)
            return
        }
        rememberAnchor(id: id, visibleTopOffset: 0)

        guard let itemIndex = itemIDs.firstIndex(of: id),
              let indexPath = NXFeedIndexMapping.indexPath(
                forItemIndex: itemIndex,
                sectionCounts: sectionCounts(in: scrollView),
                itemCount: itemIDs.count
              ) else {
            restore(anchor: (id, 0), in: scrollView, bringOnScreen: true)
            return
        }

        guard let minY = itemMinY(at: indexPath, in: scrollView) else {
            restore(anchor: (id, 0), in: scrollView, bringOnScreen: true)
            return
        }

        let visibleTopOffset = NXFeedViewport.offsetFromVisibleTop(
            itemMinY: minY,
            contentOffsetY: scrollView.contentOffset.y,
            insetTop: scrollView.adjustedContentInset.top
        )
        guard abs(visibleTopOffset) > 1.5 else { return }

        let visibleMinY = scrollView.contentOffset.y
        let visibleMaxY = visibleMinY + scrollView.bounds.height
        let isOnScreen = minY < visibleMaxY && minY + 1 > visibleMinY
        restore(anchor: (id, 0), in: scrollView, bringOnScreen: !isOnScreen)
    }

    func performAnchored(pinByIdentity: Bool = false, _ update: @escaping () -> Void) {
        if isSuspended {
            update()
            return
        }

        guard let scrollView, scrollView.window != nil else {
            pendingRestoreAnchor = lastKnownAnchor ?? pendingRestoreAnchor
            update()
            return
        }

        if isProgrammaticScrollInProgress
            || scrollView.isDragging
            || scrollView.isDecelerating
            || scrollView.isTracking {
            pendingUpdates.append(update)
            pendingPinByIdentity = pendingPinByIdentity || pinByIdentity
            scheduleFlush()
        } else {
            applyAnchored([update], pinByIdentity: pinByIdentity)
        }
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.isProgrammaticScrollInProgress
                    || self.scrollView?.isDragging == true
                    || self.scrollView?.isDecelerating == true
                    || self.scrollView?.isTracking == true {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled else { return }
            }
            let updates = self.pendingUpdates
            let pinByIdentity = self.pendingPinByIdentity
            self.pendingUpdates.removeAll()
            self.pendingPinByIdentity = false
            self.flushTask = nil
            self.applyAnchored(updates, pinByIdentity: pinByIdentity)
        }
    }

    private func applyAnchored(_ updates: [() -> Void], pinByIdentity: Bool) {
        guard !updates.isEmpty else { return }

        let oldIDs = itemIDs
        let capturedAnchor = (scrollView.flatMap { visibleAnchor(in: $0) })
            ?? lastKnownAnchor
            ?? pendingRestoreAnchor

        updates.forEach { $0() }

        let insertedAbove = capturedAnchor.map {
            NXFeedIndexMapping.itemsInsertedAbove(oldIDs: oldIDs, newIDs: itemIDs, anchorID: $0.id)
        } ?? false
        let shouldPinByIdentity = pinByIdentity || insertedAbove

        guard let anchor = capturedAnchor else { return }
        lastKnownAnchor = anchor

        guard let scrollView, scrollView.window != nil else {
            pendingRestoreAnchor = anchor
            return
        }

        startSettling(anchor: anchor, pinByIdentity: shouldPinByIdentity)
    }

    private func startSettling(anchor: (id: String, visibleTopOffset: CGFloat), pinByIdentity: Bool) {
        anchorGeneration += 1
        let generation = anchorGeneration
        settleTask?.cancel()
        pendingRestoreAnchor = anchor
        lastKnownAnchor = anchor

        // Prepends need a few frames for estimated rows to self-size. Ordinary
        // image/repost height changes only need one or two offset corrections.
        // Never run this loop during a user drag: it would fight the scroller.
        let maxSteps = pinByIdentity ? 8 : 2

        settleTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var didBringOnScreen = false
            var stableSamples = 0

            for step in 0..<maxSteps {
                guard !Task.isCancelled,
                      !self.isSuspended,
                      self.anchorGeneration == generation else { return }

                if self.scrollView?.isDragging == true
                    || self.scrollView?.isDecelerating == true
                    || self.scrollView?.isTracking == true {
                    self.lastUserScrollAt = CACurrentMediaTime()
                    self.pendingRestoreAnchor = nil
                    return
                }

                if self.scrollView == nil || self.scrollView?.window == nil {
                    self.pendingRestoreAnchor = anchor
                    return
                }

                if step == 0 {
                    await Task.yield()
                } else {
                    try? await Task.sleep(nanoseconds: 16_000_000)
                }
                guard !Task.isCancelled,
                      !self.isSuspended,
                      self.anchorGeneration == generation,
                      let scrollView = self.scrollView,
                      scrollView.window != nil,
                      !scrollView.isDragging,
                      !scrollView.isDecelerating,
                      !scrollView.isTracking else {
                    self.pendingRestoreAnchor = nil
                    return
                }

                let bringOnScreen = pinByIdentity && !didBringOnScreen
                let didCorrect = self.restore(
                    anchor: anchor,
                    in: scrollView,
                    bringOnScreen: bringOnScreen
                )
                if bringOnScreen {
                    didBringOnScreen = true
                }

                if didCorrect {
                    stableSamples = 0
                } else {
                    stableSamples += 1
                    if stableSamples >= 2 {
                        self.pendingRestoreAnchor = nil
                        return
                    }
                }
            }

            if self.anchorGeneration == generation {
                self.pendingRestoreAnchor = nil
            }
        }
    }

    @discardableResult
    private func restore(
        anchor: (id: String, visibleTopOffset: CGFloat),
        in scrollView: UIScrollView,
        bringOnScreen: Bool = false
    ) -> Bool {
        guard let itemIndex = itemIDs.firstIndex(of: anchor.id) else { return false }
        let sectionCounts = sectionCounts(in: scrollView)
        guard let indexPath = NXFeedIndexMapping.indexPath(
            forItemIndex: itemIndex,
            sectionCounts: sectionCounts,
            itemCount: itemIDs.count
        ) else { return false }

        if bringOnScreen {
            scrollToItem(at: indexPath, in: scrollView)
        }

        guard let newMinY = itemMinY(at: indexPath, in: scrollView) else { return bringOnScreen }
        let currentVisibleTopOffset = NXFeedViewport.offsetFromVisibleTop(
            itemMinY: newMinY,
            contentOffsetY: scrollView.contentOffset.y,
            insetTop: scrollView.adjustedContentInset.top
        )
        let correction = currentVisibleTopOffset - anchor.visibleTopOffset
        guard abs(correction) > 0.5 else { return bringOnScreen }

        var offset = scrollView.contentOffset
        offset.y += correction
        let minOffsetY = -scrollView.adjustedContentInset.top
        let maxOffsetY = max(
            minOffsetY,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        )
        offset.y = min(max(offset.y, minOffsetY), maxOffsetY)
        scrollView.setContentOffset(offset, animated: false)
        lastContentOffsetY = scrollView.contentOffset.y
        lastInsetTop = scrollView.adjustedContentInset.top
        return true
    }

    private func visibleAnchor(in scrollView: UIScrollView) -> (id: String, visibleTopOffset: CGFloat)? {
        let indexPaths: [IndexPath]
        if let collectionView = scrollView as? UICollectionView {
            indexPaths = collectionView.indexPathsForVisibleItems
        } else if let tableView = scrollView as? UITableView {
            indexPaths = tableView.indexPathsForVisibleRows ?? []
        } else {
            return nil
        }

        let top = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        let candidates = indexPaths.compactMap { indexPath -> (IndexPath, CGFloat)? in
            guard let minY = itemMinY(at: indexPath, in: scrollView) else { return nil }
            return (indexPath, minY)
        }
        let anchor = candidates
            .filter { $0.1 >= top - 0.5 }
            .min { $0.1 < $1.1 }
            ?? candidates.min { abs($0.1 - top) < abs($1.1 - top) }
        guard let anchor else { return nil }

        let sectionCounts = sectionCounts(in: scrollView)
        guard let itemIndex = NXFeedIndexMapping.itemIndex(
            for: anchor.0,
            sectionCounts: sectionCounts,
            itemCount: itemIDs.count
        ),
              let id = itemIDs[safe: itemIndex] else { return nil }
        let visibleTopOffset = NXFeedViewport.offsetFromVisibleTop(
            itemMinY: anchor.1,
            contentOffsetY: scrollView.contentOffset.y,
            insetTop: scrollView.adjustedContentInset.top
        )
        let resolved = (id, visibleTopOffset)
        lastKnownAnchor = resolved
        lastContentOffsetY = scrollView.contentOffset.y
        lastInsetTop = scrollView.adjustedContentInset.top
        return resolved
    }

    private func itemMinY(at indexPath: IndexPath, in scrollView: UIScrollView) -> CGFloat? {
        if let collectionView = scrollView as? UICollectionView {
            return collectionView.layoutAttributesForItem(at: indexPath)?.frame.minY
        }
        if let tableView = scrollView as? UITableView,
           tableView.numberOfSections > indexPath.section,
           tableView.numberOfRows(inSection: indexPath.section) > indexPath.row {
            return tableView.rectForRow(at: indexPath).minY
        }
        return nil
    }

    private func sectionCounts(in scrollView: UIScrollView) -> [Int] {
        if let collectionView = scrollView as? UICollectionView {
            return (0..<collectionView.numberOfSections).map { collectionView.numberOfItems(inSection: $0) }
        }
        if let tableView = scrollView as? UITableView {
            return (0..<tableView.numberOfSections).map { tableView.numberOfRows(inSection: $0) }
        }
        return []
    }

    private func scrollToItem(at indexPath: IndexPath, in scrollView: UIScrollView) {
        if let collectionView = scrollView as? UICollectionView,
           collectionView.numberOfSections > indexPath.section,
           collectionView.numberOfItems(inSection: indexPath.section) > indexPath.item {
            collectionView.scrollToItem(at: indexPath, at: .top, animated: false)
        } else if let tableView = scrollView as? UITableView,
                  tableView.numberOfSections > indexPath.section,
                  tableView.numberOfRows(inSection: indexPath.section) > indexPath.row {
            tableView.scrollToRow(at: indexPath, at: .top, animated: false)
        }
    }

    private func cancelPendingWork() {
        anchorGeneration += 1
        flushTask?.cancel()
        flushTask = nil
        settleTask?.cancel()
        settleTask = nil
    }

    private func observeScrollGeometry(of scrollView: UIScrollView) {
        scrollObservations.removeAll()
        lastContentOffsetY = scrollView.contentOffset.y
        lastInsetTop = scrollView.adjustedContentInset.top

        scrollObservations.append(scrollView.observe(\.adjustedContentInset, options: [.old, .new]) { [weak self] scrollView, _ in
            MainActor.assumeIsolated {
                self?.handleAdjustedContentInsetChange(in: scrollView)
            }
        })
    }

    private func handleAdjustedContentInsetChange(in scrollView: UIScrollView) {
        let newInsetTop = scrollView.adjustedContentInset.top
        let oldInsetTop = lastInsetTop
        guard abs(newInsetTop - oldInsetTop) > 0.5 else {
            lastInsetTop = newInsetTop
            return
        }

        let isUserScrolling = scrollView.isDragging
            || scrollView.isDecelerating
            || scrollView.isTracking
        if isUserScrolling {
            lastUserScrollAt = CACurrentMediaTime()
        }

        // Live banner / safe-area inset changes should not move the post under the visible top.
        // Skip during a finger drag and for a short time after, so tab-bar minimize
        // inset animation cannot fight the scroller.
        if isSuspended || isUserScrolling || CACurrentMediaTime() - lastUserScrollAt < 0.4 {
            lastInsetTop = newInsetTop
            lastContentOffsetY = scrollView.contentOffset.y
            return
        }

        let currentOffset = scrollView.contentOffset.y
        let desired = NXFeedViewport.contentOffset(
            preservingVisibleContent: lastContentOffsetY,
            oldInsetTop: oldInsetTop,
            newInsetTop: newInsetTop
        )
        let uikitAlreadyPreserved = abs(currentOffset - desired) <= 0.5
        let offsetStillAtLastKnown = abs(currentOffset - lastContentOffsetY) <= 0.5

        lastInsetTop = newInsetTop

        // If the user has scrolled since we last recorded an offset, do not jump back.
        // Compensate only when the offset is still the one we know, or UIKit already
        // applied the exact preservation we want.
        guard offsetStillAtLastKnown || uikitAlreadyPreserved else {
            lastContentOffsetY = currentOffset
            return
        }
        guard !uikitAlreadyPreserved else {
            lastContentOffsetY = currentOffset
            return
        }

        var offset = scrollView.contentOffset
        offset.y = desired
        let minOffsetY = -newInsetTop
        let maxOffsetY = max(
            minOffsetY,
            scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        )
        offset.y = min(max(offset.y, minOffsetY), maxOffsetY)

        scrollView.setContentOffset(offset, animated: false)
        lastContentOffsetY = scrollView.contentOffset.y
    }
}

struct NXPostsFeed: View {
    
    @Environment(\.theme) private var theme
    @Environment(\.availableWidth) private var availableWidth
    @Environment(\.availableHeight) private var availableHeight
    
    private var vm: NXColumnViewModel
    private let posts: [NRPost]
    private let vmInner: NXColumnViewModelInner

    @State private var updateIsAtTopSubscription: AnyCancellable?
    @StateObject private var layoutStabilizer = NXFeedLayoutStabilizer()
    
    init(vm: NXColumnViewModel, posts: [NRPost]) {
        self.vm = vm
        self.posts = posts
        self.vmInner = vm.vmInner
    }

    private var relayFeedRelays: Set<RelayData> {
        guard let config = vm.config else { return [] }

        switch config.columnType {
        case .relays(let feed):
            return feed.relaysData
        case .relayPreview(let relayData):
            return [relayData]
        default:
            return []
        }
    }

    private var feedImageTargetSize: CGSize {
        feedImageRequestTargetSize(
            for: availableWidth,
            availableHeight: availableHeight
        )
    }
    
    var body: some View {
        // Keep List as the top-level scroll container (no GeometryReader parent) so iOS 26
        // tabBarMinimizeBehavior(.onScrollDown) can observe it as the primary scroller.
        List {
            ForEach(posts) { nrPost in
                NXListRow(nrPost: nrPost, vm: vm) {
                    PostOrThread(nrPost: nrPost, theme: theme)
                        .environment(\.availableHeight, availableHeight)
                        .environment(\.availableWidth, availableWidth)
                        .environment(
                            \.feedImageRequestTargetSize,
                            feedImageTargetSize
                        )
                        .environment(\.relayFeedRelays, relayFeedRelays)
                        .environment(\.feedLayoutStabilizer, layoutStabilizer)
                }
                .onDisappear {
                    onPostDisappear(nrPost)
                }
                .listRowSeparator(.hidden)
                .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
            }

            if let oldestPost = posts.last {
                Color.clear
                    .frame(height: 1)
                    .id("pagination-\(oldestPost.id)")
                    .onAppear {
                        vm.requestNextPageIfNeeded(until: oldestPost.created_at)
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(.init())
            }
        }
        .withContainerTopOffsetEnvironmentKey()
        .scrollOffsetID(vm.columnVMid)
        .environment(\.defaultMinListRowHeight, 50)
        .listStyle(.plain)
        .introspect(.list, on: .iOS(.v15)) { [weak vm] view in
            guard let vm else { return }
            vm.tableView = view
            layoutStabilizer.attach(to: view)
            restorePreparedScrollPositionIfNeeded(in: view)
            DispatchQueue.main.async {
                if vm.tablePrefetcher == nil {
                    vm.tablePrefetcher = NXPostsFeedTablePrefetcher()
                    vm.tablePrefetcher?.columnViewModel = vm
                    view.isPrefetchingEnabled = true
                    view.prefetchDataSource = vm.tablePrefetcher
                }
                vm.tablePrefetcher?.imageRequestTargetSize =
                    feedImageTargetSize
            }
        }
        .introspect(.list, on: .iOS(.v16...)) { [weak vm] view in
            guard let vm else { return }
            vm.collectionView = view
            layoutStabilizer.attach(to: view)
            restorePreparedScrollPositionIfNeeded(in: view)
            DispatchQueue.main.async {
                if vm.collectionPrefetcher == nil {
                    vm.collectionPrefetcher = NXPostsFeedPrefetcher()
                    vm.collectionPrefetcher?.columnViewModel = vm
                    view.isPrefetchingEnabled = true
                    view.prefetchDataSource = vm.collectionPrefetcher
                }
                vm.collectionPrefetcher?.imageRequestTargetSize =
                    feedImageTargetSize
            }
        }
        .scrollContentBackgroundHidden()
        .background(theme.listBackground)
        .onAppear {
            vmInner.performAnchoredFeedUpdate = { [weak layoutStabilizer] itemIDs, update in
                guard let layoutStabilizer else {
                    update()
                    return
                }
                // Do not force pinByIdentity here. Cross-column unread removals would
                // scrollToItem every other Mac column. Prepends still pin via itemsInsertedAbove.
                layoutStabilizer.performAnchored {
                    update()
                    // Make the post-ID lookup deterministic for the correction pass rather than
                    // depending on SwiftUI's onChange delivery order after the List mutation.
                    layoutStabilizer.updateItemIDs(itemIDs)
                }
            }
            layoutStabilizer.updateItemIDs(posts.map(\.id))
            if let readingID = vmInner.readingPostID ?? vmInner.pendingScrollToPostID {
                layoutStabilizer.rememberAnchor(id: readingID)
            }
            layoutStabilizer.resumePositionTracking()
        }
        .onChange(of: posts.map(\.id)) { itemIDs in
            // The stabilizer must resolve anchors by post identity after insertions/removals.
            // Index paths are not stable when unread posts are inserted above the viewport.
            layoutStabilizer.updateItemIDs(itemIDs)
        }
        .onChange(of: feedImageTargetSize) { newTargetSize in
            updatePrefetchImageTargetSize(newTargetSize)
        }
        .onReceive(vmInner.scrollToIndexSubject.compactMap { $0 }) { scrollToIndex in
            guard !vmInner.isPerformingScroll,
                  !vmInner.isPerformingScrollToFirstUnread else {
                vmInner.clearScrollRequest()
                return
            }
            
#if DEBUG
            L.og.debug("☘️☘️ \(vm.config?.name ?? "?") NXPostsFeed .isAtTop \(vmInner.isAtTop) scroll request \(scrollToIndex.description) -[LOG]-")
#endif
            
            performScrollToIndex(scrollToIndex)
        }
        .overlay(alignment: .topTrailing) {
            unreadCounterView
        }
        .onReceive(receiveNotification(.shouldScrollToFirstUnread)) { _ in
            guard vm.isVisible else { return }
            scrollToFirstUnread()
        }
        .onReceive(receiveNotification(.shouldScrollToTop)) { _ in
            guard vm.isVisible else { return }
            
            scrollToTop()
        }
        
        // Handle going to detail and back
        .onAppear {
            vm.resumeViewUpdates()
            updatePrefetchImageTargetSize(feedImageTargetSize)
            
            // Add updateIsAtTop() debounces - increase debounce time for better performance
            guard updateIsAtTopSubscription == nil else { return }
            updateIsAtTopSubscription = vmInner.updateIsAtTopSubject
                .debounce(for: 0.15, scheduler: RunLoop.main) // Increased from 0.075 for smoother scrolling
                .sink {
                    self._updateIsAtTop()
                }
        }
        .onDisappear {
            // When opening detail, the feed would still update in background using withAnimation { },
            // but because its not visible the hack to keep scroll position doesn't work
            // so we pause() updates (and resume() in onAppear {})
            layoutStabilizer.suspendPositionTracking()
            vm.pauseViewUpdates()
            vmInner.performAnchoredFeedUpdate = nil
        }
    }

    private func updatePrefetchImageTargetSize(_ targetSize: CGSize) {
        vm.tablePrefetcher?.imageRequestTargetSize = targetSize
        vm.collectionPrefetcher?.imageRequestTargetSize = targetSize
    }
    
    @ViewBuilder
    public var unreadCounterView: some View {
        NXUnreadCounterView(
            unreadState: vm.vmInner.unreadState,
            onTap: scrollToFirstUnread,
            onLongPress: scrollToTop
        )
            .padding(.trailing, 10)
            .padding(.top, 5)
    }
    
    private func scrollToFirstUnread() {
        guard !vmInner.isPerformingScrollToFirstUnread else { return }
        if vmInner.unreadCount == 0 {
            scrollToTop()
            return
        }

        // Walk upward from the post on screen, not from the bottom of the list.
        // After restore, a false appear on a newer row can mark a block as read;
        // the nearest unread above the reading position is still the next tap.
        let startIndex: Int = {
            if let readingID = vmInner.readingPostID ?? vmInner.pendingScrollToPostID,
               let index = posts.firstIndex(where: { $0.id == readingID }) {
                return index
            }
            if let visibleID = layoutStabilizer.visiblePostID(),
               let index = posts.firstIndex(where: { $0.id == visibleID }) {
                return index
            }
            return posts.count
        }()

        if startIndex > 0 {
            var index = startIndex - 1
            while index >= 0 {
                if let unreadCount = vmInner.unreadIds[posts[index].id], unreadCount > 0 {
                    scrollToIndex(index)
                    return
                }
                index -= 1
            }
        }

        for post in posts.reversed() {
            if let unreadCount = vmInner.unreadIds[post.id], unreadCount > 0 {
                if let firstUnreadPostIndex = posts.firstIndex(where: { $0.id == post.id }) {
                    scrollToIndex(firstUnreadPostIndex)

//                    // Regular updateIsAtTop() in onPostAppearOnce { } doesn't catch the first row appearing to set isAtTop to 0, probably because
//                    // .onAppear happens when the offset is closer (like almost appearing), not at 0 when it would be too late for lazy loading
//                    // so force update here after small delay
//                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
//                        #if DEBUG
//                        L.og.debug("☘️☘️ \(vm.config?.name ?? "?") scrollToFirstUnread -> updateIsAtTop()")
//                        #endif
//                        updateIsAtTop()
//                    }
                }
                break
            }
        }
    }
    
    private func scrollToTop() {
        scrollToIndex(0)
        vmInner.isAtTop = true
        vmInner.readingPostID = nil
        vmInner.holdUnreadAboveReadingPost = false
//        
//        // Regular updateIsAtTop() in onPostAppearOnce { } doesn't catch the first row appearing to set isAtTop to 0, probably because
//        // .onAppear happens when the offset is closer (like almost appearing), not at 0 when it would be too late for lazy loading
//        // so force update here after small delay
//        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
//            #if DEBUG
//            L.og.debug("☘️☘️ \(vm.config?.name ?? "?") scrollToFirstUnread -> updateIsAtTop()")
//            #endif
//            updateIsAtTop()
//        }
    }
    
    private func performScrollToIndex(_ scrollToIndex: Int) {
        // While we scroll to previous index here, we are triggering onPostAppearOnce(), which updates markAsRead
        // But it wasn't a real onPostAppearOnce, so we need to avoid that markAsRead. Using isPerformingScroll flag to track that, and prevent re-entrancy.
        vmInner.isPerformingScroll = true
        
        Task { @MainActor in
            let proxy = ScrollOffset.proxy(.top, id: vm.columnVMid)
            let restorePostID = vmInner.pendingScrollToPostID
            let resolvedScrollToIndex: Int = if let restorePostID,
                                                case .posts(let currentPosts) = vm.viewState,
                                                let currentIndex = currentPosts.firstIndex(where: { $0.id == restorePostID }) {
                currentIndex
            } else {
                scrollToIndex
            }
            
            // Only proceed if we're in a valid scroll state
            guard proxy.offset >= 0 else {
                vmInner.isPerformingScroll = false
                vmInner.clearScrollRequest()
                vmInner.pendingScrollToPostID = nil
                return
            }
            
            // Disable animations for smoother performance
            UIView.performWithoutAnimation {
                let scrollView: UIScrollView? = vm.collectionView ?? vm.tableView
                if let scrollView, let indexPath = feedIndexPath(for: resolvedScrollToIndex, in: scrollView) {
                    if let collectionView = vm.collectionView {
                        collectionView.scrollToItem(at: indexPath, at: .top, animated: false)
                    } else if let tableView = vm.tableView {
                        tableView.scrollToRow(at: indexPath, at: .top, animated: false)
                    }
                    vmInner.isAtTop = resolvedScrollToIndex == 0
                }
            }

            let rememberedID = restorePostID
                ?? posts[safe: resolvedScrollToIndex]?.id
            if let rememberedID {
                vmInner.readingPostID = rememberedID
                layoutStabilizer.rememberAnchor(id: rememberedID)
                layoutStabilizer.pinItemToVisibleTop(id: rememberedID)
                restoreUnreadIdsAbove(postID: rememberedID)
            }
            
            vmInner.clearScrollRequest()
            vmInner.pendingScrollToPostID = nil

            // This is feed restoration, not unread navigation. Keep the established lightweight
            // path so subsequent new-post insertion can preserve position with withAnimation.
            try? await Task.sleep(nanoseconds: 100_000_000)
            vmInner.isPerformingScroll = false
            vmInner.updateIsAtTopSubject.send()
        }
    }
    
    private func scrollToIndex(_ scrollToIndex: Int) {
        vmInner.isPerformingScrollToFirstUnread = true
        let targetPost = posts[safe: scrollToIndex]
        if let targetPost {
            layoutStabilizer.rememberAnchor(id: targetPost.id, visibleTopOffset: 0)
            vmInner.readingPostID = targetPost.id
        }

        let scrollView: UIScrollView? = vm.collectionView ?? vm.tableView
        let indexPath = scrollView.flatMap { feedIndexPath(for: scrollToIndex, in: $0) }

        if #available(iOS 16.0, *), let collectionView = vm.collectionView, let indexPath {
            layoutStabilizer.beginProgrammaticScroll()
            collectionView.scrollToItem(at: indexPath, at: .top, animated: true)
            vmInner.isAtTop = scrollToIndex == 0
            finishUnreadScroll(targetPost: targetPost)
        } else if let tableView = vm.tableView, let indexPath {
            layoutStabilizer.beginProgrammaticScroll()
            tableView.scrollToRow(at: indexPath, at: .top, animated: true)
            vmInner.isAtTop = scrollToIndex == 0
            finishUnreadScroll(targetPost: targetPost)
        } else {
            vmInner.isPerformingScrollToFirstUnread = false
            layoutStabilizer.cancelProgrammaticScroll()
        }
    }

    private func restoreUnreadIdsAbove(postID: String) {
        guard case .posts(let currentPosts) = vm.viewState,
              let restoreIndex = currentPosts.firstIndex(where: { $0.id == postID }) else { return }
        vmInner.updateUnreadIds { unreadIds in
            for index in currentPosts.indices where index < restoreIndex {
                let post = currentPosts[index]
                if unreadIds[post.id] == nil || unreadIds[post.id] == 0 {
                    unreadIds[post.id] = 1 + post.parentPosts.count
                }
            }
        }
    }

    private func feedIndexPath(for itemIndex: Int, in scrollView: UIScrollView) -> IndexPath? {
        NXFeedIndexMapping.indexPath(
            forItemIndex: itemIndex,
            sectionCounts: {
                if let collectionView = scrollView as? UICollectionView {
                    return (0..<collectionView.numberOfSections).map { collectionView.numberOfItems(inSection: $0) }
                }
                if let tableView = scrollView as? UITableView {
                    return (0..<tableView.numberOfSections).map { tableView.numberOfRows(inSection: $0) }
                }
                return []
            }(),
            itemCount: posts.count
        )
    }

    private func finishUnreadScroll(targetPost: NRPost?) {
        Task { @MainActor in
            // Animated scroll duration varies with distance. Wait for UIKit to actually finish,
            // then correct once after any self-sizing rows encountered along the way have laid out.
            var previousOffset: CGFloat?
            var stableSamples = 0
            for _ in 0..<40 {
                let scrollView: UIScrollView? = vm.collectionView ?? vm.tableView
                guard let scrollView else { break }
                let currentOffset = scrollView.contentOffset.y
                if let previousOffset, abs(previousOffset - currentOffset) < 0.5,
                   !scrollView.isDragging, !scrollView.isDecelerating, !scrollView.isTracking {
                    stableSamples += 1
                } else {
                    stableSamples = 0
                }
                previousOffset = currentOffset

                // Programmatic animated scrolling does not consistently set isDecelerating.
                // Requiring several stable presentation samples avoids interrupting its animation.
                if stableSamples >= 3 {
                    await layoutStabilizer.finishProgrammaticScroll {
                        if let id = targetPost?.id {
                            layoutStabilizer.pinItemToVisibleTop(id: id)
                        }
                    }
                    break
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            if layoutStabilizer.isProgrammaticScrollPending {
                await layoutStabilizer.finishProgrammaticScroll {
                    if let id = targetPost?.id {
                        layoutStabilizer.pinItemToVisibleTop(id: id)
                    }
                }
            }
            if let targetPost {
                // Do not depend on onAppear here: List may reuse an already-visible row and never
                // fire it again. Consume exactly the post selected by the unread index at tap time.
                performIDCollectionUpdates(for: targetPost, vm: vm)
                performUnreadMarkingUpdates(for: targetPost, vm: vm)
            }
            vmInner.isPerformingScrollToFirstUnread = false
            vmInner.updateIsAtTopSubject.send()
        }
    }

    private func restorePreparedScrollPositionIfNeeded(in scrollView: UIScrollView) {
        guard vmInner.isPreparingForScrollRestore else { return }
        let restorePostID = vmInner.pendingScrollToPostID ?? vmInner.readingPostID
        let restoreIndex = restorePostID.flatMap { postID in posts.firstIndex(where: { $0.id == postID }) }
            ?? vmInner.pendingScrollToIndex
        guard let restoreIndex, restoreIndex > 0 else { return }

        let sectionCounts: [Int]
        if let collectionView = scrollView as? UICollectionView {
            sectionCounts = (0..<collectionView.numberOfSections).map { collectionView.numberOfItems(inSection: $0) }
        } else if let tableView = scrollView as? UITableView {
            sectionCounts = (0..<tableView.numberOfSections).map { tableView.numberOfRows(inSection: $0) }
        } else {
            return
        }
        guard let indexPath = NXFeedIndexMapping.indexPath(
            forItemIndex: restoreIndex,
            sectionCounts: sectionCounts,
            itemCount: posts.count
        ) else { return }

        UIView.setAnimationsEnabled(false)
        if let collectionView = scrollView as? UICollectionView {
            collectionView.scrollToItem(at: indexPath, at: .top, animated: false)
        } else if let tableView = scrollView as? UITableView {
            tableView.scrollToRow(at: indexPath, at: .top, animated: false)
        }
        UIView.setAnimationsEnabled(true)

        if let restorePostID {
            vmInner.readingPostID = restorePostID
            layoutStabilizer.rememberAnchor(id: restorePostID)
        }
        vmInner.isAtTop = false
        vmInner.updateIsAtTopSubject.send()
    }

    private func _updateIsAtTop() {
        guard !vmInner.isPreparingForScrollRestore,
              !vmInner.isPerformingScroll else { return }

        // The ScrollOffset proxy reports 0 when it has no subscription, which looks like
        // "at top" and used to send a restored feed into the prepend-at-top path.
        let scrollView: UIScrollView? = vm.collectionView ?? vm.tableView
        guard let scrollView else { return }

        let isAtTopNow = scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + 5
        
        // Only update if the state actually changed
        guard vmInner.isAtTop != isAtTopNow else { return }
        
        vmInner.isAtTop = isAtTopNow
        if isAtTopNow {
            vmInner.readingPostID = nil
            vmInner.holdUnreadAboveReadingPost = false
        }
        
#if DEBUG
        L.og.debug("☘️☘️ \(vm.config?.name ?? "?") contentOffset.y: \(scrollView.contentOffset.y) isAtTop: \(isAtTopNow) -[LOG]-")
#endif
        
        // Only mark all as read when transitioning to top, not when leaving top
        if isAtTopNow {
            Task.detached(priority: .userInitiated) {
                await MainActor.run {
                    self.markAllAsRead()
                }
            }
        }
    }

    private func onPostDisappear(_ nrPost: NRPost) {
        // Only trigger updateIsAtTop if we're not performing programmatic scrolls
        guard !vmInner.isPerformingScroll && !vmInner.isPerformingScrollToFirstUnread else { return }
        
#if DEBUG
        L.og.debug("☘️☘️ \(vm.config?.name ?? "?") NXPostsFeed.onPostDisappear() -> updateIsAtTop() BEFORE: \(vmInner.isAtTop) -[LOG]-")
#endif
        vmInner.updateIsAtTopSubject.send()
    }
    
    private func markAllAsRead() {
        if !vmInner.unreadIds.isEmpty {
#if DEBUG
            L.og.debug("☘️☘️ \(vm.config?.name ?? "?") NXPostsFeed.markAllAsRead() -[LOG]-")
#endif
            vmInner.unreadIds = [:]
        }
    }
}



func performIDCollectionUpdates(for nrPost: NRPost, vm: NXColumnViewModel) {
    if nrPost.postOrThreadAttributes.parentPosts.isEmpty {
        if nrPost.kind == 6, let firstQuoteId = nrPost.firstQuoteId {
            vm.markShortIdsSeen([nrPost.shortId, String(firstQuoteId.prefix(8))])
        }
        else {
            vm.markShortIdSeen(nrPost.shortId)
        }
    }
    else {
        let leafIds: Set<String> = Set(nrPost.postOrThreadAttributes.parentPosts.map { $0.shortId } + [nrPost.shortId])
        vm.markShortIdsSeen(leafIds)
    }
}

@MainActor
func performUnreadMarkingUpdates(for nrPost: NRPost, vm: NXColumnViewModel) {
    let vmInner = vm.vmInner
    vm.newestMarkedAsRead = max(nrPost.createdAt, vm.newestMarkedAsRead ?? .distantPast)
    // Early exit if no unread items to process
    guard vmInner.unreadIds[nrPost.id] != 0 else { return }
    
    // Batch unread ID updates
    var idsToMarkAsRead: [String] = []
    var notificationPairs: [(String, UUID)] = []
    
    vmInner.updateUnreadIds { unreadIds in
        // Current post
        unreadIds[nrPost.id] = 0
        idsToMarkAsRead.append(nrPost.shortId)
        notificationPairs.append((nrPost.id, vm.columnVMid))

        // Quote posts
        if nrPost.kind == 6, let firstQuoteId = nrPost.firstQuoteId {
            let shortQuoteId = String(firstQuoteId.prefix(8))
            idsToMarkAsRead.append(shortQuoteId)
            notificationPairs.append((firstQuoteId, vm.columnVMid))
        }

        // Parent posts
        if !nrPost.parentPosts.isEmpty {
            let parentShortIds = nrPost.parentPosts.map { $0.shortId }
            idsToMarkAsRead.append(contentsOf: parentShortIds)
            notificationPairs.append(contentsOf: nrPost.parentPosts.map { ($0.id, vm.columnVMid) })
        }

        // Mark remaining posts in feed as read (optimize this heavy operation)
        if let appearedIndex = vm.currentNRPostsOnScreen.firstIndex(where: { $0.id == nrPost.id }) {
            for i in appearedIndex..<vm.currentNRPostsOnScreen.count {
                if unreadIds[vm.currentNRPostsOnScreen[i].id] != 0 {
                    unreadIds[vm.currentNRPostsOnScreen[i].id] = 0
                    idsToMarkAsRead.append(vm.currentNRPostsOnScreen[i].shortId)

                    if vm.currentNRPostsOnScreen[i].isRepost, let firstQuoteId = vm.currentNRPostsOnScreen[i].firstQuoteId {
                        idsToMarkAsRead.append(String(firstQuoteId.prefix(8)))
                    }

                    if !vm.currentNRPostsOnScreen[i].parentPosts.isEmpty {
                        idsToMarkAsRead.append(contentsOf: vm.currentNRPostsOnScreen[i].parentPosts.map { $0.shortId })
                    }
                }
            }
        }
    }
    
    vm.markAsRead(idsToMarkAsRead)
    
    for (id, columnId) in notificationPairs {
        FeedsCoordinator.shared.markedAsReadSubject.send((id, columnId))
    }
    
    // Update UI immediately for responsiveness
    vmInner.updateIsAtTopSubject.send()
}
