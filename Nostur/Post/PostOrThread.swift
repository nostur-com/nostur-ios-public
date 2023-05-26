//
//  PostOrThread.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/03/2023.
//

import SwiftUI

struct PostOrThread: View {
    @ObservedObject var nrPost: NRPost
//    var nrPost: NRPost
//    let fullWidth:Bool
    @ObservedObject var settings:SettingsStore = .shared

    var body: some View {
        VStack(spacing:0) {
            ForEach(nrPost.parentPosts.indices, id:\.self) { index in
                PostRowDeletable(nrPost: nrPost.parentPosts[index],
                        inThread: (nrPost.replyToId != nil && index != 0),
                                 connect: nrPost.parentPosts[index].replyToId != nil || index > 0 ? .both : .bottom, fullWidth: settings.fullWidthImages, isDetail: false)
                    .id(nrPost.parentPosts[index].id)
            }
            PostRowDeletable(nrPost: nrPost, inThread: nrPost.replyToId != nil && nrPost.parentPosts.count > 0, connect: nrPost.replyToId != nil ? .top : nil, fullWidth: settings.fullWidthImages, isDetail: false)
                .id(nrPost.id)
        }
        .boxShadow()
        .padding(.horizontal, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
        .padding(.vertical, 10)
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
            
            let nrPosts = onlyRootEvents.compactMap { NRPost(event: $0) }
            
            ScrollView {
                VStack(spacing: 0) {
    //                ForEach(nrPosts) { nrPost in
                    ForEach(Array(nrPosts.dropFirst(12))) { nrPost in
                        PostOrThread(nrPost: nrPost)
                            .overlay {
                                GeometryReader { geo in
                                    HStack {
                                        Spacer()
                                        Text("H: \(nrPost.anyName): \(Int(geo.size.height))")
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
