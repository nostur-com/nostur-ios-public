//
//  Kind1222.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/06/2025.
//

import SwiftUI

// Kind 1222 and 1244
// 1222 for root messages and kind: 1244 for reply messages to be used for short voice messages, typically up to 60 seconds in length.
struct Kind1222: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    @Environment(\.theme) private var theme
    @Environment(\.containerID) private var containerID
    @Environment(\.availableWidth) private var availableWidth
    
    @ObservedObject private var settings: SettingsStore = .shared
    private let nrPost: NRPost
    @ObservedObject private var nrContact: NRContact
    
    private let hideFooter: Bool // For rendering in NewReply
    private let missingReplyTo: Bool // For rendering in thread
    private var connect: ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    private let isReply: Bool // is reply on PostDetail
    private let isDetail: Bool
    private let isEmbedded: Bool
    private let fullWidth: Bool
    private let grouped: Bool
    private let forceAutoload: Bool
    
    private let THREAD_LINE_OFFSET = 24.0
    
    private var isOlasGeneric: Bool { (nrPost.kind == 1 && (nrPost.kTag ?? "") == "20") }
    
    @State var localAudioFileURL: URL? = nil
    
    init(nrPost: NRPost, hideFooter: Bool = true, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil, isReply: Bool = false, isDetail: Bool = false, isEmbedded: Bool = false, fullWidth: Bool, grouped: Bool = false, forceAutoload: Bool = false) {
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
        PostLayout(nrPost: nrPost, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect,
                   isReply: isReply, isDetail: isDetail, fullWidth: fullWidth || isOlasGeneric, forceAutoload: forceAutoload, nxViewingContext: nxViewingContext, containerID: containerID, theme: theme, availableWidth: availableWidth) { 
            if (isDetail) {
                if missingReplyTo || nxViewingContext.contains(.screenshot) {
                    ReplyingToFragmentView(nrPost: nrPost)
                }
                if let subject = nrPost.subject {
                    Text(subject)
                        .fontWeight(.bold)
                        .lineLimit(3)
                }
                if availableWidth < 75 { // Probably too many embeds in embeds in embeds in embeds, no space left
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                else {
                    self.audioView
                }
            }
            else {
                
                if missingReplyTo || nxViewingContext.contains(.screenshot) {
                    ReplyingToFragmentView(nrPost: nrPost)
                }
                if let subject = nrPost.subject {
                    Text(subject)
                        .fontWeight(.bold)
                        .lineLimit(3)
                }
                if availableWidth < 75 { // Probably too many embeds in embeds in embeds in embeds, no space left
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                else {
                    self.audioView
                }

            }
        }
    }
    
    @ViewBuilder
    private var audioView: some View {
        if let audioUrl = nrPost.audioUrl {
            VoiceMessagePlayer(url: audioUrl, samples: nrPost.samples)
        }
        else {
            Text("Error: missing audio file")
        }
    }
    
    @ViewBuilder
    private var embeddedView: some View {
        PostEmbeddedLayout(nrPost: nrPost) {
            
            if missingReplyTo || nxViewingContext.contains(.screenshot) {
                ReplyingToFragmentView(nrPost: nrPost)
            }
            if let subject = nrPost.subject {
                Text(subject)
                    .fontWeight(.bold)
                    .lineLimit(3)
            }
            if availableWidth < 75 { // Probably too many embeds in embeds in embeds in embeds, no space left
                Image(systemName: "exclamationmark.triangle.fill")
            }
            else {
                self.audioView
            }
        }
    }
}


#Preview("Voice Message") {
    PreviewContainer({ pe in
        pe.parseMessages([
//            ###"["EVENT","voice",{"id":"3d89633c73db03ec49431e98a01f57d268f51d684d4f213a1f970fa3bb1b3714","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1747141170,"kind":1222,"tags":[],"content":"https://24242.io/1ca0ab176fa1259847f57b8bf93d38790e8797c7762762673b5aec46885140f9.webm","sig":"6785c8b32fcb9e03f02b25ccdbce211c43e74742b8f70f91b4629f323b56b16b8f1ab6a10421e97e5e37834fcc55e799370e62d78daffa56bf70ca1ab1b16fa1"}]"###
//            ###"["EVENT","voice",{"id":"3d89633c73db03ec49431e98a01f57d268f51d684d4f213a1f970fa3bb1b3714","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1747141170,"kind":1222,"tags":[],"content":"http://localhost:3000/f3290797cd055bc7417a4736e09b509abc9ba08d3558f1c48d9d348711512ec0.m4a","sig":"6785c8b32fcb9e03f02b25ccdbce211c43e74742b8f70f91b4629f323b56b16b8f1ab6a10421e97e5e37834fcc55e799370e62d78daffa56bf70ca1ab1b16fa1"}]"###
            ###"["EVENT","dit_is_een_test",{"kind":1244,"sig":"3e77e6e5ee807aee5f7bcac2823b251a85f671c259de570902f465d5818d99adfe1bd86c47b4b7354d4b22719803c1287c8fad4d7a9825ad157accf4fcd21994","created_at":1753312512,"tags":[["imeta","url https://nostr-relay.derekross.me/4c8b12f4006638e6eaa7a67e19853c78af1b7d92089726b1c2c002a5f437e770.mp4","duration 3","waveform 0.0001592034314105065 0.0003290001847047085 0.0003072103568434128 0.00020839611689525784 0.00014554743605555223 0.00019666003747672206 0.0003410468310428211 0.0004292219860993555 0.0004074977453352198 0.00029751770026937934 0.00017718645787329645 0.00027404276652808976 0.000333538369959863 0.00020731079495354347 0.00025008775799453516 0.0001866116786248802 0.00016417033854843565 0.00013624919101631736 0.0001954941858347246 0.00021383796416952377 0.00018249900677316382 0.15202560962905337 1 1 1 0.8607285860465468 0.9684180423190824 1 0.983100970978501 0.3355982242823201 0.06504723194745848 0.060426563963534706 0.15415644219772145 0.8266969096324623 0.924652826757403 0.7231233474834893 0.6969984025456932 0.5406940403138826 0.29333673266604376 0.04066423626998921 0.00827338226119906 0.0017047669101290263 0.4189347776008603 0.9458867261438759 0.9992015105334466 0.9505273806899488 0.9694314973893869 0.9163677734728124 1 1 1 0.8878309112803399 0.7613994777132127 0.4547521614989133 0.34055785359034707 0.334645630449503 0.37757558569647076 0.5706866610475935 0.8145147960920833 0.9834331665797273 0.9515133971359129 1 1 1 0.8170028393114037 0.5336769108151852 0.717912773986336 0.7013297264612575 0.6255995771045625 0.1685605540656668 0.07695243787755748 0.2208840146545031 0.9245755078684137 1 1 1 0.892752117666626 0.3439287993850313 0.3201297811283105 0.4146092361044427 0.31183268862843655 0.1791698782767675 0.019536569571616976 0.005424238309603646 0.0011200097902841597 0.00016063301853935284 0.000060623862529968664 0.00005719094083299219 0.00005526227717279569 0.00005446096638255449 0.00005626091080537237 0.00005198288812952957 0.00005209553409909116 0.0000535382345132043 0.00004961747593199775 0.000058005077658410855 0.0000546221977901008 0.00005370227630207984 0.00004612783935442024 0.00004542354591150558"],["p","cfb9b7be3ddecf3e787534aebfae23e66c4f8f76dc037dfee3ce9766fbeb1247"],["e","87a44d855190bfaab966acbcbf4d73a4300457a19af83d69e639693efd3e02b9"],["k","1222"],["P","cfb9b7be3ddecf3e787534aebfae23e66c4f8f76dc037dfee3ce9766fbeb1247"],["E","87a44d855190bfaab966acbcbf4d73a4300457a19af83d69e639693efd3e02b9"],["K","1222"]],"id":"01791e717cb911955397d44e9c0c4db863e0d18179a6090fcd1aada19ae99d95","content":"https://nostr-relay.derekross.me/4c8b12f4006638e6eaa7a67e19853c78af1b7d92089726b1c2c002a5f437e770.mp4","pubkey":"3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24"}]"###,
            ###"["EVENT","dit_is_een_test",{"id":"3d89633c73db03ec49431e98a01f57d268f51d684d4f213a1f970fa3bb1b3714","pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","created_at":1747141170,"kind":1222,"tags":[],"content":"http://localhost:3000/6d99ec56d05e444c048bedb88bd21c7636c36b2ac855aa9867b688ba4c994cb1.m4a","sig":"6785c8b32fcb9e03f02b25ccdbce211c43e74742b8f70f91b4629f323b56b16b8f1ab6a10421e97e5e37834fcc55e799370e62d78daffa56bf70ca1ab1b16fa1"}]"###,
            ###"["EVENT","fiatjaf",{"tags":[["p","cfb9b7be3ddecf3e787534aebfae23e66c4f8f76dc037dfee3ce9766fbeb1247"],["e","a196725e420b7bcb758e291833e745c34d7f5ff65eddad435dbbe07783348669"],["k","1222"],["P","cfb9b7be3ddecf3e787534aebfae23e66c4f8f76dc037dfee3ce9766fbeb1247"],["E","a196725e420b7bcb758e291833e745c34d7f5ff65eddad435dbbe07783348669"],["K","1222"]],"pubkey":"cfb9b7be3ddecf3e787534aebfae23e66c4f8f76dc037dfee3ce9766fbeb1247","content":"https://blossom.primal.net/2b80f037585b413ef48c433903153e6cc1cdd06890d1123e15e5df585870e07a.mp4","id":"96dd82763abe004512b0077233af307bd6cc55cae1dce87612b3e061fee99461","sig":"8a2c18d3dbc37a5483e05be05b085ccce03b3b49d1440d8a24903d2b29a356f94960ff7215de5730912bb65529541a76a4794fc5e9e4ed2b92b3509258bc8a3e","created_at":1752243807,"kind":1244}]"###,
            ###"["EVENT","fab",{"id":"16ac8c7c0e36b7356e45fd94e1c98d91ddf00a46daf2aeb4bcbec7e89685fcb4","pubkey":"4b2fd609cf60e9769440bc3cb03d1f60eeac6d55f69938048dd401bef8d9a9c4","sig":"bcb2b62160260da00f322d89c5f08230c0bea1815358cca10e327a1daf4919a50cf849da7c0f72520aee2ad2b03a69f0d170d75e33dcb0ba7922abee8bb997fb","content":"https://media.utxo.nl/wp-content/uploads/nostr/1/c/1cfc2c3bf9269135a3d536e940f13ffbaf20e2f6b643562d2f43f5dc56f7a234.m4a","kind":1222,"created_at":1753574278,"tags":[["imeta","url https://media.utxo.nl/wp-content/uploads/nostr/1/c/1cfc2c3bf9269135a3d536e940f13ffbaf20e2f6b643562d2f43f5dc56f7a234.m4a","duration 3","waveform 0 0 0 3 8 2 3 0 0 1 2 3 4 4 2 5 2 0 4 2 2 2 1 0 0 0 5 1 2 3 7 3 0 21 6 2 1 1 0 1 0 3 3 4 7 4 1 2 1 9 6 11 51 23 15 34 2 75 100 100 100 100 56 72 54 100 100 100 45 92 10 100 100 100 92 63 15 2 22 2 1 0 0 4 3 1 3 3 3 2 1 2 2 2 0 4 0 6 1 3 0","sha256 1cfc2c3bf9269135a3d536e940f13ffbaf20e2f6b643562d2f43f5dc56f7a234"],["client","Nostur","31990:9be0be0fc079548233231614e4e1efc9f28b0db398011efeecf05fe570e5dd33:1685868693432"]]}]"###
        ])
        pe.loadContacts()
        pe.loadPosts()
    }) {
        PreviewFeed {
            // 3d89633c73db03ec49431e98a01f57d268f51d684d4f213a1f970fa3bb1b3714
            // 96dd82763abe004512b0077233af307bd6cc55cae1dce87612b3e061fee99461
            // 01791e717cb911955397d44e9c0c4db863e0d18179a6090fcd1aada19ae99d95
            // 16ac8c7c0e36b7356e45fd94e1c98d91ddf00a46daf2aeb4bcbec7e89685fcb4
            if let voiceMessage = PreviewFetcher.fetchNRPost("16ac8c7c0e36b7356e45fd94e1c98d91ddf00a46daf2aeb4bcbec7e89685fcb4") {
                Box {
                    PostRowDeletable(nrPost: voiceMessage, theme: Themes.default.theme)
                }
            }
//            if let nrPost = PreviewFetcher.fetchNRPost() {
//                Box {
//                    PostRowDeletable(nrPost: nrPost, theme: Themes.default.theme)
//                }
//            }
//            if let article = PreviewFetcher.fetchNRPost("d3f509e5eb6dd06f96d4797969408f5f9c90e9237f012f83130b1fa592b26433") {
//                Box {
//                    PostRowDeletable(nrPost: article, theme: Themes.default.theme)
//                }
//            }
            Spacer()
        }
        .background(Themes.default.theme.listBackground)
    }
}
