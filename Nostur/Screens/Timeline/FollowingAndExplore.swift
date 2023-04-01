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
    @AppStorage("selected_subtab") var selectedSubTab = "Explore"
    
    @State var showingNewNote = false
    @State var noteCancellationId:UUID?
    
    var body: some View {
        let _ = Self._printChanges()
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
                
                
                //                Picker(selection: $selectedSubTab, label: Text("List")) {
                //                    Text("Following").tag("Following")
                //                    Text("Explore").tag("Explore")
                //                }
                //                .pickerStyle(.segmented)
                
                switch selectedSubTab {
                    case "Following":
                        if ns.followingPublicKeys.count > 0 {
                            ListViewContainer(pubkey: ns.activeAccountPublicKey, pubkeys: ns.followingPublicKeys, listId: "Following", listType: .account)
                        }
                        else {
                            ProgressView()
                        }
                    case "Explore":
                        if ns.rawExplorePubkeys.count > 0 {
                            ListViewContainer(pubkey: ns.activeAccountPublicKey, pubkeys: ns.explorePubkeys, listId: "Explore", listType: .explore)
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
            //            .onChange(of: selectedSubTab) { listId in
            //
            //            }
        }
    }
}

struct FollowingAndExplore_Previews: PreviewProvider {
    static var previews: some View {
        FollowingAndExplore()
            .withPreviewEnvironment()
    }
}
