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
    @State private var showNewDMSheet = false
    
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
                                self.newDMbutton
                                    .sharedBackgroundVisibility(.hidden)
                                self.toolbarMenu
                                    .sharedBackgroundVisibility(.hidden)
                            }
                        }
                        else {
                            $0.toolbar {
                                self.newDMbutton
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
                    .sheet(isPresented: $showNewDMSheet) {
                        NBNavigationStack {
                            SelectDMRecipientSheet(accountPubkey: la.pubkey, onSelect: { selectedContactPubkeys in
                                navPath.append(NewDMConversation(accountPubkey: la.pubkey, participants: selectedContactPubkeys.union([la.pubkey])))
                            })
                            .nosturNavBgCompat(theme: theme)
                            .environment(\.theme, theme)
                        }
                        .nbUseNavigationStack(.never)
                        .presentationBackgroundCompat(theme.listBackground)
                    }
                    .onReceive(receiveNotification(.triggerDM)) { notification in
                        let newDMConversation = notification.object as! NewDMConversation
                        navPath.append(newDMConversation)
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
    
    @ToolbarContentBuilder
    private var newDMbutton: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button("New Message", systemImage: "square.and.pencil") {
                guard AccountsState.shared.fullAccounts.contains(where: { $0.publicKey == la.pubkey }) else {
                    showReadOnlyMessage()
                    return
                }
                showNewDMSheet = true
            }
        }
    }
}
