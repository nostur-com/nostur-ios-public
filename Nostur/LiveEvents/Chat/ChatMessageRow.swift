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
    
    private var zoomableId: String
    
    init(nrChat: NRChatMessage, zoomableId: String = "Default") {
        self.nrChat = nrChat
        self.pfpAttributes = nrChat.pfpAttributes
        self.zoomableId = zoomableId
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
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
                        if let nrContact = pfpAttributes.contact {
                            navigateTo(NRContactPath(nrContact: nrContact, navigationTitle: nrContact.anyName))
                        }
                        else {
                            navigateTo(ContactPath(key: nrChat.pubkey))
                        }
                    }
                Text(pfpAttributes.anyName)
                    .foregroundColor(themes.theme.accent)
                    .onTapGesture {
                        if IS_IPHONE {
                            if AnyPlayerModel.shared.viewMode == .detailstream {
                                AnyPlayerModel.shared.viewMode = .overlay
                            }
                            else if LiveKitVoiceSession.shared.visibleNest != nil {
                                LiveKitVoiceSession.shared.visibleNest = nil
                            }
                        }
                        
                        if let nrContact = pfpAttributes.contact {
                            navigateTo(NRContactPath(nrContact: nrContact, navigationTitle: nrContact.anyName))
                        }
                        else {
                            navigateTo(ContactPath(key: nrChat.pubkey))
                        }
                    }
                Ago(nrChat.created_at).foregroundColor(themes.theme.secondary)
            }
            ChatRenderer(nrChat: nrChat, availableWidth: vc.availableWidth, forceAutoload: false, theme: themes.theme, zoomableId: zoomableId)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: 450, alignment: .top)
        }
    }
}
