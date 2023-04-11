//
//  FollowingAndGlobal.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/02/2023.
//

import SwiftUI

struct FollowingAndExplore: View { //, Equatable {
    
    @ObservedObject var account:Account
    @EnvironmentObject var ns:NosturState
    @AppStorage("selected_tab") var selectedTab = "Main"
    @AppStorage("selected_subtab") var selectedSubTab = "Following"
    
    @State var showingNewNote = false
    @State var noteCancellationId:UUID?
    
    var body: some View {
        let _ = Self._printChanges()
            VStack {
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
                        if account.followingPublicKeys.count > 0 {
                            ListViewContainer(vm: LVMManager.shared.followingLVM(forAccount: account))
//                            ListViewContainer(pubkey: ns.activeAccountPublicKey, pubkeys: ns.followingPublicKeys, listId: "Following", listType: .account)
//                                .equatable()
                        }
                        else {
                            ProgressView()
                        }
                    case "Explore":
                        if ns.rawExplorePubkeys.count > 0 {
                          ListViewContainer(vm: LVMManager.shared.exploreLVM(forAccount: account))
//                            ListViewContainer(pubkey: ns.activeAccountPublicKey, pubkeys: ns.explorePubkeys, listId: "Explore", listType: .explore)
//                                .equatable()
                        }
                        else {
                            ProgressView()
                        }
                    default:
                        Text("🥪")


                }
                Spacer()
            }
//            .withNavigationDestinations()
            .navigationTitle(selectedSubTab)
            .navigationBarHidden(true)
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct FollowingAndExplore_Previews: PreviewProvider {
    static var previews: some View {
        if let account = PreviewFetcher.fetchAccount() {
            FollowingAndExplore(account: account)
                .withPreviewEnvironment()
        }
    }
}
