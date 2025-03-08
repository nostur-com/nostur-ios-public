//
//  MacListsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/05/2023.
//

import SwiftUI
import NavigationBackport

let COLUMN_SPACING = 1.0

@available(iOS 16.0, *)
struct MacListsView: View {
    @EnvironmentObject private var la: LoggedInAccount
    @EnvironmentObject private var themes: Themes
    let SIDEBAR_WIDTH: CGFloat = 50.0
    @StateObject private var dim = DIMENSIONS()
    @StateObject private var childDM = DIMENSIONS()
    @StateObject private var vm: MacListState = .shared

    @State var availableFeeds: [CloudFeed] = []
    @State private var columnWidth: CGFloat = 200.0
    
    var body: some View {
//        let _ = Self._printChanges()
        GeometryReader { geo in
            HStack(spacing: COLUMN_SPACING) {
                // Tabs on the side
                SideTabs(columnsCount: $vm.columnsCount, selectedTab: $vm.selectedTab)
                    .frame(width: SIDEBAR_WIDTH)
                
                // Main list (following/notifications/bookmarks)
                TabView(selection: $vm.selectedTab) {
                        PhoneViewIsh()
                        .environmentObject(childDM)
                            .tag("Main")
                            .toolbar(.hidden, for: .tabBar)
                        
                        NotificationsContainer()
                            .tag("Notifications")
                            .toolbar(.hidden, for: .tabBar)

                        Search()
                            .tag("Search")
                            .toolbar(.hidden, for: .tabBar)
                        
                        BookmarksAndPrivateNotes()
                            .tag("Bookmarks")
                            .toolbar(.hidden, for: .tabBar)
                    }
                    .frame(width: columnWidth)
                    .debugDimensions()
                
                // Extra lists (+ -)
                ForEach(0..<max(1,vm.columnsCount), id:\.self) { columnIndex in
                    MacList(availableWidth: columnSize(geo.size.width)) {
                        ColumnViewWrapper(availableFeeds: availableFeeds)
                    }
                    .id(columnIndex)
                    .frame(width: columnWidth)
                    .debugDimensions()
                }
            }
            .onAppear {
                columnWidth = columnSize(geo.size.width)
                childDM.listWidth = columnWidth
            }
            .onChange(of: geo.size.width) { newValue in
                if newValue != columnWidth {
                    columnWidth = columnSize(geo.size.width)
                    childDM.listWidth = columnWidth
                }
            }
            .onChange(of: vm.columnsCount) { _ in
                let newColumnSize = columnSize(geo.size.width)
                if columnWidth != newColumnSize {
                    columnWidth = newColumnSize
                    childDM.listWidth = newColumnSize
                }
            }
        }
        .onAppear {
            availableFeeds = CloudFeed.fetchAll(context: DataProvider.shared().viewContext)
        }
        .withSheets()
        .environmentObject(dim)
        .withLightningEffect()
    }
    
    func columnSize(_ availableWidth: CGFloat) -> CGFloat {
        let totalColumns = vm.columnsCount + 1 // +1 for main column
        let spacing = Double((totalColumns + 1)) * COLUMN_SPACING // +1 for side bar
        
        return CGFloat((availableWidth - SIDEBAR_WIDTH - spacing) / Double(totalColumns))
    }
}

// Copy pasta from FollowAndExplore, removed "Explore" stuff
struct PhoneViewIsh: View {
    
    @EnvironmentObject private var la: LoggedInAccount
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var dim: DIMENSIONS
    @ObservedObject private var ss: SettingsStore = .shared
    
    @State private var didCreate = false
    @State var didSend = false
    
    
    @State var followingConfig: NXColumnConfig?
    
