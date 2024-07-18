//
//  PostOrThread.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/03/2023.
//

import SwiftUI

struct PostOrThread: View {
    @EnvironmentObject private var themes: Themes
    private let nrPost: NRPost
    @ObservedObject private var postOrThreadAttributes: NRPost.PostOrThreadAttributes
    private var grouped = false
    private var rootId:String? = nil
    @ObservedObject private  var settings:SettingsStore = .shared
    
    init(nrPost: NRPost, grouped: Bool = false, rootId: String? = nil) {
        self.nrPost = nrPost
        self.postOrThreadAttributes = nrPost.postOrThreadAttributes
        self.grouped = grouped
        self.rootId = rootId
    }
    
    var body: some View {
//        #if DEBUG
//        let _ = Self._printChanges()
//        #endif
        if postOrThreadAttributes.parentPosts.isEmpty { // Single Post
            Box(nrPost: nrPost, theme: themes.theme) {
                PostRowDeletable(nrPost: nrPost, missingReplyTo: nrPost.replyToId != rootId && nrPost.replyToId != nil && postOrThreadAttributes.parentPosts.isEmpty, connect: nrPost.replyToId != nil ? .top : nil, fullWidth: settings.fullWidthImages, isDetail: false, grouped:grouped, theme: themes.theme)
//                    .transaction { t in
//                        t.animation = nil
//                    }
            }
            .id(nrPost.id) // without .id the .ago on posts is wrong, not sure why. NRPost is Identifiable, Hashable, Equatable
//            .withoutAnimation()
//            .transaction { t in
//                t.animation = nil
//            }
            .background {
                if nrPost.kind == 30023 {
                    themes.theme.secondaryBackground
//                        .withoutAnimation()
    //                    .transaction { t in
    //                        t.animation = nil
    //                    }
                }
                else {
                    themes.theme.background
//                        .withoutAnimation()
    //                    .transaction { t in
    //                        t.animation = nil
    //                    }
                }
            } // Still need .background here, normally use Box, but this is for between Boxes (in the same thread)
            .padding(.top, 10)
            .background { // This is the background between PostOrThread's.
                themes.theme.listBackground
//                    .withoutAnimation()
    //                .transaction { t in t.animation = nil }
            }
        }
        else { // Reply thread
            VStack(spacing: 10) {
                ForEach(postOrThreadAttributes.parentPosts) { nrParent in
                    Box(nrPost: nrParent, theme: themes.theme) {
                        PostRowDeletable(nrPost: nrParent,
                                         missingReplyTo: nrParent.replyToId != rootId && nrParent.replyToId != nil && nrParent.id == postOrThreadAttributes.parentPosts.first?.id,
                                         connect: nrParent.replyToId != nil || postOrThreadAttributes.parentPosts.first?.id != nrParent.id ? .both : .bottom, fullWidth: settings.fullWidthImages, isDetail: false, grouped:grouped, theme: themes.theme)
    //                    .transaction { t in
    //                        t.animation = nil
    //                    }
                    }
                    .id(nrParent.id) // without .id the .ago on posts is wrong, not sure why. NRPost is Identifiable, Hashable, Equatable
                    //                .padding([.top, .horizontal], nrParent.kind == 30023 ? -20 : 10)
//                    .withoutAnimation()
                    .fixedSize(horizontal: false, vertical: true) // Needed or we get whitespace, equal height posts
    //                .transaction { t in
    //                    t.animation = nil
    //                }
                }

                Box(nrPost: nrPost, theme: themes.theme) {
                    PostRowDeletable(nrPost: nrPost, missingReplyTo: nrPost.replyToId != rootId && nrPost.replyToId != nil && postOrThreadAttributes.parentPosts.isEmpty, connect: nrPost.replyToId != nil ? .top : nil, fullWidth: settings.fullWidthImages, isDetail: false, grouped:grouped, theme: themes.theme)
    //                    .transaction { t in
    //                        t.animation = nil
    //                    }
                }
                .id(nrPost.id) // without .id the .ago on posts is wrong, not sure why. NRPost is Identifiable, Hashable, Equatable
//                .withoutAnimation()
                .fixedSize(horizontal: false, vertical: true) // Needed or we get whitespace, equal height posts
    //            .transaction { t in
    //                t.animation = nil
    //            }
            }
            .background {
                if nrPost.kind == 30023 {
                    themes.theme.secondaryBackground
//                        .withoutAnimation()
    //                    .transaction { t in
    //                        t.animation = nil
    //                    }
                }
                else {
                    themes.theme.background
//                        .withoutAnimation()
    //                    .transaction { t in
    //                        t.animation = nil
    //                    }
                }
            } // Still need .background here, normally use Box, but this is for between Boxes (in the same thread)
            .padding(.top, 10)
            .background { // This is the background between PostOrThread's.
                themes.theme.listBackground
//                    .withoutAnimation()
    //                .transaction { t in t.animation = nil }
            }
        }
    }
}

