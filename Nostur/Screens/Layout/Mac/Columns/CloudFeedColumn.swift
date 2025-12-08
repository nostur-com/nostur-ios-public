//
//  CloudFeedColumn.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/10/2025.
//

import SwiftUI
import NavigationBackport

struct CloudFeedColumn: View {
    @Environment(\.theme) private var theme
    @Environment(\.macColumnsState) private var vm
    var feed: CloudFeed
    @State private var columnConfig: NXColumnConfig?
    
    var body: some View {
        Container {
            if columnConfig == nil {
                ProgressView()
                    .onAppear {
                        columnConfig = NXColumnConfig(id: feed.subscriptionId, columnType: feed.feedType, accountPubkey: feed.accountPubkey, name: feed.name_)
                    }
            }
            else if let columnConfig {
                AvailableWidthContainer {
                    NXColumnView(config: columnConfig, isVisible: true)
                        .modifier { // need to hide glass bg in 26+
                            if #available(iOS 26.0, *) {
                                $0.toolbar {
                                    settingsButton
                                    .sharedBackgroundVisibility(.hidden)
                                }
                            }
                            else {
                                $0.toolbar {
                                    settingsButton
                                }
                            }
                        }
                }
            }
        }
        .background(theme.listBackground)
        .onValueChange(feed, action: { oldFeed, newFeed in
            guard oldFeed != newFeed else { return }
            self.columnConfig = NXColumnConfig(
                id: newFeed.subscriptionId,
                columnType: newFeed.feedType,
                accountPubkey: newFeed.accountPubkey,
                name: newFeed.name_
            )
        })
    }
    
    @ToolbarContentBuilder
    private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(String(localized: "Feed Settings", comment: "Menu item for toggling feed settings"), systemImage: "gearshape") {
                AppSheetsModel.shared.feedSettingsFeed = feed
            }
        }
    }
}
