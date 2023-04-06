//
//  PostOrThread.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/03/2023.
//

import SwiftUI

struct PostOrThreadMaxOneParent: View {
    let vPost:VPost
    let THREAD_LINE_OFFSET = 35.0
    
    @State var color1 = Color.purple
    @State var color2 = Color.green
    @State var color3 = Color.pink
    
    var body: some View {
        if let replyToVPost = vPost.event.replyTo?.toVPost() {
            VStack(spacing: 0) {
                ZStack {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Color("LightGray")
                                .frame(maxWidth: 1, maxHeight: .infinity)
                                .padding(.top, 40)
                                .offset(x:THREAD_LINE_OFFSET, y: 32)
                            Spacer()
                        }
                    }
                    NoteRow(vPost: replyToVPost)
                }
                .background(Color.systemBackground)
                .onTapGesture {
                    navigateTo(replyToVPost)
                }
                
                ZStack {
                    VStack(spacing:0) {
                        HStack(spacing:0) {
                            Color("LightGray")
                                .frame(width: 1, height: 17)
                                .offset(x:THREAD_LINE_OFFSET, y: 0)
                            Spacer()
                        }
                        Spacer()
                    }
                    NoteRow(vPost: vPost, inThread: true)
                }
                .background(Color.systemBackground)
                .onTapGesture {
                    navigateTo(vPost)
                }
            }
        }
        else {
            NoteRow(vPost: vPost)
                .background(Color.systemBackground)
                .onTapGesture {
                    if (vPost.event.isRepost) {
                        if let vPostRepost = vPost.event.firstQuote?.toVPost() {
                            navigateTo(vPostRepost)
                        }
                        else if let firstQuoteId = vPost.event.firstQuoteId {
                            navigateTo(NotePath(id: firstQuoteId))
                        }
                        else {
                            navigateTo(vPost)
                        }
                    }
                    else {
                        navigateTo(vPost)
                    }
                }
        }
    }
}

struct PostOrThread: View {
    let vPost:VPost
    let THREAD_LINE_OFFSET = 35.0
    
    @State var color1 = Color.purple
    @State var color2 = Color.green
    @State var color3 = Color.pink
    
    var body: some View {
        if vPost.parentPosts.count > 0 {
            VStack(spacing: 0) {
                ForEach(vPost.parentPosts.indices, id:\.self) { index in
                    if index == 0 && vPost.parentPosts[index].event.replyToId != nil {
                        Button("Show this thread") {
                            navigateTo(vPost.parentPosts[index])
                        }.padding(.top, 10)
                    }
                    ZStack {
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                Color("LightGray")
                                    .frame(maxWidth: 1, maxHeight: .infinity)
                                    .padding(.top, index == 0 ? 40 : 0)
                                    .offset(x:THREAD_LINE_OFFSET, y: vPost.parentPosts[index].event.replyToId == nil  ? 32 : 0)
                                Spacer()
                            }
                        }
                        NoteRow(vPost: vPost.parentPosts[index], inThread: index == 0 ? false : true)
                    }
                    .id(vPost.id + vPost.parentPosts[index].id)
                    .background(Color.systemBackground)
                    .onTapGesture {
                        navigateTo(vPost.parentPosts[index])
                    }
                }
                ZStack {
                    VStack(spacing:0) {
                        HStack(spacing:0) {
                            Color("LightGray")
                                .frame(width: 1, height: 17)
                                .offset(x:THREAD_LINE_OFFSET, y: 0)
                            Spacer()
                        }
                        Spacer()
                    }
                    NoteRow(vPost: vPost, inThread: true)
                        .id(vPost.id)
                }
                .background(Color.systemBackground)
                .onTapGesture {
                    navigateTo(vPost)
                }
            }
        }
        else {
            VStack(spacing: 0) {
                if vPost.event.replyToId != nil {
                    Button("Show this thread") {
                        navigateTo(vPost)
                    }.padding(.top, 10)
                }
                NoteRow(vPost: vPost, inThread: false)
                    .id(vPost.id)
                    .background(Color.systemBackground)
                    .onTapGesture {
                        if (vPost.event.isRepost) {
                            if let vPostRepost = vPost.event.firstQuote?.toVPost() {
                                navigateTo(vPostRepost)
                            }
                            else if let firstQuoteId = vPost.event.firstQuoteId {
                                navigateTo(NotePath(id: firstQuoteId))
                            }
                            else {
                                navigateTo(vPost)
                            }
                        }
                        else {
                            navigateTo(vPost)
                        }
                    }
            }
        }
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
