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
    @EnvironmentObject private var la: LoggedInAccount
    @Environment(\.theme) private var theme
    @EnvironmentObject private var dim: DIMENSIONS
    @ObservedObject private var ss: SettingsStore = .shared
    
    @State private var didCreate = false
    @State var didSend = false
    
    
    @State var followingConfig: NXColumnConfig?
    
    @State private var navPath = NBNavigationPath()
    @State private var lastPathPostId: String? = nil // Need to track .id of last added to navigation stack so we can remove on undo send if needed
    
    @State private var showLiveEventsBanner = false
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        NBNavigationStack(path: $navPath) {
            VStack(spacing: 0) {
                ZStack {
                    theme.listBackground // needed to give this ZStack and parents size, else weird startup animation sometimes
                    // FOLLOWING
                    if let followingConfig {
                        AvailableWidthContainer {
                            NXColumnView(config: followingConfig, isVisible: true)
                        }
                    }
                }
            }
//            .navigationBarHidden(true)
            .withNavigationDestinations()
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
            ScreenSpace.shared.mainTabSize = CGSize(width: dim.listWidth, height: ScreenSpace.shared.screenSize.height)
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
            guard !IS_IPAD || horizontalSizeClass == .compact else { return }
            guard selectedTab() == "Main" else { return }

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
