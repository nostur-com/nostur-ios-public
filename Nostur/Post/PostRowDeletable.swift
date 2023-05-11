//
//  PostRowDeletable.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/05/2023.
//

import SwiftUI

struct PostRowDeletable: View {
    let vPost:VPost
    @ObservedObject var event:Event
    var hideFooter = true // For rendering in NewReply
    var inThread = false // For rendering in thread, hide "Replying to.."
    var connect:ThreadConnectDirection? = nil
    var fullWidth:Bool = false
    var isReply:Bool = false // is reply on PostDetail (needs 2*10 less box width)
    var isDetail:Bool = false
    var fetchOnAppear:Bool = false
    
    init(vPost:VPost, hideFooter:Bool = false, inThread:Bool = false, connect: ThreadConnectDirection? = nil, fullWidth:Bool = false, isReply:Bool = false, isDetail:Bool = false, fetchOnAppear:Bool = false) {
        self.vPost = vPost
        self.event = vPost.event
        self.hideFooter = hideFooter
        self.inThread = inThread
        self.connect = connect
        self.fullWidth = fullWidth
        self.isReply = isReply
        self.isDetail = isDetail
        self.fetchOnAppear = fetchOnAppear
    }
    
    var body: some View {
        if event.deletedById == nil {
            NoteRow(vPost: vPost, hideFooter: hideFooter, inThread: inThread, connect: connect, fullWidth: fullWidth, isReply: isReply, isDetail: isDetail, fetchOnAppear:fetchOnAppear)
        }
        else {
            Text("_Post deleted by \(vPost.displayName)_").hCentered()
        }
    }
}


//// TODO: ADD PREVIEW
//struct PostRowDeletable_Previews: PreviewProvider {
//    static var previews: some View {
//        PostRowDeletable()
//    }
//}
