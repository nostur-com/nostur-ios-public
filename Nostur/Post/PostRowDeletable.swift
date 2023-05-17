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
    var inThread = false // For rendering in thread, hide "Replying to.."
    var connect:ThreadConnectDirection? = nil
    var fullWidth:Bool = false
    var isReply:Bool = false // is reply on PostDetail (needs 2*10 less box width)
    var isDetail:Bool = false
    
    init(nrPost:NRPost, hideFooter:Bool = false, inThread:Bool = false, connect: ThreadConnectDirection? = nil, fullWidth:Bool = false, isReply:Bool = false, isDetail:Bool = false) {
        self.nrPost = nrPost
        self.hideFooter = hideFooter
        self.inThread = inThread
        self.connect = connect
        self.fullWidth = fullWidth
        self.isReply = isReply
        self.isDetail = isDetail
    }
    
    var body: some View {
        if nrPost.deletedById == nil {
            NoteRow(nrPost: nrPost, hideFooter: hideFooter, inThread: inThread, connect: connect, fullWidth: fullWidth, isReply: isReply, isDetail: isDetail)
        }
        else {
            Text("_Post deleted by \(nrPost.anyDisplayName)_").hCentered()
        }
    }
}
