//
//  ChatPendingZapRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/03/2025.
//

import SwiftUI

struct ChatPendingZapRow: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var dim: DIMENSIONS
    @EnvironmentObject private var vc: ViewingContext
    private var pendingZap: NRChatPendingZap
    @ObservedObject private var nrContact: NRContact
    
    @ObservedObject var settings: SettingsStore = .shared
    
    private var zoomableId: String
    @Binding private var selectedContact: NRContact?
    
    init(pendingZap: NRChatPendingZap, zoomableId: String = "Default", selectedContact: Binding<NRContact?>) {
        self.pendingZap = pendingZap
        self.nrContact = pendingZap.nrContact
        self.zoomableId = zoomableId
        _selectedContact = selectedContact
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.badge.clock.fill").foregroundColor(.yellow.opacity(0.75))
                    Text(pendingZap.amount.satsFormatted + " sats")
                        .fontWeightBold()
                }
                .padding(.leading, 7)
                .padding(.trailing, 8)
                
                .padding(.vertical, 2)
                .foregroundColor(Color.white)
                .background {
                    theme.accent
                        .clipShape(Capsule())
                }
                
                MiniPFP(pictureUrl: nrContact.pictureUrl)
                    
                Text(nrContact.anyName)
                    
                Ago(pendingZap.createdAt)
                    .foregroundColor(theme.secondary)

                if settings.displayUserAgentEnabled, let via = pendingZap.via {
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
                
                navigateToContact(pubkey: nrContact.pubkey, nrContact: nrContact, context: "Default")                
            }))
            .foregroundColor(theme.accent)
            
            NXContentRenderer(nxEvent: pendingZap.nxEvent, contentElements: pendingZap.content, zoomableId: zoomableId)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: 1800, alignment: .top)
                .clipped()
        }
    }
}
