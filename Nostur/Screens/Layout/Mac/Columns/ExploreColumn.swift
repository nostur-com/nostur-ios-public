//
//  ExploreColumn.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/11/2025.
//

import SwiftUI
import NavigationBackport

// Copy pasta from PhoneViewish, turned from Following into Explore
struct ExploreColumn: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.availableWidth) private var availableWidth
    @Environment(\.theme) private var theme
    @ObservedObject private var ss: SettingsStore = .shared
    
    @State private var didCreate = false
    @State var exploreConfig: NXColumnConfig?
    
    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        ZStack {
            theme.listBackground // needed to give this ZStack and parents size, else weird startup animation sometimes
            // FOLLOWING
            if let exploreConfig {
                AvailableWidthContainer {
                    NXColumnView(config: exploreConfig, isVisible: true)
                        .modifier {
                            if #available(iOS 26.0, *) {
                                $0.toolbar {
                                    settingsButton(exploreConfig)
                                    .sharedBackgroundVisibility(.hidden)
                                }
                            }
                            else {
                                $0.toolbar {
                                    settingsButton(exploreConfig)
                                }
                            }
                        }
                }
            }
        }
        .onAppear {
            guard !didCreate else { return }
            didCreate = true
            createExploreFeed()
        }
        .background(theme.listBackground)
    }
    
    @ToolbarContentBuilder
    private func settingsButton(_ config: NXColumnConfig) -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(String(localized: "Feed Settings", comment: "Menu item for toggling feed settings"), systemImage: "gearshape") {
                AppSheetsModel.shared.feedSettingsFeed = config.feed
            }
        }
    }

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
            
            guard exploreFeeds.count > 1 else { return }
            for e in exploreFeedsNewest.dropFirst(1) {
                context.delete(e)
            }
            DataProvider.shared().saveToDiskNow(.viewContext)
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
            
            // Resume Where Left: Default on for contact-based. Default off for relay-based
            newExploreFeed.continue = true
            
            DataProvider.shared().saveToDiskNow(.viewContext) { // callback after save:
                exploreConfig = NXColumnConfig(id: newExploreFeed.subscriptionId, columnType: .following(newExploreFeed), accountPubkey: EXPLORER_PUBKEY, name: "Explore")
            }
        }
    }
}
