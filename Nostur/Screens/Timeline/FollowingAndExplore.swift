//
//  FollowingAndGlobal.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/02/2023.
//

import SwiftUI

struct FollowingAndExplore: View { //, Equatable {
    @EnvironmentObject var dim:DIMENSIONS
    @ObservedObject var account:Account
    @EnvironmentObject var ns:NosturState
    @AppStorage("selected_tab") var selectedTab = "Main"
    @AppStorage("selected_subtab") var selectedSubTab = "Following"
    @AppStorage("selected_listId") var selectedListId = ""
    
    @State var showingNewNote = false
    @State var noteCancellationId:UUID?
    
    @FetchRequest
    var lists:FetchedResults<NosturList>
    @State var selectedList:NosturList?
    
    init(account:Account) {
        self.account = account
        let r = NosturList.fetchRequest()
        r.predicate = NSPredicate(format: "showAsTab == true")
        r.sortDescriptors = [NSSortDescriptor(keyPath:\NosturList.createdAt, ascending: false)]
        _lists = FetchRequest(fetchRequest: r)
    }
    
    var body: some View {
        let _ = Self._printChanges()
            VStack(spacing:0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing:0) {
                        TabButton(
                            action: { selectedSubTab = "Following" },
                            title: "Following",
                            selected: selectedSubTab == "Following")
                        Spacer()
                        ForEach(lists) { list in
                            TabButton(
                                action: {
                                    selectedSubTab = "List"
                                    selectedList = list
                                    selectedListId = list.subscriptionId
                                },
                                title: list.name_,
                                selected: selectedSubTab == "List" && selectedList == list )
                            Spacer()
                        }
                        TabButton(
                            action: { selectedSubTab = "Explore"},
                            title: "Explore",
                            selected: selectedSubTab == "Explore")
                    }
                    .frame(width: dim.listWidth)
                }
                switch selectedSubTab {
                    case "Following":
                        if account.followingPublicKeys.count > 0 {
                            ListViewContainer(vm: LVMManager.shared.followingLVM(forAccount: account))
                        }
                        else {
                            ProgressView()
                                .centered()
                        }
                    case "Explore":
                        if ns.rawExplorePubkeys.count > 0 {
                          ListViewContainer(vm: LVMManager.shared.exploreLVM(forAccount: account))
                        }
                        else {
                            ProgressView()
                                .centered()
                        }
                    case "List":
                        if let list = selectedList {
                            ListViewContainer(vm: LVMManager.shared.listLVM(forAccount: account, andList: list))
                                .navigationTitle(list.name_)
                                .id(list.subscriptionId)
                        }
                        else {
                            ProgressView()
                                .centered()
                        }
                    default:
                        Text("🥪")
                            .centered()


                }
            }
            .onAppear {
                if selectedSubTab == "List" {
                    if let list = lists.first(where: { $0.subscriptionId == selectedListId }) {
                        selectedList = list
                    }
                    else {
                        selectedList = lists.first
                    }
                }
            }
            .navigationTitle(selectedSubTab)
//            .navigationBarHidden(true)
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct FollowingAndExplore_Previews: PreviewProvider {
    static var previews: some View {
        if let account = NosturState.shared.account {
            NavigationStack {
                FollowingAndExplore(account: account)
            }
            .withPreviewEnvironment()
        }
    }
}
