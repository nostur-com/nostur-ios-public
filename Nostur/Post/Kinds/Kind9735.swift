//
//  Kind9735.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/06/2026.
//

import SwiftUI

struct Kind9735: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    @Environment(\.availableWidth) private var availableWidth
    
    @ObservedObject private var settings: SettingsStore = .shared
    private let nrPost: NRPost
    @ObservedObject private var nrContact: NRContact
    @State private var showMore = false
    
    private let hideFooter: Bool // For rendering in NewReply
    private let missingReplyTo: Bool // For rendering in thread
    private var connect: ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    private let isReply: Bool // is reply on PostDetail
    private let isDetail: Bool
    private let isEmbedded: Bool
    private let fullWidth: Bool
    private let grouped: Bool
    private let forceAutoload: Bool
    private let fromPubkey: String
    
    private let THREAD_LINE_OFFSET = 24.0
    
    
    private var availableWidth_: CGFloat { // dim.listWidth is now .availableWidth, so now this one is .availableWidth_
        if isDetail || fullWidth || isEmbedded {
            return availableWidth - 20
        }
        
        return DIMENSIONS.availableNoteRowImageWidth(availableWidth)
    }
    
    private var isOlasGeneric: Bool { (nrPost.kind == 1 && (nrPost.kTag ?? "") == "20") }
    
    @State var showMiniProfile = false
    @State var clipBottomHeight: CGFloat = 900.0
    
    init(nrPost: NRPost, hideFooter: Bool = true, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil,
         isReply: Bool = false, isDetail: Bool = false, isEmbedded: Bool = false, fullWidth: Bool, grouped: Bool = false,
         forceAutoload: Bool = false, fromPubkey: String) {
        self.nrPost = nrPost
        self.nrContact = nrPost.contact
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.isReply = isReply
        self.fullWidth = fullWidth
        self.isDetail = isDetail
        self.isEmbedded = isEmbedded
        self.grouped = grouped
        self.forceAutoload = forceAutoload
        self.fromPubkey = fromPubkey
//        _clipBottomHeight = State(wrappedValue: isEmbedded ? 300.0 : 900.0)
    }
    
    var body: some View {
        if nrPost.plainTextOnly {
            Text("TODO PLAINTEXTONLY") // TODO: PLAIN TEXTO ONLY
        }
        else if isEmbedded {
            self.embeddedView
        }
        else {
            self.normalView
        }
    }
    
    private var shouldAutoload: Bool {
        return !nrPost.isNSFW && (forceAutoload || SettingsStore.shouldAutodownload(nrPost) || nxViewingContext.contains(.screenshot))
    }
    
    @ViewBuilder
    private var normalView: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        ZapLayout(nrPost: nrPost, fromPubkey: fromPubkey, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect, isReply: isReply,
                   isDetail: isDetail, fullWidth: fullWidth || isOlasGeneric, forceAutoload: forceAutoload, isItem: true, nxViewingContext: nxViewingContext, containerID: containerID, theme: theme, availableWidth: availableWidth) {
            if (isDetail) {
                if availableWidth < 75 { // Probably too many embeds in embeds in embeds in embeds, no space left
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                ContentRenderer(nrPost: nrPost, showMore: .constant(true), isDetail: isDetail, fullWidth: fullWidth, forceAutoload: forceAutoload)
                    .environment(\.availableWidth, availableWidth_)
                    .frame(maxWidth: .infinity, alignment:.leading)
            }
            else {
                if availableWidth < 75 { // Probably too many embeds in embeds in embeds in embeds, no space left
                    Image(systemName: "exclamationmark.triangle.fill")
                }

                ContentRenderer(nrPost: nrPost, showMore: $showMore, isDetail: isDetail, fullWidth: fullWidth, forceAutoload: forceAutoload)
                    .environment(\.availableWidth, availableWidth_)
//                    .fixedSize(horizontal: false, vertical: true) // <-- this or child .fixedSizes will try to render outside frame and cutoff (because clipped() below)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: nrPost.sizeEstimate.rawValue, maxHeight: clipBottomHeight, alignment: .top)
                    .clipBottom(height: clipBottomHeight)
                    .overlay(alignment: .bottomTrailing) {
                        if (nrPost.previewWeights?.moreItems ?? false) && !showMore {
                            ZStack(alignment: .bottomTrailing) { // Make whole area tappable for expand / show more
                                Color.clear
                                Image(systemName: "chevron.compact.down")
                                    .foregroundColor(.white)
                                    .padding(5)
                                    .padding(.top, 5)
                                    .background {
                                        RoundedRectangle(cornerRadius: 5)
                                            .foregroundColor(theme.accent)
                                    }
                            }
                            .contentShape(Rectangle())
                            .highPriorityGesture(TapGesture().onEnded {
                                showMore = true
                                clipBottomHeight = 28000.0
                            })
                        }
                    }
            }
        }
    }
    
    @ViewBuilder
    private var embeddedView: some View {
        PostEmbeddedLayout(nrPost: nrPost) {
            if availableWidth < 75 { // Probably too many embeds in embeds in embeds in embeds, no space left
                Image(systemName: "exclamationmark.triangle.fill")
            }
            HStack(alignment: .top, spacing: 5) {
                ZapAmountView(nrPost: nrPost, fromPubkey: fromPubkey, withPFP: false, nxViewingContext: nxViewingContext, containerID: containerID, theme: theme)
                
                ContentRenderer(nrPost: nrPost, showMore: $showMore, isDetail: false, fullWidth: fullWidth, forceAutoload: shouldAutoload)
                    .environment(\.availableWidth, availableWidth_)
                    .frame(minHeight: nrPost.sizeEstimate.rawValue, maxHeight: clipBottomHeight, alignment: .top)
                    .clipBottom(height: clipBottomHeight)
                    .overlay(alignment: .bottomTrailing) {
                        if (nrPost.previewWeights?.moreItems ?? false) && !showMore {
                            ZStack(alignment: .bottomTrailing) { // Make whole area tappable for expand / show more
                                Color.clear
                                
                                Image(systemName: "chevron.compact.down")
                                    .foregroundColor(.white)
                                    .padding(5)
                                    .padding(.top, 5)
                                    .background {
                                        RoundedRectangle(cornerRadius: 5)
                                            .foregroundColor(theme.accent)
                                    }
                            }
                            .contentShape(Rectangle())
                            .highPriorityGesture(TapGesture().onEnded {
                                showMore = true
                                clipBottomHeight = 28000.0
                            })
                        }
                    }
            }
        }
    }
}

