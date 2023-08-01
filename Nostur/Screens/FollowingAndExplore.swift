//
//  FollowingAndExplore.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/02/2023.
//

import SwiftUI
import Combine

struct FollowingAndExplore: View {
    @EnvironmentObject var dim:DIMENSIONS
    @ObservedObject var account:Account
    @ObservedObject var ss:SettingsStore = .shared
    @AppStorage("selected_tab") var selectedTab = "Main"
    @AppStorage("selected_subtab") var selectedSubTab = "Following"
    @AppStorage("selected_listId") var selectedListId = ""
    
    @State var showingNewNote = false
    @State var noteCancellationId:UUID?
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath:\NosturList.createdAt, ascending: false)], predicate: NSPredicate(format: "showAsTab == true"))
    var lists:FetchedResults<NosturList>
    @State private var selectedList:NosturList?
    @StateObject private var exploreVM:LVM = LVMManager.shared.exploreLVM()
    
    @State var tabsOffsetY:CGFloat = 0.0
    
    var navigationTitle:String {
        if selectedSubTab == "List" {
            return (selectedList?.name_ ?? String(localized:"List"))
        }
        if selectedSubTab == "Following" {
            return String(localized:"Following", comment:"Tab title for feed of people you follow")
        }
        if selectedSubTab == "Explore" {
            return String(localized:"Explore", comment:"Tab title for the Explore feed")
        }
        return String(localized:"Feed", comment:"Tab title for a feed")
    }
    
    @State var showFeedSettings = false
    
    var body: some View {
        //        let _ = Self._printChanges()
        VStack(spacing:0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing:0) {
                    TabButton(
                        action: { selectedSubTab = "Following" },
                        title: String(localized:"Following", comment:"Tab title for feed of people you follow"),
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
                        title: String(localized:"Explore", comment:"Tab title for the Explore feed"),
                        selected: selectedSubTab == "Explore")
                }
                .frame(width: dim.listWidth, height: max(36.0 + tabsOffsetY,0))
                .offset(y: tabsOffsetY)
                .onReceive(receiveNotification(.scrollingUp)) { _ in
                    guard !IS_CATALYST && ss.autoHideBars else { return }
                    withAnimation {
                        tabsOffsetY = 0.0
                    }
                }
                .onReceive(receiveNotification(.scrollingDown)) { _ in
                    guard !IS_CATALYST  && ss.autoHideBars else { return }
                    withAnimation {
                        tabsOffsetY = -36.0
                    }
                }
                .toolbar(IS_CATALYST || tabsOffsetY == 0.0 ? .visible : .hidden)
            }
            
            ZStack {
                // FOLLOWING
                if (account.followingPublicKeys.count <= 1) {
                    VStack {
                        Spacer()
                        Text("You are not following anyone yet, visit the explore tab and follow some people")
                            .multilineTextAlignment(.center)
                            .padding(.all, 30.0)
                        
                        Button {
                            selectedSubTab = "Explore"
                        } label: {
                            Text("Explore", comment: "Button to go to the Explore tab")
                        }.buttonStyle(.borderedProminent)
                        Spacer()
                    }
                }
                else {
                    ListViewContainer(vm: LVMManager.shared.followingLVM(forAccount: account))
                        .opacity(selectedSubTab == "Following" ? 1 : 0)
                }
                
                // LISTS
                ForEach(lists) { list in
                    ListViewContainer(vm: LVMManager.shared.listLVM(forList: list))
                        .id(list.subscriptionId)
                        .opacity(selectedSubTab == "List" && list == selectedList ? 1 : 0)
                }
                
                // EXPLORE
                ListViewContainer(vm: exploreVM)
                    .opacity(selectedSubTab == "Explore" ? 1 : 0)
            }
            
        }
        .overlay(alignment: .top) {
            if showFeedSettings {
                switch selectedSubTab {
                case "Following":
                    FeedSettings(lvm: LVMManager.shared.followingLVM(forAccount: account), showFeedSettings: $showFeedSettings)
                case "List":
                    if let list = selectedList {
                        FeedSettings(lvm: LVMManager.shared.listLVM(forList: list), showFeedSettings: $showFeedSettings, list:list)
                    }
                case "Explore":
                    FeedSettings(lvm: exploreVM, showFeedSettings: $showFeedSettings)
                default:
                    EmptyView()
                }
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
        .onChange(of: account, perform: { newAccount in
            guard account != newAccount else { return }
            L.og.info("Account changed from: \(account.name)/\(account.publicKey) to \(newAccount.name)/\(newAccount.publicKey)")
            LVMManager.shared.listVMs.filter { $0.pubkey == account.publicKey }
                .forEach { lvm in
                    lvm.cleanUp()
                }
            LVMManager.shared.listVMs.removeAll(where: { $0.pubkey == account.publicKey })
        })
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(receiveNotification(.showFeedToggles)) { _ in
            showFeedSettings = true
        }
    }
}

struct FollowingAndExplore_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            NavigationStack {
                if let account = NosturState.shared.account {
                    FollowingAndExplore(account: account)
                }
            }
        }
    }
}
