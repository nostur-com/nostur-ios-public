//
//  DirectMessageRows.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/09/2023.
//

import SwiftUI
import NavigationBackport

struct DirectMessageRows: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var la: LoggedInAccount
    let pubkey: String
    @Binding var conversationRows: [Conversation]
    
    
    var body: some View {
        List {
            ForEach(conversationRows) { conv in
                NBNavigationLink(value: conv) {
                    AppEnvironment(la: la) {
                        ConversationRowView(conv)
                    }
                }
                .nbUseNavigationStack(.never)
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
                    .tint(Color.red)

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
                    .tint(theme.accent)
                }
            }
            .listRowBackground(theme.listBackground)
        }
        .listStyle(.plain)
    }
}
