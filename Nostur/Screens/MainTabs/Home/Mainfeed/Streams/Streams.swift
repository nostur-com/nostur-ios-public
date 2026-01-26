//
//  Streams.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/01/2026.
//

import SwiftUI
import NavigationBackport

struct Streams: View {
    @Environment(\.theme) private var theme
    @ObservedObject var settings: SettingsStore = .shared
    @EnvironmentObject var streamsVM: StreamsViewModel
    @StateObject private var speedTest = NXSpeedTest()
    @State private var showSettings = false
    
    @Weak private var collectionView: UICollectionView?    
    @Weak private var tableView: UITableView?
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Main" }
        set { setSelectedTab(newValue) }
    }
    
    private var selectedSubTab: String {
        get { UserDefaults.standard.string(forKey: "selected_subtab") ?? "Streams" }
        set { setSelectedSubTab(newValue) }
    }
    
    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        Container {
            switch streamsVM.state {
            case .initializing, .loading:
                CenteredProgressView()
            case .ready:
                List {
                    ForEach(streamsVM.streams) { nrLiveEvent in
                        LiveStreamRow(liveEvent: nrLiveEvent)
                            .listRowSeparator(.hidden)
                            .listRowBackground(theme.background)
                            .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                }
                .environment(\.defaultMinListRowHeight, 0)
                .listStyle(.plain)
                .refreshable {
                    await streamsVM.refresh()
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
                    guard selectedTab == "Main" && selectedSubTab == "Streams" else { return }
                    self.scrollTo(index: 0)
                }
                .onReceive(receiveNotification(.shouldScrollToFirstUnread)) { _ in
                    guard selectedTab == "Main" && selectedSubTab == "Streams" else { return }
                    self.scrollTo(index: 0)
                }
                .onReceive(receiveNotification(.activeAccountChanged)) { _ in
                    streamsVM.reload()
                }
                .padding(0)
            case .timeout:
                VStack {
                    Text("Time-out while loading discover feed")
                    Button("Try again") { streamsVM.reload() }
                }
                .centered()
            }
        }
        .background(theme.listBackground)
        .overlay(alignment: .top) {
            LoadingBar(loadingBarViewState: $speedTest.loadingBarViewState)
        }
        .onAppear {
            guard IS_DESKTOP_COLUMNS() || (selectedTab == "Main" && selectedSubTab == "Streams") else { return }
            streamsVM.load(speedTest: speedTest)
        }
        .onChange(of: selectedSubTab) { newValue in
            guard !IS_DESKTOP_COLUMNS() && newValue == "Streams" else { return }
            streamsVM.load(speedTest: speedTest) // didLoad is checked in .load() so no need here
        }
        .onReceive(receiveNotification(.showFeedToggles)) { _ in
            showSettings = true
        }
        .sheet(isPresented: $showSettings) {
            NBNavigationStack {
                StreamsFeedSettings(streamsVM: streamsVM)
                    .environment(\.theme, theme)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close", systemImage: "xmark") {
                                showSettings = false
                            }
                        }
                    }
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
        }
    }
}

#Preview {
    Streams()
        .environmentObject(StreamsViewModel())
        .environmentObject(Themes.default)
}

@_spi(Advanced) import SwiftUIIntrospect
extension Streams {
    
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
