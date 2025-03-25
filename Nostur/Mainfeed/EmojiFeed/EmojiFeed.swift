//
//  EmojiFeed.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/09/2023.
//

import SwiftUI
import NavigationBackport

struct EmojiFeed: View {
    @EnvironmentObject private var themes: Themes
    @ObservedObject var settings: SettingsStore = .shared
    @EnvironmentObject var vm: EmojiFeedViewModel
    @StateObject private var speedTest = NXSpeedTest()
    @State private var showSettings = false
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Main" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_tab") }
    }
    
    private var selectedSubTab: String {
        get { UserDefaults.standard.string(forKey: "selected_subtab") ?? "Emoji" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_subtab") }
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ScrollViewReader { proxy in
            switch vm.state {
            case .initializing, .loading:
                CenteredProgressView()
                    .task(id: "emoji") {
                        do {
                            try await Task.sleep(nanoseconds: UInt64(vm.timeoutSeconds) * NSEC_PER_SEC)
                            vm.timeout()
                        } catch { }
                    }
            case .ready:
                List(vm.feedPosts) { nrPost in
                    ZStack { // <-- added because "In Lists, the Top-Level Structure Type _ConditionalContent Can Break Lazy Loading" (https://fatbobman.com/en/posts/tips-and-considerations-for-using-lazy-containers-in-swiftui/)
                        PostOrThread(nrPost: nrPost)
                            .onBecomingVisible {
                                // SettingsStore.shared.fetchCounts should be true for below to work
                                vm.prefetch(nrPost)
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
                    await vm.refresh()
                }
                .onReceive(receiveNotification(.shouldScrollToTop)) { _ in
                    guard selectedTab == "Main" && selectedSubTab == "Emoji" else { return }
                    self.scrollToTop(proxy)
                }
                .onReceive(receiveNotification(.shouldScrollToFirstUnread)) { _ in
                    guard selectedTab == "Main" && selectedSubTab == "Emoji" else { return }
                    self.scrollToTop(proxy)
                }
                .onReceive(receiveNotification(.activeAccountChanged)) { _ in
                    vm.reload()
                }
                .padding(0)
            case .timeout:
                VStack {
                    Spacer()
                    Text("Time-out while loading feed")
                    Button("Try again") { vm.reload() }
                    Spacer()
                }
            }
        }
        .background(themes.theme.listBackground)
        .overlay(alignment: .top) {
            LoadingBar(loadingBarViewState: $speedTest.loadingBarViewState)
        }
        .onAppear {
            guard selectedTab == "Main" && selectedSubTab == "Emoji" else { return }
            vm.load(speedTest: speedTest)
        }
        .onReceive(receiveNotification(.scenePhaseActive)) { _ in
            guard !IS_CATALYST else { return }
            guard selectedTab == "Main" && selectedSubTab == "Emoji" else { return }
            guard vm.shouldReload else { return }
            vm.state = .loading
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { // Reconnect delay
                vm.load(speedTest: speedTest)
            }
        }
        .onChange(of: selectedSubTab) { newValue in
            guard newValue == "Emoji" else { return }
            vm.load(speedTest: speedTest) // didLoad is checked in .load() so no need here
        }
        .onReceive(receiveNotification(.showFeedToggles)) { _ in
            showSettings = true
        }
        .sheet(isPresented: $showSettings) {
            NBNavigationStack {
                EmojiFeedSettings(vm: vm)
                    .environmentObject(themes)
            }
            .nbUseNavigationStack(.never)
        }
    }
    
    private func scrollToTop(_ proxy: ScrollViewProxy) {
        guard let topPost = vm.feedPosts.first else { return }
        withAnimation {
            proxy.scrollTo(topPost.id, anchor: .top)
        }
    }
}

struct EmojiFeed_Previews: PreviewProvider {
    static var previews: some View {
        EmojiFeed()
            .environmentObject(EmojiFeedViewModel())
            .environmentObject(Themes.default)
    }
}
