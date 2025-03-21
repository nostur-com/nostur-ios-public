//
//  DirectMessageRows.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/09/2023.
//

import SwiftUI
import NavigationBackport

struct DirectMessageRows: View {
    @EnvironmentObject private var dim: DIMENSIONS
    @EnvironmentObject private var themes: Themes
    let pubkey: String
    @Binding var conversationRows: [Conversation]
    
    
    var body: some View {
        List {
            ForEach(conversationRows) { conv in
                NBNavigationLink(value: conv) {
                    AppEnvironment {
                        ConversationRowView(conv)
                            .environmentObject(dim)
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
                    .tint(themes.theme.accent)
                }
            }
            .listRowBackground(themes.theme.listBackground)
        }
        .listStyle(.plain)
    }
}
