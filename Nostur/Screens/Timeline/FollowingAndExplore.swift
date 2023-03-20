//
//  FollowingAndGlobal.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/02/2023.
//

import SwiftUI

struct FollowingAndExplore: View {
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var nav:NavigationModel
    //    @State var timelinePath = NavigationPath()
    //    @State var explorePath = NavigationPath()
    @AppStorage("selected_subtab") var selectedSubTab = "Explore"
    
    var body: some View {
        NavigationStack(path: $nav.mainPath) {
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
                ZStack {
                    switch selectedSubTab {
                        case "Following":
                            ListViewContainer(pubkey: ns.activeAccountPublicKey, pubkeys: ns.followingPublicKeys, listId: "Following", listType: .account)
                                .frame(maxWidth: 600)
                                .opacity(selectedSubTab == "Following" ? 1 : 0)
                            
                        default:
                            if (ns.rawExplorePubkeys.count > 0) {
                                ListViewContainer(pubkey: ns.activeAccountPublicKey, pubkeys: ns.explorePubkeys, listId: "Explore", listType: .explore)
                                    .frame(maxWidth: 600)
                                    .opacity(selectedSubTab == "Explore" ? 1 : 0)
                            }
                            else {
                                CenteredProgressView()
                                    .frame(maxWidth: 600)
                                    .opacity(selectedSubTab == "Explore" ? 1 : 0)
                            }
                    }
                }
                Spacer()
            }
            .withNavigationDestinations()
            .navigationTitle(selectedSubTab)
            .navigationBarHidden(true)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct FollowingAndExplore_Previews: PreviewProvider {
    static var previews: some View {
        FollowingAndExplore()
            .withPreviewEnvironment()
    }
}
