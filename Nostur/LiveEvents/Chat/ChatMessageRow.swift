//
//  ChatMessageRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/02/2025.
//

import SwiftUI

struct ChatMessageRow: View {
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var dim: DIMENSIONS
    @EnvironmentObject private var vc: ViewingContext
    @ObservedObject private var nrChat: NRChatMessage
    @ObservedObject private var pfpAttributes: PFPAttributes
    
    @ObservedObject var settings: SettingsStore = .shared
    
    private var zoomableId: String
    @Binding private var selectedContact: NRContact?
    
    init(nrChat: NRChatMessage, zoomableId: String = "Default", selectedContact: Binding<NRContact?>) {
        self.nrChat = nrChat
        self.pfpAttributes = nrChat.pfpAttributes
        self.zoomableId = zoomableId
        _selectedContact = selectedContact
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                MiniPFP(pictureUrl: pfpAttributes.pfpURL)
                
                Text(pfpAttributes.anyName)
                    .foregroundColor(themes.theme.accent)

                Ago(nrChat.created_at).foregroundColor(themes.theme.secondary)
                
                if settings.displayUserAgentEnabled, let via = nrChat.via {
                    Text(String(format: "via %@", via))
                        .font(.subheadline)
                        .lineLimit(1)
                        .layoutPriority(3)
                        .foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
            .highPriorityGesture(TapGesture().onEnded({ _ in
                if let nrContact = pfpAttributes.contact {
                    selectedContact = nrContact
                }
                else if let nrContact = nrChat.contact {
                    selectedContact = nrContact
                }
                else {
                    if AnyPlayerModel.shared.viewMode == .detailstream {
                        AnyPlayerModel.shared.viewMode = .overlay
                    }
                    else if LiveKitVoiceSession.shared.visibleNest != nil {
                        LiveKitVoiceSession.shared.visibleNest = nil
                    }
                    
                    if let nrContact = pfpAttributes.contact {
                        navigateTo(NRContactPath(nrContact: nrContact, navigationTitle: nrContact.anyName), context: "Default")
                    }
                    else {
                        navigateTo(ContactPath(key: nrChat.pubkey), context: "Default")
                    }
                }
            }))
            
            ChatRenderer(nrChat: nrChat, availableWidth: min(600, vc.availableWidth) - 10, forceAutoload: false, theme: themes.theme, zoomableId: zoomableId)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: 1800, alignment: .top)
                .clipped()
        }
    }
}
