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
    @State private var showingNewDM = false
    @State private var preloadNewDMInfo: (String, NRContact)? = nil // pubkey and Contact

    
    var body: some View {
        VStack(spacing: 0) {
            DMsInnerList(pubkey: la.pubkey, navPath: $navPath, vm: vm)
                .navigationTitle("Messages")
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
}
