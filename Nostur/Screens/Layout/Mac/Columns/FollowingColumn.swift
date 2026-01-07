//
//  FollowingColumn.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2026.
//


import SwiftUI
import NavigationBackport

// NotificationsColumn uses own StateObject for each column
// MainNotificationsColumn uses NotificationsViewModel.shared

struct FollowingColumn: View {
    @Environment(\.theme) private var theme
    @Environment(\.macColumnsState) private var vm
    public var pubkey: String
    @Binding public var columnType: MacColumnType
    public var isSomeoneElsesFeed: Bool = false
    
    @State private var columnConfig: NXColumnConfig?
    
    var body: some View {
        Container {
            if columnConfig == nil {
                ProgressView()
                    .onAppear {
                        if isSomeoneElsesFeed {
                            columnConfig = NXColumnConfig(id: "List-\(pubkey.prefix(18))", columnType: .someoneElses(pubkey), name: "Other feed")
                        }
                        else {
                            loadAccountFeed(pubkey)
                        }
                    }
            }
            else if let columnConfig {
                AvailableWidthContainer {
                    NXColumnView(config: columnConfig, isVisible: true)
//                        .modifier { // need to hide glass bg in 26+
//                            if #available(iOS 26.0, *) {
//                                $0.toolbar {
//                                    settingsButton
//                                        .sharedBackgroundVisibility(.hidden)
//                                }
//                            }
//                            else {
//                                $0.toolbar {
//                                    settingsButton
//                                }
//                            }
//                        }
                }
            }
        }
        .background(theme.listBackground)
        .onValueChange(pubkey, action: { oldPubkey, pubkey in
            guard oldPubkey != pubkey else { return }
            if isSomeoneElsesFeed {
                self.columnConfig = NXColumnConfig(id: "List-\(pubkey.prefix(18))", columnType: .someoneElses(pubkey), name: "Other feed")
            }
            else {
                loadAccountFeed(pubkey)
            }
        })
    }
    
    @MainActor
    private func loadAccountFeed(_ pubkey: String) {
        guard let account = account(by: pubkey) else { return }
        Task { @MainActor in
            let config = await createFollowingFeed(account)
            self.columnConfig = config
        }
    }
    
//    @ToolbarContentBuilder
//    private var settingsButton: some ToolbarContent {
//        ToolbarItem(placement: .navigationBarTrailing) {
//            Button(String(localized: "Feed Settings", comment: "Menu item for toggling feed settings"), systemImage: "gearshape") {
//                AppSheetsModel.shared.feedSettingsFeed = feed
//            }
//        }
//    }
}

//@available(iOS 17.0, *)
//#Preview {
//    @Previewable @State var navPath = NBNavigationPath()
//    @Previewable @State var columnType: MacColumnType = .following(nil)
//    PreviewContainer({ pe in
//        pe.loadContacts()
//        pe.loadPosts()
//    }) {
//        NBNavigationStack(path: $navPath) {
//            FollowingColumn(
//                pubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e",
//                navPath: $navPath,
//                columnType: $columnType
//            )
//        }
//    }
//}
//.onReceive(receiveNotification(.showingSomeoneElsesFeed)) { notification in
//    let nrContact = notification.object as! NRContact
//    if SettingsStore.shared.appWideSeenTracker {
//        Deduplicator.shared.onScreenSeen = []
//    }
//    createSomeoneElsesFeed(nrContact.pubkey)
//}


private func createFollowingFeed(_ account: CloudAccount) async -> NXColumnConfig {
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
        if followingFeeds.count > 1 {
            for f in followingFeedsNewest.dropFirst(1) {
                context.delete(f)
            }
            DataProvider.shared().saveToDiskNow(.viewContext)
        }
        return NXColumnConfig(id: followingFeed.subscriptionId, columnType: .following(followingFeed), accountPubkey: account.publicKey, name: "Following")
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
        
        return await withCheckedContinuation { continuation in
            DataProvider.shared().saveToDiskNow(.viewContext) { // callback after save:
                let config = NXColumnConfig(id: newFollowingFeed.subscriptionId, columnType: .following(newFollowingFeed), accountPubkey: account.publicKey, name: "Following")
                continuation.resume(returning: config)
            }
        }
    }
}
