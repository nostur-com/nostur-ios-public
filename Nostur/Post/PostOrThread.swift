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
    let nav:NavigationModel = .shared
    
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
                    nav.navigateTo(replyToVPost)
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
                    nav.navigateTo(vPost)
                }
            }
        }
        else {
            NoteRow(vPost: vPost)
                .background(Color.systemBackground)
                .onTapGesture {
                    if (vPost.event.isRepost) {
                        if let vPostRepost = vPost.event.firstQuote?.toVPost() {
                            nav.navigateTo(vPostRepost)
                        }
                        else if let firstQuoteId = vPost.event.firstQuoteId {
                            nav.navigateTo(NotePath(id: firstQuoteId))
                        }
                        else {
                            nav.navigateTo(vPost)
                        }
                    }
                    else {
                        nav.navigateTo(vPost)
                    }
                }
        }
    }
}

struct PostOrThread: View {
    let vPost:VPost
    let THREAD_LINE_OFFSET = 35.0
    let nav:NavigationModel = .shared
    
    @State var color1 = Color.purple
    @State var color2 = Color.green
    @State var color3 = Color.pink
    
    var body: some View {
        if vPost.parentPosts.count > 0 {
            VStack(spacing: 0) {
                ForEach(vPost.parentPosts) { parent in
                    ZStack {
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                Color("LightGray")
                                    .frame(maxWidth: 1, maxHeight: .infinity)
                                    .padding(.top, parent.event.replyToId == nil ? 40 : 0)
                                    .offset(x:THREAD_LINE_OFFSET, y: parent.event.replyToId == nil  ? 32 : 0)
                                Spacer()
                            }
                        }
                        NoteRow(vPost: parent)
//                            .background(Color.random)
                    }
                    .background(Color.systemBackground)
                    .onTapGesture {
                        nav.navigateTo(parent)
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
                }
                .background(Color.systemBackground)
                .onTapGesture {
                    nav.navigateTo(vPost)
                }
            }
        }
        else {
            NoteRow(vPost: vPost)
                .background(Color.systemBackground)
                .onTapGesture {
                    if (vPost.event.isRepost) {
                        if let vPostRepost = vPost.event.firstQuote?.toVPost() {
                            nav.navigateTo(vPostRepost)
                        }
                        else if let firstQuoteId = vPost.event.firstQuoteId {
                            nav.navigateTo(NotePath(id: firstQuoteId))
                        }
                        else {
                            nav.navigateTo(vPost)
                        }
                    }
                    else {
                        nav.navigateTo(vPost)
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
