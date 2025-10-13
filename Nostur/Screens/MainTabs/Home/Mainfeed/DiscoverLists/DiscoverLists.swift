//
//  DiscoverLists.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/04/2025.
//

import SwiftUI
import NavigationBackport

struct DiscoverLists: View {
    @Environment(\.theme) private var theme
    @ObservedObject var settings: SettingsStore = .shared
    @EnvironmentObject var discoverListsVM: DiscoverListsViewModel
    @StateObject private var speedTest = NXSpeedTest()
    @State private var showSettings = false
    
    @Weak private var collectionView: UICollectionView?    
    @Weak private var tableView: UITableView?
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Main" }
        set { setSelectedTab(newValue) }
    }
    
    private var selectedSubTab: String {
        get { UserDefaults.standard.string(forKey: "selected_subtab") ?? "DiscoverLists" }
        set { setSelectedSubTab(newValue) }
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        Container {
            switch discoverListsVM.state {
            case .initializing, .loading:
                CenteredProgressView()
            case .ready:
                List {
                    ForEach(discoverListsVM.discoverLists) { nrPost in
                        ZStack { // <-- added because "In Lists, the Top-Level Structure Type _ConditionalContent Can Break Lazy Loading" (https://fatbobman.com/en/posts/tips-and-considerations-for-using-lazy-containers-in-swiftui/)
                            Box(nrPost: nrPost) {
                                PostRowDeletable(nrPost: nrPost, isDetail: false)
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(theme.listBackground)
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                }
                .environment(\.defaultMinListRowHeight, 0)
                .listStyle(.plain)
                .refreshable {
                    await discoverListsVM.refresh()
                }
                .introspect(.list, on: .iOS(.v15)) { view in
                    DispatchQueue.main.async {
                      self.tableView = view
                    }
                }
                .introspect(.list, on: .iOS(.v16...)) { view in
                    DispatchQueue.main.async {
                      self.collectionView = view
                    }
                }
                .onReceive(receiveNotification(.shouldScrollToTop)) { _ in
                    guard selectedTab == "Main" && selectedSubTab == "DiscoverLists" else { return }
                    self.scrollTo(index: 0)
                }
                .onReceive(receiveNotification(.shouldScrollToFirstUnread)) { _ in
                    guard selectedTab == "Main" && selectedSubTab == "DiscoverLists" else { return }
                    self.scrollTo(index: 0)
                }
                .onReceive(receiveNotification(.activeAccountChanged)) { _ in
                    discoverListsVM.reload()
                }
                .padding(0)
            case .timeout:
                VStack {
                    Text("Time-out while loading discover feed")
                    Button("Try again") { discoverListsVM.reload() }
                }
                .centered()
            }
        }
        .background(theme.listBackground)
        .overlay(alignment: .top) {
            LoadingBar(loadingBarViewState: $speedTest.loadingBarViewState)
        }
        .onAppear {
            guard IS_DESKTOP_COLUMNS() || (selectedTab == "Main" && selectedSubTab == "DiscoverLists") else { return }
            discoverListsVM.load(speedTest: speedTest)
        }
        .onChange(of: selectedSubTab) { newValue in
            guard !IS_CATALYST else { return }
            guard newValue == "DiscoverLists" else { return }
            discoverListsVM.load(speedTest: speedTest) // didLoad is checked in .load() so no need here
        }
        .onReceive(receiveNotification(.showFeedToggles)) { _ in
            showSettings = true
        }
        .sheet(isPresented: $showSettings) {
            NBNavigationStack {
                DiscoverListsFeedSettings(discoverListsVM: discoverListsVM)
                    .environment(\.theme, theme)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
        }
    }
}

struct DiscoverLists_Previews: PreviewProvider {
    static var previews: some View {
        DiscoverLists()
            .environmentObject(DiscoverListsViewModel())
            .environmentObject(Themes.default)
    }
}

@_spi(Advanced) import SwiftUIIntrospect
extension DiscoverLists {
    
    // Scroll instantly instead of waiting to finish scrolling before it works (when using ScrollViewProxy)
    private func scrollTo(index: Int) {

        if #available(iOS 16.0, *) { // iOS 16+ UICollectionView
            if let collectionView,
               let rows = collectionView.dataSource?.collectionView(collectionView, numberOfItemsInSection: 0),
               rows > index
            {
                collectionView.scrollToItem(at: .init(row: index, section: 0), at: .top, animated: true)
            }
        }
        else { // iOS 15 UITableView
            if let tableView,
               let rows = tableView.dataSource?.tableView(tableView, numberOfRowsInSection: 0),
               rows > index
            {
                tableView.scrollToRow(at: .init(row: index, section: 0), at: .top, animated: true)
            }
        }
    }
}
