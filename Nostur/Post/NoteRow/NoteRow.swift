//
//  NoteRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/03/2023.
//

import SwiftUI

struct NoteRow: View {
    private let nrPost: NRPost
    private var hideFooter = true // For rendering in NewReply
    private var missingReplyTo = false // For rendering in thread, hide "Replying to.."
    private var connect: ThreadConnectDirection? = nil
    private let fullWidth: Bool
    private let isReply: Bool // is reply on PostDetail (needs 2*10 less box width)
    private let isDetail: Bool
    private let grouped: Bool
    private var theme: Theme
    
    init(nrPost: NRPost, hideFooter: Bool = false, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil, fullWidth: Bool = false, isReply: Bool = false, isDetail: Bool = false, grouped: Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.fullWidth = fullWidth
        self.isReply = isReply
        self.isDetail = isDetail
        self.grouped = grouped
        self.theme = theme
    }
        
    var body: some View {
//        #if DEBUG
//        let _ = Self._printChanges()
//        #endif
        if (nrPost.isRepost) {
            Repost(nrPost: nrPost, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect, fullWidth: fullWidth, isReply: isReply, isDetail: isDetail, grouped: grouped, theme: theme)
        }
        else { // IS NOT A REPOST
            KindResolver(nrPost: nrPost, fullWidth: fullWidth, hideFooter: hideFooter, missingReplyTo: missingReplyTo, isReply: isReply, isDetail: isDetail, connect: connect, grouped: grouped, theme: theme)
                .onAppear { self.enqueue() }
                .onDisappear { self.dequeue() }
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

enum ThreadConnectDirection {
    case top
    case bottom
    case both
}
