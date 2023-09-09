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
            ScrollView {
                if hotVM.hotPosts.isEmpty {
                    CenteredProgressView()
                }
                else {
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
                        }
                    }
                    .padding(0)
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
                }
            }
            .padding(0)
        }
        .background(theme.listBackground)
        .onAppear {
            guard selectedTab == "Main" && selectedSubTab == "Hot" else { return }
            hotVM.load()
        }
        .onReceive(receiveNotification(.scenePhaseActive)) { _ in
            guard selectedTab == "Main" && selectedSubTab == "Hot" else { return }
            hotVM.hotPosts = []
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { // Reconnect delay
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


