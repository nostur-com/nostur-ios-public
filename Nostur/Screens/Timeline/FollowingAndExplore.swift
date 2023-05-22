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
//        let _ = Self._printChanges()
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
                
                ZStack {
                    // FOLLOWING
                    ListViewContainer(vm: LVMManager.shared.followingLVM(forAccount: account))
                        .opacity(selectedSubTab == "Following" ? 1 : 0)
                    
                    // LISTS
                    ForEach(lists) { list in
                        ListViewContainer(vm: LVMManager.shared.listLVM(forAccount: account, andList: list))
                            .navigationTitle(list.name_)
                            .id(list.subscriptionId)
                            .opacity(selectedSubTab == "List" && list == selectedList ? 1 : 0)
                    }

                    // EXPLORE
                    ListViewContainer(vm: LVMManager.shared.exploreLVM(forAccount: account))
                        .opacity(selectedSubTab == "Explore" ? 1 : 0)
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
        NavigationStack {
            if let account = NosturState.shared.account {
                FollowingAndExplore(account: account)
            }
        }
        .withPreviewEnvironment()
    }
}
