//
//  Discover.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/06/2024.
//

import SwiftUI
import NavigationBackport

struct Discover: View {
    @Environment(\.theme) private var theme
    @ObservedObject var settings: SettingsStore = .shared
    @EnvironmentObject var discoverVM: DiscoverViewModel
    @StateObject private var speedTest = NXSpeedTest()
    @State private var showSettings = false
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Main" }
        set { setSelectedTab(newValue) }
    }
    
    private var selectedSubTab: String {
        get { UserDefaults.standard.string(forKey: "selected_subtab") ?? "Discover" }
        set { setSelectedSubTab(newValue) }
    }
    
    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        ScrollViewReader { proxy in
            switch discoverVM.state {
            case .initializing, .loading:
                CenteredProgressView()
                    .task(id: "discover") {
                        do {
                            try await Task.sleep(nanoseconds: UInt64(discoverVM.timeoutSeconds) * NSEC_PER_SEC)
                            Task { @MainActor in
                                if discoverVM.discoverPosts.isEmpty {
                                    discoverVM.timeout()
                                }
                            }
                        } catch { }
                    }
            case .ready:
                List {
                    self.topAnchor
                    
                    ForEach(discoverVM.discoverPosts) { nrPost in
                        ZStack { // <-- added because "In Lists, the Top-Level Structure Type _ConditionalContent Can Break Lazy Loading" (https://fatbobman.com/en/posts/tips-and-considerations-for-using-lazy-containers-in-swiftui/)
                            PostOrThread(nrPost: nrPost, theme: theme)
                                .task {
                                    // SettingsStore.shared.fetchCounts should be true for below to work
                                    discoverVM.prefetch(nrPost)
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
                    await discoverVM.refresh()
                }
                .onReceive(receiveNotification(.shouldScrollToTop)) { _ in
                    guard selectedTab == "Main" && selectedSubTab == "Discover" else { return }
                    self.scrollToTop(proxy)
                }
                .onReceive(receiveNotification(.shouldScrollToFirstUnread)) { _ in
                    guard selectedTab == "Main" && selectedSubTab == "Discover" else { return }
                    self.scrollToTop(proxy)
                }
                .onReceive(receiveNotification(.activeAccountChanged)) { _ in
                    discoverVM.reload()
                }
                .padding(0)
            case .timeout:
                VStack {
                    Text("Time-out while loading discover feed")
                    Button("Try again") { discoverVM.reload() }
                }
                .centered()
            }
        }
        .background(theme.listBackground)
        .overlay(alignment: .top) {
            LoadingBar(loadingBarViewState: $speedTest.loadingBarViewState)
        }
        .onAppear {
            guard IS_DESKTOP_COLUMNS() || (selectedTab == "Main" && selectedSubTab == "Discover") else { return }
            discoverVM.load(speedTest: speedTest)
        }
        .onReceive(receiveNotification(.scenePhaseActive)) { _ in
            guard !IS_CATALYST else { return }
            guard selectedTab == "Main" && selectedSubTab == "Discover" else { return }
            guard discoverVM.shouldReload else { return }
            discoverVM.state = .loading
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { // Reconnect delay
                discoverVM.load(speedTest: speedTest)
            }
        }
        .onChange(of: selectedSubTab) { newValue in
            guard newValue == "Discover" else { return }
            discoverVM.load(speedTest: speedTest) // didLoad is checked in .load() so no need here
        }
        .onReceive(receiveNotification(.showFeedToggles)) { _ in
            showSettings = true
        }
        .sheet(isPresented: $showSettings) {
            NBNavigationStack {
                DiscoverFeedSettings(discoverVM: discoverVM)
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
    
    @ViewBuilder
    var topAnchor: some View {
        Color.clear
            .listRowSeparator(.hidden)
            .listRowBackground(theme.listBackground)
            .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
            .frame(height: 0)
            .id("top")
    }
    
    private func scrollToTop(_ proxy: ScrollViewProxy) {
        guard discoverVM.discoverPosts.first != nil else { return }
        withAnimation {
            proxy.scrollTo("top", anchor: .top)
        }
    }
}

struct Discover_Previews: PreviewProvider {
    static var previews: some View {
        Discover()
            .environmentObject(DiscoverViewModel())
            .environmentObject(Themes.default)
    }
}
