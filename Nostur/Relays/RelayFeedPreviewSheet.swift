//
//  RelayFeedPreviewSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/08/2025.
//

import SwiftUI
import NavigationBackport

// For relay feeds
struct RelayFeedPreviewSheet: View {
    @Environment(\.theme) private var theme
    public var config: NXColumnConfig
    public var authPubkey: String? = nil

    @State private var previewTitle = "Relay Preview"
    
    private var relayData: RelayData? {
        if case .relayPreview(let relayData) = config.columnType {
            return relayData
        }
        return nil
    }
    
    var body: some View {
        NXColumnView(config: config, isVisible: true, header: {
            Button("Add this feed to your tabs") {
                createFeed()
            }
            .frame(height: 40)
            .frame(maxWidth: .infinity, alignment: .center) // Make toolbar background fill full width
            .background(theme.listBackground)
        })
        .environment(\.nxViewingContext, [.feedPreview])
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack {
                    Text(previewTitle)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    sendNotification(.shouldScrollToTop)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                HStack {
                    Button("Close", systemImage: "xmark") {
                        AppSheetsModel.shared.dismiss()
                    }
                    .labelStyle(.iconOnly)
                    
                    previewFeedActionsMenu
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        
        .onAppear {
            if let relayData {
                previewTitle = relayData.url
            }
        }
    }
    
    private var previewFeedActionsMenu: some View {
        Menu(content: {
            Button("Pin relay feed as tab") {
                createFeed()
            }
        }, label: {
            Image(systemName: "pin.circle")
        })
    }
    
    private func createFeed() {
        if let relayData {
            createFeedFromRelayData(relayData, authPubkey: authPubkey)
        }
    }
}

@MainActor
func createFeedFromRelayData(_ relayData: RelayData, authPubkey: String? = nil) {
    // Create CloudFeed
    let newFeed = CloudFeed(context: DataProvider.shared().viewContext)
    newFeed.id = UUID()
    newFeed.name = relayData.url
        .replacingOccurrences(of: "wss://", with: "") // remove wss:// from default title
        .replacingOccurrences(of: "ws://", with: "")  // remove ws:// from default title
    
    newFeed.relays = relayData.url
    
    if let cloudRelay = newFeed.relays_.first { // should be existing or added on the fly in CloudFeed.relays_ getter
        // almost always need auth for relay feeds
        cloudRelay.auth = true
    }
    
    newFeed.showAsTab = true
    newFeed.createdAt = .now
    newFeed.type = CloudFeedType.relays.rawValue
    newFeed.wotEnabled = false
    newFeed.order = 0
    newFeed.accountPubkey = authPubkey
    
    // Resume Where Left: Default on for contact-based. Default off for relay-based
    newFeed.continue = false
    
    DataProvider.shared().saveToDiskNow(.viewContext)
    
    // Close sheet
    AppSheetsModel.shared.dismiss()
    
    if IS_DESKTOP_COLUMNS() {
        // Create new column, or replace last column (if too many)
        if !MacColumnsVM.shared.allowAddColumn {
            MacColumnsVM.shared.columns.removeLast()
        }
        MacColumnsVM.shared.addColumn(MacColumnConfig(type: .cloudFeed, cloudFeedId: newFeed.id?.uuidString))
    }
    else {
        // Change active tab to this new feed
        UserDefaults.standard.setValue("Main", forKey: "selected_tab") // Main feed tab
        UserDefaults.standard.setValue("List", forKey: "selected_subtab") // Select List
        UserDefaults.standard.setValue(newFeed.subscriptionId, forKey: "selected_listId") // Which list
    }
}

struct RelayFeedPreviewInfo: Identifiable, Equatable {
    let id = UUID()
    let relayUrl: String
}

#Preview {
    PreviewContainer {
        NBNavigationStack {
            // 1. RelayData
            let relayData = RelayData.new(url: "ws://localhost:49201")
            
            // 2. NXColumnConfig
            let config = NXColumnConfig(id: "FeedPreview", columnType: .relayPreview(relayData), name: "Relay Preview")
            
            // 3. NXColumnView
            RelayFeedPreviewSheet(config: config)
        }
    }
}
