//
//  NXPostsFeed.swift
//  Nosturix
//
//  Created by Fabian Lachman on 01/08/2024.
//

import SwiftUI
@_spi(Advanced) import SwiftUIIntrospect

struct NXPostsFeed: View {
    
    @EnvironmentObject private var themes: Themes
    
    private var vm: NXColumnViewModel
    private let posts: [NRPost]
    @ObservedObject private var vmInner: NXColumnViewModelInner
    
    @State private var collectionView: UICollectionView?
    @State private var collectionPrefetcher: NXPostsFeedPrefetcher?
    
    @State private var tableView: UITableView?
    @State private var tablePrefetcher: NXPostsFeedTablePrefetcher?
    
    init(vm: NXColumnViewModel, posts: [NRPost]) {
        self.vm = vm
        self.posts = posts
        self.vmInner = vm.vmInner
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ScrollViewReader { proxy in
            List {
                ForEach(posts) { nrPost in
                    ZStack(alignment: .leading) {
                        PostOrThread(nrPost: nrPost)
                            .onBecomingVisible {
                                // SettingsStore.shared.fetchCounts should be true for below to work
                                vm.prefetch(nrPost)
                            }
                    }
                    .id(nrPost.id)
                    .onAppear {
                        onPostAppear(nrPost)
                    }                    
                    .onDisappear {
                        onPostDisappear(nrPost)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(themes.theme.listBackground)
                    .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
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
            }
            .scrollContentBackgroundHidden()
            .onChange(of: vmInner.scrollToIndex) { scrollToIndex in
                L.og.debug("☘️☘️ \(vm.config?.id ?? "?") NXPostsFeed onChange(of: vm.scrollToIndex) \(scrollToIndex?.description ?? "?")")
                
                if #available(iOS 16.0, *) { // iOS 16+ UICollectionView
                    if let collectionView,
                       let scrollToIndex,
                       let rows = collectionView.dataSource?.collectionView(collectionView, numberOfItemsInSection: 0),
                       rows > scrollToIndex
                    {
                        if collectionView.contentOffset.y == 0 {
                            collectionView.scrollToItem(at: .init(row: scrollToIndex, section: 0),
                                                        at: .top,
                                                        animated: false)
                            vmInner.scrollToIndex = nil
                        }
                    }
                }
                else { // iOS 15 UITableView
                    
                    if let tableView,
                       let scrollToIndex,
                       let rows = tableView.dataSource?.tableView(tableView, numberOfRowsInSection: 0),
                       rows > scrollToIndex
                    {
                        if tableView.contentOffset.y == 0 {
                            tableView.scrollToRow(at: .init(row: scrollToIndex, section: 0), at: .top, animated: false)
                            vmInner.scrollToIndex = nil
                        }
                    }
                }
            }
            .onChange(of: posts) { newPosts in
                updateIsAtTop() // TODO: in .async or not?
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
            #if DEBUG
            .overlay(alignment: .bottom) {
                VStack {
                    Text("posts: \(posts.count) atTop: \(vmInner.isAtTop ? "1" : "0") load time: \(vm.formattedLoadTime)")
                    ConnectionDebugger()
                }
            }
            #endif
            .onReceive(receiveNotification(.shouldScrollToFirstUnread)) { _ in
                guard vm.isVisible else { return }
                scrollToFirstUnread(proxy)
            }
            .onReceive(receiveNotification(.shouldScrollToTop)) { _ in
                guard vm.isVisible else { return }
                
                scrollToTop(proxy)
            }
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
                }
                break
            }
        }
    }
    
    private func scrollToTop(_ proxy: ScrollViewProxy) {
        guard let topPost = posts.first else { return }
        withAnimation {
            proxy.scrollTo(topPost.id, anchor: .top)
            vmInner.isAtTop = true
        }
    }
    
    private func onPostAppear(_ nrPost: NRPost) {
        updateIsAtTop()
        loadMoreIfNeeded()
        vm.haltProcessing() // will stop new updates on screen for 2.5 seconds
        if vmInner.unreadIds[nrPost.id] != 0 {
            vmInner.unreadIds[nrPost.id] = 0
        }
        if let appearedIndex = posts.firstIndex(where: { $0.id == nrPost.id }) {
            if appearedIndex == 0 && !vmInner.unreadIds.isEmpty {
                vmInner.unreadIds = [:]
            }
            
            for i in appearedIndex..<posts.count {
                if vmInner.unreadIds[posts[i].id] != 0 {
                    vmInner.unreadIds[posts[i].id] = 0
                }
            }
        }
    }
    
    private func updateIsAtTop() {
        if #available(iOS 16.0, *) { // iOS 16+ UICollectionView
            if let collectionView {
                if collectionView.contentOffset.y <= 3 {
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
        updateIsAtTop()
    }
}
