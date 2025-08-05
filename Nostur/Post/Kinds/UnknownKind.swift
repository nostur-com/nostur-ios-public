//
//  UnknownKind.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/08/2024.
//

import SwiftUI

struct UnknownKind: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    @Environment(\.theme) private var theme
    @EnvironmentObject private var dim: DIMENSIONS
    @ObservedObject private var settings: SettingsStore = .shared
    private let nrPost: NRPost
    @ObservedObject private var nrContact: NRContact
    @ObservedObject private var highlightAttributes: HighlightAttributes
    
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
    
    init(nrPost: NRPost, hideFooter: Bool = true, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil, isReply: Bool = false, isDetail: Bool = false, isEmbedded: Bool = false, fullWidth: Bool, grouped: Bool = false, forceAutoload: Bool = false) {
        self.nrPost = nrPost
        self.nrContact = nrPost.contact
        self.highlightAttributes = nrPost.highlightAttributes
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
        if isEmbedded {
            self.embeddedView
        }
        else {
            self.normalView
        }
    }
    
    private var shouldAutoload: Bool {
        return !nrPost.isNSFW && (forceAutoload || SettingsStore.shouldAutodownload(nrPost) || nxViewingContext.contains(.screenshot))
    }
    
    @StateObject private var model = UnknownKindModel()
    
    @ViewBuilder
    private var normalView: some View {
        PostLayout(nrPost: nrPost, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect, isReply: isReply, isDetail: isDetail, fullWidth: fullWidth, forceAutoload: true) {
            unknownKindView
        }
    }
    
    @ViewBuilder
    private var embeddedView: some View {
        PostEmbeddedLayout(nrPost: nrPost) {
            unknownKindView
        }
    }
    
    @ViewBuilder
    private var unknownKindView: some View {
        switch model.state {
        case .loading:
            CenteredProgressView()
                .frame(height: 150)
                .onAppear {
                    model.load(unknownKind: nrPost.kind, eventId: nrPost.id, pubkey: nrPost.pubkey, dTag: nrPost.dTag, alt: nrPost.alt)
                }
        case .ready((let suggestedApps, let title)):
            VStack(alignment: .leading) {
                HStack {
                    Text("\(Image(systemName: "app.fill")) \(title)")
                        .fontWeight(.bold).lineLimit(1)
                    Spacer()
//                    Button(action: showNip89Info, label: {
//                        Image(systemName: "questionmark.circle")
//                            .foregroundColor(theme.secondary)
//                            .font(.caption)
//                    })
                }
                if !suggestedApps.isEmpty {
                    Text("Open with").font(.caption).foregroundColor(theme.secondary)
                    Divider()
                        .padding(.horizontal, -10)
                    
                    ForEach(suggestedApps) { app in
                        AppRow(app: app)
                    }
                }
                else {
                    Text("\(Image(systemName: "exclamationmark.triangle.fill")) kind \(Double(nrPost.kind).clean) type not (yet) supported")
                        .fontWeight(.bold).lineLimit(1)
                    NRTextDynamic((nrPost.content ?? nrPost.alt) ?? "")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        case .timeout:
            VStack {
                Label(String(localized: "kind \(Double(nrPost.kind).clean) type not (yet) supported", comment: "Message shown when a 'kind X' post is not yet supported"), systemImage: "exclamationmark.triangle.fill")
                    .hCentered()
                    .frame(maxWidth: .infinity)
                    .background(theme.lineColor.opacity(0.2))
                NRTextDynamic((nrPost.content ?? nrPost.alt) ?? "")
            }
        }
    }
}


#Preview {
    PreviewContainer({ pe in
        pe.parseMessages([
            // FLARE Handler information (web app that handles kind 34236)
            ###"["EVENT","edb5e0fc-78d376d19cd",{"content":"{\"name\":\"Flare\",\"display_name\":\"Flare\",\"nip05\":\"\",\"picture\":\"https://www.flare.pub//icons/icon-192x192.png\",\"banner\":\"\",\"about\":\"Flare is the next era of video streaming. You host your own content, post it to Nostr, and share it with the world. There's nothing the Commies can do about it\",\"lud16\":\"\",\"website\":\"https://www.flare.pub/\"}","created_at":1703160358,"id":"85446af5864f647ecfeb170fcb215aab70c864f34417d9723e2036f5ae9456c5","kind":31990,"pubkey":"3356de61b39647931ce8b2140b2bab837e0810c0ef515bbe92de0248040b8bdd","sig":"c2cf7650424eacb1f7d7fedb03a06ded234c200a27b2677b143aa77b31819e7ec1fd97adf0639d5a9925d53ec70c05dfcbd39d5dd4ffb81548c320d1ea2d1d60","tags":[["d","1703150957505"],["published_at","1703150957"],["t","video"],["t","music"],["r","https://www.flare.pub/"],["alt","Nostr App: Flare"],["r","https://github.com/zmeyer44/flare","source"],["zap","17717ad4d20e2a425cda0a2195624a0a4a73c4f6975f16b1593fc87fa46f2d58","wss://relay.nostr.band","9"],["zap","3356de61b39647931ce8b2140b2bab837e0810c0ef515bbe92de0248040b8bdd","wss://relay.nostr.band","1"],["p","17717ad4d20e2a425cda0a2195624a0a4a73c4f6975f16b1593fc87fa46f2d58","wss://relay.nostr.band","author"],["k","0"],["k","34235"],["web","https://www.flare.pub/w/<bech32>","naddr"],["web","https://www.flare.pub/channel/<bech32>","npub"]]}]"###,
            
            // A video event (34236)
            ###"["EVENT","ebb2bb4d-d5ca-4a40-8d84-018d4d713c07",{"content":"Unless he's a BSVer...","created_at":1704145399,"id":"04b6343a794bffdd74025748441afc0871d88e60fdab3dcefcbf6f94443750be","kind":34236,"pubkey":"fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52","sig":"f80b4412d97154d1619973b1539cb747c2be86a49faa604ba8c0c4c6a23f325b5cb907b3928abfcc8c6a4dafa4669698e71ae8ee6fa32a41f424e8f5d3dc2e97","tags":[["d","LcLDAUW"],["url","https://www.youtube.com/watch?v=jCMwDh3wmKU"],["title","It's not ok to laugh at the mentally ill"],["summary","Unless he's a BSVer..."],["published_at","1704145399"],["client","flare"],["thumb","http://i3.ytimg.com/vi/jCMwDh3wmKU/hqdefault.jpg"],["image","http://i3.ytimg.com/vi/jCMwDh3wmKU/hqdefault.jpg"],["content-warning","You'll lose 10 IQ points for watching this video"],["t","comedy"],["t","tragic"]]}]"###,
            
            
            // Recommendation event by Fabian, recommending Flare for kind 34235
            ###"["EVENT","edb5e0fc-78d5-41c3-bc80-703a376d19cd",{"content":"","created_at":1704230858,"id":"a2423c341bdfe8d31614957944979aa6386159805b3d854f399a69907a5c0f42","kind":31989,"pubkey":"9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e","sig":"118acc47e2712cd576d92acddf84ab14523a284ceddf678a58e7e24072d9c33594cd8e1ec5643533238a8cb4c9628481ed25ad8d30f0d685d3132e0b42930b66","tags":[["d","34235"],["a","31990:3356de61b39647931ce8b2140b2bab837e0810c0ef515bbe92de0248040b8bdd:1703150957505","wss://relay.nostr.band","web"]]}]"###,
            
            // Recommendation event by other user, recommending Flare for kind 34235
            ###"["EVENT","edb5e0fc-78d5-41c3-bc80-703a376d19cd",{"content":"","created_at":1703161801,"id":"e5eafd9efab845bb4162ff03e3c5f67470e5c941401c68b53661e07c6af5c5b8","kind":31989,"pubkey":"3356de61b39647931ce8b2140b2bab837e0810c0ef515bbe92de0248040b8bdd","sig":"38cfd6926279eeacc5a269a134a1127e73e0694348fbec07f6cf99ffba287f94b81b826193f66f58afb9a0b84c95599a5a70e9d6c53fe358603045844ecc74a8","tags":[["d","34235"],["a","31990:3356de61b39647931ce8b2140b2bab837e0810c0ef515bbe92de0248040b8bdd:1703150957505","wss://relay.nostr.band","web"]]}]"###,
        
        ])
    }) {
        PreviewFeed {
            if let unknownKind = PreviewFetcher.fetchNRPost("04b6343a794bffdd74025748441afc0871d88e60fdab3dcefcbf6f94443750be") {
                Box {
                    PostRowDeletable(nrPost: unknownKind)
                }
            }
        }
    }
}