struct PostOrThread15: View {
    private var themes: Themes
    private var dim: DIMENSIONS
    private let nrPost: NRPost
    private var grouped = false
    private var rootId: String? = nil
    
    init(nrPost: NRPost, grouped: Bool = false, rootId: String? = nil, themes: Themes, dim: DIMENSIONS) {
        self.nrPost = nrPost
        self.grouped = grouped
        self.rootId = rootId
        self.themes = themes
        self.dim = dim
    }
    
    var body: some View {
        PostOrThread(nrPost: nrPost, grouped: grouped, rootId: rootId)
            .environmentObject(themes)
            .environmentObject(dim)
    }
}

func onlyRootOrReplyingToFollower(_ event:Event) -> Bool {
    if let replyToPubkey = event.replyTo?.pubkey {
        if isFollowing(replyToPubkey) {
            return true
        }
    }
    return event.replyToId == nil
}

import NavigationBackport

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
            NBNavigationStack {
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

// Content to debug cutoff text, wrong .fixedSize etc
#Preview {
    PreviewContainer({ pe in
    
        pe.parseMessages([
            
            ###"["EVENT","repost",{"kind":6,"id":"43340b307c7b4cb76e29f3a8dd796279c5d27e1729d8ab3f68d961397d4c478a","pubkey":"eab0e756d32b80bcd464f3d844b8040303075a13eabc3599a762c9ac7ab91f4f","created_at":1721273990,"tags":[["e","53087fec373112df4c3e5d1f1b1d228473b55f50125dd6bd3640f411cad2e5cd"],["p","50d94fc2d8580c682b071a542f8b1e31a200b0508bab95a33bef0855df281d63"]],"content":"{\"tags\":[],\"id\":\"53087fec373112df4c3e5d1f1b1d228473b55f50125dd6bd3640f411cad2e5cd\",\"pubkey\":\"50d94fc2d8580c682b071a542f8b1e31a200b0508bab95a33bef0855df281d63\",\"content\":\"Huge milestone: First demo of Nostr Web Services (NWS) bringing TCP to Nostr. With NWS, you can host any existing web application on Nostr without having to use DNS or even announce your public IP to the world, simply by sharing your service's npub (or nprofile).\\n\\nTry it out the demo yourself. Here is a Cashu test mint running with NWS. Let's use curl to retrieve the mint's information. The request travels from your computer to the public NWS entry relay, then through nostr to the service's NWS exit relay. At the other end is a Cashu mint with HTTPS encryption.\\n\\n```\\ncurl -s -x socks5h:\\/\\/relay.8333.space:8882 https:\\/\\/nprofile1qqs8a8nk09fhrxylcd42haz8ev4cprhnk5egntvs0whafvaaxpk8plgpzemhxue69uhhyetvv9ujuwpnxvejuumsv93k2g6k9kr\\/v1\\/info --insecure | jq\\n```\\n\\nhttps:\\/\\/m.primal.net\\/JTMl.png \\n\\nI can't stress this enough: THE MINT RUNS BEHIND HTTPS!\\n\\nThe NWS entry relay can't read your traffic. It's encrypted. We can host public entry relays that can be used by anyone.\\n\\nThis means we can plug the entire internet to it 🌐.\\n\\nLet's plug it into Cashu for now. Nutshell wallet supports socks5 proxies (that's how it uses Tor). By setting the public entry relay as the proxy, the wallet can now connect to a mint's npub\\/nprofile and communicate with it via NWS.\\n\\nhttps:\\/\\/m.primal.net\\/JTot.png \\n\\nThis is going to be so freaking cool. And it's going to be a lot more useful than just for Cashu. There are still bugs and issues that need to be ironed out but the code is coming out soon. Watch this space.\",\"sig\":\"640d0ef5e8c7b3303e8077217ee43d3b8fcc45729bb50877684496c576e9ad477350602bb7d4b4731b12364a43fed84a5a1c1170d1529866607549b54d24ee60\",\"kind\":1,\"created_at\":1721208525}","sig":"791393a87acbc2b4a37053937837a4bb784f8c34f969d89c7bbd41a754479433ef5de8c0cf13a74ef9965b97a8a3b5deac21b82564b48c07839cd26c3559fac7"}]"###,
            ###"["EVENT",]"###,
            
//            ###"["EVENT","root",{"created_at":1721256083,"sig":"7e2ac6eee57c247c53d8eb066a0c8c93dbfa6b1b59fef65adf6e8f5d849abd28c6d2bda0e2bf28fc473b276605915b83058c8f8c28e45f6f2fd87420fdc5ed6a","pubkey":"04c960497af618ae18f5147b3e5c309ef3d8a6251768a1c0820e02c93768cc3b","content":"WOW !\nI am loving the Gallery #Amethyst\nThank you so much for this awesome improvement,  Devs!!! \nI was using tags to keep up with notes, but know I don't need it!!!\n\nYOU ARE DOING AN AMAZING WORK!!!\n\nI love #Nostr and I love you all! 🔥⚡🔥\nhttps://image.nostr.build/4c3ff209c0c57e7aef4629ebb04186e5f0f4fb7fb7e1dd2430bab5399b0b4e50.jpg\n\nhttps://image.nostr.build/a2ae05026bed7238481e967bdff18bb61ed508675014444cf704e6fc77802ef1.jpg","id":"c8b4b5268edc80b6e8af3288f6e3a73a991f908287fa3848e3054b7bbb140897","tags":[["t","Amethyst"],["t","amethyst"],["t","Nostr"],["t","nostr"],["r","https://image.nostr.build/4c3ff209c0c57e7aef4629ebb04186e5f0f4fb7fb7e1dd2430bab5399b0b4e50.jpg"],["r","https://image.nostr.build/a2ae05026bed7238481e967bdff18bb61ed508675014444cf704e6fc77802ef1.jpg"],["imeta","url https://image.nostr.build/4c3ff209c0c57e7aef4629ebb04186e5f0f4fb7fb7e1dd2430bab5399b0b4e50.jpg","m image/jpeg","alt Verifiable file url","x fc93d6ab17d4a723acebcfe50aecdf7d838cd0ad49f1ff34019cf1f4993de99b","size 34534","dim 1080x1080","blurhash UwM|]szwbtr@|qspn%W:RiX6S2W;r^WCbbj[","ox 4c3ff209c0c57e7aef4629ebb04186e5f0f4fb7fb7e1dd2430bab5399b0b4e50"],["imeta","url https://image.nostr.build/a2ae05026bed7238481e967bdff18bb61ed508675014444cf704e6fc77802ef1.jpg","m image/jpeg","alt Verifiable file url","x 71f27d5fa45d68e53da494d47ae10c0f9d2cd2c70a5bdbd7c47d26d27d47757e","size 34470","dim 1024x1024","blurhash UES#@xj[?wj[s.fkW=ay%hfPMcj[o~f6ROj[","ox a2ae05026bed7238481e967bdff18bb61ed508675014444cf704e6fc77802ef1"]],"kind":1}]"###,
            
//            ###"["EVENT","parent",{"id":"c0a2c2bdec5139129ee37ecbdc8b7b6f51a15ac5ac6b4e60c1692a62cc115778","created_at":1721259387,"sig":"6c1913f3b83ef648989a4f0d59c99f7c1fc144395141cff9f9ff9970c195d10fa993d628a2695ca83dc2e47324c54c03471bb26bda2ba7e680be0f1536c85c80","pubkey":"460c25e682fda7832b52d1f22d3d22b3176d972f60dcdc3212ed8c92ef85065c","tags":[["e","c8b4b5268edc80b6e8af3288f6e3a73a991f908287fa3848e3054b7bbb140897","","root"],["p","04c960497af618ae18f5147b3e5c309ef3d8a6251768a1c0820e02c93768cc3b"],["p","99bb5591c9116600f845107d31f9b59e2f7c7e09a1ff802e84f1d43da557ca64","","mention"]],"kind":1,"content":"You should thank nostr:nprofile1qqsfnw64j8y3zesqlpz3qlf3lx6eutmu0cy6rluq96z0r4pa54tu5eqpz9mhxue69uhkummnw3ezuamfdejj7qg4waehxw309aex2mrp0yhxgctdw4eju6t09uq3qamnwvaz7tmwdaehgu3wd4hk6tcdt5dav He did all of this. :)"}]"###,
            
            ###"["EVENT","parent",{"id":"67a2ff9cdd0f4dd1c3c2edc722451a079aea6db5d9cfd15b98173cc7fd4fb9df","content":"Is there any event metadata that would allow a client to recognize a post that is picture-focused? I’ve noticed in Nostur that nostr:npub1n0sturny6w9zn2wwexju3m6asu7zh7jnv2jt2kx6tlmfhs7thq0qnflahe is rendering long form differently in the timeline and it looks great. Could imagine a different rendering for pictures that would look cleaner (like instagram) if the client could parse those out","kind":1,"created_at":1721259769,"tags":[["e","c8b4b5268edc80b6e8af3288f6e3a73a991f908287fa3848e3054b7bbb140897","","root"],["e","c0a2c2bdec5139129ee37ecbdc8b7b6f51a15ac5ac6b4e60c1692a62cc115778","","reply"],["p","460c25e682fda7832b52d1f22d3d22b3176d972f60dcdc3212ed8c92ef85065c"],["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"],["client","Nostur","31990:9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33:1685868693432"]],"pubkey":"c80b5248fbe8f392bc3ba45091fb4e6e2b5872387601bf90f53992366b30d720","sig":"749364beb2ee193a3e5aab3d3f219d0d2fb099ce68dcad98b4cb5735d9ba9a2a9200effd6a3f5e40048783309db10b41d20cf4a490fee89fcd4cdf59b8515086"}]"###,
                            
            ###"["EVENT","reply",{"tags":[["e","c8b4b5268edc80b6e8af3288f6e3a73a991f908287fa3848e3054b7bbb140897","","root"],["e","c0a2c2bdec5139129ee37ecbdc8b7b6f51a15ac5ac6b4e60c1692a62cc115778"],["e","67a2ff9cdd0f4dd1c3c2edc722451a079aea6db5d9cfd15b98173cc7fd4fb9df","","reply"],["p","460c25e682fda7832b52d1f22d3d22b3176d972f60dcdc3212ed8c92ef85065c"],["p","9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"],["p","c80b5248fbe8f392bc3ba45091fb4e6e2b5872387601bf90f53992366b30d720"]],"created_at":1721259928,"kind":1,"id":"148f326f04d10c1ef210d25a434ae8a4bc9e1087e9ddd87ad9323e1d21aa9751","content":"Sure, it's all about coding the parser and sending it to a different layout 😎\n\nSend a pic of what you are referring from Nostur :)","pubkey":"460c25e682fda7832b52d1f22d3d22b3176d972f60dcdc3212ed8c92ef85065c","sig":"e3116437ffee9020bd9f5c6be5cbda4f445d0991b05a434dd7025d3360e8b7336b3c09f8dac551b3cc48558bf1db7cad1553cb2f30b0ba11375ea3720ca4a7fc"}]"###
        ])
        
        pe.loadPosts()
        pe.loadContacts()
        SettingsStore.shared.fullWidthImages = false
    }) {
        NBNavigationStack {
            SmoothListMock {
                
                Color.red
                    .frame(height: 30)
                    .debugDimensions("spacer", alignment: .center)
                
                if let fz = PreviewFetcher.fetchNRPost("43340b307c7b4cb76e29f3a8dd796279c5d27e1729d8ab3f68d961397d4c478a") {
                    PostOrThread(nrPost: fz)
                }
                
                if let reply = PreviewFetcher.fetchEvent("148f326f04d10c1ef210d25a434ae8a4bc9e1087e9ddd87ad9323e1d21aa9751") {
                    let _ = reply.parentEvents = Event.getParentEvents(reply, fixRelations: true)
                    let nrReply = NRPost(event: reply, withReplyTo: true, withParents: true, withReplies: false, plainText: false)
                    
                    PostOrThread(nrPost: nrReply)
                }
                
                if let p = PreviewFetcher.fetchNRPost() {
                    PostOrThread(nrPost: p)
                }
            }
        }
    }
}
