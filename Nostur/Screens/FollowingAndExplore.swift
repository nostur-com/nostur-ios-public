//
//  FollowingAndExplore.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/02/2023.
//

import SwiftUI
import Combine
import NavigationBackport

struct FollowingAndExplore: View, Equatable {
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.account == rhs.account && lhs.showingOtherContact == rhs.showingOtherContact
    }
    
    @EnvironmentObject private var la: LoggedInAccount
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var dim: DIMENSIONS
    @ObservedObject var account: CloudAccount
    @Binding var showingOtherContact: NRContact?
    @ObservedObject private var ss: SettingsStore = .shared
    @AppStorage("selected_subtab") private var selectedSubTab = "Following"
    @AppStorage("selected_listId") private var selectedListId = ""
    
    @AppStorage("enable_hot_feed") private var enableHotFeed: Bool = true
    @AppStorage("enable_gallery_feed") private var enableGalleryFeed: Bool = true
    @AppStorage("enable_article_feed") private var enableArticleFeed: Bool = true
    @AppStorage("enable_explore_feed") private var enableExploreFeed: Bool = true
    
    @State private var showingNewNote = false
    @State private var noteCancellationId: UUID?
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath:\CloudFeed.createdAt, ascending: false)], predicate: NSPredicate(format: "showAsTab == true"))
    var lists:FetchedResults<CloudFeed>
    @State private var selectedList: CloudFeed?
    @StateObject private var exploreVM: LVM = LVMManager.shared.exploreLVM()
    @StateObject private var hotVM = HotViewModel()
    @StateObject private var articlesVM = ArticlesFeedViewModel()
    @StateObject private var galleryVM = GalleryViewModel()
    
    @State var tabsOffsetY: CGFloat = 0.0
    @State var didSend = false
    
    private var navigationTitle: String {
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
            return String(localized:"Hot", comment:"Tab title for the Hot feed")
        }
        if selectedSubTab == "Gallery" {
            return String(localized:"Gallery", comment:"Tab title for the Gallery feed")
        }
        if selectedSubTab == "Articles" {
            return String(localized:"Articles", comment:"Tab title for the Articles feed")
        }
        return String(localized:"Feed", comment:"Tab title for a feed")
    }
    
    @State var showFeedSettings = false
    
    // If only the Following feed is enabled and all other feeds are disabled, we can hide the entire tab bar
    private var shouldHideTabBar: Bool {
        if (account.followingPubkeys.count > 10 && enableHotFeed) { return false }
        if (account.followingPubkeys.count > 10 && enableGalleryFeed) { return false }
        if enableExploreFeed { return false }
        if (account.followingPubkeys.count > 10 && enableArticleFeed) { return false }
        if lists.count > 0 { return false }
            
        return true
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        VStack(spacing:0) {
            if !shouldHideTabBar {
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
                        
                        if account.followingPubkeys.count > 10 && enableHotFeed {
                            TabButton(
                                action: { selectedSubTab = "Hot" },
                                title: String(localized:"Hot", comment:"Tab title for feed of hot/popular posts"),
                                secondaryText: String(format: "%ih", hotVM.ago),
                                selected: selectedSubTab == "Hot")
                            Spacer()
                        }
                        
                        if account.followingPubkeys.count > 10 && enableGalleryFeed {
                            TabButton(
                                action: {
                                    if IS_CATALYST { // On macOS we open the Gallery in the detail pane
                                        navigateOnDetail(ViewPath.Gallery(vm: galleryVM))
                                    }
                                    else {
                                        selectedSubTab = "Gallery"
                                    }
                                },
                                title: String(localized:"Gallery", comment:"Tab title for gallery feed"),
                                secondaryText: String(format: "%ih", galleryVM.ago),
                                selected: selectedSubTab == "Gallery")
                            Spacer()
                        }
                        
                        if enableExploreFeed {
                            TabButton(
                                action: { selectedSubTab = "Explore" },
                                title: String(localized:"Explore", comment:"Tab title for the Explore feed"),
                                selected: selectedSubTab == "Explore")
                        }
                        
                        if account.followingPubkeys.count > 10 && enableArticleFeed {
                            Spacer()
                            TabButton(
                                action: { selectedSubTab = "Articles" },
                                title: String(localized:"Articles", comment:"Tab title for feed of articles"),
    //                            secondaryText: articlesVM.agoText,
                                selected: selectedSubTab == "Articles")
                        }
                    }
    //                .padding(.horizontal, 10)
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
                    .toolbarVisibleCompat(IS_CATALYST || tabsOffsetY == 0.0 ? .visible : .hidden)
                }
                .frame(width: dim.listWidth, height: max(44.0 + tabsOffsetY,0))
            }
            
            ZStack {
                themes.theme.listBackground // needed to give this ZStack and parents size, else weird startup animation sometimes
                
                // FOLLOWING
                if (showingOtherContact == nil && account.followingPubkeys.count <= 1 && !didSend) {
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
                        .buttonStyle(NRButtonStyle(theme: themes.theme, style: .borderedProminent))
                        Spacer()
                    }
                    .onReceive(receiveNotification(.didSend)) { _ in
                        didSend = true
                    }
                }
                else {
                    ListViewContainer(vm: LVMManager.shared.followingLVM(forAccount: account))
                        .opacity(selectedSubTab == "Following" ? 1 : 0)
//                        .withoutAnimation()
                }
                
                // LISTS
                ForEach(lists) { list in
                    ListViewContainer(vm: LVMManager.shared.listLVM(forList: list))
//                        .id(list.subscriptionId)
                        .opacity(selectedSubTab == "List" && list == selectedList ? 1 : 0)
//                        .withoutAnimation()
                }
                
                // EXPLORE
                if enableExploreFeed {
                    ListViewContainer(vm: exploreVM)
                        .opacity(selectedSubTab == "Explore" ? 1 : 0)
    //                    .withoutAnimation()
                }
                
                
                // HOT/ARTICLES/GALLERY
                if account.followingPubkeys.count > 10 {
                    switch selectedSubTab {
                    case "Hot":
                        Hot()
                            .environmentObject(hotVM)
                    case "Articles":
                        ArticlesFeed()
                            .environmentObject(articlesVM)
                    case "Gallery":
                        Gallery()
                            .environmentObject(galleryVM)
                    default:
                        EmptyView()
                    }                        
                }
                
                
            }
            
        }
        .sheet(isPresented: $showFeedSettings, content: {
            NBNavigationStack {
                switch selectedSubTab {
                case "Following":
                    FeedSettings(lvm: LVMManager.shared.followingLVM(forAccount: account))
                        .environmentObject(la)
                case "List":
                    if let list = selectedList {
                        FeedSettings(lvm: LVMManager.shared.listLVM(forList: list), list:list)
                            .environmentObject(la)
                    }
                case "Explore":
                    FeedSettings(lvm: exploreVM)
                        .environmentObject(la)
                case "Hot":
                    HotFeedSettings(hotVM: hotVM)
                case "Articles":
                    ArticleFeedSettings(vm: articlesVM)
                case "Gallery":
                    GalleryFeedSettings(vm: galleryVM)
                default:
                    EmptyView()
                }
            }
            .nbUseNavigationStack(.never)
        })
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
            
            if newAccount.followingPubkeys.count <= 10 && selectedSubTab == "Hot" {
                selectedSubTab = "Following"
            }
        })
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(receiveNotification(.showFeedToggles)) { _ in
            showFeedSettings = true
        }
        .onReceive(lists.publisher.collect()) { lists in
            if !lists.isEmpty && self.lists.count != lists.count {
                removeDuplicateLists()
            }
        }
        .onChange(of: shouldHideTabBar) { newValue in
            // We we disable all feeds, the tab bar disappears but does not auto switch to the Following feed, leaving an empty screen, this fixes that:
            if newValue && selectedSubTab != "Following"  {
                selectedSubTab = "Following"
            }
        }
    }
    
    func removeDuplicateLists() {
        var uniqueLists = Set<UUID>()
        let sortedLists = lists.sorted {
            if ($0.showAsTab && !$1.showAsTab) { return true }
            else {
                return ($0.createdAt as Date?) ?? Date.distantPast > ($1.createdAt as Date?) ?? Date.distantPast
            }
        }
        
        let duplicates = sortedLists
            .filter { list in
                guard let id = list.id else { return false }
                return !uniqueLists.insert(id).inserted
            }
        
        duplicates.forEach {
            DataProvider.shared().viewContext.delete($0)
        }
        if !duplicates.isEmpty {
            L.cloud.debug("Deleting: \(duplicates.count) duplicate feeds")
            DataProvider.shared().save()
        }
    }
}

struct FollowingAndExplore_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            NBNavigationStack {
                if let account = account() {
                    FollowingAndExplore(account: account, showingOtherContact: .constant(nil))
                }
            }
        }
    }
}
