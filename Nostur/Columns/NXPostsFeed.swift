//
//  NXPostsFeed.swift
//  Nosturix
//
//  Created by Fabian Lachman on 01/08/2024.
//

import SwiftUI
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
    private var pendingUpdates: [() -> Void] = []
    private var flushTask: Task<Void, Never>?
    private var isProgrammaticScrollInProgress = false

    var isProgrammaticScrollPending: Bool {
        isProgrammaticScrollInProgress
    }

    func attach(to scrollView: UIScrollView) {
        self.scrollView = scrollView
    }

    func beginProgrammaticScroll() {
        isProgrammaticScrollInProgress = true
    }

    func cancelProgrammaticScroll() {
        isProgrammaticScrollInProgress = false
        scheduleFlush()
    }

    func finishProgrammaticScroll(finalPosition: () -> Void) async {
        isProgrammaticScrollInProgress = false
        flushTask?.cancel()
        flushTask = nil

        guard let scrollView else {
            let updates = pendingUpdates
            pendingUpdates.removeAll()
            updates.forEach { $0() }
            finalPosition()
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

        let updates = pendingUpdates
        pendingUpdates.removeAll()
        updates.forEach { $0() }

        await Task.yield()
        try? await Task.sleep(nanoseconds: 20_000_000)
        scrollView.layoutIfNeeded()
        finalPosition()
        scrollView.layoutIfNeeded()

        snapshot?.removeFromSuperview()
    }

    func performAnchored(_ update: @escaping () -> Void) {
        guard let scrollView else {
            update()
            return
        }

        if isProgrammaticScrollInProgress
            || scrollView.isDragging
            || scrollView.isDecelerating
            || scrollView.isTracking {
            pendingUpdates.append(update)
            scheduleFlush()
        } else {
            applyAnchored([update])
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
            self.pendingUpdates.removeAll()
            self.flushTask = nil
            self.applyAnchored(updates)
        }
    }

    private func applyAnchored(_ updates: [() -> Void]) {
        guard !updates.isEmpty else { return }
        guard let scrollView else {
            updates.forEach { $0() }
            return
        }

        let anchor = visibleAnchor(in: scrollView)
        updates.forEach { $0() }

        DispatchQueue.main.async { [weak self, weak scrollView] in
            guard let self, let scrollView, !scrollView.isDragging, !scrollView.isDecelerating else { return }
            scrollView.layoutIfNeeded()
            guard let anchor,
                  let newMinY = self.itemMinY(at: anchor.indexPath, in: scrollView) else { return }
            let newViewportY = newMinY - scrollView.contentOffset.y
            let correction = newViewportY - anchor.viewportY
            guard abs(correction) > 0.5 else { return }
            var offset = scrollView.contentOffset
            offset.y += correction
            scrollView.setContentOffset(offset, animated: false)
        }
    }

    private func visibleAnchor(in scrollView: UIScrollView) -> (indexPath: IndexPath, viewportY: CGFloat)? {
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
        return (anchor.0, anchor.1 - scrollView.contentOffset.y)
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
            DispatchQueue.main.async {
                vm.tableView = view
                layoutStabilizer.attach(to: view)
                if vm.tablePrefetcher == nil {
                    vm.tablePrefetcher = NXPostsFeedTablePrefetcher()
                    vm.tablePrefetcher?.columnViewModel = vm
                    view.isPrefetchingEnabled = true
                    view.prefetchDataSource = vm.tablePrefetcher
                }
                vm.tablePrefetcher?.imageRequestTargetSize =
                    feedImageTargetSize
            }
            
            // Special handling for the anti-flicker approach
            if vm.vmInner.isPreparingForScrollRestore, let pendingIndex = vm.vmInner.pendingScrollToIndex {
                // Immediately scroll to the target index without animation
                if let rows = view.dataSource?.tableView(view, numberOfRowsInSection: 0),
                   rows > pendingIndex {
                    UIView.setAnimationsEnabled(false)
                    view.scrollToRow(at: .init(row: pendingIndex, section: 0), at: .top, animated: false)
                    UIView.setAnimationsEnabled(true)
                    
                    if pendingIndex > 0 {
                        vm.vmInner.updateIsAtTopSubject.send()
                    }
                }
            }
        }
        .introspect(.list, on: .iOS(.v16...)) { [weak vm] view in
            guard let vm else { return }
            DispatchQueue.main.async {
                vm.collectionView = view
                layoutStabilizer.attach(to: view)
                
                if vm.collectionPrefetcher == nil {
                    vm.collectionPrefetcher = NXPostsFeedPrefetcher()
                    vm.collectionPrefetcher?.columnViewModel = vm
                    view.isPrefetchingEnabled = true
                    view.prefetchDataSource = vm.collectionPrefetcher
                }
                vm.collectionPrefetcher?.imageRequestTargetSize =
                    feedImageTargetSize
            }
            
            // Special handling for the anti-flicker approach
            if vm.vmInner.isPreparingForScrollRestore, let pendingIndex = vm.vmInner.pendingScrollToIndex {
                // Immediately scroll to the target index without animation
                if let rows = view.dataSource?.collectionView(view, numberOfItemsInSection: 0),
                   rows > pendingIndex {
                    UIView.setAnimationsEnabled(false)
                    view.scrollToItem(at: .init(row: pendingIndex, section: 0), at: .top, animated: false)
                    UIView.setAnimationsEnabled(true)
                    
                    if pendingIndex > 0 {
                        vm.vmInner.updateIsAtTopSubject.send()
                    }
                }
            }
        }
        .scrollContentBackgroundHidden()
        .background(theme.listBackground)
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
            vm.pauseViewUpdates()
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
        if vmInner.unreadCount == 0 {
            scrollToTop()
            return
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
            
            // Only proceed if we're in a valid scroll state
            guard proxy.offset >= 0 else {
                vmInner.isPerformingScroll = false
                vmInner.clearScrollRequest()
                return
            }
            
            // Disable animations for smoother performance
            UIView.performWithoutAnimation {
                if #available(iOS 16.0, *) { // iOS 16+ UICollectionView
                    if let vmCollectionView = vm.collectionView,
                       let rows = vmCollectionView.dataSource?.collectionView(vmCollectionView, numberOfItemsInSection: 0),
                       rows > scrollToIndex {
                        vmCollectionView.scrollToItem(at: .init(row: scrollToIndex, section: 0), at: .top, animated: false)
                        vmInner.isAtTop = scrollToIndex == 0
                    }
                } else { // iOS 15 UITableView
                    if let vmTableView = vm.tableView,
                       let rows = vmTableView.dataSource?.tableView(vmTableView, numberOfRowsInSection: 0),
                       rows > scrollToIndex {
                        vmTableView.scrollToRow(at: .init(row: scrollToIndex, section: 0), at: .top, animated: false)
                        vmInner.isAtTop = scrollToIndex == 0
                    }
                }
            }
            
            vmInner.clearScrollRequest()
            
            // Reset flag and update state after a brief delay
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            vmInner.isPerformingScroll = false
            vmInner.updateIsAtTopSubject.send()
        }
    }
    
    private func scrollToIndex(_ scrollToIndex: Int) {
        vmInner.isPerformingScrollToFirstUnread = true

        if #available(iOS 16.0, *) { // iOS 16+ UICollectionView
            if let vmCollectionView = vm.collectionView,
               let rows = vmCollectionView.dataSource?.collectionView(vmCollectionView, numberOfItemsInSection: 0),
               rows > scrollToIndex
            {
                layoutStabilizer.beginProgrammaticScroll()
                vmCollectionView.scrollToItem(at: .init(row: scrollToIndex, section: 0), at: .top, animated: true)
                vmInner.isAtTop = scrollToIndex == 0 // false unless scrollToIndex == 0
                
                finishUnreadScroll(to: scrollToIndex)
            } else {
                vmInner.isPerformingScrollToFirstUnread = false
                layoutStabilizer.cancelProgrammaticScroll()
            }
        }
        else { // iOS 15 UITableView
            if let vmTableView = vm.tableView,
               let rows = vmTableView.dataSource?.tableView(vmTableView, numberOfRowsInSection: 0),
               rows > scrollToIndex
            {
                layoutStabilizer.beginProgrammaticScroll()
                vmTableView.scrollToRow(at: .init(row: scrollToIndex, section: 0), at: .top, animated: true)
                vmInner.isAtTop = scrollToIndex == 0 // false unless scrollToIndex == 0
                finishUnreadScroll(to: scrollToIndex)
            } else {
                vmInner.isPerformingScrollToFirstUnread = false
                layoutStabilizer.cancelProgrammaticScroll()
            }
        }
    }

    private func finishUnreadScroll(to index: Int) {
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
                        if let collectionView = vm.collectionView,
                           collectionView.numberOfItems(inSection: 0) > index {
                            collectionView.scrollToItem(at: .init(row: index, section: 0), at: .top, animated: false)
                        } else if let tableView = vm.tableView,
                                  tableView.numberOfRows(inSection: 0) > index {
                            tableView.scrollToRow(at: .init(row: index, section: 0), at: .top, animated: false)
                        }
                    }
                    break
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            if layoutStabilizer.isProgrammaticScrollPending {
                await layoutStabilizer.finishProgrammaticScroll { }
            }
            vmInner.isPerformingScrollToFirstUnread = false
            vmInner.updateIsAtTopSubject.send()
        }
    }

    private func _updateIsAtTop() {
        let proxy = ScrollOffset.proxy(.top, id: vm.columnVMid)
        let offset = proxy.offset
        
        // Cache the offset threshold to avoid recalculation
        let threshold: CGFloat = -5
        let isAtTopNow = offset >= threshold
        
        // Only update if the state actually changed
        guard vmInner.isAtTop != isAtTopNow else { return }
        
        vmInner.isAtTop = isAtTopNow
        
#if DEBUG
        L.og.debug("☘️☘️ \(vm.config?.name ?? "?") proxy.offset: \(offset) isAtTop: \(isAtTopNow) -[LOG]-")
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
