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
    
    @EnvironmentObject private var themes: Themes
    
    private var vm: NXColumnViewModel
    private let posts: [NRPost]
    @ObservedObject private var vmInner: NXColumnViewModelInner
//    private let isVisible: Bool
    
    @Weak private var collectionView: UICollectionView?
    @State private var collectionPrefetcher: NXPostsFeedPrefetcher?
    
    @Weak private var tableView: UITableView?
    @State private var tablePrefetcher: NXPostsFeedTablePrefetcher?
    
    @State private var updateIsAtTopSubscription: AnyCancellable?
    
#if DEBUG
    @ObservedObject private var speedTest: NXSpeedTest
#endif
    
    init(vm: NXColumnViewModel, posts: [NRPost]) {
        self.vm = vm
#if DEBUG
        self.speedTest = vm.speedTest
#endif
        self.posts = posts
        self.vmInner = vm.vmInner
    }
    
#if DEBUG
    @ViewBuilder
    private var speedTestView: some View {
        VStack {
            Text("Speed final: \(speedTest.totalTimeSinceStarting)")
            if let timestampFirstFetchFinished = speedTest.timestampFirstFetchFinished, let sinceFetchStart = speedTest.timestampFirstFetchStarted {
                Text("First fetch finished: \(timestampFirstFetchFinished.timeIntervalSince(sinceFetchStart))")
            }
            if let sinceFetchStart = speedTest.timestampFirstFetchStarted {
                ForEach(Array(speedTest.relaysFinishedAt.enumerated()), id: \.offset) { index, timestamp in
                    Text("\(timestamp.timeIntervalSince(sinceFetchStart))")
                }
                Divider()
                ForEach(Array(speedTest.relaysFinishedLater.enumerated()), id: \.offset) { index, timestamp in
                    Text("\(timestamp.timeIntervalSince(sinceFetchStart))")
                }
            }
        }
        .background(Color.black.opacity(0.7))
        .foregroundColor(.white)
    }
