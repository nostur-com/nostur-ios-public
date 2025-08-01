//
//  FollowingAndExplore.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/02/2023.
//

import SwiftUI
import Combine
import NavigationBackport
import NostrEssentials

let MAINFEEDS_TABS_HEIGHT = 42.0

struct MainFeedsScreen: View {
    
    @EnvironmentObject private var la: LoggedInAccount
    @Environment(\.theme) private var theme
    @EnvironmentObject private var dim: DIMENSIONS
    @Binding var showingOtherContact: NRContact?
    @ObservedObject private var ss: SettingsStore = .shared
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Main" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_tab") }
    }
    @AppStorage("selected_subtab") private var selectedSubTab = "Following"
    @AppStorage("selected_listId") private var selectedListId = ""
    
    @AppStorage("enable_zapped_feed") private var enableZappedFeed: Bool = true
    @AppStorage("enable_hot_feed") private var enableHotFeed: Bool = true
    @AppStorage("enable_picture_feed") private var enablePictureFeed: Bool = true
    @AppStorage("enable_emoji_feed") private var enableEmojiFeed: Bool = true
    @AppStorage("enable_discover_feed") private var enableDiscoverFeed: Bool = true
    @AppStorage("enable_discover_lists_feed") private var enableDiscoverListsFeed: Bool = true
    @AppStorage("enable_gallery_feed") private var enableGalleryFeed: Bool = true
    @AppStorage("enable_article_feed") private var enableArticleFeed: Bool = true
    @AppStorage("enable_explore_feed") private var enableExploreFeed: Bool = true    
    
    @State private var noteCancellationId: UUID?
    @State private var didCreate = false
    
    
    @FetchRequest(sortDescriptors: [SortDescriptor(\CloudFeed.order, order: .forward)], predicate: NSPredicate(format: "showAsTab == true"))
    var lists: FetchedResults<CloudFeed>
    @State private var selectedList: CloudFeed?

    @StateObject private var zappedVM = ZappedViewModel()
    @StateObject private var hotVM = HotViewModel()
    @StateObject private var emojiVM = EmojiFeedViewModel()
//    @StateObject private var discoverVM = DiscoverViewModel()
    @StateObject private var discoverListsVM = DiscoverListsViewModel()
    @StateObject private var articlesVM = ArticlesFeedViewModel()
    @StateObject private var galleryVM = GalleryViewModel()

    @State private var showingNewNote = false
    @State private var didSend = false
    
    @State private var columnConfigs: [NXColumnConfig] = []
    @State private var followingConfig: NXColumnConfig?
    @State private var pictureConfig: NXColumnConfig?
    @State private var exploreConfig: NXColumnConfig?
    
    @State private var backlog = Backlog()
    
    @AppStorage("feed_emoji_type") var emojiType: String = "😂"
    
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
        if selectedSubTab == "Emoji" {
            return emojiType
        }
        if selectedSubTab == "Zapped" {
            return String(localized: "Zapped", comment: "Tab title for the Zapped feed")
        }
        if selectedSubTab == "Hot" {
            return String(localized: "Hot", comment: "Tab title for the Hot feed")
        }
