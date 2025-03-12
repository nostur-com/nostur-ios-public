//
//  NRKinds.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/05/2023.
//

import SwiftUI

struct KindFileMetadata {
    var url:String
    var m:String?
    var hash:String?
    var dim:String?
    var blurhash:String?
}

// We expect to show these properly
let SUPPORTED_VIEW_KINDS: Set<Int64> = [1,6,20,9802,30023,99999,20]

// We don't expect to show these, but anyone can quote or reply to any event so we still need to show something
let KNOWN_VIEW_KINDS: Set<Int64> = [0,3,4,5,7,1984,9734,9735,30009,8,30008]

// Need to clean up, AnyKind is only in Kind1Both?? shouldn't be there
struct AnyKind: View {
    @EnvironmentObject private var dim: DIMENSIONS
    private var nrPost: NRPost
    private var hideFooter: Bool = false
    private var autoload: Bool = false
    private var availableWidth: CGFloat
    private var theme: Theme
    
    @State private var didStart = false
    
    init(_ nrPost: NRPost, hideFooter: Bool = false, autoload: Bool = false, availableWidth: CGFloat, theme: Theme) {
        self.nrPost = nrPost
        self.hideFooter = hideFooter
        self.autoload = autoload
        self.availableWidth = availableWidth
        self.theme = theme
    }
    
    var body: some View {
        if SUPPORTED_VIEW_KINDS.contains(nrPost.kind) {
            switch nrPost.kind {
                case 1: // generic olas
                    if (nrPost.kTag ?? "" == "20"), let imageUrl = nrPost.imageUrls.first {
                        ContentRenderer(nrPost: nrPost, isDetail: false, fullWidth: true, availableWidth: availableWidth, forceAutoload: autoload, theme: theme, didStart: $didStart)
                            .padding(.vertical, 10)
                    }
                    else {
                        EmptyView()
                    }
                case 20:
                if let imageUrl = nrPost.imageUrls.first {
                        VStack {
                            MediaContentView(
                                media: MediaContent(
                                    url: imageUrl,
                                    dimensions: findImetaDimensions(nrPost.fastTags, url: imageUrl.absoluteString)
                                ),
                                availableWidth: dim.listWidth,
                                placeholderHeight: dim.listWidth, // Same as width so 1:1 (square)
                                contentMode: .fit,
                                imageUrls: nrPost.imageUrls
                            )
//                            PictureEventView(imageUrl: imageUrl, autoload: autoload, theme: theme, availableWidth: imageWidth, imageUrls: nrPost.imageUrls)
                                .padding(.horizontal, -10)
                                .overlay(alignment: .bottomTrailing) {
                                    if nrPost.imageUrls.count > 1 {
                                        Text("\(nrPost.imageUrls.count - 1) more")
                                            .fontWeightBold()
                                            .foregroundColor(.white)
                                            .padding(5)
                                            .background(.black)
                                            .allowsHitTesting(false)
                                    }
                                }
                            
                            ContentRenderer(nrPost: nrPost, isDetail: false, fullWidth: true, availableWidth: availableWidth, forceAutoload: autoload, theme: theme, didStart: $didStart)
                                .padding(.vertical, 10)
                        }
                    }
                    else {
                        EmptyView()
                    }
                case 99999:
                    let title = nrPost.eventTitle ?? "Untitled"
                    if let eventUrl = nrPost.eventUrl {
                        VideoEventView(title: title, url: eventUrl, summary: nrPost.eventSummary, imageUrl: nrPost.eventImageUrl, autoload: true, theme: theme)
                            .padding(.vertical, 10)
                    }
                    else {
                        EmptyView()
                    }
//                case 9735: TODO: ....
//                    ZapReceipt(sats: , receiptPubkey: , fromPubkey: , from: )
                default:
                    EmptyView()
            }
        }
        else if KNOWN_VIEW_KINDS.contains(nrPost.kind) {
            KnownKindView(nrPost: nrPost, hideFooter: hideFooter, theme: theme)
                .padding(.vertical, 10)
        }
        else {
            UnknownKindView(nrPost: nrPost, theme: theme)
                .padding(.vertical, 10)
        }
    }
}

// Kinds we know and need but don't really render
struct KnownKindView: View {
    @ObservedObject private var settings: SettingsStore = .shared
    @EnvironmentObject private var dim: DIMENSIONS
    private let nrPost: NRPost
    @ObservedObject var pfpAttributes: PFPAttributes
    private let hideFooter: Bool
    private let theme: Theme
    
    init(nrPost: NRPost, hideFooter: Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.pfpAttributes = nrPost.pfpAttributes
        self.hideFooter = hideFooter
        self.theme = theme
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Nostr event")
                    .font(.caption)
                Spacer()
                LazyNoteMenuButton(nrPost: nrPost)
            }
            Text(fallbackDescription(for: nrPost))
                .fontWeightBold()
            
            
            HStack {
                Spacer()
                ZappablePFP(pubkey: nrPost.pubkey, pfpAttributes: pfpAttributes, size: 25.0, zapEtag: nrPost.id, forceFlat: dim.isScreenshot)
                    .onTapGesture {
                        if let nrContact = nrPost.contact {
                            navigateTo(nrContact)
                        }
                        else {
                            navigateTo(ContactPath(key: nrPost.pubkey))
                        }
                    }
                
                Text(pfpAttributes.anyName)
                    .foregroundColor(.primary)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .layoutPriority(2)
                    .onTapGesture {
                        if let nrContact = nrPost.contact {
                            navigateTo(NRContactPath(nrContact: nrContact, navigationTitle: nrContact.anyName))
                        }
                        else {
                            navigateTo(ContactPath(key: nrPost.pubkey))
                        }
                    }
                    .onAppear {
                        guard nrPost.contact == nil else { return }
                        bg().perform {
                            EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "KnownKindView.001")
                            QueuedFetcher.shared.enqueue(pTag: nrPost.pubkey)
                        }
                    }
                    .onDisappear {
                        QueuedFetcher.shared.dequeue(pTag: nrPost.pubkey)
                    }
                
