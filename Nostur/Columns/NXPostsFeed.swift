//
//  NXPostsFeed.swift
//  Nosturix
//
//  Created by Fabian Lachman on 01/08/2024.
//

import SwiftUI
@_spi(Advanced) import SwiftUIIntrospect
import Combine

struct NXPostsFeed: View {
    
    @Environment(\.theme) private var theme
    
    private var vm: NXColumnViewModel
    private let posts: [NRPost]
    @ObservedObject private var vmInner: NXColumnViewModelInner

    @Weak private var collectionView: UICollectionView?
    @State private var collectionPrefetcher: NXPostsFeedPrefetcher?
    
    @Weak private var tableView: UITableView?
    @State private var tablePrefetcher: NXPostsFeedTablePrefetcher?
    
    @State private var updateIsAtTopSubscription: AnyCancellable?
    
    // State variables for unread counter position
    @AppStorage("nx_unread_counter_offset_x") private var nxUnreadCounterOffsetX: Double = 0
    @AppStorage("nx_unread_counter_offset_y") private var nxUnreadCounterOffsetY: Double = 0
    
    @State private var dragOffset = CGSize.zero
    
    init(vm: NXColumnViewModel, posts: [NRPost]) {
        self.vm = vm
        self.posts = posts
        self.vmInner = vm.vmInner
    }
    
    var body: some View {
        List(posts) { nrPost in
            NXListRow {
                PostOrThread(nrPost: nrPost)
            } onAppearOnce: {
                return self.onPostAppearOnce(nrPost)
            }
            .onDisappear {
                onPostDisappear(nrPost)
            }
            .listRowSeparator(.hidden)
            .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
        .withContainerTopOffsetEnvironmentKey()
        .scrollOffsetID(vm.columnVMid)
        .environment(\.defaultMinListRowHeight, 50)
        .listStyle(.plain)
        .introspect(.list, on: .iOS(.v15)) { view in
            DispatchQueue.main.async {
              self.tableView = view    
                if tablePrefetcher == nil {
                    tablePrefetcher = NXPostsFeedTablePrefetcher()
                    tablePrefetcher?.columnViewModel = vm
                    view.isPrefetchingEnabled = true
                    view.prefetchDataSource = tablePrefetcher
                }
            }
            
            // Special handling for the anti-flicker approach
            if vmInner.isPreparingForScrollRestore, let pendingIndex = vmInner.pendingScrollToIndex {
                // Immediately scroll to the target index without animation
                if let rows = view.dataSource?.tableView(view, numberOfRowsInSection: 0),
                   rows > pendingIndex {
                    UIView.setAnimationsEnabled(false)
                    view.scrollToRow(at: .init(row: pendingIndex, section: 0), at: .top, animated: false)
                    UIView.setAnimationsEnabled(true)
                    
                    if pendingIndex > 0 {
                        updateIsAtTop()
                    }
                }
            }
        }
        .introspect(.list, on: .iOS(.v16...)) { view in
            DispatchQueue.main.async {
              self.collectionView = view
                
                if collectionPrefetcher == nil {
                    collectionPrefetcher = NXPostsFeedPrefetcher()
                    collectionPrefetcher?.columnViewModel = vm
                    view.isPrefetchingEnabled = true
                    view.prefetchDataSource = collectionPrefetcher
                }
            }
            
            // Special handling for the anti-flicker approach
            if vmInner.isPreparingForScrollRestore, let pendingIndex = vmInner.pendingScrollToIndex {
                // Immediately scroll to the target index without animation
                if let rows = view.dataSource?.collectionView(view, numberOfItemsInSection: 0),
                   rows > pendingIndex {
                    UIView.setAnimationsEnabled(false)
                    view.scrollToItem(at: .init(row: pendingIndex, section: 0), at: .top, animated: false)
                    UIView.setAnimationsEnabled(true)
                    
                    if pendingIndex > 0 {
                        updateIsAtTop()
                    }
                }
            }
        }
        .scrollContentBackgroundHidden()
        .background(theme.listBackground)
        .onChange(of: vmInner.scrollToIndex) { scrollToIndex in
            guard let scrollToIndex else { return }
            guard !vmInner.isPerformingScroll else { return } // Prevent re-entrancy
            guard !vmInner.isPerformingScrollToFirstUnread else { return } // Prevent re-entrancy
            
#if DEBUG
            L.og.debug("☘️☘️ \(vm.config?.name ?? "?") NXPostsFeed .isAtTop \(vmInner.isAtTop) onChange(of: vm.scrollToIndex) \(scrollToIndex.description)")
#endif
            
            performScrollToIndex(scrollToIndex)
        }
        .overlay(alignment: .topTrailing) {
            if vmInner.unreadCount != 0 {
                unreadCounterView
                    .offset(x: nxUnreadCounterOffsetX + dragOffset.width,
                           y: nxUnreadCounterOffsetY + dragOffset.height)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                dragOffset = value.translation
                            }
                            .onEnded { value in
                                let newX = nxUnreadCounterOffsetX + value.translation.width
                                let newY = nxUnreadCounterOffsetY + value.translation.height
                                
                                // Constrain position within screen bounds with padding
                                let minX: CGFloat = -(ScreenSpace.shared.mainTabSize.width - 91) // not offscreen to the left
                                let minY: CGFloat = 0 // already top-right, don't move more
                                let maxX: CGFloat = 0 // already top-right, don't move more
                                let maxY: CGFloat = ScreenSpace.shared.mainTabSize.height - 296 // not too low
                                
                                let clampedX = min(max(newX, minX), maxX)
                                let clampedY = min(max(newY, minY), maxY)
                                
                                // Save position to UserDefaults
                                nxUnreadCounterOffsetX = clampedX
                                nxUnreadCounterOffsetY = clampedY
                                dragOffset = .zero
                            }
                    )
                    .onTapGesture {
                        scrollToFirstUnread()
                    }
                    .simultaneousGesture(LongPressGesture().onEnded { _ in
                        scrollToTop()
                    })
            }
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
    
    @ViewBuilder
    public var unreadCounterView: some View {
        NXUnreadCounterView(vm: vm.vmInner)
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
                vmInner.scrollToIndex = nil
                return
            }
            
            // Disable animations for smoother performance
            UIView.performWithoutAnimation {
                if #available(iOS 16.0, *) { // iOS 16+ UICollectionView
                    if let collectionView,
                       let rows = collectionView.dataSource?.collectionView(collectionView, numberOfItemsInSection: 0),
                       rows > scrollToIndex {
                        collectionView.scrollToItem(at: .init(row: scrollToIndex, section: 0), at: .top, animated: false)
                        vmInner.isAtTop = scrollToIndex == 0
                    }
                } else { // iOS 15 UITableView
                    if let tableView,
                       let rows = tableView.dataSource?.tableView(tableView, numberOfRowsInSection: 0),
                       rows > scrollToIndex {
                        tableView.scrollToRow(at: .init(row: scrollToIndex, section: 0), at: .top, animated: false)
                        vmInner.isAtTop = scrollToIndex == 0
                    }
                }
            }
            