//        if selectedSubTab == "Discover" {
//            return String(localized: "Discover", comment: "Tab title for the Discover feed")
//        }
        if selectedSubTab == "DiscoverLists" {
            return String(localized: "Discover Lists", comment: "Tab title for the Discover Lists feed")
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
        if (la.viewFollowingPublicKeys.count > 10 && enableZappedFeed) { return false }
        if (la.viewFollowingPublicKeys.count > 10 && enableHotFeed) { return false }
        if (la.viewFollowingPublicKeys.count > 10 && enablePictureFeed) { return false }
        if (la.viewFollowingPublicKeys.count > 10 && enableEmojiFeed) { return false }
        if (la.viewFollowingPublicKeys.count > 10 && enableGalleryFeed) { return false }
//        if (la.viewFollowingPublicKeys.count > 10 && enableDiscoverFeed) { return false }
        if enableDiscoverListsFeed { return false }
        if enableExploreFeed { return false }
        if (la.viewFollowingPublicKeys.count > 10 && enableArticleFeed) { return false }
        if lists.count > 0 { return false }
            
        return true
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ZStack {
                    if !shouldHideTabBar {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing:0) {
                                TabButton(
                                    action: { selectedSubTab = "Following" },
                                    title: String(localized:"Following", comment:"Tab title for feed of people you follow"),
                                    selected: selectedSubTab == "Following")
                                .id("Following")
                                Spacer()
                                
                                if la.viewFollowingPublicKeys.count > 10 && enablePictureFeed {
                                    TabButton(
                                        action: { selectedSubTab = "Picture" },
                                        systemIcon: "photo",
                                        selected: selectedSubTab == "Picture")
                                    .id("Picture")
                                    Spacer()
                                }
                                
                                ForEach(lists) { list in
                                    TabButton(
                                        action: {
                                            selectedSubTab = "List"
                                            selectedList = list
                                            selectedListId = list.subscriptionId
                                        },
                                        title: list.name_,
                                        selected: selectedSubTab == "List" && selectedList == list )
                                    .id(list.id)
                                    Spacer()
                                }
                                
                                if la.viewFollowingPublicKeys.count > 10 && enableEmojiFeed {
                                    TabButton(
                                        action: { selectedSubTab = "Emoji" },
                                        imageName: emojiType == "😂" ? "LaughterIcon" : "RageIcon",
                                        secondaryText: String(format: "%ih", emojiVM.ago),
                                        selected: selectedSubTab == "Emoji")
                                    .id("Emoji")
                                    Spacer()
                                }
                                
                                if la.viewFollowingPublicKeys.count > 10 && enableZappedFeed {
                                    TabButton(
                                        action: { selectedSubTab = "Zapped" },
                                        title: String(localized:"Zapped", comment:"Tab title for feed of most zapped posts"),
                                        secondaryText: String(format: "%ih", zappedVM.ago),
                                        selected: selectedSubTab == "Zapped")
                                    .id("Zapped")
                                    Spacer()
                                }
                                
                                if la.viewFollowingPublicKeys.count > 10 && enableHotFeed {
                                    TabButton(
                                        action: { selectedSubTab = "Hot" },
                                        title: String(localized:"Hot", comment:"Tab title for feed of hot/popular posts"),
                                        secondaryText: String(format: "%ih", hotVM.ago),
                                        selected: selectedSubTab == "Hot")
                                    .id("Hot")
                                    Spacer()
                                }
                                
                                if enableDiscoverListsFeed {
                                    TabButton(
                                        action: { selectedSubTab = "DiscoverLists" },
                                        title: String(localized: "Discover", comment:"Tab title for Discover Lists feed"),
                                        selected: selectedSubTab == "DiscoverLists")
                                    .id("DiscoverLists")
                                    Spacer()
                                }
        //                        else if la.viewFollowingPublicKeys.count > 10 && enableDiscoverFeed {
        //                            TabButton(
        //                                action: { selectedSubTab = "Discover" },
        //                                title: String(localized: "Discover", comment:"Tab title for Discover feed"),
        //                                secondaryText: String(format: "%ih", discoverVM.ago),
        //                                selected: selectedSubTab == "Discover")
    //                                .id("Discover")
        //                            Spacer()
        //                        }
                                
                                if la.viewFollowingPublicKeys.count > 10 && enableGalleryFeed {
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
                                    .id(IS_CATALYST ? "GalleryMac" : "Gallery")
                                    Spacer()
                                }
                                
                                if enableExploreFeed {
                                    TabButton(
                                        action: { selectedSubTab = "Explore" },
                                        title: String(localized:"Explore", comment:"Tab title for the Explore feed"),
                                        selected: selectedSubTab == "Explore")
                                    .id("Explore")
                                }
                                
                                if la.viewFollowingPublicKeys.count > 10 && enableArticleFeed {
                                    Spacer()
                                    TabButton(
                                        action: { selectedSubTab = "Articles" },
                                        title: String(localized:"Articles", comment:"Tab title for feed of articles"),
            //                            secondaryText: articlesVM.agoText,
                                        selected: selectedSubTab == "Articles"
                                    )
                                    .id("Articles")
                                }
                            }
                            .frame(minWidth: dim.listWidth)
                        }
                        .frame(width: dim.listWidth, height: MAINFEEDS_TABS_HEIGHT)
                    }
                }
                .onAppear {
                    ScreenSpace.shared.mainTabSize = CGSize(width: dim.listWidth, height: ScreenSpace.shared.screenSize.height)
                    if selectedSubTab == "List" {
                        if let list = lists.first(where: { $0.subscriptionId == selectedListId }) {
                            selectedList = list
                        }
                        else {
                            selectedList = lists.first
                        }
                    }
                    
                    guard !didCreate else { return }
                    didCreate = true
                    loadColumnConfigs()
                    createFollowingFeed(la.account)
                    createPictureFeed(la.account)
                    createExploreFeed() // Also create Explore Feed
                    
                    // Make sure selected tab is visible at launch
                    if selectedSubTab == "List" {
                        if let selectedList {
                            proxy.scrollTo(selectedList.id, anchor: .trailing)
                        }
                    }
                    else {
                        proxy.scrollTo(selectedSubTab, anchor: .trailing)
                    }
                }
            }
          
            
            LiveEventsBanner()
            
            ZStack {
                theme.listBackground // needed to give this ZStack and parents size, else everything becomes weird small
                
                // FOLLOWING
                if (showingOtherContact == nil && la.viewFollowingPublicKeys.count <= 1 && !didSend) {
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
                        .buttonStyle(NRButtonStyle(theme: theme, style: .borderedProminent))
                        Spacer()
                    }
                    .onReceive(receiveNotification(.didSend)) { _ in
                        didSend = true
                    }
                }
                else {
//                    AudioRecorderContentView()
                    if let followingConfig {
                        AvailableWidthContainer {
                            NXColumnView(config: followingConfig, isVisible: selectedSubTab == "Following")
                        }
//                        .id(followingConfig.id)
                        .opacity(selectedSubTab == "Following" ? 1.0 : 0)
                    }
                }
                
                if let pictureConfig, la.viewFollowingPublicKeys.count > 10  {
                    AvailableWidthContainer {
                        NXColumnView(config: pictureConfig, isVisible: selectedSubTab == "Picture")
                    }
//                        .id(pictureConfig.id)
                    .opacity(selectedSubTab == "Picture" ? 1.0 : 0)
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
                
                // DISCOVER LISTS / FOLLOW PACKS
                if selectedSubTab == "DiscoverLists" {
                    AvailableWidthContainer {
                        DiscoverLists()
                            .environmentObject(discoverListsVM)
                    }
                }
                
                // ZAPPED/HOT/ARTICLES/GALLERY
                if la.viewFollowingPublicKeys.count > 10 {
                    AvailableWidthContainer {
                        switch selectedSubTab {
                        case "Emoji":
                            EmojiFeed()
                                .environmentObject(emojiVM)
                        case "Zapped":
                            Zapped()
                                .environmentObject(zappedVM)
                        case "Hot":
                            Hot()
                                .environmentObject(hotVM)
//                        case "Discover":
//                            Discover()
//                                .environmentObject(discoverVM)
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
                .overlay(alignment: .bottomTrailing) {
                    NewNoteButton(showingNewNote: $showingNewNote)
                        .padding([.top, .leading, .bottom], 10)
                        .padding([.trailing], 25)
                        .buttonStyleGlassProminent()
                }
            
            AudioOnlyBarSpace()
        }
        .onChange(of: selectedListId) { newListId in
            if !columnConfigs.contains(where: { $0.id == newListId }) {
                loadColumnConfigs()
            }
            if let list = lists.first(where: { $0.subscriptionId == newListId }) {
                selectedList = list
            }
        }
        .onChange(of: la.account) { [oldAccount = la.account] newAccount in
            guard oldAccount != newAccount else { return }
            L.og.info("Account changed from: \(oldAccount.name)/\(oldAccount.publicKey) to \(newAccount.name)/\(newAccount.publicKey)")
            if SettingsStore.shared.appWideSeenTracker {
                Deduplicator.shared.onScreenSeen = []
            }
            createFollowingFeed(newAccount)
            createPictureFeed(newAccount)
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(lists.publisher.collect()) { lists in
            guard didCreate else { return } // Only update here after .onAppear { } has ran.
            
            if !lists.isEmpty && self.lists.filter({ $0.showAsTab }) .count != columnConfigs.count {
                removeDuplicateLists()
                loadColumnConfigs()
                
                if let list = lists.first(where: { $0.subscriptionId == selectedListId }) {
                    selectedList = list
                }
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
            createFollowingFeed(la.account)
            createPictureFeed(la.account)
        }
        .onReceive(Importer.shared.importedMessagesFromSubscriptionIds.receive(on: RunLoop.main)) { [weak backlog] subscriptionIds in
            bg().perform {
                guard let backlog else { return }
                let reqTasks = backlog.tasks(with: subscriptionIds)
                reqTasks.forEach { task in
                    task.process()
                }
            }
        }
        
        .sheet(isPresented: $showingNewNote) {
            NRNavigationStack {
                if la.account.isNC {
                    WithNSecBunkerConnection(nsecBunker: NSecBunkerManager.shared) {
                        ComposePost(onDismiss: { showingNewNote = false }, kind: selectedTab == "Main" && selectedSubTab == "Picture" ? .picture : nil)
                            .environmentObject(dim)
                    }
                    .environment(\.theme, theme)
                }
                else {
                    ComposePost(onDismiss: { showingNewNote = false }, kind: selectedTab == "Main" && selectedSubTab == "Picture" ? .picture : nil)
                        .environmentObject(dim)
                        .environment(\.theme, theme)
                }
            }
            .presentationBackgroundCompat(theme.listBackground)
            .environmentObject(la)
        }
        
        .onReceive(receiveNotification(.newTemplatePost)) { _ in
            // Note: use  Drafts.shared.draft = ...
            showingNewNote = true
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
                    case .picture(_):
                        return false
                    case .pubkeys(_):
                        return true
                    case .relays(_):
                        return true
                    case .followSet(_), .followPack(_):
                        return true
                    default:
                        return false
                }
            }
            .map { list in
                return NXColumnConfig(id: list.subscriptionId, columnType: list.feedType, accountPubkey: list.accountPubkey, name: list.name_)
            }
        
        self.checkForListUpdates()
    }
    
    private func checkForListUpdates() {
        let followSetConfigs: [NXColumnConfig] = columnConfigs.filter {
            if case .followSet(_) = $0.columnType {
                return true
            }
            if case .followPack(_) = $0.columnType {
                return true
            }
            return false
        }
        
        for config in followSetConfigs {
            guard let aTag = config.feed?.aTag else { continue }
            let since: Int? = config.feed?.refreshedAt.map { Int($0.timeIntervalSince1970) }
            let subscriptionId = config.feed?.subscriptionId ?? String(UUID().uuidString.prefix(48))
            
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) loadColumnConfigs: Checking list update -[LOG]-")
#endif
            
            let reqTask = ReqTask(
                debounceTime: 3.0,
                subscriptionId: "KIND-30000-\(subscriptionId)",
                reqCommand: { taskId in
                    nxReq(
                        Filters(
                            authors: [aTag.pubkey],
                            kinds: [30000,39089],
                            tagFilter: TagFilter(tag: "d", values: [aTag.definition]),
                            since: since,
                            limit: 5
                        ),
                        subscriptionId: taskId,
                        isActiveSubscription: false
                    )
                },
                processResponseCommand: { (taskId, _, _) in
                    bg().perform {
                        if let kind3000Event = Event.fetchReplacableEvent(aTag: aTag, context: bg()) {
                            let latestPubkeys = Set(kind3000Event.fastPs.map { $0.1 })
                            Task { @MainActor in
#if DEBUG
                                L.og.debug("☘️☘️ \(config.name) loadColumnConfigs: Updating pubkeys to: \(latestPubkeys) -[LOG]-")
#endif
                                config.feed?.contactPubkeys = latestPubkeys
                            }
                        }
                    }
                },
                timeoutCommand: { taskId in
#if DEBUG
                    L.og.debug("☘️☘️ \(config.name) loadColumnConfigs: no update needed -[LOG]-")
#endif
                })
            
            backlog.add(reqTask)
            reqTask.fetch()
        }
    }
    
    private func createFollowingFeed(_ account: CloudAccount) {
        let context = viewContext()
        let fr = CloudFeed.fetchRequest()
        fr.predicate = NSPredicate(format: "type = %@ AND accountPubkey = %@", CloudFeedType.following.rawValue, account.publicKey)
        
        let followingFeeds: [CloudFeed] = (try? context.fetch(fr)) ?? []
        let followingFeedsNewest: [CloudFeed] = followingFeeds
            .sorted(by: { a, b in
                let mostRecentA = max(a.createdAt ?? .now, a.refreshedAt ?? .now)
                let mostRecentB = max(b.createdAt ?? .now, b.refreshedAt ?? .now)
                return mostRecentA > mostRecentB
            })
        
        if let followingFeed = followingFeedsNewest.first {
            followingConfig = NXColumnConfig(id: followingFeed.subscriptionId, columnType: .following(followingFeed), accountPubkey: account.publicKey, name: "Following")
            for f in followingFeedsNewest.dropFirst(1) {
                context.delete(f)
            }
            DataProvider.shared().save()
        }
        else {
            let newFollowingFeed = CloudFeed(context: context)
            newFollowingFeed.wotEnabled = false // WoT is only for hashtags or relays feeds
            newFollowingFeed.name = "Following for " + account.anyName
            newFollowingFeed.showAsTab = false // or it will appear in "List" / "Custom Feeds"
            newFollowingFeed.id = UUID()
            newFollowingFeed.createdAt = .now
            newFollowingFeed.accountPubkey = account.publicKey
            newFollowingFeed.type = CloudFeedType.following.rawValue
            newFollowingFeed.order = 0
            DataProvider.shared().save() { // callback after save:
                followingConfig = NXColumnConfig(id: newFollowingFeed.subscriptionId, columnType: .following(newFollowingFeed), accountPubkey: account.publicKey, name: "Following")
            }
        }
    }
    
    private func createPictureFeed(_ account: CloudAccount) {
        let context = viewContext()
        let fr = CloudFeed.fetchRequest()
        fr.predicate = NSPredicate(format: "type = %@ AND accountPubkey = %@", CloudFeedType.picture.rawValue, account.publicKey)
        
        let feeds: [CloudFeed] = (try? context.fetch(fr)) ?? []
        let feedsNewest: [CloudFeed] = feeds
            .sorted(by: { a, b in
                let mostRecentA = max(a.createdAt ?? .now, a.refreshedAt ?? .now)
                let mostRecentB = max(b.createdAt ?? .now, b.refreshedAt ?? .now)
                return mostRecentA > mostRecentB
            })
        
        if let feed = feedsNewest.first {
            pictureConfig = NXColumnConfig(id: feed.subscriptionId, columnType: .picture(feed), accountPubkey: account.publicKey, name: "Picture")
            for f in feedsNewest.dropFirst(1) {
                context.delete(f)
            }
            DataProvider.shared().save()
        }
        else {
            let newFeed = CloudFeed(context: context)
            newFeed.wotEnabled = false // WoT is only for hashtags or relays feeds
            newFeed.name = "📸"
            newFeed.showAsTab = false // or it will appear in "List" / "Custom Feeds"
            newFeed.id = UUID()
            newFeed.createdAt = .now
            newFeed.accountPubkey = account.publicKey
            newFeed.type = CloudFeedType.picture.rawValue
            newFeed.repliesEnabled = false
            newFeed.order = 0
            DataProvider.shared().save() { // callback after save:
                pictureConfig = NXColumnConfig(id: newFeed.subscriptionId, columnType: .picture(newFeed), accountPubkey: account.publicKey, name: "Picture")
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
        
        let exploreFeeds: [CloudFeed] = (try? context.fetch(fr)) ?? []
        let exploreFeedsNewest: [CloudFeed] = exploreFeeds
            .sorted(by: { a, b in
                let mostRecentA = max(a.createdAt ?? .now, a.refreshedAt ?? .now)
                let mostRecentB = max(b.createdAt ?? .now, b.refreshedAt ?? .now)
                return mostRecentA > mostRecentB
            })
        
        if let exploreFeed = exploreFeedsNewest.first {
            exploreConfig = NXColumnConfig(id: exploreFeed.subscriptionId, columnType: .following(exploreFeed), accountPubkey: EXPLORER_PUBKEY, name: "Explore")
            for e in exploreFeedsNewest.dropFirst(1) {
                context.delete(e)
            }
            DataProvider.shared().save()
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
            newExploreFeed.order = 0
            
            DataProvider.shared().save() { // callback after save:
                exploreConfig = NXColumnConfig(id: newExploreFeed.subscriptionId, columnType: .following(newExploreFeed), accountPubkey: EXPLORER_PUBKEY, name: "Explore")
            }
        }
    }
}

#Preview {
    PreviewContainer {
        NBNavigationStack {
            MainFeedsScreen(showingOtherContact: .constant(nil))
        }
    }
}


#Preview("with Posts") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadFollows()
    }) {
        NBNavigationStack {
            MainFeedsScreen(showingOtherContact: .constant(nil))
        }
    }
}
