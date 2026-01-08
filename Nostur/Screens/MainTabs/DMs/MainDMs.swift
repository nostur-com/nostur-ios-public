//
//  DMs.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/09/2023.
//

import SwiftUI
import Combine
import NavigationBackport

struct MainDMs: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.theme) private var theme
    @EnvironmentObject var la: LoggedInAccount
    
    @Binding var navPath: NBNavigationPath
    @ObservedObject private var vm: DMsVM = .shared
    @State private var showSettingsSheet = false
    @State private var showNewDMSheet = false

    
    var body: some View {
        VStack(spacing: 0) {
            DMsInnerList(pubkey: la.pubkey, navPath: $navPath, vm: vm)
                .navigationTitle("Messages")
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
                            navPath.append(NewDMConversation(accountPubkey: la.pubkey, participants: selectedContactPubkeys.union([la.pubkey]), parentDMsVM: vm))
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
            
                
            
            AudioOnlyBarSpace()
        }
        .environment(\.containerID, "Messages")
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
