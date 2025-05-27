//
//  ChatPendingZapRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/03/2025.
//

import SwiftUI

struct ChatPendingZapRow: View {
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var dim: DIMENSIONS
    @EnvironmentObject private var vc: ViewingContext
    private var pendingZap: NRChatPendingZap
    @ObservedObject private var pfpAttributes: PFPAttributes
    
    private var zoomableId: String
    
    init(pendingZap: NRChatPendingZap, zoomableId: String = "Default") {
        self.pendingZap = pendingZap
        self.pfpAttributes = pendingZap.pfpAttributes
        self.zoomableId = zoomableId
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
                    themes.theme.accent
                        .clipShape(Capsule())
                }
                
                MiniPFP(pictureUrl: pfpAttributes.pfpURL)
                    .onTapGesture {
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
                            navigateTo(ContactPath(key: pendingZap.pubkey), context: "Default")
                        }
                    }
                Text(pfpAttributes.anyName)
                    .onTapGesture {
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
                            navigateTo(ContactPath(key: pendingZap.pubkey), context: "Default")
                        }
                    }
                Ago(pendingZap.createdAt)
                    .foregroundColor(themes.theme.secondary)
            }
            .foregroundColor(themes.theme.accent)
            
            NXContentRenderer(nxEvent: pendingZap.nxEvent, contentElements: pendingZap.content, zoomableId: zoomableId)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: 450, alignment: .top)
        }
    }
}
