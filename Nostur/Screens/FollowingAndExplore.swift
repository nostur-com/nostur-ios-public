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
    @AppStorage("enable_discover_feed") private var enableDiscoverFeed: Bool = true
    @AppStorage("enable_gallery_feed") private var enableGalleryFeed: Bool = true
    @AppStorage("enable_article_feed") private var enableArticleFeed: Bool = true
    @AppStorage("enable_explore_feed") private var enableExploreFeed: Bool = true
    
    @AppStorage("enable_live_events") private var enableLiveEvents: Bool = true
    
    @State private var showingNewNote = false
    @State private var noteCancellationId: UUID?
    @State private var didCreate = false
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath:\CloudFeed.createdAt, ascending: false)], predicate: NSPredicate(format: "showAsTab == true"))
    var lists: FetchedResults<CloudFeed>
    @State private var selectedList: CloudFeed?

    @StateObject private var hotVM = HotViewModel()
    @StateObject private var discoverVM = DiscoverViewModel()
    @StateObject private var articlesVM = ArticlesFeedViewModel()
    @StateObject private var galleryVM = GalleryViewModel()
    
    @State var tabsOffsetY: CGFloat = 0.0
    @State var didSend = false
    
    @State var columnConfigs: [NXColumnConfig] = []
    @State var followingConfig: NXColumnConfig?
    @State var exploreConfig: NXColumnConfig?
    
    private var navigationTitle: String {
        if selectedSubTab == "List" {
            return (selectedList?.name_ ?? String(localized: "List"))
        }
        if selectedSubTab == "Following" {
            return String(localized: "Following", comment: "Tab title for feed of people you follow")
        }
        if selectedSubTab == "Explore" {
            return String(localized: "Explore", comment: "Tab title for the Explore feed")
        }
        if selectedSubTab == "Hot" {
            return String(localized: "Hot", comment: "Tab title for the Hot feed")
        }
        if selectedSubTab == "Discover" {
            return String(localized: "Discover", comment: "Tab title for the Discover feed")
        }
        if selectedSubTab == "Gallery" {
            return String(localized: "Gallery", comment: "Tab title for the Gallery feed")
        }
        if selectedSubTab == "Articles" {
            return String(localized: "Articles", comment: "Tab title for the Articles feed")
        }
        return String(localized: "Feed", comment: "Tab title for a feed")
    }

    // If only the Following feed is enabled and all other feeds are disabled, we can hide the entire tab bar
    private var shouldHideTabBar: Bool {
        if (account.followingPubkeys.count > 10 && enableHotFeed) { return false }
        if (account.followingPubkeys.count > 10 && enableGalleryFeed) { return false }
        if (account.followingPubkeys.count > 10 && enableDiscoverFeed) { return false }
        if enableExploreFeed { return false }
        if (account.followingPubkeys.count > 10 && enableArticleFeed) { return false }
        if lists.count > 0 { return false }
            
        return true
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        VStack(spacing: 0) {
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
                        
                        if account.followingPubkeys.count > 10 && enableDiscoverFeed {
                            TabButton(
                                action: { selectedSubTab = "Discover" },
                                title: String(localized: "Discover", comment:"Tab title for Discover feed"),
                                secondaryText: String(format: "%ih", discoverVM.ago),
                                selected: selectedSubTab == "Discover")
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
            
            if enableLiveEvents && 1 == 2 {
                LiveEventsBanner()
                    .animation(.easeIn, value: enableLiveEvents)
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
                            enableExploreFeed = true
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
                    if let followingConfig {
                        AvailableWidthContainer {
                            NXColumnView(config: followingConfig, isVisible: selectedSubTab == "Following")
                        }
                        .id(followingConfig.id)
                        .opacity(selectedSubTab == "Following" ? 1.0 : 0)
                    }
                }
                
                // LISTS
                ForEach(columnConfigs) { config in
                    AvailableWidthContainer {
                        NXColumnView(config: config, isVisible: selectedSubTab == "List" && selectedList?.subscriptionId == config.id)
                    }
                    .id(config.id)
                    .opacity(selectedSubTab == "List" && selectedList?.subscriptionId == config.id  ? 1.0 : 0)
                }
                
                // EXPLORE
                if enableExploreFeed, let exploreConfig = exploreConfig {
                    AvailableWidthContainer {
                        NXColumnView(config: exploreConfig, isVisible: selectedSubTab == "Explore")
                    }
                    .id(exploreConfig.id)
                    .opacity(selectedSubTab == "Explore" ? 1.0 : 0)
                }
                
                // HOT/ARTICLES/GALLERY
                if account.followingPubkeys.count > 10 {
                    switch selectedSubTab {
                    case "Hot":
                        Hot()
                            .environmentObject(hotVM)
                    case "Discover":
                        Discover()
                            .environmentObject(discoverVM)
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
        .onAppear {
            if selectedSubTab == "List" {
                if let list = lists.first(where: { $0.subscriptionId == selectedListId }) {
                    selectedList = list
                }
                else {
                    selectedList = lists.first
                }
            }
            // Make hot feed posts available to discover feed to not show the same posts
            if discoverVM.hotVM == nil {
                discoverVM.hotVM = hotVM
            }
            
            guard !didCreate else { return }
            didCreate = true
            loadColumnConfigs()
            createFollowingFeed()
            createExploreFeed() // Also create Explore Feed
        }
        .onChange(of: account, perform: { newAccount in
            guard account != newAccount else { return }
            L.og.info("Account changed from: \(account.name)/\(account.publicKey) to \(newAccount.name)/\(newAccount.publicKey)")
            createFollowingFeed()
        })
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(lists.publisher.collect()) { lists in
            if !lists.isEmpty && self.lists.count != lists.count {
                removeDuplicateLists()
                loadColumnConfigs()
            }
        }
        .onChange(of: shouldHideTabBar) { newValue in
            // We we disable all feeds, the tab bar disappears but does not auto switch to the Following feed, leaving an empty screen, this fixes that:
            if newValue && selectedSubTab != "Following"  {
                selectedSubTab = "Following"
            }
        }
        .onReceive(receiveNotification(.showingSomeoneElsesFeed)) { notification in
            let nrContact = notification.object as! NRContact
            if SettingsStore.shared.appWideSeenTracker {
                Deduplicator.shared.onScreenSeen = []
            }
            createSomeoneElsesFeed(nrContact.pubkey)
        }
        .onReceive(receiveNotification(.revertToOwnFeed)) { _ in
            if SettingsStore.shared.appWideSeenTracker {
                Deduplicator.shared.onScreenSeen = []
            }
            createFollowingFeed()
        }        
    }
    
    private func removeDuplicateLists() {
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
    
    private func loadColumnConfigs() {
        columnConfigs = lists
            .filter {
                switch $0.feedType {
                    case .pubkeys(_):
                        return true
                    case .relays(_):
                        return true
                    default:
                        return false
                }
            }
            .map { list in
                NXColumnConfig(id: list.subscriptionId, columnType: list.feedType, accountPubkey: list.accountPubkey, name: list.name_)
            }
    }
    
    private func createFollowingFeed() {
        let context = viewContext()
        let fr = CloudFeed.fetchRequest()
        fr.predicate = NSPredicate(format: "type == %@ && accountPubkey == %@", CloudFeedType.following.rawValue, la.pubkey)
        if let followingFeed = try? context.fetch(fr).first {
            followingConfig = NXColumnConfig(id: followingFeed.subscriptionId, columnType: .following(followingFeed), accountPubkey: la.pubkey, name: "Following")
        }
        else {
            let newFollowingFeed = CloudFeed(context: context)
            newFollowingFeed.wotEnabled = false // WoT is only for hashtags or relays feeds
            newFollowingFeed.name = "Following for " + la.account.anyName
            newFollowingFeed.showAsTab = false // or it will appear in "List" / "Custom Feeds" 
            newFollowingFeed.id = UUID()
            newFollowingFeed.createdAt = .now
            newFollowingFeed.accountPubkey = la.pubkey
            newFollowingFeed.type = CloudFeedType.following.rawValue
            DataProvider.shared().save() { // callback after save:
                followingConfig = NXColumnConfig(id: newFollowingFeed.subscriptionId, columnType: .following(newFollowingFeed), accountPubkey: la.pubkey, name: "Following")
            }
            
            // Check for existing ListState
            let fr = ListState.fetchRequest()
            fr.predicate = NSPredicate(format: "listId == %@ && pubkey == %@", "Following", la.pubkey)
            if let followingListState = try? context.fetch(fr).first {
                newFollowingFeed.repliesEnabled = !followingListState.hideReplies
            }
        }
    }
    
    private func createSomeoneElsesFeed(_ pubkey: String) {
        
        // Switch to main tab
        UserDefaults.standard.setValue("Main", forKey: "selected_tab")
        UserDefaults.standard.setValue("Following", forKey: "selected_subtab")
        
        followingConfig = NXColumnConfig(id: "List-\(pubkey.prefix(18))", columnType: .someoneElses(pubkey), name: "Other feed")
    }
    
    // Copy paste of createFollowingFeed
    private func createExploreFeed() {
        let context = viewContext()
        let fr = CloudFeed.fetchRequest()
        fr.predicate = NSPredicate(format: "type == %@ && accountPubkey == %@", CloudFeedType.following.rawValue, EXPLORER_PUBKEY)
        if let exploreFeed = try? context.fetch(fr).first {
            exploreConfig = NXColumnConfig(id: exploreFeed.subscriptionId, columnType: .following(exploreFeed), accountPubkey: EXPLORER_PUBKEY, name: "Explore")
        }
        else {
            let newExploreFeed = CloudFeed(context: context)
            newExploreFeed.wotEnabled = false // WoT is only for hashtags or relays feeds
            newExploreFeed.name = "Explore feed"
            newExploreFeed.showAsTab = false // or it will appear in "List" / "Custom Feeds"
            newExploreFeed.id = UUID()
            newExploreFeed.createdAt = .now
            newExploreFeed.accountPubkey = EXPLORER_PUBKEY
            newExploreFeed.type = CloudFeedType.following.rawValue
            newExploreFeed.repliesEnabled = false
            
            DataProvider.shared().save() { // callback after save:
                followingConfig = NXColumnConfig(id: newExploreFeed.subscriptionId, columnType: .following(newExploreFeed), accountPubkey: EXPLORER_PUBKEY, name: "Explore")
            }
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
