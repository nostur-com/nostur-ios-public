//
//  Hot.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/09/2023.
//

import SwiftUI
import NavigationBackport

struct Hot: View {
    @EnvironmentObject private var themes: Themes
    @ObservedObject var settings: SettingsStore = .shared
    @EnvironmentObject var hotVM: HotViewModel
    @State private var showSettings = false
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Main" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_tab") }
    }
    
    private var selectedSubTab: String {
        get { UserDefaults.standard.string(forKey: "selected_subtab") ?? "Hot" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_subtab") }
    }
    
    @Namespace private var top
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ScrollViewReader { proxy in
            switch hotVM.state {
            case .initializing, .loading:
                CenteredProgressView()
                    .task(id: "hot") {
                        do {
                            try await Task.sleep(nanoseconds: UInt64(hotVM.timeoutSeconds) * NSEC_PER_SEC)
                            hotVM.timeout()
                        } catch { }
                    }
            case .ready:
                ScrollView {
                    Color.clear.frame(height: 1).id(top)
                    if !hotVM.hotPosts.isEmpty {
                        LazyVStack(spacing: GUTTER) {
                            ForEach(hotVM.hotPosts) { post in
                                Box(nrPost: post) {
                                    PostRowDeletable(nrPost: post, missingReplyTo: true, fullWidth: settings.fullWidthImages, theme: themes.theme)
                                }
                                .fixedSize(horizontal: false, vertical: true) // <--  seems to fix missing text (truncated because no space maybe?) Seems to be needed in LazyVStack but not in List 
                                .id(post.id) // without .id the .ago on posts is wrong, not sure why. NRPost is Identifiable, Hashable, Equatable
//                                .transaction { t in
//                                    t.animation = nil
//                                }
                                .onBecomingVisible {
                                    // SettingsStore.shared.fetchCounts should be true for below to work
                                    hotVM.prefetch(post)
                                }
                            }
                        }
                        .padding(0)
                    }
                    else {
                        Button("Refresh") { hotVM.reload() }
                            .centered()
                    }
                }
                .refreshable {
                    await hotVM.refresh()
                }
                .onReceive(receiveNotification(.shouldScrollToTop)) { _ in
                    guard selectedTab == "Main" && selectedSubTab == "Hot" else { return }
                    withAnimation {
                        proxy.scrollTo(top)
                    }
                }
                .onReceive(receiveNotification(.shouldScrollToFirstUnread)) { _ in
                    guard selectedTab == "Main" && selectedSubTab == "Hot" else { return }
                    withAnimation {
                        proxy.scrollTo(top)
                    }
                }
                .onReceive(receiveNotification(.activeAccountChanged)) { _ in
                    hotVM.reload()
                }
                .padding(0)
            case .timeout:
                VStack {
                    Spacer()
                    Text("Time-out while loading hot feed")
                    Button("Try again") { hotVM.reload() }
                    Spacer()
                }
            }
        }
        .background(themes.theme.listBackground)
        .onAppear {
            guard selectedTab == "Main" && selectedSubTab == "Hot" else { return }
            hotVM.load()
        }
        .onReceive(receiveNotification(.scenePhaseActive)) { _ in
            guard !IS_CATALYST else { return }
            guard selectedTab == "Main" && selectedSubTab == "Hot" else { return }
            guard hotVM.shouldReload else { return }
            hotVM.state = .loading
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { // Reconnect delay
                hotVM.load()
            }
        }
        .onChange(of: selectedSubTab) { newValue in
            guard newValue == "Hot" else { return }
            hotVM.load() // didLoad is checked in .load() so no need here
        }
        .onReceive(receiveNotification(.showFeedToggles)) { _ in
            showSettings = true
        }
        .sheet(isPresented: $showSettings) {
            NBNavigationStack {
                HotFeedSettings(hotVM: hotVM)
                    .environmentObject(themes)
            }
            .nbUseNavigationStack(.never)
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
