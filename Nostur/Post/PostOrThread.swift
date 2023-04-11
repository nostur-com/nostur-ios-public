//
//  PostOrThread.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/03/2023.
//

import SwiftUI

struct PostOrThread: View {
    var vPost: VPost

    var body: some View {
        VStack(spacing:0) {
            ForEach(vPost.parentPosts.indices, id:\.self) { index in
//                if index == 0 && vPost.parentPosts[index].event.replyToId != nil {
//                    Button("Show this thread") {
//                        navigateTo(vPost.parentPosts[index])
//                    }.padding(.top, 10)
//                }
                NoteRow(vPost: vPost.parentPosts[index],
                        inThread: (vPost.event.replyToId != nil && index != 0),
                        connect: vPost.parentPosts[index].event.replyToId != nil || index > 0 ? .both : .bottom)
                    .background(Color.systemBackground)
                    .onTapGesture {
                        guard vPost.event.deletedById == nil else { return }
                        navigateTo(vPost)
                    }
                    .id(vPost.parentPosts[index].id)
            }
//            if vPost.event.replyToId != nil && vPost.parentPosts.count == 0 {
//                Button("Show this thread") {
//                    navigateTo(vPost)
//                }.padding(.top, 10)
//            }
            NoteRow(vPost: vPost, inThread: vPost.event.replyToId != nil && vPost.parentPosts.count > 0, connect: vPost.event.replyToId != nil ? .top : nil)
                .background(Color.systemBackground)
                .onTapGesture {
                    guard vPost.event.deletedById == nil else { return }
                    if vPost.isRepost, let repostVPost = vPost.event.firstQuote?.toVPost() {
                        navigateTo(repostVPost)
                    }
                    else {
                        navigateTo(vPost)
                    }
                }
                .id(vPost.id)
        }
        .boxShadow()
        .padding(5)
        .background(Color("ListBackground"))
//        .onAppear {
//            print("onAPPEAR \(vPost.id)")
//        }
    }
}

struct PostOrThread_Previews: PreviewProvider {
    static var previews: some View {
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
            LazyVStack(spacing: 0) {
                ForEach(vPosts) { vPost in
//                ForEach(Array(vPosts.dropFirst(2))) { vPost in
                    PostOrThread(vPost: vPost)
                        .boxShadow()
                }
            }
        }
        .background(.gray)
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
