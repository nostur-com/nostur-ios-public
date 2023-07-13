//
//  PostOrThread.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/03/2023.
//

import SwiftUI

struct PostOrThread: View {
    @ObservedObject var nrPost: NRPost
    var grouped = false
    var rootId:String? = nil
    @ObservedObject var settings:SettingsStore = .shared

    var body: some View {
        VStack(spacing:0) {
            ForEach(nrPost.parentPosts) { nrParent in
                PostRowDeletable(nrPost: nrParent,
                                 missingReplyTo: nrParent.replyToId != rootId && nrParent.replyToId != nil && nrParent.id == nrPost.parentPosts.first?.id,
                                 connect: nrParent.replyToId != nil || nrPost.parentPosts.first?.id != nrParent.id ? .both : .bottom, fullWidth: settings.fullWidthImages, isDetail: false, grouped:grouped)
                    .frame(maxHeight: DIMENSIONS.POST_MAX_ROW_HEIGHT)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(nrParent.id)
            }
            PostRowDeletable(nrPost: nrPost, missingReplyTo: nrPost.replyToId != rootId && nrPost.replyToId != nil && nrPost.parentPosts.isEmpty, connect: nrPost.replyToId != nil ? .top : nil, fullWidth: settings.fullWidthImages, isDetail: false, grouped:grouped)
                .frame(maxHeight: DIMENSIONS.POST_MAX_ROW_HEIGHT)
                .fixedSize(horizontal: false, vertical: true)
                .id(nrPost.id)
        }
        .roundedBoxShadow()
        .padding(.horizontal, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
        .padding(.vertical, 10)
    }
}
//
//struct PostOrThread_Previews: PreviewProvider {
//    static var previews: some View {
//        VStack {
//            let ns:NosturState = .shared
//            let events = PreviewFetcher.fetchEvents(ns.followingPublicKeys, kind: 1)
//            
//            let onlyRootEvents = events
//                .map {
//                    $0.parentEvents = Event.getParentEvents($0)
//                    return $0
//                }
//                .filter(onlyRootOrReplyingToFollower)
//            
//            let nrPosts = onlyRootEvents.compactMap { NRPost(event: $0) }
//            
//            ScrollView {
//                VStack(spacing: 0) {
//    //                ForEach(nrPosts) { nrPost in
//                    ForEach(Array(nrPosts.dropFirst(12))) { nrPost in
//                        PostOrThread(nrPost: nrPost)
//                            .overlay {
//                                GeometryReader { geo in
//                                    HStack {
//                                        Spacer()
//                                        Text("H: \(nrPost.anyName): \(Int(geo.size.height))")
//                                            .padding(10)
//                                            .foregroundColor(.white)
//                                            .background(.red)
//                                    }
//                                }
//                            }
//                            .boxShadow()
//                    }
//                }
//            }
//            .background(.gray)
//        }
//        .withPreviewEnvironment()
//    }
//}


func onlyRootOrReplyingToFollower(_ event:Event) -> Bool {
    if let replyToPubkey = event.replyTo?.pubkey {
        if NosturState.shared.followingPublicKeys.contains(replyToPubkey) {
            return true
        }
    }
    return event.replyToId == nil
}

struct PostOrThreadSingle_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            let messages:[String] = [
                ###"["EVENT", "1",{"pubkey":"958b754a1d3de5b5eca0fe31d2d555f451325f8498a83da1997b7fcd5c39e88c","content":"Fr fr \n\nps. wen dms","id":"52a42cd7eb167fd4890b12fe97542072dd0da5e4d84613d111d7e793e38beb4d","created_at":1685412992,"sig":"4ff41c04a84292976c21f479b1ed4ebe44fda1872ba15ff7c9db0eb42994a3fc8d83c0fce55135d2679d4db53ab8d13ead88a7dfe27461de4b876a9e02f32407","kind":1,"tags":[["e","1965f2a2f673265645a024c76aaab4ddf84a00fbc920473b9b87006a19c7197d"],["p","d61f3bc5b3eb4400efdae6169a5c17cabf3246b514361de939ce4a1a0da6ef4a"]]}]"###,
                ###"["EVENT", "2", {"pubkey":"d61f3bc5b3eb4400efdae6169a5c17cabf3246b514361de939ce4a1a0da6ef4a","content":"all questions that start with \"wen\" always have the same answer: \n\ntwo weeks","id":"b3ba8df46978ba2f463e14bd623da373088525e8673ef5f2b1995dff62c8f323","created_at":1685413160,"sig":"7f66f44c9e4f8c61e0725da40a7786015ee7dd25c6877fbb44d851a1de4e451656810fc6d7b548e77b8b6260d967c76d5a2d1644689662d828a25a2ec5f79f0a","kind":1,"tags":[["e","52a42cd7eb167fd4890b12fe97542072dd0da5e4d84613d111d7e793e38beb4d","","reply"],["p","958b754a1d3de5b5eca0fe31d2d555f451325f8498a83da1997b7fcd5c39e88c"]]}]"###
            ]
            pe.parseMessages(messages)
        }) {
            NavigationStack {
                ScrollView {
                    LazyVStack {
                        if let p = PreviewFetcher.fetchNRPost() {
                            PostOrThread(nrPost: p)
                                .onAppear {
                                    p.loadParents()
                                }
                        }
                    }
                }
                .background(Color("ListBackground"))
            }
        }
    }
}
