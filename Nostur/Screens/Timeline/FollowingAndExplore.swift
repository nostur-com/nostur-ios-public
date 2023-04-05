//
//  FollowingAndGlobal.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/02/2023.
//

import SwiftUI

struct FollowingAndExplore: View, Equatable {
    
    static func == (lhs: FollowingAndExplore, rhs: FollowingAndExplore) -> Bool {
        lhs.selectedSubTab == rhs.selectedSubTab
    }
    
    @EnvironmentObject var ns:NosturState
    @State var navPath = NavigationPath()
    @AppStorage("selected_tab") var selectedTab = "Main"
    @AppStorage("selected_subtab") var selectedSubTab = "Explore"
    
    @State var showingNewNote = false
    @State var noteCancellationId:UUID?
    
    var body: some View {
        let _ = Self._printChanges()
        NavigationStack(path: $navPath) {
            VStack {
                AppTopBar()
                    .padding(5)
                
                HStack {
                    TabButton(
                        action: { selectedSubTab = "Following" },
                        title: "Following",
                        selected: selectedSubTab == "Following")
                    
                    TabButton(
                        action: { selectedSubTab = "Explore"},
                        title: "Explore",
                        selected: selectedSubTab == "Explore")
                }
                
                switch selectedSubTab {
                    case "Following":
                        if ns.followingPublicKeys.count > 0 {
                            ListViewContainer(pubkey: ns.activeAccountPublicKey, pubkeys: ns.followingPublicKeys, listId: "Following", listType: .account)
                                .equatable()
                        }
                        else {
                            ProgressView()
                        }
                    case "Explore":
                        if ns.rawExplorePubkeys.count > 0 {
                            ListViewContainer(pubkey: ns.activeAccountPublicKey, pubkeys: ns.explorePubkeys, listId: "Explore", listType: .explore)
                                .equatable()
                        }
                        else {
                            ProgressView()
                        }
                    default:
                        Text("🥪")
                        
                        
                }
                Spacer()
            }
            .withNavigationDestinations()
            .navigationTitle(selectedSubTab)
            .navigationBarHidden(true)
            .navigationBarTitleDisplayMode(.inline)
        }
        .onReceive(receiveNotification(.navigateTo)) { notification in
            let destination = notification.object as! NavigationDestination
            guard !IS_IPAD else { return }
            guard selectedTab == "Main" else { return }
            navPath.append(destination.destination)
        }
        .onReceive(receiveNotification(.navigateToOnMain)) { notification in
            let destination = notification.object as! NavigationDestination
            navPath.append(destination.destination)
        }
        .onReceive(receiveNotification(.clearNavigation)) { notification in
            navPath.removeLast(navPath.count)
        }
    }
}
