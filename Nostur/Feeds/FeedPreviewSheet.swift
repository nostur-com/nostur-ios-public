//
//  FeedPreviewSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/03/2025.
//

import SwiftUI
import NostrEssentials

struct FeedPreviewSheet: View {
    
    private var nrPost: NRPost // The kind:30000 list (from naddr or nevent)
    private let config: NXColumnConfig
    
    @ObservedObject private var pfpAttributes: PFPAttributes
    
    init(nrPost: NRPost, config: NXColumnConfig) {
        self.nrPost = nrPost
        self.config = config
        self.pfpAttributes = nrPost.pfpAttributes
    }
    
    var body: some View {
        NXColumnView(config: config, isVisible: true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                CloseButton(action: {
                    AppSheetsModel.shared.dismiss() // Normal @Environment(\.dismiss) is broken with NavigationBackport
                })
            }
            
            ToolbarItem(placement: .principal) {
                HStack {
                    Text("**\((nrPost.eventTitle ?? nrPost.dTag) ?? "List")** by ")
                        .lineLimit(1)
                        .layoutPriority(1)
                    ObservedPFP(pfp: nrPost.pfpAttributes, size: 20.0)
                        .onTapGesture {
                            navigateToContact(pubkey: nrPost.pubkey, nrPost: nrPost, pfpAttributes: pfpAttributes)
                        }
                        .layoutPriority(2)
                    Text(pfpAttributes.anyName)
                        .lineLimit(1)
                        .layoutPriority(3)
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                previewFeedActionsMenu
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var previewFeedActionsMenu: some View {
        Menu(content: {
            Button("Subscribe") {
                createFeedFromList()
            }
            
            Button("Copy list address") {
                let relaysForHint: Set<String> = resolveRelayHint(forPubkey: nrPost.pubkey, receivedFromRelays: nrPost.footerAttributes.relays)
                if let si = try? NostrEssentials.ShareableIdentifier("naddr", kind: Int(nrPost.kind), pubkey: nrPost.pubkey, dTag: nrPost.dTag, relays: Array(relaysForHint)) {
                    UIPasteboard.general.string = "nostr:\(si.identifier)"
                    
                    sendNotification(.anyStatus, ("Address copied to clipboard", "APP_NOTICE"))
                }
            }
        }, label: {
            Image(systemName: "pin.circle")
        })
    }
    
    private func createFeedFromList() {
        // Create CloudFeed
        let newFeed = CloudFeed(context: DataProvider.shared().viewContext)
        newFeed.id = UUID()
        newFeed.name = (nrPost.eventTitle ?? nrPost.dTag) ?? "List"
        newFeed.showAsTab = true
        newFeed.createdAt = .now
        newFeed.type = nrPost.kind == 39089 ? CloudFeedType.followPack.rawValue : CloudFeedType.followSet.rawValue
        newFeed.wotEnabled = false
        newFeed.contactPubkeys = config.pubkeys // TODO: Need to keep updated from kind:30000 updates
        newFeed.listId = nrPost.aTag
        newFeed.order = 0
        
        DataProvider.shared().save()
        
        // Close sheet
        AppSheetsModel.shared.dismiss()
        
        // Change active tab to this new feed
        UserDefaults.standard.setValue("Main", forKey: "selected_tab") // Main feed tab
        UserDefaults.standard.setValue("List", forKey: "selected_subtab") // Select List
        UserDefaults.standard.setValue(newFeed.subscriptionId, forKey: "selected_listId") // Which list
    }
}

struct FeedPreviewInfo: Identifiable, Equatable {
    let id = UUID()
    let config: NXColumnConfig
    let nrPost: NRPost
}

#Preview("Feed preview") {
    PreviewContainer({ pe in
        pe.parseMessages([
            ###"["EVENT","list",{"tags":[["d","OeZ118avD0JxUYiASaFfh"],["title","curmudgeons"],["p","0c405798e0e39caf54d2b211879ba1d6a965109b1389fa55da5bb20dd96ba5a0"],["p","52b4a076bcbbbdc3a1aefa3735816cf74993b1b8db202b01c883c58be7fad8bd"],["p","4c800257a588a82849d049817c2bdaad984b25a45ad9f6dad66e47d3b47e3b2f"],["p","80caa3337d33760ee355697260af0a038ae6a82e6d0b195c7db3c7d02eb394ee"],["p","c55476b5799dd1dd158aec8e1f319f1cdcef2768919670f1ed3e8f3e733a1732"],["p","fd208ee8c8f283780a9552896e4823cc9dc6bfd442063889577106940fd927c1"],["p","3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"]],"kind":30000,"pubkey":"9ca0bd7450742d6a20319c0e3d4c679c9e046a9dc70e8ef55c2905e24052340b","sig":"2c858e84623d36b81964eb10cd2ca02f38590e4e931c16f0c941e2734cfa1f0d38f3d2bcd09dcb504b4b33d07360c91d136caf217dd000976a75b39340b0eb36","id":"c4dab9d7ced0a943bc48a0c831e646085f2426ecbf68afc37f3ebe4abb87c89c","content":"","created_at":1743290706}]"###
        ])
        
    }) {
        if let kind3000list = PreviewFetcher.fetchNRPost("c4dab9d7ced0a943bc48a0c831e646085f2426ecbf68afc37f3ebe4abb87c89c") {
            let pubkeys = kind3000list.fastTags.filter { $0.0 == "p" && isValidPubkey($0.1) }.map { $0.1 }
            
            // 1. NXColumnConfig
            let config = NXColumnConfig(id: "FeedPreview", columnType: .pubkeysPreview(Set(pubkeys)), name: "Preview")
            
            // 2. NXColumnView
            FeedPreviewSheet(nrPost: kind3000list, config: config)
        }
    }
}
