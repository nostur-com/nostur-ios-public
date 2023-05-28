//
//  PostRowDeletable.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/05/2023.
//

import SwiftUI

struct PostRowDeletable: View {
    @ObservedObject var nrPost:NRPost // Need for .deletedById
    var hideFooter = true // For rendering in NewReply
    var missingReplyTo = false // For rendering in thread, hide "Replying to.."
    var connect:ThreadConnectDirection? = nil
    var fullWidth:Bool = false
    var isReply:Bool = false // is reply on PostDetail (needs 2*10 less box width)
    var isDetail:Bool = false
    var grouped:Bool = false
    
    init(nrPost:NRPost, hideFooter:Bool = false, missingReplyTo:Bool = false, connect: ThreadConnectDirection? = nil, fullWidth:Bool = false, isReply:Bool = false, isDetail:Bool = false, grouped:Bool = false) {
        self.nrPost = nrPost
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.fullWidth = fullWidth
        self.isReply = isReply
        self.isDetail = isDetail
        self.grouped = grouped
    }
    
    var body: some View {
        if nrPost.deletedById == nil {
            NoteRow(nrPost: nrPost, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect, fullWidth: fullWidth, isReply: isReply, isDetail: isDetail, grouped:grouped)
        }
        else {
            Text("_Post deleted by \(nrPost.anyName)_").hCentered()
        }
    }
}
