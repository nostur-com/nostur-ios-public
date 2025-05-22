//
//  Zapped.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/03/2025.
//

import SwiftUI
import NavigationBackport

struct Zapped: View {
    @EnvironmentObject private var themes: Themes
    @ObservedObject var settings: SettingsStore = .shared
    @EnvironmentObject var zappedVM: ZappedViewModel
    @StateObject private var speedTest = NXSpeedTest()
    @State private var showSettings = false
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Main" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_tab") }
    }
    
    private var selectedSubTab: String {
        get { UserDefaults.standard.string(forKey: "selected_subtab") ?? "Zapped" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_subtab") }
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ScrollViewReader { proxy in
            switch zappedVM.state {
            case .initializing, .loading:
                CenteredProgressView()
            case .ready:
                List {
                    self.topAnchor
                    
                    ForEach(zappedVM.zappedPosts) { nrPost in
                        ZStack { // <-- added because "In Lists, the Top-Level Structure Type _ConditionalContent Can Break Lazy Loading" (https://fatbobman.com/en/posts/tips-and-considerations-for-using-lazy-containers-in-swiftui/)
                            PostOrThread(nrPost: nrPost)
                                .onBecomingVisible {
                                    // SettingsStore.shared.fetchCounts should be true for below to work
                                    zappedVM.prefetch(nrPost)
                                }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(themes.theme.listBackground)
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                }
                .environment(\.defaultMinListRowHeight, 0)
                .listStyle(.plain)
                .refreshable {
                    await zappedVM.refresh()
                }
                .onReceive(receiveNotification(.shouldScrollToTop)) { _ in
                    guard selectedTab == "Main" && selectedSubTab == "Zapped" else { return }
                    self.scrollToTop(proxy)
                }
                .onReceive(receiveNotification(.shouldScrollToFirstUnread)) { _ in
                    guard selectedTab == "Main" && selectedSubTab == "Zapped" else { return }
                    self.scrollToTop(proxy)
                }
                .onReceive(receiveNotification(.activeAccountChanged)) { _ in
                    zappedVM.reload()
                }
                .padding(0)
            case .timeout:
                VStack {
                    Text("Time-out while loading hot feed")
                    Button("Try again") { zappedVM.reload() }
                }
                .centered()
            }
        }
        .background(themes.theme.listBackground)
        .overlay(alignment: .top) {
            LoadingBar(loadingBarViewState: $speedTest.loadingBarViewState)
        }
        .onAppear {
            guard selectedTab == "Main" && selectedSubTab == "Zapped" else { return }
            zappedVM.load(speedTest: speedTest)
        }
        .onReceive(receiveNotification(.scenePhaseActive)) { _ in
            guard !IS_CATALYST else { return }
            guard selectedTab == "Main" && selectedSubTab == "Zapped" else { return }
            guard zappedVM.shouldReload else { return }
            zappedVM.state = .loading
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { // Reconnect delay
                zappedVM.load(speedTest: speedTest)
            }
        }
        .onChange(of: selectedSubTab) { newValue in
            guard newValue == "Zapped" else { return }
            zappedVM.load(speedTest: speedTest) // didLoad is checked in .load() so no need here
        }
        .onReceive(receiveNotification(.showFeedToggles)) { _ in
            showSettings = true
        }
        .sheet(isPresented: $showSettings) {
            NBNavigationStack {
                ZappedFeedSettings(zappedVM: zappedVM)
                    .environmentObject(themes)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(themes.theme.listBackground)
        }
    }
    
    @ViewBuilder
    var topAnchor: some View {
        Color.clear
            .listRowSeparator(.hidden)
            .listRowBackground(themes.theme.listBackground)
            .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
            .frame(height: 0)
            .id("top")
    }
    
    private func scrollToTop(_ proxy: ScrollViewProxy) {
        guard zappedVM.zappedPosts.first != nil else { return }
        withAnimation {
            proxy.scrollTo("top", anchor: .top)
        }
    }
}

struct Zapped_Previews: PreviewProvider {
    static var previews: some View {
        Zapped()
            .environmentObject(ZappedViewModel())
            .environmentObject(Themes.default)
    }
}
