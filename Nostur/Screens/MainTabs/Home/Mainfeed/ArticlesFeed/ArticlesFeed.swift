//
//  ArticlesFeed.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/09/2023.
//

import SwiftUI
import NavigationBackport

struct ArticlesFeed: View {
    @Environment(\.theme) private var theme
    @ObservedObject var settings:SettingsStore = .shared
    @EnvironmentObject var vm: ArticlesFeedViewModel
    @StateObject private var speedTest = NXSpeedTest()
    @State private var showSettings = false
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Main" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_tab") }
    }
    
    private var selectedSubTab: String {
        get { UserDefaults.standard.string(forKey: "selected_subtab") ?? "Articles" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_subtab") }
    }
    
    @Namespace var top
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ScrollViewReader { proxy in
            if vm.nothingFound {
                Text("No articles found from your follow list in selected time frame.")
                    .multilineTextAlignment(.center)
                    .centered()
            }
            else if vm.articles.isEmpty {
                CenteredProgressView()
            }
            else {
                ScrollView {
                    Color.clear.frame(height: 1).id(top)
                    LazyVStack(spacing: GUTTER) {
                        ForEach(vm.articles) { post in
                            Box(nrPost: post) {
                                PostRowDeletable(nrPost: post, missingReplyTo: true, fullWidth: settings.fullWidthImages)
                            }
                            .id(post.id) // without .id the .ago on posts is wrong, not sure why. NRPost is Identifiable, Hashable, Equatable
//                            .transaction { t in
//                                t.animation = nil
//                            }
                            .onBecomingVisible {
                                // SettingsStore.shared.fetchCounts should be true for below to work
                                vm.prefetch(post)
                            }
                        }
                    }
                    .padding(0)
                    .onReceive(receiveNotification(.shouldScrollToTop)) { _ in
                        guard selectedTab == "Main" && selectedSubTab == "Articles" else { return }
                        withAnimation {
                            proxy.scrollTo(top)
                        }
                    }
                    .onReceive(receiveNotification(.shouldScrollToFirstUnread)) { _ in
                        guard selectedTab == "Main" && selectedSubTab == "Articles" else { return }
                        withAnimation {
                            proxy.scrollTo(top)
                        }
                    }
                    .onReceive(receiveNotification(.activeAccountChanged)) { _ in
                        vm.reload()
                    }
                }
                .refreshable {
                    await vm.refresh()
                }
                .padding(0)
            }
        }
        .background(theme.listBackground)
        .overlay(alignment: .top) {
            LoadingBar(loadingBarViewState: $speedTest.loadingBarViewState)
        }
        .onAppear {
            guard selectedTab == "Main" && selectedSubTab == "Articles" else { return }
            vm.load(speedTest: speedTest)
        }
        .onReceive(receiveNotification(.scenePhaseActive)) { _ in
            guard selectedTab == "Main" && selectedSubTab == "Articles" else { return }
            guard vm.shouldReload else { return }
            vm.articles = []
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { // Reconnect delay
                vm.load(speedTest: speedTest)
            }
        }
        .onChange(of: selectedSubTab) { newValue in
            guard newValue == "Articles" else { return }
            vm.load(speedTest: speedTest) // didLoad is checked in .load() so no need here
        }
        .onReceive(receiveNotification(.showFeedToggles)) { _ in
            showSettings = true
        }
        .sheet(isPresented: $showSettings) {
            NBNavigationStack {
                ArticleFeedSettings(vm: vm)
                    .environment(\.theme, theme)
            }
            .nbUseNavigationStack(.never)
            .presentationBackgroundCompat(theme.listBackground)
        }
    }
}

struct ArticlesFeed_Previews: PreviewProvider {
    static var previews: some View {
        ArticlesFeed()
            .environmentObject(ArticlesFeedViewModel())
            .environmentObject(Themes.default)
    }
}
