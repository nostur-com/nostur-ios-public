//
//  PostRowView.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/03/2025.
//

import SwiftUI

// Todo, when all works, rename to PostRowView
struct PostRowDeletable: View {
    private let nrPost: NRPost // Need for .deletedById
    @ObservedObject private var postRowDeletableAttributes: PostRowDeletableAttributes
    private var hideFooter = true // For rendering in NewReply
    private var missingReplyTo = false // For rendering in thread, hide "Replying to.."
    private var connect: ThreadConnectDirection? = nil
    private var fullWidth: Bool = false
    private var isReply: Bool = false // is reply on PostDetail (needs 2*10 less box width)
    private var isDetail: Bool = false
    private var isEmbedded: Bool = false
    private var ignoreBlock: Bool = false // Force show, when we open profile of blocked account
    private var theme: Theme
    
    init(nrPost: NRPost, hideFooter: Bool = false, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil, fullWidth: Bool = false, isReply: Bool = false, isDetail: Bool = false, isEmbedded: Bool = false, ignoreBlock: Bool = false, theme: Theme = Themes.default.theme) {
        self.nrPost = nrPost
        self.postRowDeletableAttributes = nrPost.postRowDeletableAttributes
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.fullWidth = fullWidth
        self.isReply = isReply
        self.isDetail = isDetail
        self.isEmbedded = isEmbedded
        self.ignoreBlock = ignoreBlock
        self.theme = theme
    }
    
    var body: some View {
//        #if DEBUG
//        let _ = Self._printChanges()
//        #endif
        if !ignoreBlock && postRowDeletableAttributes.blocked {
            HStack {
                Text("_Post from blocked account hidden_", comment: "Message shown when a post is from a blocked account")
                Button(String(localized: "Reveal", comment: "Button to reveal a blocked a post")) { nrPost.blocked = false }
                    .buttonStyle(.bordered)
            }
            .padding(.leading, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .hCentered()
        }
        else if postRowDeletableAttributes.deletedById == nil {
            if (nrPost.isRepost) {
                Repost(nrPost: nrPost, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect, fullWidth: fullWidth, isReply: isReply, isDetail: isDetail, theme: theme)
            }
            else { // IS NOT A REPOST
                KindResolver(nrPost: nrPost, fullWidth: fullWidth, hideFooter: hideFooter, missingReplyTo: missingReplyTo, isReply: isReply, isDetail: isDetail, isEmbedded: isEmbedded, connect: connect, theme: theme)
                    .onAppear { self.enqueue() }
                    .onDisappear { self.dequeue() }
            }
        }
        else {
            HStack {
                Text("_Post deleted by \(nrPost.anyName)_", comment: "Message shown when a post is deleted by (name)")
                Button(String(localized: "Undelete", comment: "Button to undelete a deleted post")) { nrPost.undelete() }
                    .buttonStyle(.bordered)
            }
            .padding(.leading, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .hCentered()
        }
    }
    
    private func enqueue() {
        if !nrPost.missingPs.isEmpty {
            bg().perform {
                EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "KindResolver.001")
                QueuedFetcher.shared.enqueue(pTags: nrPost.missingPs)
            }
        }
    }
    
    private func dequeue() {
        if !nrPost.missingPs.isEmpty {
            QueuedFetcher.shared.dequeue(pTags: nrPost.missingPs)
        }
    }
}
