//
//  Hot.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/09/2023.
//

import SwiftUI

struct Hot: View {
    @EnvironmentObject var theme:Theme
    @ObservedObject var settings:SettingsStore = .shared
    @ObservedObject var hotVM:HotViewModel
    
    @AppStorage("selected_tab") var selectedTab = "Main"
    @AppStorage("selected_subtab") var selectedSubTab = "Hot"
    
    @Namespace var top
    
    var body: some View {
        ScrollViewReader { proxy in
            switch hotVM.state {
            case .initializing:
                EmptyView()
            case .loading:
                CenteredProgressView()
                    .task(id: "hot") {
                        do {
                            try await Task.sleep(
                                until: .now + .seconds(hotVM.timeoutSeconds),
                                tolerance: .seconds(2),
                                clock: .continuous
                            )
                            hotVM.timeout()
                        } catch {
                            
                        }
                    }
            case .ready:
                ScrollView {
                    Color.clear.frame(height: 1).id(top)
                    LazyVStack(spacing: 10) {
                        ForEach(hotVM.hotPosts) { post in
                            Box(nrPost: post) {
                                PostRowDeletable(nrPost: post, missingReplyTo: true, fullWidth: settings.fullWidthImages)
                            }
                            .id(post.id) // without .id the .ago on posts is wrong, not sure why. NRPost is Identifiable, Hashable, Equatable
                            .transaction { t in
                                t.animation = nil
                            }
                            .onBecomingVisible {
                                // SettingsStore.shared.fetchCounts should be true for below to work
                                hotVM.prefetch(post)
                            }
                        }
                    }
                    .padding(0)
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
        .background(theme.listBackground)
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
    }
}

struct Hot_Previews: PreviewProvider {
    static var previews: some View {
        Hot(hotVM: HotViewModel())
            .environmentObject(Theme.default)
    }
}
