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
    @ObservedObject public var nrChat: NRChatMessage
    @State private var didStart = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                MiniPFP(pictureUrl: nrChat.contact?.pictureUrl)
                    .onTapGesture {
                        if IS_IPHONE {
                            if AnyPlayerModel.shared.viewMode == .detailstream {
                                AnyPlayerModel.shared.viewMode = .overlay
                            }
                            else if LiveKitVoiceSession.shared.visibleNest != nil {
                                LiveKitVoiceSession.shared.visibleNest = nil
                            }
                        }
                        if let nrContact = nrChat.contact {
                            navigateTo(NRContactPath(nrContact: nrContact, navigationTitle: nrContact.anyName))
                        }
                        else {
                            navigateTo(ContactPath(key: nrChat.pubkey))
                        }
                    }
                Text(nrChat.anyName ?? "...")
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
                        
                        if let nrContact = nrChat.contact {
                            navigateTo(NRContactPath(nrContact: nrContact, navigationTitle: nrContact.anyName))
                        }
                        else {
                            navigateTo(ContactPath(key: nrChat.pubkey))
                        }
                    }
                Ago(nrChat.created_at).foregroundColor(themes.theme.secondary)
            }
            ChatRenderer(nrChat: nrChat, availableWidth: vc.availableWidth, forceAutoload: false, theme: themes.theme, didStart: $didStart)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: 450, alignment: .top)
        }
        .onAppear {
            if !nrChat.missingPs.isEmpty {
                bg().perform {
                    QueuedFetcher.shared.enqueue(pTags: nrChat.missingPs)
                }
            }
        }
    }
}
