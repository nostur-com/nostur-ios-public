//
//  KindResolver.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/05/2023.
//

import SwiftUI

struct KindResolver: View {
    
    let vPost:VPost
    var fullWidth:Bool = false
    var hideFooter:Bool = false // For rendering in NewReply
    var inThread:Bool = false // For rendering in thread
    var isReply:Bool = false 
    var isDetail:Bool = false
    var connect:ThreadConnectDirection? = nil
    var fetchOnAppear:Bool = false
    
    var body: some View {
        if vPost.isHighlight {
            Highlight(vPost: vPost, hideFooter: false, inThread:inThread, connect:connect)
                .onAppear {
                    guard fetchOnAppear else { return }
                    if vPost.event.contact == nil {
                        EventRelationsQueue.shared.addAwaitingEvent(vPost.event)
                        req(RM.getUserMetadata(pubkey: vPost.event.pubkey))
                    }
                }
        }
        else if fullWidth {
            Kind1(vPost: vPost, hideFooter:false, isDetail:isDetail)
                .onAppear {
                    guard fetchOnAppear else { return }
                    if vPost.event.contact == nil {
                        EventRelationsQueue.shared.addAwaitingEvent(vPost.event)
                        req(RM.getUserMetadata(pubkey: vPost.event.pubkey))
                    }
                }
        }
        else {
            Kind1Default(vPost: vPost, hideFooter:false, connect: connect, isDetail:isDetail)
                .onAppear {
                    guard fetchOnAppear else { return }
                    if vPost.event.contact == nil {
                        EventRelationsQueue.shared.addAwaitingEvent(vPost.event)
                        req(RM.getUserMetadata(pubkey: vPost.event.pubkey))
                    }
                }
        }
    }
}

struct KindResolver_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            if let vPost = PreviewFetcher.fetchVPost() {
                KindResolver(vPost: vPost)
            }
        }
        .withPreviewEnvironment()
    }
}
