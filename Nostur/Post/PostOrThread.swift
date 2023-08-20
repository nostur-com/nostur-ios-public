//
//  PostOrThread.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/03/2023.
//

import SwiftUI

struct Box<Content: View>: View {
    let content: Content
    var kind:Int = 1

    init(kind:Int = 1, @ViewBuilder _ content:()->Content) {
        self.kind = kind
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 10) {
            content
        }
        .padding(10)
        .background(kind == 30023 ? Color(.secondarySystemBackground) : Color.systemBackground)
    }
}

struct PostOrThread: View {
    let nrPost: NRPost
    @ObservedObject var postOrThreadAttributes: NRPost.PostOrThreadAttributes
    var grouped = false
    var rootId:String? = nil
    @ObservedObject var settings:SettingsStore = .shared
    
    init(nrPost: NRPost, grouped: Bool = false, rootId: String? = nil) {
        self.nrPost = nrPost
        self.postOrThreadAttributes = nrPost.postOrThreadAttributes
        self.grouped = grouped
        self.rootId = rootId
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(nrPost.parentPosts) { nrParent in
                PostRowDeletable(nrPost: nrParent,
                                 missingReplyTo: nrParent.replyToId != rootId && nrParent.replyToId != nil && nrParent.id == nrPost.parentPosts.first?.id,
                                 connect: nrParent.replyToId != nil || nrPost.parentPosts.first?.id != nrParent.id ? .both : .bottom, fullWidth: settings.fullWidthImages, isDetail: false, grouped:grouped)
                .contentShape(Rectangle())
                .onTapGesture {
                    if nrParent.kind == 30023 {
                        navigateTo(ArticlePath(id: nrParent.id, navigationTitle: nrParent.articleTitle ?? "Article"))
                    }
                    else {
                        navigateTo(nrParent)
                    }
                }
            }
            PostRowDeletable(nrPost: nrPost, missingReplyTo: nrPost.replyToId != rootId && nrPost.replyToId != nil && nrPost.parentPosts.isEmpty, connect: nrPost.replyToId != nil ? .top : nil, fullWidth: settings.fullWidthImages, isDetail: false, grouped:grouped)
                .contentShape(Rectangle())
                .onTapGesture {
                    if nrPost.isRepost {
                        if let firstQuote = nrPost.firstQuote {
                            if firstQuote.kind == 30023 {
                                navigateTo(ArticlePath(id: firstQuote.id, navigationTitle: firstQuote.articleTitle ?? "Article"))
                            }
                            else {
                                navigateTo(firstQuote)
                            }
                        }
                        else if let firstQuoteId = nrPost.firstQuoteId {
                            navigateTo(NotePath(id: firstQuoteId))
                        }
                    }
                    else {
                        if nrPost.kind == 30023 {
                            navigateTo(ArticlePath(id: nrPost.id, navigationTitle: nrPost.articleTitle ?? "Article"))
                        }
                        else {
                            navigateTo(nrPost)
                        }
                    }
                }
        }
        .padding(10)
        .background(nrPost.kind == 30023 ? Color(.secondarySystemBackground) : Color.systemBackground)
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
