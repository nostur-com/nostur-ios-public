//
//  FollowingAndExplore.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/02/2023.
//

import SwiftUI
import Combine

struct FollowingAndExplore: View {
    @EnvironmentObject var theme:Theme
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
    @StateObject private var hotVM = HotViewModel()
    @StateObject private var articlesVM = ArticlesFeedViewModel()
    @StateObject private var galleryVM = GalleryViewModel()
    
    @State var tabsOffsetY:CGFloat = 0.0
    @State var didSend = false
    
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
        if selectedSubTab == "Hot" {
            return String(localized:"Explore", comment:"Tab title for the Hot feed")
        }
        if selectedSubTab == "Gallery" {
            return String(localized:"Gallery", comment:"Tab title for the Gallery feed")
        }
        return String(localized:"Feed", comment:"Tab title for a feed")
    }
    
    @State var showFeedSettings = false
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
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
                    
                    if account.follows_.count > 10 {
                        TabButton(
                            action: { selectedSubTab = "Hot" },
                            title: String(localized:"Hot", comment:"Tab title for feed of hot/popular posts"),
                            secondaryText: String(format: "%ih", hotVM.ago),
                            selected: selectedSubTab == "Hot")
                        Spacer()
                    }
                    
                    if account.follows_.count > 10 {
                        TabButton(
                            action: { selectedSubTab = "Gallery" },
                            title: String(localized:"Gallery", comment:"Tab title for gallery feed"),
                            secondaryText: String(format: "%ih", galleryVM.ago),
                            selected: selectedSubTab == "Gallery")
                        Spacer()
                    }
                    
                    TabButton(
                        action: { selectedSubTab = "Explore"},
                        title: String(localized:"Explore", comment:"Tab title for the Explore feed"),
                        selected: selectedSubTab == "Explore")
                    
                    if account.follows_.count > 10 {
                        Spacer()
                        TabButton(
                            action: { selectedSubTab = "Articles" },
                            title: String(localized:"Articles", comment:"Tab title for feed of articles"),
//                            secondaryText: articlesVM.agoText,
                            selected: selectedSubTab == "Articles")
                    }
                }
                .padding(.horizontal, 10)
                .frame(minWidth: dim.listWidth)
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
            .frame(width: dim.listWidth, height: max(36.0 + tabsOffsetY,0))
            
            ZStack {
                // FOLLOWING
                if (account.getFollowingPublicKeys().count <= 1 && !didSend) {
                    VStack {
                        Spacer()
                        Text("You are not following anyone yet, visit the explore tab and follow some people")
                            .multilineTextAlignment(.center)
                            .padding(.all, 30.0)
                        
                        Button {
                            selectedSubTab = "Explore"
                        } label: {
                            Text("Explore", comment: "Button to go to the Explore tab")
                        }
                        .buttonStyle(NRButtonStyle(theme: Theme.default, style: .borderedProminent))
                        Spacer()
                    }
                    .onReceive(receiveNotification(.didSend)) { _ in
                        didSend = true
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
                
                
                // HOT/ARTICLES/GALLERY
                if account.follows_.count > 10 {
                    Hot(hotVM: hotVM)
                        .opacity(selectedSubTab == "Hot" ? 1 : 0)
                    
                    ArticlesFeed(vm: articlesVM)
                        .opacity(selectedSubTab == "Articles" ? 1 : 0)
                    
                    Gallery(vm: galleryVM)
                        .opacity(selectedSubTab == "Gallery" ? 1 : 0)
                }
                
                
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
                case "Hot":
                    HotFeedSettings(hotVM: hotVM, showFeedSettings: $showFeedSettings)
                case "Articles":
                    ArticleFeedSettings(vm: articlesVM, showFeedSettings: $showFeedSettings)
                case "Gallery":
                    GalleryFeedSettings(vm: galleryVM, showFeedSettings: $showFeedSettings)
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
            LVMManager.shared.followingLVM(forAccount: newAccount).restoreSubscription()
            
            if newAccount.follows_.count <= 10 && selectedSubTab == "Hot" {
                selectedSubTab = "Following"
            }
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
                if let account = account() {
                    FollowingAndExplore(account: account)
                }
            }
        }
    }
}