#endif
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ScrollViewReader { proxy in
            List(posts) { nrPost in
                ZStack { // <-- added because "In Lists, the Top-Level Structure Type _ConditionalContent Can Break Lazy Loading" (https://fatbobman.com/en/posts/tips-and-considerations-for-using-lazy-containers-in-swiftui/)
                    PostOrThread(nrPost: nrPost)
                        .onBecomingVisible {
                            // SettingsStore.shared.fetchCounts should be true for below to work
                            vm.prefetch(nrPost)
                            if nrPost.postOrThreadAttributes.parentPosts.isEmpty {
                                vm.allIdsSeen.insert(nrPost.shortId)
                            }
                            else {
                                let leafIds: Set<String> = Set(nrPost.postOrThreadAttributes.parentPosts.map { $0.shortId } + [nrPost.shortId])
                                vm.allIdsSeen.formUnion(leafIds)
                            }
                        }
                        .onAppear {
                            onPostAppear(nrPost)
                        }
                        .onDisappear {
                            onPostDisappear(nrPost)
                        }
                }
                .id(nrPost.id) // <-- must use .id or can't .scrollTo
                .listRowSeparator(.hidden)
                .listRowBackground(themes.theme.listBackground)
                .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            .environment(\.defaultMinListRowHeight, 50)
            .listStyle(.plain)
            .introspect(.list, on: .iOS(.v15)) { view in
                DispatchQueue.main.async {
                  self.tableView = view
                }
                if tablePrefetcher == nil {
                    tablePrefetcher = NXPostsFeedTablePrefetcher()
                    tablePrefetcher?.columnViewModel = vm
                    view.isPrefetchingEnabled = true
                    view.prefetchDataSource = tablePrefetcher
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
                }
                if collectionPrefetcher == nil {
                    collectionPrefetcher = NXPostsFeedPrefetcher()
                    collectionPrefetcher?.columnViewModel = vm
                    view.isPrefetchingEnabled = true
                    view.prefetchDataSource = collectionPrefetcher
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
            .onChange(of: vmInner.scrollToIndex) { scrollToIndex in
                guard let scrollToIndex else { return }
                guard !vmInner.isPerformingScroll else { return } // Prevent re-entrancy
                
#if DEBUG
                L.og.debug("☘️☘️ \(vm.config?.name ?? "?") NXPostsFeed .isAtTop \(vmInner.isAtTop) onChange(of: vm.scrollToIndex) \(scrollToIndex.description)")
#endif
      
                // While we scroll to previous index here, we are triggering onPostAppear(), which updates markAsRead
                // But it wasn't a real onPostAppear, so we need to avoid that markAsRead. Using isPerformingScroll flag to track that, and prevent re-entrancy.
                vmInner.isPerformingScroll = true
                
                // Anti-flicker approach
                DispatchQueue.main.async {
                    // Completely disable animations during the scroll
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    UIView.setAnimationsEnabled(false)
                    
                    if #available(iOS 16.0, *) { // iOS 16+ UICollectionView
                        if let collectionView,
                           let rows = collectionView.dataSource?.collectionView(collectionView, numberOfItemsInSection: 0),
                           rows > scrollToIndex
                        {
#if DEBUG
                            L.og.debug("☘️☘️ \(vm.config?.name ?? "?") collectionView.contentOffset.y: \(collectionView.contentOffset.y) -[LOG]-")
#endif
                            
                            if collectionView.contentOffset.y == 0 {
                                // Perform the scroll with all animations disabled
                                collectionView.layer.removeAllAnimations()
                                collectionView.scrollToItem(at: .init(row: scrollToIndex, section: 0),
                                                           at: .top,
                                                           animated: false)
                                vmInner.isAtTop = scrollToIndex == 0 // false unless scrollToIndex == 0
                            }
                            vmInner.scrollToIndex = nil
                        }
                    }
                    else { // iOS 15 UITableView
                        if let tableView,
                           let rows = tableView.dataSource?.tableView(tableView, numberOfRowsInSection: 0),
                           rows > scrollToIndex
                        {
                            if tableView.contentOffset.y == 0 {
                                // Perform the scroll with all animations disabled
                                tableView.layer.removeAllAnimations()
                                tableView.scrollToRow(at: .init(row: scrollToIndex, section: 0), 
                                                    at: .top, 
                                                    animated: false)
                                vmInner.isAtTop = scrollToIndex == 0 // false unless scrollToIndex == 0
                            }
                            vmInner.scrollToIndex = nil
                        }
                    }
                    
                    // Re-enable animations
                    UIView.setAnimationsEnabled(true)
                    CATransaction.commit()
                    
                    // Reset flags after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        vmInner.isPerformingScroll = false
                        updateIsAtTop()
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                unreadCounterView
                    .onTapGesture {
                        scrollToFirstUnread(proxy)
                    }
                    .simultaneousGesture(LongPressGesture().onEnded { _ in
                        scrollToTop(proxy)
                    })
            }
            .onReceive(receiveNotification(.shouldScrollToFirstUnread)) { _ in
                guard vm.isVisible else { return }
                scrollToFirstUnread(proxy)
            }
            .onReceive(receiveNotification(.shouldScrollToTop)) { _ in
                guard vm.isVisible else { return }
                
                scrollToTop(proxy)
            }
            
            // Handle going to detail and back
            .onAppear {
                guard vm.isPaused else { return }
                vm.resume()
            }
            .onDisappear {
                // When opening detail, the feed would still update in background using withAnimation { },
                // but because its not visible the hack to keep scroll position doesn't work
                // so we pause() updates (and resume() in onAppear {})
                guard !vm.isPaused else { return }
                vm.pause()
            }
            
            // Add updateIsAtTop() debounces
            .onAppear {
                guard updateIsAtTopSubscription == nil else { return }
                updateIsAtTopSubscription = vmInner.updateIsAtTopSubject
                    .debounce(for: 0.075, scheduler: RunLoop.main)
                    .sink {
                        self._updateIsAtTop()
                    }
            }
            
#if DEBUG
            .overlay(alignment: .bottom) {
                speedTestView
            }
#endif
        }
    }
    
    @ViewBuilder
    public var unreadCounterView: some View {
        NXUnreadCounterView(vm: vm.vmInner)
            .padding(.trailing, 10)
            .padding(.top, 5)
    }
    
    private func scrollToFirstUnread(_ proxy: ScrollViewProxy) {
        if vmInner.unreadCount == 0 {
            scrollToTop(proxy)
            return
        }
        for post in posts.reversed() {
            if let unreadCount = vmInner.unreadIds[post.id], unreadCount > 0 {
                if let firstUnreadPost = posts.first(where: { $0.id == post.id }) {
                    withAnimation {
                        // NOTE: This can crash, but so far only only iOS 16.1?
                        proxy.scrollTo(firstUnreadPost.id, anchor: .top)
                    }

                    // Regular updateIsAtTop() in onPostAppear { } doesn't catch the first row appearing to set isAtTop to 0, probably because
                    // .onAppear happens when the offset is closer (like almost appearing), not at 0 when it would be too late for lazy loading
                    // so force update here after small delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        #if DEBUG
                        L.og.debug("☘️☘️ \(vm.config?.name ?? "?") scrollToFirstUnread -> updateIsAtTop()")
                        #endif
                        updateIsAtTop()
                    }
                }
                break
            }
        }
    }
    
    private func scrollToTop(_ proxy: ScrollViewProxy) {
        guard let topPost = posts.first else { return }
        withAnimation {
            proxy.scrollTo(topPost.id, anchor: .top)
        }
        vmInner.isAtTop = true
        
        // Regular updateIsAtTop() in onPostAppear { } doesn't catch the first row appearing to set isAtTop to 0, probably because
        // .onAppear happens when the offset is closer (like almost appearing), not at 0 when it would be too late for lazy loading
        // so force update here after small delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            #if DEBUG
            L.og.debug("☘️☘️ \(vm.config?.name ?? "?") scrollToFirstUnread -> updateIsAtTop()")
            #endif
            updateIsAtTop()
        }
    }
    
    private func onPostAppear(_ nrPost: NRPost) {
#if DEBUG
L.og.debug("☘️☘️ \(vm.config?.name ?? "?") NXPostsFeed.onPostAppear() -> updateIsAtTop() BEFORE: \(vmInner.isAtTop) -[LOG]-")
#endif
        updateIsAtTop()
        loadMoreIfNeeded()
//        vm.haltProcessing() // will stop new updates on screen for 5.0 seconds
        
        // Don't update markAsRead if the onPostAppear is happening because of scrollToIndex (hidden scroll to keep scroll position)
        // Only update if it is actual user based scroll
        guard !vmInner.isPerformingScroll else { return }
        
        if vmInner.unreadIds[nrPost.id] != 0 {
            vmInner.unreadIds[nrPost.id] = 0
            vmInner.updateIsAtTopSubject.send()
            vm.markAsRead(nrPost.shortId)
            
            if !nrPost.parentPosts.isEmpty {
                vm.markAsRead(nrPost.parentPosts.map { $0.shortId })
            }
            
            if nrPost.isRepost, let shortId = nrPost.firstQuote?.shortId {
                vm.markAsRead(shortId)
            }
        }
        if let appearedIndex = posts.firstIndex(where: { $0.id == nrPost.id }) {
            if vmInner.isAtTop && appearedIndex == 0 && !vmInner.unreadIds.isEmpty {
#if DEBUG
                L.og.debug("☘️☘️ \(vm.config?.name ?? "?") NXPostsFeed.onPostAppear() .isAtTop \(vmInner.isAtTop) appearedIndex == 0 --> vmInner.unreadIds = [:] -[LOG]-")
#endif
                vmInner.unreadIds = [:]
                vmInner.updateIsAtTopSubject.send()
            }
            
            for i in appearedIndex..<posts.count {
                if vmInner.unreadIds[posts[i].id] != 0 {
                    vmInner.unreadIds[posts[i].id] = 0
                    vmInner.updateIsAtTopSubject.send()
                    vm.markAsRead(posts[i].shortId)
                    
                    if !posts[i].parentPosts.isEmpty {
                        vm.markAsRead(posts[i].parentPosts.map { $0.shortId })
                    }
                    
                    if posts[i].isRepost, let shortId = posts[i].firstQuote?.shortId {
                        vm.markAsRead(shortId)
                    }
                }
            }
        }
    }
    
    private func updateIsAtTop() {
        vmInner.updateIsAtTopSubject.send()
    }
    
    private func _updateIsAtTop() {
        if #available(iOS 16.0, *) { // iOS 16+ UICollectionView
            if let collectionView {
#if DEBUG
L.og.debug("☘️☘️ \(vm.config?.name ?? "?") collectionView.contentOffset.y: \(collectionView.contentOffset.y) -[LOG]-")
#endif
                
                if collectionView.contentOffset.y <= 3 {
                    if !vmInner.isAtTop {
                        vmInner.isAtTop = true
#if DEBUG
L.og.debug("☘️☘️ \(vm.config?.name ?? "?") vmInner.isAtTop set to true -[LOG]-")
#endif
                    }
                }
                else {
                    if vmInner.isAtTop {
                        vmInner.isAtTop = false
                    }
                }
            }
        }
        else { // iOS 15 UITableView
            if let tableView {
                if tableView.contentOffset.y <= 3 {
                    if !vmInner.isAtTop {
                        vmInner.isAtTop = true
                    }
                }
                else {
                    if vmInner.isAtTop {
                        vmInner.isAtTop = false
                    }
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
#if DEBUG
L.og.debug("☘️☘️ \(vm.config?.name ?? "?") NXPostsFeed.onPostDisappear() -> updateIsAtTop() BEFORE: \(vmInner.isAtTop) -[LOG]-")
#endif
        updateIsAtTop()
    }
}
