//
//  ChatPendingZapRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/03/2025.
//

import SwiftUI

struct ChatConfirmedZapRow: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var dim: DIMENSIONS
    @EnvironmentObject private var vc: ViewingContext
    private var confirmedZap: NRChatConfirmedZap
    @ObservedObject private var nrContact: NRContact
    
    @ObservedObject var settings: SettingsStore = .shared
    
    private var zoomableId: String
    @Binding private var selectedContact: NRContact?

    
    init(confirmedZap: NRChatConfirmedZap, zoomableId: String = "Default", selectedContact: Binding<NRContact?>) {
        self.confirmedZap = confirmedZap
        self.nrContact = confirmedZap.nrContact
        self.zoomableId = zoomableId
        _selectedContact = selectedContact
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
                HStack {
                    
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill").foregroundColor(.yellow)
                        Text(confirmedZap.amount, format: .number.notation((.compactName)))
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
                            
                    Ago(confirmedZap.zapRequestCreatedAt)
                        .foregroundColor(theme.secondary)
                    
                    if settings.displayUserAgentEnabled, let via = confirmedZap.via {
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
                    
                    navigateTo(NRContactPath(nrContact: nrContact, navigationTitle: nrContact.anyName), context: "Default")
                }))
                .foregroundColor(theme.accent)
                
            NXContentRenderer(nxEvent: confirmedZap.nxEvent, contentElements: confirmedZap.content, zoomableId: zoomableId)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(maxHeight: 1800, alignment: .top)
                    .clipped()
            }
    }
}
