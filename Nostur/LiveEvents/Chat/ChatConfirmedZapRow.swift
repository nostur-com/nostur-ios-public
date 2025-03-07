//
//  ChatPendingZapRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/03/2025.
//

import SwiftUI

struct ChatConfirmedZapRow: View {
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var dim: DIMENSIONS
    @EnvironmentObject private var vc: ViewingContext
    private var confirmedZap: NRChatConfirmedZap
    @ObservedObject private var pfpAttributes: PFPAttributes
    
    @State private var didStart = false
    
    init(confirmedZap: NRChatConfirmedZap) {
        self.confirmedZap = confirmedZap
        self.pfpAttributes = confirmedZap.pfpAttributes
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
                HStack {
                    
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill").foregroundColor(.yellow)
                        Text(confirmedZap.amount.satsFormatted)
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
                            if IS_IPHONE {
                                if AnyPlayerModel.shared.viewMode == .detailstream {
                                    AnyPlayerModel.shared.viewMode = .overlay
                                }
                                else if LiveKitVoiceSession.shared.visibleNest != nil {
                                    LiveKitVoiceSession.shared.visibleNest = nil
                                }
                            }
                            if let nrContact = confirmedZap.contact {
                                navigateTo(NRContactPath(nrContact: nrContact, navigationTitle: nrContact.anyName))
                            }
                            else {
                                navigateTo(ContactPath(key: confirmedZap.zapRequestPubkey))
                            }
                        }
                    
                    Text(pfpAttributes.anyName)
                        .onTapGesture {
                            if IS_IPHONE {
                                if AnyPlayerModel.shared.viewMode == .detailstream {
                                    AnyPlayerModel.shared.viewMode = .overlay
                                }
                                else if LiveKitVoiceSession.shared.visibleNest != nil {
                                    LiveKitVoiceSession.shared.visibleNest = nil
                                }
                            }
                            if let nrContact = confirmedZap.contact {
                                navigateTo(NRContactPath(nrContact: nrContact, navigationTitle: nrContact.anyName))
                            }
                            else {
                                navigateTo(ContactPath(key: confirmedZap.zapRequestPubkey))
                            }
                        }
                            
                    Ago(confirmedZap.zapRequestCreatedAt)
                        .foregroundColor(themes.theme.secondary)
                }
                .foregroundColor(themes.theme.accent)
                
                NXContentRenderer(nxEvent: confirmedZap.nxEvent, contentElements: confirmedZap.content, didStart: $didStart)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(maxHeight: 450, alignment: .top)
            }
    }
}
