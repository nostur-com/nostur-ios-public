//
//  ContentTypeColumn.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/11/2025.
//

import SwiftUI
import NavigationBackport

// Copy pasta from PhoneViewish, turned from Following into Explore, Turned into generic ContentTypeColumn
struct ContentTypeColumn: View {
    @Environment(\.availableWidth) private var availableWidth
    @Environment(\.theme) private var theme
    
    public let pubkey: String
    @Binding var navPath: NBNavigationPath
    @Binding var columnType: MacColumnType
    
    @State private var didCreate = false
    @State var config: NXColumnConfig?
    
    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        ZStack {
            theme.listBackground // needed to give this ZStack and parents size, else weird startup animation sometimes
            // FOLLOWING
            if let config {
                AvailableWidthContainer {
                    NXColumnView(config: config, isVisible: true)
                        .modifier {
                            if #available(iOS 26.0, *) {
                                $0.toolbar {
                                    newPostButton(config)
                                        .sharedBackgroundVisibility(.hidden)
                                    settingsButton(config)
                                        .sharedBackgroundVisibility(.hidden)
                                }
                            }
                            else {
                                $0.toolbar {
                                    newPostButton(config)
                                    settingsButton(config)
                                }
                            }
                        }
                }
            }
        }
        .background(theme.listBackground)
        .onAppear {
            guard !didCreate else { return }
            didCreate = true
            createFeed(pubkey)
        }
        .onValueChange(pubkey) { oldPubkey, newPubkey in
            guard oldPubkey != newPubkey else { return }
            createFeed(pubkey)
        }
    }
    
    @ToolbarContentBuilder
    private func newPostButton(_ config: NXColumnConfig) -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if case .picture(_) = config.columnType { // No settings for .picture
                Button("Post New Photo", systemImage: "square.and.pencil") {
                    guard isFullAccount() else { showReadOnlyMessage(); return }
                    AppSheetsModel.shared.newPostInfo = NewPostInfo(kind: .picture)
                }
            }
            
            if case .yak(_) = config.columnType { // No settings for .yak
                Button("New Voice Message", systemImage: "square.and.pencil") {
                    guard isFullAccount() else { showReadOnlyMessage(); return }
                    AppSheetsModel.shared.newPostInfo = NewPostInfo(kind: .shortVoiceMessage)
                }
            }
            
            if case .vine(_) = config.columnType {
                Button("New Short Video", systemImage: "square.and.pencil") {
                    guard isFullAccount() else { showReadOnlyMessage(); return }
                    AppSheetsModel.shared.newPostInfo = NewPostInfo(kind: .shortVideos)
                }
            }
        }
    }
    
    @ToolbarContentBuilder
    private func settingsButton(_ config: NXColumnConfig) -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if case .vine(_) = config.columnType { // No settings for .vine
               
            }
            else { // Settings on every feed type except .vine
                Button(String(localized: "Feed Settings", comment: "Menu item for toggling feed settings"), systemImage: "gearshape") {
                    AppSheetsModel.shared.feedSettingsFeed = config.feed
                }
            }
        }
    }

    private func createFeed(_ pubkey: String) {
        let cloudFeedType: CloudFeedType = switch columnType {
        case .yaks(_):
            CloudFeedType.yak
        case .vines(_):
            CloudFeedType.vine
        default: // .photos(_)
            CloudFeedType.picture
        }

        let result = CloudFeed.reconciledAccountFeed(
            type: cloudFeedType,
            accountPubkey: pubkey,
            accountName: account(by: pubkey)?.anyName ?? pubkey,
            context: viewContext()
        )
        let feed = result.feed
        let feedColumnType: NXColumnType = switch columnType {
        case .yaks(_):
            .yak(feed)
        case .vines(_):
            .vine(feed)
        default: // .photos(_)
            .picture(feed)
        }

        config = NXColumnConfig(
            id: feed.subscriptionId,
            columnType: feedColumnType,
            accountPubkey: pubkey,
            name: "\(feed.feedTitle()) for \(account(by: pubkey)?.anyName ?? pubkey)"
        )
        if result.didChange {
            DataProvider.shared().saveToDiskNow(.viewContext)
        }
    }
}
