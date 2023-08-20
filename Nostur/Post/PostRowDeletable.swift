//
//  PostRowDeletable.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/05/2023.
//

import SwiftUI

struct PostRowDeletable: View {
    let nrPost:NRPost // Need for .deletedById
    @ObservedObject var postRowDeletableAttributes: NRPost.PostRowDeletableAttributes
    var hideFooter = true // For rendering in NewReply
    var missingReplyTo = false // For rendering in thread, hide "Replying to.."
    var connect:ThreadConnectDirection? = nil
    var fullWidth:Bool = false
    var isReply:Bool = false // is reply on PostDetail (needs 2*10 less box width)
    var isDetail:Bool = false
    var grouped:Bool = false
    
    init(nrPost:NRPost, hideFooter:Bool = false, missingReplyTo:Bool = false, connect: ThreadConnectDirection? = nil, fullWidth:Bool = false, isReply:Bool = false, isDetail:Bool = false, grouped:Bool = false) {
        self.nrPost = nrPost
        self.postRowDeletableAttributes = nrPost.postRowDeletableAttributes
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.fullWidth = fullWidth
        self.isReply = isReply
        self.isDetail = isDetail
        self.grouped = grouped
    }
    
    var body: some View {
        if postRowDeletableAttributes.blocked {
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
            NoteRow(nrPost: nrPost, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect, fullWidth: fullWidth, isReply: isReply, isDetail: isDetail, grouped:grouped)
        }
        else {
            Text("_Post deleted by \(nrPost.anyName)_", comment: "Message shown when a post is deleted by (name)").hCentered()
        }
    }
}
