//
//  DirectMessageRows.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/09/2023.
//

import SwiftUI

struct DirectMessageRows: View {
    @EnvironmentObject private var themes:Themes
    let pubkey:String
    @Binding var conversationRows:[Conversation]
    
    
    var body: some View {
        List {
            ForEach(conversationRows) { conv in
                NavigationLink(value: conv) {
                    ConversationRowView(conv)
                        .swipeActions {
                            Button(role: .destructive) {
                                conv.dmState.isHidden.toggle()
                                DirectMessageViewModel.default.load()
                            } label: {
                                if conv.dmState.isHidden {
                                    Label("Unhide", systemImage: "trash.slash")
                                }
                                else {
                                    Label("Hide", systemImage: "trash")
                                }
                            }
   
                            Button {
                                conv.dmState.isPinned.toggle()
                                DirectMessageViewModel.default.load()
                            } label: {
                                if conv.dmState.isPinned {
                                    Label("Unpin", systemImage: "pin.slash")
                                }
                                else {
                                    Label("Pin", systemImage: "pin")
                                }
                            }
                            .tint(themes.theme.accent)
                        }
                }
            }
            .listRowBackground(themes.theme.listBackground)
        }
        .listStyle(.plain)
    }
}
