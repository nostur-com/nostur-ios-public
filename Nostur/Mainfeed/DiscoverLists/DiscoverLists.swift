//
//  DiscoverLists.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/04/2025.
//

import SwiftUI
import NavigationBackport

struct DiscoverLists: View {
    @EnvironmentObject private var themes: Themes
    @ObservedObject var settings: SettingsStore = .shared
    @EnvironmentObject var discoverListsVM: DiscoverListsViewModel
    @StateObject private var speedTest = NXSpeedTest()
    @State private var showSettings = false
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Main" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_tab") }
    }
    
    private var selectedSubTab: String {
        get { UserDefaults.standard.string(forKey: "selected_subtab") ?? "DiscoverLists" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_subtab") }
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ScrollViewReader { proxy in
            switch discoverListsVM.state {
            case .initializing, .loading:
                CenteredProgressView()
                    .task(id: "discoverLists") {
                        do {
                            try await Task.sleep(nanoseconds: UInt64(8) * NSEC_PER_SEC)
                            discoverListsVM.timeout()
                        } catch { }
                    }
            case .ready:
                List(discoverListsVM.discoverLists) { nrPost in
                    ZStack { // <-- added because "In Lists, the Top-Level Structure Type _ConditionalContent Can Break Lazy Loading" (https://fatbobman.com/en/posts/tips-and-considerations-for-using-lazy-containers-in-swiftui/)
                        Box(nrPost: nrPost, theme: themes.theme) {
                            PostRowDeletable(nrPost: nrPost, isDetail: false, theme: themes.theme)
                        }
                    }
                    .id(nrPost.id) // <-- must use .id or can't .scrollTo
                    .listRowSeparator(.hidden)
                    .listRowBackground(themes.theme.listBackground)
                    .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
                .environment(\.defaultMinListRowHeight, 50)
                .listStyle(.plain)
                .refreshable {
                    await discoverListsVM.refresh()
                }
                .onReceive(receiveNotification(.shouldScrollToTop)) { _ in
                    guard selectedTab == "Main" && selectedSubTab == "DiscoverLists" else { return }
                    self.scrollToTop(proxy)
                }
                .onReceive(receiveNotification(.shouldScrollToFirstUnread)) { _ in
                    guard selectedTab == "Main" && selectedSubTab == "DiscoverLists" else { return }
                    self.scrollToTop(proxy)
                }
                .onReceive(receiveNotification(.activeAccountChanged)) { _ in
                    discoverListsVM.reload()
                }
                .padding(0)
            case .timeout:
                VStack {
                    Spacer()
                    Text("Time-out while loading discover feed")
                    Button("Try again") { discoverListsVM.reload() }
                    Spacer()
                }
            }
        }
        .background(themes.theme.listBackground)
        .overlay(alignment: .top) {
            LoadingBar(loadingBarViewState: $speedTest.loadingBarViewState)
        }
        .onAppear {
            guard selectedTab == "Main" && selectedSubTab == "DiscoverLists" else { return }
            discoverListsVM.load(speedTest: speedTest)
        }
        .onChange(of: selectedSubTab) { newValue in
            guard newValue == "DiscoverLists" else { return }
            discoverListsVM.load(speedTest: speedTest) // didLoad is checked in .load() so no need here
        }
        .onReceive(receiveNotification(.showFeedToggles)) { _ in
            showSettings = true
        }
        .sheet(isPresented: $showSettings) {
            NBNavigationStack {
                DiscoverListsFeedSettings(discoverListsVM: discoverListsVM)
                    .environmentObject(themes)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(themes.theme.listBackground)
        }
    }
    
    private func scrollToTop(_ proxy: ScrollViewProxy) {
        guard let topPost = discoverListsVM.discoverLists.first else { return }
        withAnimation {
            proxy.scrollTo(topPost.id, anchor: .top)
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