    @State private var navPath = NBNavigationPath()
    @State private var lastPathPostId: String? = nil // Need to track .id of last added to navigation stack so we can remove on undo send if needed
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        NBNavigationStack(path: $navPath) {
            VStack(spacing: 0) {
                ZStack {
                    themes.theme.listBackground // needed to give this ZStack and parents size, else weird startup animation sometimes
                    // FOLLOWING
                    if let followingConfig {
                        AvailableWidthContainer {
                            NXColumnView(config: followingConfig, isVisible: true)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .withNavigationDestinations()
        }
        .nbUseNavigationStack(.never)
        .onAppear {
            guard !didCreate else { return }
            didCreate = true
            createFollowingFeed(la.account)
        }
        .onChange(of: la.account, perform: { newAccount in
            guard la.account != newAccount else { return }
            L.og.info("Account changed from: \(la.account.name)/\(la.account.publicKey) to \(newAccount.name)/\(newAccount.publicKey)")
            if SettingsStore.shared.appWideSeenTracker {
                Deduplicator.shared.onScreenSeen = []
            }
            createFollowingFeed(newAccount)
        })
//        .navigationTitle(navigationTitle)
//        .navigationBarTitleDisplayMode(.inline)
        
        
        .onReceive(receiveNotification(.navigateTo)) { notification in
            let destination = notification.object as! NavigationDestination
            navPath.append(destination.destination)
            
            // We need to know which .id is last added the stack (for undo), but we can't get from .navPath (private / internal)
            // So we track it separately in .lastPathPostId
            if (type(of: destination.destination) == NRPost.self) {
                let lastPath = destination.destination as! NRPost
                lastPathPostId = lastPath.id
            }
        }
        .onReceive(receiveNotification(.navigateToOnMain)) { notification in
            let destination = notification.object as! NavigationDestination
            navPath.append(destination.destination)
            
            
            // We need to know which .id is last added the stack (for undo), but we can't get from .navPath (private / internal)
            // So we track it separately in .lastPathPostId
            if (type(of: destination.destination) == NRPost.self) {
                let lastPath = destination.destination as! NRPost
                lastPathPostId = lastPath.id
            }
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
            DataProvider.shared().save() { // callback after save:
                followingConfig = NXColumnConfig(id: newFollowingFeed.subscriptionId, columnType: .following(newFollowingFeed), accountPubkey: account.publicKey, name: "Following")
            }
            
            // Check for existing ListState
            let fr = ListState.fetchRequest()
            fr.predicate = NSPredicate(format: "listId = %@ AND pubkey = %@", "Following", account.publicKey)
            if let followingListState = try? context.fetch(fr).first {
                newFollowingFeed.repliesEnabled = !followingListState.hideReplies
            }
        }
    }
}

struct ColumnViewWrapper: View {
    let availableFeeds:[CloudFeed]
    @State private var selectedFeed: CloudFeed? = nil
    @State private var navPath = NBNavigationPath()
//    @State private var lvm:LVM? = nil
    
    var body: some View {
//        Text("uuuh")
//        NXColumnConfigurator()
        ColumnView(availableFeeds: availableFeeds, selectedFeed: $selectedFeed, navPath: $navPath)
    }
}

struct ColumnView: View {
    @EnvironmentObject private var themes:Themes
    let availableFeeds: [CloudFeed]
    @Binding var selectedFeed: CloudFeed?
    @Binding var navPath: NBNavigationPath
//    @Binding var lvm:LVM?
    
    var body: some View {
        NBNavigationStack(path: $navPath) {
            ZStack {
                themes.theme.listBackground
                VStack {
                    Button("feeds....") {
                        navPath.append(ViewPath.Lists)
                    }
                    FeedSelector(feeds: availableFeeds, selected: $selectedFeed)
                        .padding(.top, 10)
    //                if let lvm = lvm {
    //                    Color.green
    ////                    ListViewContainer(vm: lvm)
    ////                        .overlay(alignment: .topTrailing) {
    ////                            ListUnreadCounter(vm: lvm, theme: themes.theme)
    ////                                .padding(.trailing, 10)
    ////                                .padding(.top, 5)
    ////                        }
    //                }
                    Spacer()
                }
                if selectedFeed == nil {
                    VStack(alignment:.leading) {
                        
                        Text("Choose content for this column")
                        
                        Group {
                            
                            Button { } label: {
                                Label("Following", systemImage: "person.3.fill")
                            }
                            
                            Button { } label: {
                                Label("Custom Feed", systemImage: "person.3")
                            }
                            
                            Button { } label: {
                                Label("Profile", systemImage: "person.fill")
                            }
    //
    //                        Button { } label: {
    //                            Label("Private notes", systemImage: "note.text")
    //                        }
                            
                            Button { } label: {
                                Label("Hashtag", systemImage: "number")
                            }
                            
                            Button { } label: {
                                Label("Messages", systemImage: "envelope")
                            }
                            
                            Button { } label: {
                                Label("Notifications", systemImage: "bell.fill")
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .withNavigationDestinations()
            .onChange(of: selectedFeed) { newFeed in

            }
        }
    }
}

struct MacListHeader: View {
    var title:String? = nil
    
    var body: some View {
        
        TabButton(action: {
            
        }, title: title ?? "List")
    }
}


struct MacList<Content: View>: View {
    
    private let content: Content
    let dim: DIMENSIONS

    init(availableWidth: CGFloat = 600, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.dim = DIMENSIONS()
        self.dim.listWidth = CGFloat(availableWidth)
    }
    
    var body: some View {
        content
            .environmentObject(dim)
    }
}


struct SideTabs:View {
    @EnvironmentObject private var themes: Themes
    @Binding var columnsCount: Int
    @Binding var selectedTab: String
    
    var body: some View {
        VStack(alignment: .center) {
            if let account = account() {
                PFP(pubkey: account.publicKey, account: account, size:30)
                    .padding(10)
            }
            
            Group {
                
                Button("Following", systemImage: "house.fill") {
                    selectedTab = "Main"
                }
                .frame(width: 40, height: 40)
                .background(selectedTab == "Main" ? themes.theme.accent.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
                
                Button("Notifications", systemImage: "bell.fill") {
                    selectedTab = "Notifications"
                }
                .frame(width: 40, height: 40)
                .background(selectedTab == "Notifications" ? themes.theme.accent.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
                
                Button("Search", systemImage: "magnifyingglass") {
                    selectedTab = "Search"
                }
                .frame(width: 40, height: 40)
                .background(selectedTab == "Search" ? themes.theme.accent.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
                
                Button("Bookmarks", systemImage: "bookmark.fill") {
                    selectedTab = "Bookmarks"
                }
                .frame(width: 40, height: 40)
                .background(selectedTab == "Bookmarks" ? themes.theme.accent.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
                
                Button("Messages", systemImage: "envelope.fill") {
                    selectedTab = "Messages"
                }
                .frame(width: 40, height: 40)
                .background(selectedTab == "Messages" ? themes.theme.accent.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
            
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.system(size: 20))
            .foregroundColor(themes.theme.accent)
            
            Spacer()
            
            
            Group {
                Button { addColumn() } label: {
                    Image(systemName: "rectangle.stack.fill.badge.plus")
                }
                Color.clear.frame(height: 5)
                Button { removeColumn() } label: {
                    Image(systemName: "rectangle.stack.badge.minus")
                }
            }
            Spacer()
            
            Button { SettingsStore.shared.proMode = false } label:  {
                Image(systemName: "star.fill")
            }
        }
//        .padding(.top, 100)
    }
    
    func addColumn() {
        guard columnsCount < 10 else { return }
        columnsCount += 1
    }
    
    func removeColumn() {
        guard columnsCount > 1 else { return }
        columnsCount -= 1
    }
}

@available(iOS 16.0, *)
struct MacListsView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            
            pe.loadContacts()
            pe.loadCloudFeeds()
//            pe.loadRelayNosturLists()
            
        }, previewDevice:PreviewDevice(rawValue: "My Mac (Mac Catalyst)"), content: {
            MacListsView()
        })
    }
}