@available(iOS 26.0, *)
#Preview("Reply to zap") {
    @Previewable @Environment(\.theme) var theme
  
    PreviewContainer({ pe in
//        pe.parseMessages([
//            ###"["EVENT", "post", {"sig":"d738ce15015972d0697547bd62608ff07c57cbddc8030a5ee7f4004661a8bb46e623edf099678b778430f35619137a78b52d315ba34699d5bac864b44576175a","tags":[["t","gitcitadel"],["client","imwald"]],"id":"81c213f681ca1410c4033cf12bdfa0855cd28cfadb78ff6111457a7f3c45bd4a","kind":1,"pubkey":"dd664d5e4016433a8cd69f005ae1480804351789b59de5af06276de65633d319","created_at":1780290709,"content":"Watching the whole Nostr money debates...\nWhen your team couldn't get a grant.\nWhen your team couldn't get a NIP.\nWhen you're running on volunteers,  donations, and fees.\nWhen you have to grind every zap into dust and dig out the leftover change from your day job, to squeeze out the infrastructure costs.\nWhen you build and run everything as cheaply as possible because you are broke.\n\nhttps://media.tenor.com/frMfHHLz05YAAAAC/atg-stucapa.gif\n\nGM 💖\n\nWe are still here. We are still building. And there are now more of us. #GitCitadel"}]"###,
//            ###"["EVENT", "zap", {"sig":"421f4afd6a3ef4d0c08e422a791934fbda9d58498449509b4f03f287fe45bd2e5996819a676a30d9edee70dd9d07f57b977bed3994608352ef9263961229854c","tags":[["p","dd664d5e4016433a8cd69f005ae1480804351789b59de5af06276de65633d319"],["e","81c213f681ca1410c4033cf12bdfa0855cd28cfadb78ff6111457a7f3c45bd4a"],["bolt11","lnbc210u1p4pmqajpp5am8ajk2rvlvsn3a70pakr2t58c6dr30raulpe8qaf4gvaaq84w6qdqqcqzzsxqyz5vqrzjqvueefmrckfdwyyu39m0lf24sqzcr9vcrmxrvgfn6empxz7phrjxvrttncqq0lcqqyqqqqlgqqqqqqgq2qsp598rn0daqg7u0fwy3fv9m598rsceycpvjgrkmez4r9c0w9d8vaajq9qxpqysgqz6enr7y6law6p4hct5uuv8eskjdxxkxtqtwmwvejvplxh3qwxurrdjplaefk08qaqp43z33nuf48exteqepef4f0z8q9jxsn0yts33gqkuupvy"],["description","{\"id\":\"a11f56de1aebd1d83193ac369386d0f994a53fcefa81e218363ad9f7e1194a84\",\"pubkey\":\"e2ccf7cf20403f3f2a4a55b328f0de3be38558a7d5f33632fdaaefc726c1c8eb\",\"created_at\":1780319154,\"kind\":9734,\"tags\":[[\"p\",\"dd664d5e4016433a8cd69f005ae1480804351789b59de5af06276de65633d319\"],[\"e\",\"81c213f681ca1410c4033cf12bdfa0855cd28cfadb78ff6111457a7f3c45bd4a\"],[\"relays\",\"wss://theforest.nostr1.com\",\"wss://relay.utxo.one/inbox\",\"wss://relay.primal.net\",\"wss://nos.lol\",\"wss://relay.wisp.talk\"],[\"amount\",\"21000000\"],[\"lnurl\",\"silberengel@minibits.cash\"],[\"client\",\"Wisp\"]],\"content\":\"keep building \",\"sig\":\"9b65baed7413bd4561b04983c87454fe5e1ff82129b0955e1f9d3cf71dfc2d20e234a6f375fceae3c010cf0d43924b1c26099d066f5c6e0bf3ccfadc709da71d\"}"]],"id":"a6f2a9d444fd81905d0407bcd264b6699122668bcc4ab71998b2d0a7638b0060","kind":9735,"pubkey":"beeb48407a6f087ea8f76dc384a5d88c67ced9bd9fb0cdba90930210df3d92e7","created_at":1780319157,"content":"keep building "}]"###,
//            ###"["EVENT", "replyToZap", {"content":"Woo woo! My second superchat. Thanks! 💝","id":"e28bbdb4f000e9e88dbd637230898667662cc010f126de2460a13c4547e73166","sig":"780297c0c7b340f464a7a9a4a2a2ebfaae2ebe623b4d4a29f0573ae929c4db61ffdd463863e36d975ba080bdac8d9c09ee1a398746a5641708ab1f9e259148f1","pubkey":"dd664d5e4016433a8cd69f005ae1480804351789b59de5af06276de65633d319","tags":[["E","a6f2a9d444fd81905d0407bcd264b6699122668bcc4ab71998b2d0a7638b0060","wss://theforest.nostr1.com/","beeb48407a6f087ea8f76dc384a5d88c67ced9bd9fb0cdba90930210df3d92e7"],["P","beeb48407a6f087ea8f76dc384a5d88c67ced9bd9fb0cdba90930210df3d92e7"],["K","9735"],["e","a6f2a9d444fd81905d0407bcd264b6699122668bcc4ab71998b2d0a7638b0060","wss://theforest.nostr1.com/","beeb48407a6f087ea8f76dc384a5d88c67ced9bd9fb0cdba90930210df3d92e7"],["k","9735"],["p","beeb48407a6f087ea8f76dc384a5d88c67ced9bd9fb0cdba90930210df3d92e7"],["client","imwald"]],"kind":1111,"created_at":1780319435}]"###
//        ])
//        
        pe.parseEventJSON([
            // profiles
            ###"{"tags":[["about","🎵Die Gedanken sind frei."],["banner","https://i.nostr.build/FEZrgz9lthZrfndJ.jpg"],["display_name","Laeserin"],["lud16","stellainforest@cake.cash"],["name","Laeserin"],["nip05","laeserin@gitcitadel.com"],["website","https://jumble.imwald.eu"],["picture","https://i.nostr.build/thumb/RlkuVFMWOXpshf8k.webp"],["nip05","laeserin@theforest.nostr1.com"],["website","https://blog.imwald.eu"],["website","https://alexandria.gitcitadel.eu/start"],["website","https://git.imwald.eu/silberengel/scriptorium-obsidian"],["website","https://gitcitadel.com"],["nip05","laeserin@sovbit.host"],["nip05","laeserin@nostr.land"],["client","imwald"]],"sig":"a34b8b56bc8f59ea672a1300da83bf86a9aafbed9c81cbc40720f57c7051648a89ca1108f5710f52b762b40184a440784bd29c5dfe8975be0bc8365fea3a9b50","content":"{\"about\":\"🎵Die Gedanken sind frei.\",\"banner\":\"https://i.nostr.build/FEZrgz9lthZrfndJ.jpg\",\"display_name\":\"Laeserin\",\"lud16\":\"stellainforest@cake.cash\",\"name\":\"Laeserin\",\"nip05\":\"laeserin@gitcitadel.com\",\"website\":\"https://jumble.imwald.eu\",\"picture\":\"https://i.nostr.build/thumb/RlkuVFMWOXpshf8k.webp\",\"displayName\":\"Laeserin\"}","kind":0,"pubkey":"dd664d5e4016433a8cd69f005ae1480804351789b59de5af06276de65633d319","id":"0dac87837fc8a3a076a3ad4bc44a646a3f71245d4a559cec77b8efd26d3bc13c","created_at":1781066474}"###,
            ###"{"pubkey":"e2ccf7cf20403f3f2a4a55b328f0de3be38558a7d5f33632fdaaefc726c1c8eb","sig":"4411abe00fc7f2d133796c5d90a8c77fe54f3fdf92c2d0aa4564556c16eda8e22b5de3eb4fbcb68a6da5b601d1706a866b2bb3534b413ce6af007e02c9b86193","created_at":1780258946,"content":"{\"display_name\":\"utxo the webmaster 🧑‍💻\",\"name\":\"utxo the webmaster 🧑‍💻\",\"about\":\"Wisp - https://wisp.mobile\\nNostr Archives - https://NostrArchives.com\\n\\nhttps://github.com/barrydeen\",\"picture\":\"https://npub1utx00neqgqln72j22kej3ux7803c2k986henvvha4thuwfkper4s7r50e8.blossom.band/bb8c182bd6f0a2c2d80589b6a2000ea083eb4e182e00c48f548744a739ae0326.jpg\",\"nip05\":\"_@utxo.one\",\"banner\":\"https://i.nostr.build/TSZWL281MD6ulMXf.gif\",\"lud16\":\"utxo@rizful.com\"}","kind":0,"tags":[],"id":"20358836be8288890c33561f09aec2801539e0b6e06fdf76f783aa55d3f91020"}"###,
            
            // root post
            ###"{"sig":"d738ce15015972d0697547bd62608ff07c57cbddc8030a5ee7f4004661a8bb46e623edf099678b778430f35619137a78b52d315ba34699d5bac864b44576175a","tags":[["t","gitcitadel"],["client","imwald"]],"id":"81c213f681ca1410c4033cf12bdfa0855cd28cfadb78ff6111457a7f3c45bd4a","kind":1,"pubkey":"dd664d5e4016433a8cd69f005ae1480804351789b59de5af06276de65633d319","created_at":1780290709,"content":"Watching the whole Nostr money debates...\nWhen your team couldn't get a grant.\nWhen your team couldn't get a NIP.\nWhen you're running on volunteers,  donations, and fees.\nWhen you have to grind every zap into dust and dig out the leftover change from your day job, to squeeze out the infrastructure costs.\nWhen you build and run everything as cheaply as possible because you are broke.\n\nhttps://media.tenor.com/frMfHHLz05YAAAAC/atg-stucapa.gif\n\nGM 💖\n\nWe are still here. We are still building. And there are now more of us. #GitCitadel"}"###,
            // zap on post
            ###"{"sig":"421f4afd6a3ef4d0c08e422a791934fbda9d58498449509b4f03f287fe45bd2e5996819a676a30d9edee70dd9d07f57b977bed3994608352ef9263961229854c","tags":[["p","dd664d5e4016433a8cd69f005ae1480804351789b59de5af06276de65633d319"],["e","81c213f681ca1410c4033cf12bdfa0855cd28cfadb78ff6111457a7f3c45bd4a"],["bolt11","lnbc210u1p4pmqajpp5am8ajk2rvlvsn3a70pakr2t58c6dr30raulpe8qaf4gvaaq84w6qdqqcqzzsxqyz5vqrzjqvueefmrckfdwyyu39m0lf24sqzcr9vcrmxrvgfn6empxz7phrjxvrttncqq0lcqqyqqqqlgqqqqqqgq2qsp598rn0daqg7u0fwy3fv9m598rsceycpvjgrkmez4r9c0w9d8vaajq9qxpqysgqz6enr7y6law6p4hct5uuv8eskjdxxkxtqtwmwvejvplxh3qwxurrdjplaefk08qaqp43z33nuf48exteqepef4f0z8q9jxsn0yts33gqkuupvy"],["description","{\"id\":\"a11f56de1aebd1d83193ac369386d0f994a53fcefa81e218363ad9f7e1194a84\",\"pubkey\":\"e2ccf7cf20403f3f2a4a55b328f0de3be38558a7d5f33632fdaaefc726c1c8eb\",\"created_at\":1780319154,\"kind\":9734,\"tags\":[[\"p\",\"dd664d5e4016433a8cd69f005ae1480804351789b59de5af06276de65633d319\"],[\"e\",\"81c213f681ca1410c4033cf12bdfa0855cd28cfadb78ff6111457a7f3c45bd4a\"],[\"relays\",\"wss://theforest.nostr1.com\",\"wss://relay.utxo.one/inbox\",\"wss://relay.primal.net\",\"wss://nos.lol\",\"wss://relay.wisp.talk\"],[\"amount\",\"21000000\"],[\"lnurl\",\"silberengel@minibits.cash\"],[\"client\",\"Wisp\"]],\"content\":\"keep building \",\"sig\":\"9b65baed7413bd4561b04983c87454fe5e1ff82129b0955e1f9d3cf71dfc2d20e234a6f375fceae3c010cf0d43924b1c26099d066f5c6e0bf3ccfadc709da71d\"}"]],"id":"a6f2a9d444fd81905d0407bcd264b6699122668bcc4ab71998b2d0a7638b0060","kind":9735,"pubkey":"beeb48407a6f087ea8f76dc384a5d88c67ced9bd9fb0cdba90930210df3d92e7","created_at":1780319157,"content":"keep building "}"###,
            // reply to zap
            ###"{"content":"Woo woo! My second superchat. Thanks! 💝","id":"e28bbdb4f000e9e88dbd637230898667662cc010f126de2460a13c4547e73166","sig":"780297c0c7b340f464a7a9a4a2a2ebfaae2ebe623b4d4a29f0573ae929c4db61ffdd463863e36d975ba080bdac8d9c09ee1a398746a5641708ab1f9e259148f1","pubkey":"dd664d5e4016433a8cd69f005ae1480804351789b59de5af06276de65633d319","tags":[["E","a6f2a9d444fd81905d0407bcd264b6699122668bcc4ab71998b2d0a7638b0060","wss://theforest.nostr1.com/","beeb48407a6f087ea8f76dc384a5d88c67ced9bd9fb0cdba90930210df3d92e7"],["P","beeb48407a6f087ea8f76dc384a5d88c67ced9bd9fb0cdba90930210df3d92e7"],["K","9735"],["e","a6f2a9d444fd81905d0407bcd264b6699122668bcc4ab71998b2d0a7638b0060","wss://theforest.nostr1.com/","beeb48407a6f087ea8f76dc384a5d88c67ced9bd9fb0cdba90930210df3d92e7"],["k","9735"],["p","beeb48407a6f087ea8f76dc384a5d88c67ced9bd9fb0cdba90930210df3d92e7"],["client","imwald"]],"kind":1111,"created_at":1780319435}"###
        ])
        
    }) {
        PreviewApp {
            if let replyToZap = PreviewFetcher.fetchNRPost("e28bbdb4f000e9e88dbd637230898667662cc010f126de2460a13c4547e73166") {
                PostDetailView(nrPost: replyToZap)
            }
        }
    }
}

