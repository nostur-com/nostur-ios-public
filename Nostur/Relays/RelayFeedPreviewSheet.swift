//
//  RelayFeedPreviewSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/08/2025.
//

import SwiftUI
import NavigationBackport

struct RelayFeedPreviewSheet: View {
    
    var config: NXColumnConfig
    
    @State private var relayConnectionAdded = false
    @State private var previewTitle = "Relay Preview"
    
    private var relayData: RelayData? {
        if case .relayPreview(let relayData) = config.columnType {
            return relayData
        }
        return nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if relayConnectionAdded {
                NXColumnView(config: config, isVisible: true, header: {
                    Button("Add this feed to your tabs") {
                        createFeed()
                    }
                    .frame(height: 40)
                })
            }
            else {
                CenteredProgressView()
            }
        }
        .environment(\.nxViewingContext, [.feedPreview])
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                CloseButton(action: {
                    AppSheetsModel.shared.dismiss() // Normal @Environment(\.dismiss) is broken with NavigationBackport
                })
            }

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
                previewFeedActionsMenu
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        
        .onAppear {
            if let relayData {
                previewTitle = relayData.url
            }
            addRelayConnection()
        }
    }
    
    private func addRelayConnection() {
        guard let relayData else { return }
        // Temporarily add relay connection to connection pool, or REQ will go nowhere
        ConnectionPool.shared.addConnection(relayData) { conn in
            conn.connect()
            Task { @MainActor in
                relayConnectionAdded = true
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
            createFeedFromRelayData(relayData)
        }
    }
}

@MainActor
func createFeedFromRelayData(_ relayData: RelayData) {
    // Create CloudFeed
    let newFeed = CloudFeed(context: DataProvider.shared().viewContext)
    newFeed.id = UUID()
    newFeed.name = relayData.url
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
    
    DataProvider.shared().save()
    
    // Close sheet
    AppSheetsModel.shared.dismiss()
    
    // Change active tab to this new feed
    UserDefaults.standard.setValue("Main", forKey: "selected_tab") // Main feed tab
    UserDefaults.standard.setValue("List", forKey: "selected_subtab") // Select List
    UserDefaults.standard.setValue(newFeed.subscriptionId, forKey: "selected_listId") // Which list
}

struct RelayFeedPreviewInfo: Identifiable, Equatable {
    let id = UUID()
    let config: NXColumnConfig
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
