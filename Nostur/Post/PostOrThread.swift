//
//  PostOrThread.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/03/2023.
//

import SwiftUI

struct PostOrThread: View {
    var vPost: VPost
    let fullWidth:Bool
    
    init(vPost: VPost, fullWidth: Bool = false) {
        self.vPost = vPost
        self.fullWidth = fullWidth
    }

    var body: some View {
        VStack(spacing:0) {
            ForEach(vPost.parentPosts.indices, id:\.self) { index in
                PostRowDeletable(vPost: vPost.parentPosts[index],
                        inThread: (vPost.event.replyToId != nil && index != 0),
                        connect: vPost.parentPosts[index].event.replyToId != nil || index > 0 ? .both : .bottom, fullWidth: fullWidth, isDetail: false)
                    .id(vPost.parentPosts[index].id)
            }
            PostRowDeletable(vPost: vPost, inThread: vPost.event.replyToId != nil && vPost.parentPosts.count > 0, connect: vPost.event.replyToId != nil ? .top : nil, fullWidth: fullWidth, isDetail: false)
                .id(vPost.id)
        }
    }
}

struct PostOrThread_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            let ns:NosturState = .shared
            let events = PreviewFetcher.fetchEvents(ns.followingPublicKeys, kind: 1)
            
            let onlyRootEvents = events
                .map {
                    $0.parentEvents = Event.getParentEvents($0)
                    return $0
                }
                .filter(onlyRootOrReplyingToFollower)
            
            let vPosts = onlyRootEvents.compactMap { $0.toVPost() }
            
            ScrollView {
                VStack(spacing: 0) {
    //                ForEach(vPosts) { vPost in
                    ForEach(Array(vPosts.dropFirst(12))) { vPost in
                        PostOrThread(vPost: vPost)
                            .overlay {
                                GeometryReader { geo in
                                    HStack {
                                        Spacer()
                                        Text("H: \(vPost.event.username): \(Int(geo.size.height))")
                                            .padding(10)
                                            .foregroundColor(.white)
                                            .background(.red)
                                    }
                                }
                            }
                            .boxShadow()
                    }
                }
            }
            .background(.gray)
        }
        .withPreviewEnvironment()
    }
}


func onlyRootOrReplyingToFollower(_ event:Event) -> Bool {
    if let replyToPubkey = event.replyTo?.pubkey {
        if NosturState.shared.followingPublicKeys.contains(replyToPubkey) {
            return true
        }
    }
    return event.replyToId == nil
}
