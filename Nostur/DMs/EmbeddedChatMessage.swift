//
//  EmbeddedChatMessage.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/12/2025.
//

import SwiftUI

struct EmbeddedChatMessage: View {
    @Environment(\.theme) private var theme
    @Environment(\.availableWidth) private var availableWidth
    
    @ObservedObject var nrChatMessage: NRChatMessage
    var isSentByCurrentUser: Bool
    
    var body: some View {
        VStack(alignment: .leading) {
            ContactName(nrContact: nrChatMessage.nrContact)
                .fontWeightBold()
                .foregroundColor(isSentByCurrentUser ? .white : theme.primary)
            DMContentRenderer(pubkey: nrChatMessage.pubkey, contentElements: nrChatMessage.contentElementsDetail, availableWidth: availableWidth - 10, isSentByCurrentUser: isSentByCurrentUser)
        }
        .padding(8)
        .background(theme.secondary.opacity(0.3))
        .padding(.trailing, 15)
        .overlay(alignment: .leading) {
            nrChatMessage.nrContact.randomColor.frame(width: 4)
        }
    }
}
