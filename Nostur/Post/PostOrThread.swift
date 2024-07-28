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
    @ObservedObject private var postOrThreadAttributes:  PostOrThreadAttributes
    private var grouped = false
    private var rootId: String? = nil
    @ObservedObject private  var settings: SettingsStore = .shared
    
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
            .padding(.top, 2)
            .background { // This is the background between PostOrThread's.
                themes.theme.listBackground
//                    .withoutAnimation()
    //                .transaction { t in t.animation = nil }
            }
        }
        else { // Reply thread
            VStack(spacing: 2) {
                ForEach(postOrThreadAttributes.parentPosts) { nrParent in
                    Box(nrPost: nrParent, theme: themes.theme) {
                        PostRowDeletable(nrPost: nrParent,
                                         hideFooter: true,
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
            .padding(.top, 2)
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

// Content to debug cutoff text, wrong .fixedSize etc
#Preview("Quotes in quotes") {
    PreviewContainer({ pe in
    
        pe.parseMessages([
            ###"["EVENT","qInq",{"id":"ff42811e971737587e4438356891b3f88cf8c06a609cec23a3bd6e3b3ac52616","sig":"e4798a9b9d7d4a92954f997928dbfcaf3e728a3e7ce6a829f835ad92ba06135631ff2806e8d488e98a1f424bb65930d0f285c25da959e218e15c251e0b18d7a9","tags":[],"created_at":1721000374,"pubkey":"27c4d775bedfaf861452eb366e5db3d9957eb2d4a226cd8856dd5e83760abcae","kind":1,"content":"YES\n\nnostr:note16mh6fvxk9deqlyd75l52ucfvh8ucqy2d95pgzxkw7rjwa67jcj0q6a6yvg"}]"###,
            ###"["EVENT","qInq",{"sig":"e5b5096155e52629ba734fc1fd6df1991e428a6974525c3915d27ca2c19dfe30c8281985f17c9ddd546b83387317fc00c1582763dde49c11aebb0049b7797477","created_at":1721000275,"content":"Did someone say circle jerk ?\nnostr:nevent1qqsdkdmkklqxcsnkhhntcgt5t7e5cxc63h4ftt8wj988jmz0p3ue65cpzpmhxue69uhkutn0dvczummjvuhsygqcjpws5htz82up4x96nrzc902l2le9qmrtszystlzen4dqkg5mpqpsgqqqqqqsugny48","kind":1,"pubkey":"45b35521c312a5da4c2558703ad4be3d2e6d08c812551514c7a1eb7ab5fa0f04","tags":[["e","db3776b7c06c4276bde6bc21745fb34c1b1a8dea95acee914e796c4f0c799d53","","mention"],["p","18905d0a5d623ab81a98ba98c582bd5f57f2506c6b808905fc599d5a0b229b08","","mention"],["q","db3776b7c06c4276bde6bc21745fb34c1b1a8dea95acee914e796c4f0c799d53"],["zap","18905d0a5d623ab81a98ba98c582bd5f57f2506c6b808905fc599d5a0b229b08","wss://filter.nostr.wine/npub1rzg96zjavgatsx5ch2vvtq4atatly5rvdwqgjp0utxw45zeznvyqfdkxve?broadcast=true","0.9"],["zap","45b35521c312a5da4c2558703ad4be3d2e6d08c812551514c7a1eb7ab5fa0f04","wss://n.ok0.org/","0.1"]],"id":"d6efa4b0d62b720f91bea7e8ae612cb9f980114d2d02811acef0e4eeebd2c49e"}]"###,
            ###"["EVENT","qInq",{"pubkey":"18905d0a5d623ab81a98ba98c582bd5f57f2506c6b808905fc599d5a0b229b08","created_at":1720999998,"tags":[["q","8db97c069042d7201e25b7b52a771442c9418ac682f95aab2de794f090695009"],["p","f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9"]],"content":"I am now 😂😂\nnostr:note13kuhcp5sgttjq839k76j5ac5gty5rzkxstu442edu720pyrf2qys5pm3x7","kind":1,"id":"db3776b7c06c4276bde6bc21745fb34c1b1a8dea95acee914e796c4f0c799d53","sig":"51a946d66c1ca6be0d14ab441e3c803ab15eaa3095aa161f2cd9f5c30fe32c4005f523d13a08f3fe0d9c314e17edeb4c9bcd01d77bbea8a35d929bae6c97f61b"}]"###,
            ###"["EVENT","qInq",{"tags":[["q","4d5059e97b3e338afc8999e86fdf8b406377d36739a29e0009b912c946dcb0d7"],["p","18905d0a5d623ab81a98ba98c582bd5f57f2506c6b808905fc599d5a0b229b08"]],"pubkey":"f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9","sig":"277e4c7674266d0b138436bb78d07e92e834f4345728e57a17c153740e7961a51b838ad7396571af3aa71f60ddba88d9ee648dca36f3a87dcbf544446a6bac9d","id":"8db97c069042d7201e25b7b52a771442c9418ac682f95aab2de794f090695009","kind":1,"content":"Are you on Nostur too? \nnostr:note1f4g9n6tm8cec4lyfn85xlhutgp3h05m88x3fuqqfhyfvj3kukrtsvffwnh","created_at":1720999883}]"###,
            ###"["EVENT","qInq",{"pubkey":"18905d0a5d623ab81a98ba98c582bd5f57f2506c6b808905fc599d5a0b229b08","id":"4d5059e97b3e338afc8999e86fdf8b406377d36739a29e0009b912c946dcb0d7","created_at":1720999817,"tags":[["p","f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9"],["p","f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9"]],"content":"Interesting 🤔 nostr:note1sgln5lzjs9zkj7xxphx7yvg46egxm27cw2fu4v95ancgzr204ccszcm53g","sig":"64f4d6e3d4572fc4c14834fccfbf075955d8a4adfdce701eeb4e6702016a20bf12213f0e8d44f53da52691588dc90da996eed6d4e7d0a8c890f52902f6bf2022","kind":1}]"###,
            ###"["EVENT","qInq",{"created_at":1720999255,"kind":1,"id":"823f3a7c5281456978c60dcde23115d6506dabd87293cab0b4ecf0810d4fae31","sig":"2a4b65bbc3811f421238249181ed706d0f1a8f1c9683f4a123f96e9fa6f1b18584ce971ad84863898e28b2bbba696fc2c8fc392ee0d5f7a9b1d8bf58dd3135df","content":"This is getting out control 🤣\nnostr:note13awfa3utvx6zrm3tclj6yu7d9dk7ncuzvnkjcufw9kmcwtjhukysknguaq","pubkey":"f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9","tags":[["q","8f5c9ec78b61b421ee2bc7e5a273cd2b6de9e38264ed2c712e2db7872e57e589"],["p","cb5a5f84f511e5c8039210f3887272ea8d806e5f7f5b26cb443f3b6ec8b15664"]]}]"###,
            ###"["EVENT","qInq",{"kind":1,"created_at":1720999175,"content":"👇👀 🫂\nnostr:nevent1qqsvgqmmtpe05vdj7ea9xcdx0qwxw70jhvzyavuddgm5e9gf2j5tt2qpz4mhxue69uhkummnw3ezummcw3ezuer9wchsyg8cumryxsh3upfysp3suflpq9kuud0u8fs5uczrflh54gjsxv5v4ypsgqqqqqqstl4h3r","id":"8f5c9ec78b61b421ee2bc7e5a273cd2b6de9e38264ed2c712e2db7872e57e589","pubkey":"cb5a5f84f511e5c8039210f3887272ea8d806e5f7f5b26cb443f3b6ec8b15664","sig":"87153d19869a4b6306455a0228fc5d27ee5d95bb2b10ae756a2154c8c7f43c845d9a9cfe534c5efdbaee24e03e9486f2e380827e8630131a5d8aca32fa68ea60","tags":[["e","c4037b5872fa31b2f67a5361a6781c6779f2bb044eb38d6a374c950954a8b5a8","","mention"],["p","f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9","","mention"],["q","c4037b5872fa31b2f67a5361a6781c6779f2bb044eb38d6a374c950954a8b5a8"],["zap","f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9","wss://relay.wellorder.net","0.9"],["zap","cb5a5f84f511e5c8039210f3887272ea8d806e5f7f5b26cb443f3b6ec8b15664","wss://nostrelay.yeghro.site/","0.1"]]}]"###,
            ###"["EVENT","qInq",{"tags":[["q","29df2a0d9a508770244ef39c8a7ead6b85abe6155f2f91a2b0b203765d882d56"],["p","9d7d214c58fdc67b0884669abfd700cfd7c173b29a0c58ee29fb9506b8b64efa"]],"sig":"b3319711937594a7faffe08ea6b6780f8d4fbcef24bdb19d2194e6b42fe186f969fb46740ef705d8996267f95114710d1c8c3ebf74432986cd180f33acb67d1d","created_at":1720999034,"pubkey":"f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9","content":"Shhh…don’t ask. Just quote. \nnostr:note1980j5rv62zrhqfzw7wwg5l4ddwz6hes4tuherg4skgphvhvg94tqxf4eyj","kind":1,"id":"c4037b5872fa31b2f67a5361a6781c6779f2bb044eb38d6a374c950954a8b5a8"}]"###,
            ###"["EVENT","qInq",{"kind":1,"created_at":1720998992,"tags":[["p","dc4cd086cd7ce5b1832adf4fdd1211289880d2c7e295bcb0e684c01acee77c06"],["p","dc4cd086cd7ce5b1832adf4fdd1211289880d2c7e295bcb0e684c01acee77c06"]],"id":"29df2a0d9a508770244ef39c8a7ead6b85abe6155f2f91a2b0b203765d882d56","content":"I’m sure it will all make sense at some point 🤔 nostr:note1ey2xw4y274cm9urx8ll80xkxt7c6uyu798g2g67ssn9t2skd35xq4tc7cv","sig":"31d1ea3f349fcb41063475a8a5229c36058278240b3f998d5736cad0278b4c0af80d37fc31b1ac1c2ce9bc23b2f09941b8cc89ab898c0d1a4a7eb57ee97a465f","pubkey":"9d7d214c58fdc67b0884669abfd700cfd7c173b29a0c58ee29fb9506b8b64efa"}]"###,
            ###"["EVENT","qInq",{"kind":1,"id":"c91467548af571b2f0663ffe779ac65fb1ae139e29d0a46bd084cab542cd8d0c","pubkey":"dc4cd086cd7ce5b1832adf4fdd1211289880d2c7e295bcb0e684c01acee77c06","sig":"013c3cfafa7d7e5fe96b87860583828f8d54db96bce15dc472b2c2d14673eae836abbba2b4cdc05db18351dc4ac902dbe91a30e6f2f909ca10a05677a6e409fa","tags":[["e","31136e20653f4f4915564b0b1451ec667dd7c139a6d2b848e86fab5066c26705","","mention"],["p","3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24","","mention"],["q","31136e20653f4f4915564b0b1451ec667dd7c139a6d2b848e86fab5066c26705"],["zap","3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24","ws://localhost:4869","1.0"]],"created_at":1720998809,"content":"I don't get it\nnostr:nevent1qqsrzymwypjn7n6fz4tykzc528kxvlwhcyu6d54cfr5xl26svmpxwpgpr4mhxue69uhkummnw3ezucnfw33k76twv4ezuum0vd5kzmp0qgsr7acdvhf6we9fch94qwhpy0nza36e3tgrtkpku25ppuu80f69kfqrqsqqqqqpu40cm2"}]"###,
            ###"["EVENT","qInq",{"pubkey":"3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24","sig":"7a79116e06e26e958e9c934aba9dd4df43fe497b0b2059b7640aa9b7eaa9b2c2fee0b558ea931752b9967a8cd8029ef4e44e60887ae9c1a16cef9749aadc9e4f","kind":1,"created_at":1720998527,"tags":[["e","4ce3a2cec3d46b6164e7eecb740be5ab017cc2a54f3771c6de72de650eb6ff7f","","mention"],["p","f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9","","mention"],["q","4ce3a2cec3d46b6164e7eecb740be5ab017cc2a54f3771c6de72de650eb6ff7f"]],"content":"👀\nnostr:nevent1qqsyecazempag6mpvnn7ajm5p0j6kqtuc2j57dm3cm089hn9p6m07lcpzdmhxue69uhk7enxvd5xz6tw9ec82c30qgs03ekxgdp0rczjfqrrpcn7zqtdec6lcwnpfesyxnl0f239qvege2grqsqqqqqpz4f9hv","id":"31136e20653f4f4915564b0b1451ec667dd7c139a6d2b848e86fab5066c26705"}]"###,
            ###"["EVENT","qInq",{"kind":1,"sig":"23bb6ae7bae13c161e0f30b6f20fc1accfeba2a9b41390f0fcb14acb0162a8fd19be4e52d382d766efa8efb58773eeb8620202e91d50dddd471e16689266e80b","created_at":1720998269,"id":"4ce3a2cec3d46b6164e7eecb740be5ab017cc2a54f3771c6de72de650eb6ff7f","tags":[],"content":"“Quote tweeting” is the social media equivalent of a circle jerk. ","pubkey":"f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9"}]"###
           
        ])
        
        SettingsStore.shared.fullWidthImages = false
    }) {
        NBNavigationStack {
            SmoothListMock {
                
                Color.red
                    .frame(height: 30)
                    .debugDimensions("spacer", alignment: .center)
                
                if let qq = PreviewFetcher.fetchNRPost("ff42811e971737587e4438356891b3f88cf8c06a609cec23a3bd6e3b3ac52616") {
                    PostOrThread(nrPost: qq)
                }
            }
        }
    }
}


// Content to debug cutoff text, wrong .fixedSize etc
#Preview("Japanese characters bug") {
    PreviewContainer({ pe in
    
        pe.parseMessages([
            ###"["EVENT","jap",{"content":"出張の帰りに新幹線で報告書まとめたら後で楽だなあと思ってパソコン開いたけど気持ち悪くなってやめたことあるL cuttttttt tttof d d d d d d d d d a b c d","tags":[],"created_at":1721348354,"kind":1,"id":"3dcaf40eaf8820d97d0fc5ae9a2eed02b356717c88c3ee6a46f1a7d18e5caf4f","pubkey":"26bb2ebed6c552d670c804b0d655267b3c662b21e026d6e48ac93a6070530958","sig":"0be801ce1e447e59e40f8f25b3a2865ef667b1393baae7660edbbdd7e32a86bafd9fbc1b0548ddceb39f6706fec18df6b60ffd87ed4e255baa9b9428b59b1558"}]"###
        ])
        
        SettingsStore.shared.fullWidthImages = false
    }) {
        NBNavigationStack {
            SmoothListMock {
                
                Color.red
                    .frame(height: 30)
                    .debugDimensions("spacer", alignment: .center)
                
                Text("出張の帰りに新幹線で報告書まとめたら後で楽だなあと思ってパソコン開いたけど気持ち悪くなってやめたことあるL cuttttttt tttof d d d d d d d d d a b c d")
                
                if let qq = PreviewFetcher.fetchNRPost("3dcaf40eaf8820d97d0fc5ae9a2eed02b356717c88c3ee6a46f1a7d18e5caf4f") {
                    PostOrThread(nrPost: qq)
                }
            }
        }
    }
}
