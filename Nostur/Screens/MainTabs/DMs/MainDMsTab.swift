//
//  MainDMsTab.swift
//  Nostur
//
//  Created by Fabian Lachman on 16/12/2025.
//

import SwiftUI
import NavigationBackport

struct MainDMsTab: View {
    @EnvironmentObject private var la: LoggedInAccount
    @Environment(\.theme) private var theme
    @State private var navPath = NBNavigationPath()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var vm: DMsVM = .shared
    @State private var showSettingsSheet = false
    @State private var showingNewDM = false
    @State private var preloadNewDMInfo: (String, NRContact)? = nil // pubkey and Contact
    
    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        NBNavigationStack(path: $navPath) {
            VStack(spacing: 0) {
                DMsInnerList(pubkey: la.pubkey, navPath: $navPath, vm: vm)
                    .modifier { // need to hide glass bg in 26+
                        if #available(iOS 26.0, *) {
                            $0.toolbar {
                                self.toolbarMenu
                                .sharedBackgroundVisibility(.hidden)
                            }
                        }
                        else {
                            $0.toolbar {
                                self.toolbarMenu
                            }
                        }
                    }
                    .sheet(isPresented: $showSettingsSheet) {
                        NBNavigationStack {
                            DMSettingsSheet(vm: vm)
                                .environment(\.theme, theme)
                        }
                        .nbUseNavigationStack(.whenAvailable) // .never is broken on macCatalyst, showSettings = false will not dismiss  .sheet(isPresented: $showSettings) ..
                        .presentationBackgroundCompat(theme.listBackground)
                    }
                    .sheet(isPresented: $showingNewDM) {
                        NBNavigationStack {
                            NewDM(showingNewDM: $showingNewDM, tab: $vm.tab)
                                .nosturNavBgCompat(theme: theme)
                                .onAppear {
                                    if let preloadNewDMInfo {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                            sendNotification(.preloadNewDMInfo, preloadNewDMInfo)
                                        }
                                    }
                                }
                                .environment(\.theme, theme)
                                .environmentObject(la)
                        }
                        .nbUseNavigationStack(.never)
                        .presentationBackgroundCompat(theme.listBackground)
                    }
                    .onReceive(receiveNotification(.triggerDM)) { notification in
                        let preloadNewDMInfo = notification.object as! (String, NRContact)
                        self.preloadNewDMInfo = preloadNewDMInfo
                        showingNewDM = true
                    }
                    .environmentObject(VideoPostPlaybackCoordinator())
                
                AudioOnlyBarSpace()
            }
            .environmentObject(VideoPostPlaybackCoordinator())
            .background(theme.listBackground) // screen / toolbar background
//            .nosturNavBgCompat(theme: theme) // <-- Needs to be inside navigation stack
            .withNavigationDestinations(navPath: $navPath)
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.containerID, "Messages")
            .simultaneousGesture(TapGesture().onEnded({ _ in
                AppState.shared.containerIDTapped = "Messages"
            }))
            .onReceive(receiveNotification(.navigateTo)) { notification in
                let destination = notification.object as! NavigationDestination
                guard !IS_IPAD || horizontalSizeClass == .compact else { return }
                guard destination.context == "Messages" else { return }
                navPath.append(destination.destination)
            }
            .onReceive(receiveNotification(.clearNavigation)) { notification in
                navPath.removeLast(navPath.count)
            }
            .tabBarSpaceCompat()
        }
        .nbUseNavigationStack(.never)
    }
    
    @ToolbarContentBuilder
    private var toolbarMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Settings", systemImage: "gearshape") {
                showSettingsSheet = true
            }
        }
    }
}
