//
//  PostOrThread.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/03/2023.
//

import SwiftUI

struct PostOrThread: View {
    @EnvironmentObject var theme:Theme
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
                Box(nrPost: nrParent) {
                    PostRowDeletable(nrPost: nrParent,
                                     missingReplyTo: nrParent.replyToId != rootId && nrParent.replyToId != nil && nrParent.id == nrPost.parentPosts.first?.id,
                                     connect: nrParent.replyToId != nil || nrPost.parentPosts.first?.id != nrParent.id ? .both : .bottom, fullWidth: settings.fullWidthImages, isDetail: false, grouped:grouped)
//                    .transaction { t in
//                        t.animation = nil
//                    }
                }
                .id(nrParent.id) // without .id the .ago on posts is wrong, not sure why. NRPost is Identifiable, Hashable, Equatable
                //                .padding([.top, .horizontal], nrParent.kind == 30023 ? -20 : 10)
//                .transaction { t in
//                    t.animation = nil
//                }
            }

            Box(nrPost: nrPost) {
                PostRowDeletable(nrPost: nrPost, missingReplyTo: nrPost.replyToId != rootId && nrPost.replyToId != nil && nrPost.parentPosts.isEmpty, connect: nrPost.replyToId != nil ? .top : nil, fullWidth: settings.fullWidthImages, isDetail: false, grouped:grouped)
//                    .transaction { t in
//                        t.animation = nil
//                    }
            }
            .id(nrPost.id) // without .id the .ago on posts is wrong, not sure why. NRPost is Identifiable, Hashable, Equatable
            .transaction { t in
                t.animation = nil
            }
        }
        .background {
            if nrPost.kind == 30023 {
                theme.secondaryBackground
                    .transaction { t in
                        t.animation = nil
                    }
            }
            else {
                theme.background
                    .transaction { t in
                        t.animation = nil
                    }
            }
        } // Still need .background here, normally use Box, but this is for between Boxes
//        .transaction { t in
//            t.animation = nil
//        }
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
                ###"["EVENT","A",{"pubkey":"97c70a44366a6535c145b333f973ea86dfdc2d7a99da618c40c64705ad98e322","content":"Does the same thing apply to nostr?\n\n\nhttps://us-southeast-1.linodeobjects.com/dufflepud/uploads/24de9cf4-edcf-4887-b533-06dd334db394.jpg","id":"15e05654e05286ce79200b77230556033f4bdae99ea290c65ddc1f684742f478","created_at":1692539490,"sig":"5c9c583f461f2d04e41cfde9ed2abfa973ffd9e8c9d8317afb7e61929e1db035dd60eff24f03e97edf832c2d0f98348fe3bf19be23f885c7c5f901e6e3f0612c","kind":1,"tags":[["client","coracle"]]}]"###,
                ###"["EVENT","A",{"pubkey":"1bc70a0148b3f316da33fe3c89f23e3e71ac4ff998027ec712b905cd24f6a411","content":"Which trade offs are we talking about?","id":"0047225fd5ba958d71725d0744cd21b9b6ace949acab69f1fcbb8db2a7020bed","created_at":1692541496,"sig":"d7f761b5023b25291bc90a5587db7cf497e87ff97fc4ab3635acad888e88f118e144b4df3481ae440e8f5268bb92b982783ce5b4d92e542b61e9c9875d347dbd","kind":1,"tags":[["e","15e05654e05286ce79200b77230556033f4bdae99ea290c65ddc1f684742f478"],["p","97c70a44366a6535c145b333f973ea86dfdc2d7a99da618c40c64705ad98e322"]]}]"###,
                ###"["EVENT", "1",{"pubkey":"958b754a1d3de5b5eca0fe31d2d555f451325f8498a83da1997b7fcd5c39e88c","content":"Fr fr \n\nps. wen dms","id":"52a42cd7eb167fd4890b12fe97542072dd0da5e4d84613d111d7e793e38beb4d","created_at":1685412992,"sig":"4ff41c04a84292976c21f479b1ed4ebe44fda1872ba15ff7c9db0eb42994a3fc8d83c0fce55135d2679d4db53ab8d13ead88a7dfe27461de4b876a9e02f32407","kind":1,"tags":[["e","1965f2a2f673265645a024c76aaab4ddf84a00fbc920473b9b87006a19c7197d"],["p","d61f3bc5b3eb4400efdae6169a5c17cabf3246b514361de939ce4a1a0da6ef4a"]]}]"###,
                ###"["EVENT", "2", {"pubkey":"d61f3bc5b3eb4400efdae6169a5c17cabf3246b514361de939ce4a1a0da6ef4a","content":"all questions that start with \"wen\" always have the same answer: \n\ntwo weeks","id":"b3ba8df46978ba2f463e14bd623da373088525e8673ef5f2b1995dff62c8f323","created_at":1685413160,"sig":"7f66f44c9e4f8c61e0725da40a7786015ee7dd25c6877fbb44d851a1de4e451656810fc6d7b548e77b8b6260d967c76d5a2d1644689662d828a25a2ec5f79f0a","kind":1,"tags":[["e","52a42cd7eb167fd4890b12fe97542072dd0da5e4d84613d111d7e793e38beb4d","","reply"],["p","958b754a1d3de5b5eca0fe31d2d555f451325f8498a83da1997b7fcd5c39e88c"]]}]"###
            ]
            pe.parseMessages(messages)
        }) {
            NavigationStack {
                SmoothListMock {
                    if let p = PreviewFetcher.fetchNRPost("0047225fd5ba958d71725d0744cd21b9b6ace949acab69f1fcbb8db2a7020bed") {
                        PostOrThread(nrPost: p)
                            .onAppear {
                                p.loadParents()
                            }
                    }
                    if let p = PreviewFetcher.fetchNRPost() {
                        PostOrThread(nrPost: p)
                            .onAppear {
                                p.loadParents()
                            }
                    }
                }
            }
        }
    }
}
