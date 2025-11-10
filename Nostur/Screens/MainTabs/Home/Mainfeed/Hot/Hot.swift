//
//  Hot.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/09/2023.
//

import SwiftUI
import NavigationBackport

struct Hot: View {
    @Environment(\.theme) private var theme
    @ObservedObject var settings: SettingsStore = .shared
    @EnvironmentObject var hotVM: HotViewModel
    @StateObject private var speedTest = NXSpeedTest()
    @State private var showSettings = false
    
    @Weak private var collectionView: UICollectionView?    
    @Weak private var tableView: UITableView?
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Main" }
        set { setSelectedTab(newValue) }
    }
    
    private var selectedSubTab: String {
        get { UserDefaults.standard.string(forKey: "selected_subtab") ?? "Hot" }
        set { setSelectedSubTab(newValue) }
    }
    
    var body: some View {
#if DEBUG
        let _ = Self._printChanges()
#endif
        Container {
            switch hotVM.state {
            case .initializing, .loading:
                CenteredProgressView()
            case .fetchingFromFollows:
                ZStack(alignment: .center) {
                    theme.listBackground
                        .overlay(alignment: .bottom) {
                            Text("Checking what your follows reposted or reacted to...")
                                .pulseEffect()
                                .multilineTextAlignment(.center)
                                .padding(15)
                                .padding(.bottom, 75)
                        }
                    FetchingAnimationView()
                }
            case .ready:
                List {
                    ForEach(hotVM.hotPosts) { nrPost in
                        ZStack { // <-- added because "In Lists, the Top-Level Structure Type _ConditionalContent Can Break Lazy Loading" (https://fatbobman.com/en/posts/tips-and-considerations-for-using-lazy-containers-in-swiftui/)
                            PostOrThread(nrPost: nrPost, theme: theme)
                                .onBecomingVisible {
                                    // SettingsStore.shared.fetchCounts should be true for below to work
                                    hotVM.prefetch(nrPost)
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
                    await hotVM.refresh()
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
                    guard selectedTab == "Main" && selectedSubTab == "Hot" else { return }
                    self.scrollTo(index: 0)
                }
                .onReceive(receiveNotification(.shouldScrollToFirstUnread)) { _ in
                    guard selectedTab == "Main" && selectedSubTab == "Hot" else { return }
                    self.scrollTo(index: 0)
                }
                .onReceive(receiveNotification(.activeAccountChanged)) { _ in
                    hotVM.reload()
                }
                .padding(0)
            case .timeout:
                VStack {
                    Text("Time-out while loading hot feed")
                    Button("Try again") { hotVM.reload() }
                }
                .centered()
            }
        }
        .background(theme.listBackground)
        .overlay(alignment: .top) {
            LoadingBar(loadingBarViewState: $speedTest.loadingBarViewState)
        }
        .onAppear {
            guard IS_DESKTOP_COLUMNS() || (selectedTab == "Main" && selectedSubTab == "Hot") else { return }
            hotVM.load(speedTest: speedTest)
        }
        .onReceive(receiveNotification(.scenePhaseActive)) { _ in
            guard !IS_CATALYST else { return }
            guard selectedTab == "Main" && selectedSubTab == "Hot" else { return }
            guard hotVM.shouldReload else { return }
            hotVM.state = .loading
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { // Reconnect delay
                hotVM.load(speedTest: speedTest)
            }
        }
        .onChange(of: selectedSubTab) { newValue in
            guard newValue == "Hot" else { return }
            hotVM.load(speedTest: speedTest) // didLoad is checked in .load() so no need here
        }
        .onReceive(receiveNotification(.showFeedToggles)) { _ in
            showSettings = true
        }
        .sheet(isPresented: $showSettings) {
            NBNavigationStack {
                HotFeedSettings(hotVM: hotVM)
                    .environment(\.theme, theme)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
        }
    }
}

struct Hot_Previews: PreviewProvider {
    static var previews: some View {
        Hot()
            .environmentObject(HotViewModel())
            .environmentObject(Themes.default)
    }
}


@_spi(Advanced) import SwiftUIIntrospect
extension Hot {
    
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
