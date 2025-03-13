//
//  EmbeddedPost.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/01/2025.
//

import SwiftUI

struct EmbeddedPost: View {
    private let nrPost: NRPost
    @ObservedObject var prd: PostRowDeletableAttributes
    private var fullWidth: Bool
    private var forceAutoload: Bool
    private var theme: Theme
    
    @EnvironmentObject private var parentDIM: DIMENSIONS
    
    init(_ nrPost: NRPost, fullWidth: Bool = false, forceAutoload: Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.prd = nrPost.postRowDeletableAttributes
        self.fullWidth = fullWidth
        self.forceAutoload = forceAutoload
        self.theme = theme
    }
    
    private var shouldAutoload: Bool { // Only for non-detail view. On detail we force show images.
        forceAutoload || SettingsStore.shouldAutodownload(nrPost)
    }
    
    var body: some View {
        if prd.blocked {
            HStack {
                Text("_Post from blocked account hidden_", comment: "Message shown when a post is from a blocked account")
                Button(String(localized: "Reveal", comment: "Button to reveal a blocked a post")) { nrPost.blocked = false }
                    .buttonStyle(.bordered)
            }
            .padding(.leading, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.lineColor, lineWidth: 1)
            )
            .hCentered()
        }
        else if nrPost.kind == 30023 {
            ArticleView(nrPost, hideFooter: true, forceAutoload: forceAutoload, theme: theme)
                .padding(20)
                .background(
                    Color(.secondarySystemBackground)
                        .cornerRadius(15)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(.regularMaterial, lineWidth: 1)
                )
//                .debugDimensions("EmbeddedPost.ArticleView", alignment: .bottomLeading)
        }
        else if nrPost.kind == 1 {
            QuotedNoteFragmentView(nrPost: nrPost, fullWidth: fullWidth, forceAutoload: forceAutoload, theme: theme)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.lineColor, lineWidth: 1)
                )
//                .debugDimensions("EmbeddedPost.QuotedNoteFragmentView", alignment: .bottomLeading)
        }
        else if nrPost.kind == 9802 {
            HighlightRenderer(nrPost: nrPost, theme: theme)
                .padding(.top, 3)
                .padding(.bottom, 10)
        }
        else {
            NoteRow(nrPost: nrPost, hideFooter: true, missingReplyTo: false, fullWidth: fullWidth, isReply: false, isDetail: false, grouped: false, theme: theme)
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 5)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.lineColor, lineWidth: 1)
                )
//                .debugDimensions("EmbeddedPost.QuotedNoteFragmentView", alignment: .bottomLeading)
        }
    }
}
