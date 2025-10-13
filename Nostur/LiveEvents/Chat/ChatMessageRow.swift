//
//  ChatMessageRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/02/2025.
//

import SwiftUI

struct ChatMessageRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    @EnvironmentObject private var vc: ViewingContext
    @ObservedObject private var nrChat: NRChatMessage
    @ObservedObject private var nrContact: NRContact
    
    @ObservedObject var settings: SettingsStore = .shared
    
    private var zoomableId: String
    @Binding private var selectedContact: NRContact?
    
    init(nrChat: NRChatMessage, zoomableId: String = "Default", selectedContact: Binding<NRContact?>) {
        self.nrChat = nrChat
        self.nrContact = nrChat.nrContact
        self.zoomableId = zoomableId
        _selectedContact = selectedContact
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                MiniPFP(pictureUrl: nrContact.pictureUrl)
                
                Text(nrContact.anyName)
                    .foregroundColor(theme.accent)

                Ago(nrChat.created_at).foregroundColor(theme.secondary)
                
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
                selectedContact = nrContact
                if AnyPlayerModel.shared.viewMode == .detailstream {
                    AnyPlayerModel.shared.viewMode = .overlay
                }
                else if LiveKitVoiceSession.shared.visibleNest != nil {
                    LiveKitVoiceSession.shared.visibleNest = nil
                }
                
                navigateTo(NRContactPath(nrContact: nrContact, navigationTitle: nrContact.anyName), context: containerID)
            }))
            
            ChatRenderer(nrChat: nrChat, availableWidth: min(600, vc.availableWidth) - 10, forceAutoload: false, zoomableId: zoomableId)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: 1800, alignment: .top)
                .clipped()
        }
    }
}