            vmInner.scrollToIndex = nil
            
            // Reset flag and update state after a brief delay
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            vmInner.isPerformingScroll = false
            updateIsAtTop()
        }
    }
    
    private func scrollToIndex(_ scrollToIndex: Int) {
        vmInner.isPerformingScrollToFirstUnread = true

        if #available(iOS 16.0, *) { // iOS 16+ UICollectionView
            if let collectionView,
               let rows = collectionView.dataSource?.collectionView(collectionView, numberOfItemsInSection: 0),
               rows > scrollToIndex
            {
                collectionView.scrollToItem(at: .init(row: scrollToIndex, section: 0), at: .top, animated: true)
                vmInner.isAtTop = scrollToIndex == 0 // false unless scrollToIndex == 0
                
                // Reset flags after animations are re-enabled
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    vmInner.isPerformingScrollToFirstUnread = false
                    updateIsAtTop()
                }
            }
        }
        else { // iOS 15 UITableView
            if let tableView,
               let rows = tableView.dataSource?.tableView(tableView, numberOfRowsInSection: 0),
               rows > scrollToIndex
            {
                tableView.scrollToRow(at: .init(row: scrollToIndex, section: 0), at: .top, animated: true)
                vmInner.isAtTop = scrollToIndex == 0 // false unless scrollToIndex == 0
            }
            
            // Reset flags after animations are re-enabled
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                vmInner.isPerformingScrollToFirstUnread = false
                updateIsAtTop()
            }
        }
    }
    
    private func onPostAppearOnce(_ nrPost: NRPost) -> Bool {
        // Don't run if onPostAppearOnce is happening because of scrollToIndex (hidden scroll to keep scroll position)
        // Only run if it is actual user based scroll
        guard !vmInner.isPerformingScroll else { return false }
#if DEBUG
        L.og.debug("☘️☘️ \(vm.config?.name ?? "?") NXPostsFeed.onPostAppearOnce() -> updateIsAtTop() BEFORE: \(vmInner.isAtTop) -[LOG]-")
#endif
        
        // Batch async operations to avoid blocking the main thread
        Task.detached(priority: .userInitiated) {
            await vm.prefetch(nrPost)
            await vm.saveLocalFeedState()
        }
        
        updateIsAtTop()
        loadMoreIfNeeded()
        
        // Optimize ID collection operations
        performIDCollectionUpdates(for: nrPost)
        
        // Optimize unread marking operations
        performUnreadMarkingUpdates(for: nrPost)
        
        return true
    }
    
    private func performIDCollectionUpdates(for nrPost: NRPost) {
        if nrPost.postOrThreadAttributes.parentPosts.isEmpty {
            vm.allShortIdsSeen.insert(nrPost.shortId)
            if nrPost.kind == 6, let firstQuoteId = nrPost.firstQuoteId {
                vm.allShortIdsSeen.insert(String(firstQuoteId.prefix(8)))
            }
        }
        else {
            let leafIds: Set<String> = Set(nrPost.postOrThreadAttributes.parentPosts.map { $0.shortId } + [nrPost.shortId])
            vm.allShortIdsSeen.formUnion(leafIds)
        }
    }
    
    private func performUnreadMarkingUpdates(for nrPost: NRPost) {
        // Early exit if no unread items to process
        guard vmInner.unreadIds[nrPost.id] != 0 else { return }
        
        // Batch unread ID updates
        var idsToMarkAsRead: [String] = []
        var notificationPairs: [(String, UUID)] = []
        
        // Current post
        vmInner.unreadIds[nrPost.id] = 0
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
        if let appearedIndex = posts.firstIndex(where: { $0.id == nrPost.id }) {
            for i in appearedIndex..<posts.count {
                if vmInner.unreadIds[posts[i].id] != 0 {
                    vmInner.unreadIds[posts[i].id] = 0
                    idsToMarkAsRead.append(posts[i].shortId)
                    
                    if posts[i].isRepost, let firstQuoteId = posts[i].firstQuoteId {
                        idsToMarkAsRead.append(String(firstQuoteId.prefix(8)))
                    }
                    
                    if !posts[i].parentPosts.isEmpty {
                        idsToMarkAsRead.append(contentsOf: posts[i].parentPosts.map { $0.shortId })
                    }
                }
            }
        }
        
        // Batch the marking operations to reduce main thread blocking
        Task.detached(priority: .userInitiated) {
            await vm.markAsRead(idsToMarkAsRead)
            
            await MainActor.run {
                // Send notifications in batch
                for (id, columnId) in notificationPairs {
                    FeedsCoordinator.shared.markedAsUnreadSubject.send((id, columnId))
                }
            }
        }
        
        // Update UI immediately for responsiveness
        vmInner.updateIsAtTopSubject.send()
    }
    
    private func updateIsAtTop() {
        vmInner.updateIsAtTopSubject.send()
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
    
    private func loadMoreIfNeeded() {
        if #available(iOS 16.0, *) { // iOS 16+ UICollectionView
            if let collectionView,
               let lastCreatedAt = posts.last?.created_at,
               let lastItem = collectionView.indexPathsForVisibleItems.last,
               lastItem.row > (collectionView.numberOfItems(inSection: 0) - 10)
            {
                vm.onAppearSubject.send(lastCreatedAt)
            }
        }
        else { // iOS 15 UITableView
            if let tableView,
               let lastCreatedAt = posts.last?.created_at,
               let lastItem = tableView.indexPathsForVisibleRows?.last,
               lastItem.row > (tableView.numberOfRows(inSection: 0) - 10)
            {
                vm.onAppearSubject.send(lastCreatedAt)
            }
        }
    }
    
    private func onPostDisappear(_ nrPost: NRPost) {
        // Only trigger updateIsAtTop if we're not performing programmatic scrolls
        guard !vmInner.isPerformingScroll && !vmInner.isPerformingScrollToFirstUnread else { return }
        
#if DEBUG
        L.og.debug("☘️☘️ \(vm.config?.name ?? "?") NXPostsFeed.onPostDisappear() -> updateIsAtTop() BEFORE: \(vmInner.isAtTop) -[LOG]-")
#endif
        updateIsAtTop()
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
