//
//  PhoneViewIsh.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/09/2025.
//

import SwiftUI
import NavigationBackport

// Copy pasta from MainFeedsScreen, removed "Explore" and other stuff, just keep "Following" feed
struct PhoneViewIsh: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.availableWidth) private var availableWidth
    @EnvironmentObject private var la: LoggedInAccount
    @Environment(\.theme) private var theme
    @ObservedObject private var ss: SettingsStore = .shared
    
    @State private var didCreate = false
    @State var didSend = false
    
    
    @State var followingConfig: NXColumnConfig?
    
    @State private var navPath = NBNavigationPath()
    @State private var lastPathPostId: String? = nil // Need to track .id of last added to navigation stack so we can remove on undo send if needed
    
    @State private var showLiveEventsBanner = false
    
    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        NBNavigationStack(path: $navPath) {
            VStack(spacing: 0) {
                ZStack {
                    theme.listBackground // needed to give this ZStack and parents size, else weird startup animation sometimes
                    // FOLLOWING
                    if let followingConfig {
                        AvailableWidthContainer {
                            NXColumnView(config: followingConfig, isVisible: true)
                                .modifier {
                                    if #available(iOS 26.0, *) {
                                        $0.toolbar {
                                            settingsButton(followingConfig)
                                            .sharedBackgroundVisibility(.hidden)
                                        }
                                    }
                                    else {
                                        $0.toolbar {
                                            settingsButton(followingConfig)
                                        }
                                    }
                                }
                        }
                    }
                }
                
                AudioOnlyBarSpace()
            }
            .environment(\.containerID, "Default")
            .simultaneousGesture(TapGesture().onEnded({ _ in
                AppState.shared.containerIDTapped = "Default"
            }))
            .navigationTitle("Following")
            .navigationBarTitleDisplayMode(.inline)
            .withNavigationDestinations(navPath: $navPath)
            .safeAreaInset(edge: .top, alignment: .leading, spacing: 0) {
                if #available(iOS 26.0, *) {
                    LiveEventsBanner(showLiveEventsBanner: $showLiveEventsBanner)
                        .opacity(showLiveEventsBanner ? 1.0 : 0)
                        .frame(height: showLiveEventsBanner ? 50 : 0)
                }
            }
        }
        .nbUseNavigationStack(.never)
        .onAppear {
            ScreenSpace.shared.mainTabSize = CGSize(width: availableWidth, height: ScreenSpace.shared.screenSize.height)
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
        .onReceive(receiveNotification(.navigateTo)) { notification in
            let destination = notification.object as! NavigationDestination
//            guard selectedTab() == "Main" else { return }
            guard destination.context == "Default" else { return }

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
    
    @ToolbarContentBuilder
    private func settingsButton(_ config: NXColumnConfig) -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(String(localized: "Feed Settings", comment: "Menu item for toggling feed settings"), systemImage: "gearshape") {
                AppSheetsModel.shared.feedSettingsFeed = config.feed
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
            DataProvider.shared().saveToDiskNow(.viewContext)
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
            
            // Resume Where Left: Default on for contact-based. Default off for relay-based
            newFollowingFeed.continue = true
            
            DataProvider.shared().saveToDiskNow(.viewContext) { // callback after save:
                followingConfig = NXColumnConfig(id: newFollowingFeed.subscriptionId, columnType: .following(newFollowingFeed), accountPubkey: account.publicKey, name: "Following")
            }
        }
    }
}
