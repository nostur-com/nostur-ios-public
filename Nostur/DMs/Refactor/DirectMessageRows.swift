//
//  DirectMessageRows.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/09/2023.
//

import SwiftUI

struct DirectMessageRows: View {
    @EnvironmentObject var theme:Theme
    let pubkey:String
    @Binding var conversationRows:[Conversation]
    
    var body: some View {
        List {
            ForEach(conversationRows) { conv in
                NavigationLink(value: conv) {
                    ConversationRowView(conv)
                        .id(conv.contactPubkey)
                }
            }
            .listRowBackground(theme.listBackground)
        }
        .listStyle(.plain)
    }
}