@available(iOS 26.0, *)
#Preview("Zap detail") {
    @Previewable @Environment(\.theme) var theme
  
    PreviewContainer({ pe in
//        pe.parseMessages([
//            ###"["EVENT", "post", {"sig":"d738ce15015972d0697547bd62608ff07c57cbddc8030a5ee7f4004661a8bb46e623edf099678b778430f35619137a78b52d315ba34699d5bac864b44576175a","tags":[["t","gitcitadel"],["client","imwald"]],"id":"81c213f681ca1410c4033cf12bdfa0855cd28cfadb78ff6111457a7f3c45bd4a","kind":1,"pubkey":"dd664d5e4016433a8cd69f005ae1480804351789b59de5af06276de65633d319","created_at":1780290709,"content":"Watching the whole Nostr money debates...\nWhen your team couldn't get a grant.\nWhen your team couldn't get a NIP.\nWhen you're running on volunteers,  donations, and fees.\nWhen you have to grind every zap into dust and dig out the leftover change from your day job, to squeeze out the infrastructure costs.\nWhen you build and run everything as cheaply as possible because you are broke.\n\nhttps://media.tenor.com/frMfHHLz05YAAAAC/atg-stucapa.gif\n\nGM 💖\n\nWe are still here. We are still building. And there are now more of us. #GitCitadel"}]"###,
//            ###"["EVENT", "zap", {"sig":"421f4afd6a3ef4d0c08e422a791934fbda9d58498449509b4f03f287fe45bd2e5996819a676a30d9edee70dd9d07f57b977bed3994608352ef9263961229854c","tags":[["p","dd664d5e4016433a8cd69f005ae1480804351789b59de5af06276de65633d319"],["e","81c213f681ca1410c4033cf12bdfa0855cd28cfadb78ff6111457a7f3c45bd4a"],["bolt11","lnbc210u1p4pmqajpp5am8ajk2rvlvsn3a70pakr2t58c6dr30raulpe8qaf4gvaaq84w6qdqqcqzzsxqyz5vqrzjqvueefmrckfdwyyu39m0lf24sqzcr9vcrmxrvgfn6empxz7phrjxvrttncqq0lcqqyqqqqlgqqqqqqgq2qsp598rn0daqg7u0fwy3fv9m598rsceycpvjgrkmez4r9c0w9d8vaajq9qxpqysgqz6enr7y6law6p4hct5uuv8eskjdxxkxtqtwmwvejvplxh3qwxurrdjplaefk08qaqp43z33nuf48exteqepef4f0z8q9jxsn0yts33gqkuupvy"],["description","{\"id\":\"a11f56de1aebd1d83193ac369386d0f994a53fcefa81e218363ad9f7e1194a84\",\"pubkey\":\"e2ccf7cf20403f3f2a4a55b328f0de3be38558a7d5f33632fdaaefc726c1c8eb\",\"created_at\":1780319154,\"kind\":9734,\"tags\":[[\"p\",\"dd664d5e4016433a8cd69f005ae1480804351789b59de5af06276de65633d319\"],[\"e\",\"81c213f681ca1410c4033cf12bdfa0855cd28cfadb78ff6111457a7f3c45bd4a\"],[\"relays\",\"wss://theforest.nostr1.com\",\"wss://relay.utxo.one/inbox\",\"wss://relay.primal.net\",\"wss://nos.lol\",\"wss://relay.wisp.talk\"],[\"amount\",\"21000000\"],[\"lnurl\",\"silberengel@minibits.cash\"],[\"client\",\"Wisp\"]],\"content\":\"keep building \",\"sig\":\"9b65baed7413bd4561b04983c87454fe5e1ff82129b0955e1f9d3cf71dfc2d20e234a6f375fceae3c010cf0d43924b1c26099d066f5c6e0bf3ccfadc709da71d\"}"]],"id":"a6f2a9d444fd81905d0407bcd264b6699122668bcc4ab71998b2d0a7638b0060","kind":9735,"pubkey":"beeb48407a6f087ea8f76dc384a5d88c67ced9bd9fb0cdba90930210df3d92e7","created_at":1780319157,"content":"keep building "}]"###,
//            ###"["EVENT", "replyToZap", {"content":"Woo woo! My second superchat. Thanks! 💝","id":"e28bbdb4f000e9e88dbd637230898667662cc010f126de2460a13c4547e73166","sig":"780297c0c7b340f464a7a9a4a2a2ebfaae2ebe623b4d4a29f0573ae929c4db61ffdd463863e36d975ba080bdac8d9c09ee1a398746a5641708ab1f9e259148f1","pubkey":"dd664d5e4016433a8cd69f005ae1480804351789b59de5af06276de65633d319","tags":[["E","a6f2a9d444fd81905d0407bcd264b6699122668bcc4ab71998b2d0a7638b0060","wss://theforest.nostr1.com/","beeb48407a6f087ea8f76dc384a5d88c67ced9bd9fb0cdba90930210df3d92e7"],["P","beeb48407a6f087ea8f76dc384a5d88c67ced9bd9fb0cdba90930210df3d92e7"],["K","9735"],["e","a6f2a9d444fd81905d0407bcd264b6699122668bcc4ab71998b2d0a7638b0060","wss://theforest.nostr1.com/","beeb48407a6f087ea8f76dc384a5d88c67ced9bd9fb0cdba90930210df3d92e7"],["k","9735"],["p","beeb48407a6f087ea8f76dc384a5d88c67ced9bd9fb0cdba90930210df3d92e7"],["client","imwald"]],"kind":1111,"created_at":1780319435}]"###
//        ])
//
        pe.parseEventJSON([
            // profiles
            ###"{"tags":[["about","🎵Die Gedanken sind frei."],["banner","https://i.nostr.build/FEZrgz9lthZrfndJ.jpg"],["display_name","Laeserin"],["lud16","stellainforest@cake.cash"],["name","Laeserin"],["nip05","laeserin@gitcitadel.com"],["website","https://jumble.imwald.eu"],["picture","https://i.nostr.build/thumb/RlkuVFMWOXpshf8k.webp"],["nip05","laeserin@theforest.nostr1.com"],["website","https://blog.imwald.eu"],["website","https://alexandria.gitcitadel.eu/start"],["website","https://git.imwald.eu/silberengel/scriptorium-obsidian"],["website","https://gitcitadel.com"],["nip05","laeserin@sovbit.host"],["nip05","laeserin@nostr.land"],["client","imwald"]],"sig":"a34b8b56bc8f59ea672a1300da83bf86a9aafbed9c81cbc40720f57c7051648a89ca1108f5710f52b762b40184a440784bd29c5dfe8975be0bc8365fea3a9b50","content":"{\"about\":\"🎵Die Gedanken sind frei.\",\"banner\":\"https://i.nostr.build/FEZrgz9lthZrfndJ.jpg\",\"display_name\":\"Laeserin\",\"lud16\":\"stellainforest@cake.cash\",\"name\":\"Laeserin\",\"nip05\":\"laeserin@gitcitadel.com\",\"website\":\"https://jumble.imwald.eu\",\"picture\":\"https://i.nostr.build/thumb/RlkuVFMWOXpshf8k.webp\",\"displayName\":\"Laeserin\"}","kind":0,"pubkey":"dd664d5e4016433a8cd69f005ae1480804351789b59de5af06276de65633d319","id":"0dac87837fc8a3a076a3ad4bc44a646a3f71245d4a559cec77b8efd26d3bc13c","created_at":1781066474}"###,
            ###"{"pubkey":"e2ccf7cf20403f3f2a4a55b328f0de3be38558a7d5f33632fdaaefc726c1c8eb","sig":"4411abe00fc7f2d133796c5d90a8c77fe54f3fdf92c2d0aa4564556c16eda8e22b5de3eb4fbcb68a6da5b601d1706a866b2bb3534b413ce6af007e02c9b86193","created_at":1780258946,"content":"{\"display_name\":\"utxo the webmaster 🧑‍💻\",\"name\":\"utxo the webmaster 🧑‍💻\",\"about\":\"Wisp - https://wisp.mobile\\nNostr Archives - https://NostrArchives.com\\n\\nhttps://github.com/barrydeen\",\"picture\":\"https://npub1utx00neqgqln72j22kej3ux7803c2k986henvvha4thuwfkper4s7r50e8.blossom.band/bb8c182bd6f0a2c2d80589b6a2000ea083eb4e182e00c48f548744a739ae0326.jpg\",\"nip05\":\"_@utxo.one\",\"banner\":\"https://i.nostr.build/TSZWL281MD6ulMXf.gif\",\"lud16\":\"utxo@rizful.com\"}","kind":0,"tags":[],"id":"20358836be8288890c33561f09aec2801539e0b6e06fdf76f783aa55d3f91020"}"###,
            
            // root post
            ###"{"sig":"d738ce15015972d0697547bd62608ff07c57cbddc8030a5ee7f4004661a8bb46e623edf099678b778430f35619137a78b52d315ba34699d5bac864b44576175a","tags":[["t","gitcitadel"],["client","imwald"]],"id":"81c213f681ca1410c4033cf12bdfa0855cd28cfadb78ff6111457a7f3c45bd4a","kind":1,"pubkey":"dd664d5e4016433a8cd69f005ae1480804351789b59de5af06276de65633d319","created_at":1780290709,"content":"Watching the whole Nostr money debates...\nWhen your team couldn't get a grant.\nWhen your team couldn't get a NIP.\nWhen you're running on volunteers,  donations, and fees.\nWhen you have to grind every zap into dust and dig out the leftover change from your day job, to squeeze out the infrastructure costs.\nWhen you build and run everything as cheaply as possible because you are broke.\n\nhttps://media.tenor.com/frMfHHLz05YAAAAC/atg-stucapa.gif\n\nGM 💖\n\nWe are still here. We are still building. And there are now more of us. #GitCitadel"}"###,
            // zap on post
            ###"{"sig":"421f4afd6a3ef4d0c08e422a791934fbda9d58498449509b4f03f287fe45bd2e5996819a676a30d9edee70dd9d07f57b977bed3994608352ef9263961229854c","tags":[["p","dd664d5e4016433a8cd69f005ae1480804351789b59de5af06276de65633d319"],["e","81c213f681ca1410c4033cf12bdfa0855cd28cfadb78ff6111457a7f3c45bd4a"],["bolt11","lnbc210u1p4pmqajpp5am8ajk2rvlvsn3a70pakr2t58c6dr30raulpe8qaf4gvaaq84w6qdqqcqzzsxqyz5vqrzjqvueefmrckfdwyyu39m0lf24sqzcr9vcrmxrvgfn6empxz7phrjxvrttncqq0lcqqyqqqqlgqqqqqqgq2qsp598rn0daqg7u0fwy3fv9m598rsceycpvjgrkmez4r9c0w9d8vaajq9qxpqysgqz6enr7y6law6p4hct5uuv8eskjdxxkxtqtwmwvejvplxh3qwxurrdjplaefk08qaqp43z33nuf48exteqepef4f0z8q9jxsn0yts33gqkuupvy"],["description","{\"id\":\"a11f56de1aebd1d83193ac369386d0f994a53fcefa81e218363ad9f7e1194a84\",\"pubkey\":\"e2ccf7cf20403f3f2a4a55b328f0de3be38558a7d5f33632fdaaefc726c1c8eb\",\"created_at\":1780319154,\"kind\":9734,\"tags\":[[\"p\",\"dd664d5e4016433a8cd69f005ae1480804351789b59de5af06276de65633d319\"],[\"e\",\"81c213f681ca1410c4033cf12bdfa0855cd28cfadb78ff6111457a7f3c45bd4a\"],[\"relays\",\"wss://theforest.nostr1.com\",\"wss://relay.utxo.one/inbox\",\"wss://relay.primal.net\",\"wss://nos.lol\",\"wss://relay.wisp.talk\"],[\"amount\",\"21000000\"],[\"lnurl\",\"silberengel@minibits.cash\"],[\"client\",\"Wisp\"]],\"content\":\"keep building \",\"sig\":\"9b65baed7413bd4561b04983c87454fe5e1ff82129b0955e1f9d3cf71dfc2d20e234a6f375fceae3c010cf0d43924b1c26099d066f5c6e0bf3ccfadc709da71d\"}"]],"id":"a6f2a9d444fd81905d0407bcd264b6699122668bcc4ab71998b2d0a7638b0060","kind":9735,"pubkey":"beeb48407a6f087ea8f76dc384a5d88c67ced9bd9fb0cdba90930210df3d92e7","created_at":1780319157,"content":"keep building "}"###,
            // reply to zap
            ###"{"content":"Woo woo! My second superchat. Thanks! 💝","id":"e28bbdb4f000e9e88dbd637230898667662cc010f126de2460a13c4547e73166","sig":"780297c0c7b340f464a7a9a4a2a2ebfaae2ebe623b4d4a29f0573ae929c4db61ffdd463863e36d975ba080bdac8d9c09ee1a398746a5641708ab1f9e259148f1","pubkey":"dd664d5e4016433a8cd69f005ae1480804351789b59de5af06276de65633d319","tags":[["E","a6f2a9d444fd81905d0407bcd264b6699122668bcc4ab71998b2d0a7638b0060","wss://theforest.nostr1.com/","beeb48407a6f087ea8f76dc384a5d88c67ced9bd9fb0cdba90930210df3d92e7"],["P","beeb48407a6f087ea8f76dc384a5d88c67ced9bd9fb0cdba90930210df3d92e7"],["K","9735"],["e","a6f2a9d444fd81905d0407bcd264b6699122668bcc4ab71998b2d0a7638b0060","wss://theforest.nostr1.com/","beeb48407a6f087ea8f76dc384a5d88c67ced9bd9fb0cdba90930210df3d92e7"],["k","9735"],["p","beeb48407a6f087ea8f76dc384a5d88c67ced9bd9fb0cdba90930210df3d92e7"],["client","imwald"]],"kind":1111,"created_at":1780319435}"###
        ])
        
    }) {
        PreviewApp {
            if let zap = PreviewFetcher.fetchNRPost("a6f2a9d444fd81905d0407bcd264b6699122668bcc4ab71998b2d0a7638b0060") {
                PostDetailView(nrPost: zap)
            }
        }
    }
}
