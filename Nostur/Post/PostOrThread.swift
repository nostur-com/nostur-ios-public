//
//  PostOrThread.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/03/2023.
//

import SwiftUI

struct PostOrThread: View {
    let vPost:VPost
    let THREAD_LINE_OFFSET = 35.0
    let nav:NavigationModel = .shared
    
    @State var color1 = Color.purple
    @State var color2 = Color.green
    @State var color3 = Color.pink
    
    var body: some View {
        if let replyToVPost = vPost.event.replyTo?.toVPost() {
            VStack(spacing:0) {
                ZStack {
                    VStack(spacing:0) {
                        HStack(spacing:0) {
                            Color.secondary
                                .frame(maxWidth: 1, maxHeight: .infinity)
                                .padding(.top, 40)
                                .offset(x:THREAD_LINE_OFFSET, y: 30)
                            Spacer()
                        }
                    }
                    NoteRow(vPost: replyToVPost)
                }
                .background(Color.clear)
                .onTapGesture {
                    nav.navigateTo(replyToVPost)
                }

                NoteRow(vPost: vPost, inThread:true)
                .background(Color.clear)
                .onTapGesture {
                    nav.navigateTo(vPost)
                }
            }
        }
        else {
            NoteRow(vPost: vPost)
                .background(Color.clear)
                .onTapGesture {
                    nav.navigateTo(vPost)
                }
        }
    }
}

struct PostOrThread_Previews: PreviewProvider {
    static var previews: some View {
        let ns:NosturState = .shared
        let events = PreviewFetcher.fetchEvents(ns.followingPublicKeys, kind: 1)
        
        let onlyRootEvents = events
            .filter(onlyRootOrReplyingToFollower)
        
        let vPosts = onlyRootEvents.map { $0.toVPost() }
        
        VStack(spacing:0) {
            //            Text("following: \(ns.followingPublicKeys.count)")
            //            Text("vPosts: \(vPosts.count)")
            TimelineTest(vPosts: vPosts)
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


struct TimelineTest: View {
    var vPosts:[VPost] = []
    
    var body: some View {
        VStack(spacing:0) {
            List(vPosts) { vPost in
                PostOrThread(vPost: vPost)
//                    .background(.yellow)
                    .listRowInsets(EdgeInsets())
            }
            .listStyle(.plain)
        }
        .padding()
    }
}