                Text(nrPost.createdAt.formatted(date: .omitted, time: .shortened))
                Text(nrPost.createdAt.formatted(.dateTime.day().month(.defaultDigits)))
            }
            
            if (!hideFooter && settings.rowFooterEnabled) {
                CustomizableFooterFragmentView(nrPost: nrPost, theme: theme)
                    .background(nrPost.kind == 30023 ? theme.secondaryBackground : theme.background)
                    .drawingGroup(opaque: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

func fallbackDescription(for nrPost: NRPost) -> String {
    return switch nrPost.kind {
    case 0:
        "Profile update"
    case 3:
        "Follow list update"
    case 4:
        "A Direct Message"
    case 5:
        "A deletion request"
    case 7:
        "A reaction"
    case 9734:
        "A zap request"
    case 9735:
        "A zap receipt"
    case 30009:
        "A badge definition update"
    case 8:
        "A badge award"
    case 30008:
        "A profile badge update"
    default:
        "A nostr event of kind: \(nrPost.kind)"
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
            
            
            // A zap request (for embed test)
            ###"["EVENT","zapreq1",{"id":"9aaced67e48d08b9f5d10a4547dcb38303cd5cf36df29bb90b7f3c278e044ee6","pubkey":"8ea485266b2285463b13bf835907161c22bb3da1e652b443db14f9cee6720a43","created_at":1718151853,"content":"freedom tech ftw 🤘 ","tags":[["e","6fbd764e061ed91e147b87aae5eb092db5a8ff915d544a4d5e5c398035e9cf93"],["p","4d5ce768123563bc583697db5e84841fb528f7b708d966f2e546286ce3c72077"],["relays","wss://nos.lol","wss://nostr.wine","wss://pyramid.fiatjaf.com","wss://relay.primal.net","wss://relay.snort.social","wss://jd34qtxj5l2io4xbwa7nuahk36eew5ab6bgofvhuptbuxfi5y5srcbqd.local","wss://nostr.mutinywallet.com","wss://galaxy13.nostr1.com","wss://eden.nostr.land","wss://relay.damus.io"]],"kind":9734,"sig":"472db5a1486d7a9facf221ddc1bb233804b60d13123d717277c707125e3b8c0896c4dab9cf8e29f4bc31988580cb8a0db849b56c1e9132f58d5806b755bc40ee"}]"###,
            
            ###"["EVENT","emberthezapreq1",{"created_at":1718206385,"content":"Testing a zap I made yesterday supporting nostr:npub1f4www6qjx43mckpkjld4apyyr76j3aahprvkduh9gc5xec78ypmsmakqh9 and moving nostr:npub1hedhcq93v5c226w8gfece5lxkf6zldvrgygw9ppmyq3msggvl6rst8kmxw to nostr first.\n\nHow does this look nostr:npub1unmftuzmkpdjxyj4en8r63cm34uuvjn9hnxqz3nz6fls7l5jzzfqtvd0j2 ?\n\nnostr:note1n2kw6ely35ytnaw3pfz50h9nsvpu6h8ndhefhwgt0u7z0rsyfmnqypa8yl","tags":[["p","4d5ce768123563bc583697db5e84841fb528f7b708d966f2e546286ce3c72077"],["p","be5b7c00b16530a569c742738cd3e6b2742fb5834110e2843b2023b8210cfe87"],["p","e4f695f05bb05b231255ccce3d471b8d79c64a65bccc014662d27f0f7e921092"]],"kind":1,"id":"7b438527390a2dd5c5490dc2535047977e50810b3506aa924563d85d427e8c40","sig":"2447a3f2818db341210092ee1f314c811239ef7ff76c9c78bd3c731bcdfd6c7d09d29fb18761ed930f2905d61548599a873c235132d77fda238e8df83ce52959","pubkey":"8ea485266b2285463b13bf835907161c22bb3da1e652b443db14f9cee6720a43"}]"###
        
        ])
    }) {
        PreviewFeed {
            // Embedded zap req
            if let embeddedZapreq = PreviewFetcher.fetchNRPost("7b438527390a2dd5c5490dc2535047977e50810b3506aa924563d85d427e8c40") {
                Box {
                    PostRowDeletable(nrPost: embeddedZapreq)
                }
            }
            
            // Just the zap req
            if let zapreq = PreviewFetcher.fetchNRPost("9aaced67e48d08b9f5d10a4547dcb38303cd5cf36df29bb90b7f3c278e044ee6") {
                Box {
                    PostRowDeletable(nrPost: zapreq)
                }
            }
            
            // Row
            if let unknownKind = PreviewFetcher.fetchNRPost("04b6343a794bffdd74025748441afc0871d88e60fdab3dcefcbf6f94443750be") {
                Box {
                    PostRowDeletable(nrPost: unknownKind)
                }
            }
        }
    }
}
