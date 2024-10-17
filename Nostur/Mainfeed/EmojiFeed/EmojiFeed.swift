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
    @State private var showSettings = false
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Main" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_tab") }
    }
    
    private var selectedSubTab: String {
        get { UserDefaults.standard.string(forKey: "selected_subtab") ?? "Emoji" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_subtab") }
    }
    
    @Namespace private var top
    
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
                ScrollView {
                    Color.clear.frame(height: 1).id(top)
                    if !vm.feedPosts.isEmpty {
                        LazyVStack(spacing: GUTTER) {
                            ForEach(vm.feedPosts) { post in
                                Box(nrPost: post) {
                                    PostRowDeletable(nrPost: post, missingReplyTo: true, fullWidth: settings.fullWidthImages, theme: themes.theme)
                                }
                                .id(post.id) // without .id the .ago on posts is wrong, not sure why. NRPost is Identifiable, Hashable, Equatable
//                                .transaction { t in
//                                    t.animation = nil
//                                }
                                .onBecomingVisible {
                                    // SettingsStore.shared.fetchCounts should be true for below to work
                                    vm.prefetch(post)
                                }
                            }
                        }
                        .padding(0)
                    }
                    else {
                        Button("Refresh") { vm.reload() }
                            .centered()
                    }
                }
                .refreshable {
                    await vm.refresh()
                }
                .onReceive(receiveNotification(.shouldScrollToTop)) { _ in
                    guard selectedTab == "Main" && selectedSubTab == "Emoji" else { return }
                    withAnimation {
                        proxy.scrollTo(top)
                    }
                }
                .onReceive(receiveNotification(.shouldScrollToFirstUnread)) { _ in
                    guard selectedTab == "Main" && selectedSubTab == "Emoji" else { return }
                    withAnimation {
                        proxy.scrollTo(top)
                    }
                }
                .onReceive(receiveNotification(.activeAccountChanged)) { _ in
                    vm.reload()
                }
                .padding(0)
            case .timeout:
                VStack {
                    Spacer()
                    Text("Time-out while loading hot feed")
                    Button("Try again") { vm.reload() }
                    Spacer()
                }
            }
        }
        .background(themes.theme.listBackground)
        .onAppear {
            guard selectedTab == "Main" && selectedSubTab == "Emoji" else { return }
            vm.load()
        }
        .onReceive(receiveNotification(.scenePhaseActive)) { _ in
            guard !IS_CATALYST else { return }
            guard selectedTab == "Main" && selectedSubTab == "Emoji" else { return }
            guard vm.shouldReload else { return }
            vm.state = .loading
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { // Reconnect delay
                vm.load()
            }
        }
        .onChange(of: selectedSubTab) { newValue in
            guard newValue == "Emoji" else { return }
            vm.load() // didLoad is checked in .load() so no need here
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
}

struct EmojiFeed_Previews: PreviewProvider {
    static var previews: some View {
        EmojiFeed()
            .environmentObject(EmojiFeedViewModel())
            .environmentObject(Themes.default)
    }
}
