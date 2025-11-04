//
//  Kind9802.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/08/2024.
//

import SwiftUI

struct Kind9802: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    @Environment(\.theme) private var theme: Theme
    @Environment(\.availableWidth) private var availableWidth
    @Environment(\.containerID) private var containerID
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
    private let forceAutoload: Bool
    
    private let THREAD_LINE_OFFSET = 24.0
    
    
    private var availableWidth_: CGFloat {
        if isDetail || fullWidth || isEmbedded {
            return availableWidth - 20
        }
        
        return DIMENSIONS.availableNoteRowImageWidth(availableWidth)
    }
    
    init(nrPost: NRPost, hideFooter: Bool = true, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil, isReply: Bool = false, isDetail: Bool = false, isEmbedded: Bool = false, fullWidth: Bool, forceAutoload: Bool = false) {
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
    
    @ViewBuilder
    private var normalView: some View {
        PostLayout(nrPost: nrPost, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect, isReply: isReply, isDetail: isDetail, fullWidth: fullWidth, forceAutoload: true) {
            
            content
            
        }
    }
    
    @ViewBuilder
    private var embeddedView: some View {
        
        
        if let hlAuthorPubkey = highlightAttributes.authorPubkey, hlAuthorPubkey == nrPost.pubkey {
            // No need to wrap in PostEmbeddedLayout if the 9802.pubkey is the same as quoted text pubkey
            content
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !nxViewingContext.contains(.preview) else { return }
                    navigateTo(nrPost, context: containerID)
                }
        }
        else {
            PostEmbeddedLayout(nrPost: nrPost) {
                
                content
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !nxViewingContext.contains(.preview) else { return }
                        navigateTo(nrPost, context: containerID)
                    }
                
            }
        }
    }
    
    @ViewBuilder
    var content: some View {
        
        // Comment on quote from "comment" tag
        ContentRenderer(nrPost: nrPost, showMore: .constant(true), isDetail: isDetail, fullWidth: fullWidth, forceAutoload: forceAutoload)
            .environment(\.availableWidth, availableWidth_)
            .frame(maxWidth: .infinity, alignment:.leading)
        
        // The highlight, from .content
        VStack {
            Text(nrPost.content ?? "")
                .lineLimit(isDetail ? 500 : 25)
                .fixedSize(horizontal: false, vertical: true)
                .fontItalic()
                .padding(20)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !nxViewingContext.contains(.preview) else { return }
                    if let firstE = nrPost.firstE {
                        navigateTo(NotePath(id: firstE), context: containerID)
                    }
                    else if let aTag = nrPost.fastTags.first(where: { $0.0 == "a" }),
                            let naddr = try? ShareableIdentifier(aTag: aTag.1) {
                            navigateTo(Naddr1Path(naddr1: naddr.bech32string), context: containerID)
                    }
                }
                .overlay(alignment:.topLeading) {
                    Image(systemName: "quote.opening")
                        .foregroundColor(Color.secondary)
                }
                .overlay(alignment:.bottomTrailing) {
                    Image(systemName: "quote.closing")
                        .foregroundColor(Color.secondary)
                }
            
            if let hlAuthorPubkey = highlightAttributes.authorPubkey {
                PFPandName(pubkey: hlAuthorPubkey, alignment: .trailing)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !nxViewingContext.contains(.preview) else { return }
                        navigateTo(ContactPath(key: hlAuthorPubkey), context: containerID)
                    }
                    .padding(.trailing, 40)
            }
            HStack {
                Spacer()
                if let aTag = nrPost.fastTags.first(where: { $0.0 == "a" }),
                        let naddr = try? ShareableIdentifier(aTag: aTag.1) {
                    ArticleTitleByNaddr(naddr1: naddr.bech32string)
                        .onTapGesture {
                            guard !nxViewingContext.contains(.preview) else { return }
                            if let aTag = nrPost.fastTags.first(where: { $0.0 == "a" }),
                                    let naddr = try? ShareableIdentifier(aTag: aTag.1) {
                                    navigateTo(Naddr1Path(naddr1: naddr.bech32string), context: containerID)
                            }
                        }
                }
                if let url = highlightAttributes.url, let md = try? AttributedString(markdown:"[\(url)](\(url))") {
                    Text(md)
                        .lineLimit(1)
                        .font(.caption)
                }
            }
            .padding(.trailing, 40)
        }
        .padding(10)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.lineColor, lineWidth: 1)
        )
    }
}


// TODO: handle "source":
//"tags": [
//  [
//    "e",
//    "bc3d47e7f9bba39c89d969d7c2e09ba74e5bb4cd517aa99542ccbbb4d323fcbe",
//    "source"
//  ]
//]


#Preview("Highlight (9802)") {
    PreviewContainer({ pe in
        pe.parseEventJSON([
            // Source article
            ###"{"kind":30023,"id":"3b977db7b47e3db781db92fcb79ddc38070323bfa6f5bfbaca323fbd3bd7ce6c","pubkey":"97c70a44366a6535c145b333f973ea86dfdc2d7a99da618c40c64705ad98e322","created_at":1757966297,"tags":[["d","1757962925051"],["title","Information Wants to Be Free"],["summary","On digital signatures, and how they free our data from the custodians who store it."],["t","nostr"],["t","signatures"],["t","keys"],["image","https://hbr.coracle.social/98df7b82e2a374a4b5bddbca35bf157f5685b7f5394904c033b7e98e27cdd7e3.jpg"],["published_at","1757966295"],["alt","This is a long form article, you can read it in https://habla.news/a/naddr1qvzqqqr4gupzp978pfzrv6n9xhq5tvenl9e74pklmskh4xw6vxxyp3j8qkke3cezqqxnzde4xuunvv3exg6nqdf30ehdf4"]],"content":"*This is an excerpt from my recent book, Building Nostr. You can download and read the whole book for free at [building-nostr.coracle.social](https://building-nostr.coracle.social/).*\n\nDigital signatures are essential to making Nostr work. The goal of Nostr is to break down walled gardens by subverting one of their key value propositions: content authentication. Or, in other words, the ability to know that a particular person said a particular thing.\n\nThis is a challenge in the digital world because information can be copied or fabricated at will. Simply saying that someone authored a particular piece of content doesn't make it so. When you go to Twitter and you load up a tweet, you only know that tweet is real because you trust Twitter. And if someone takes a screenshot of that or copies the text and emails it to you, then you have even less assurance that what's been presented to you is authentic.\n\nWhat this means is that data that is not cryptographically signed is tightly coupled to custody. The only person who can reliably attest to the authenticity of a given piece of information is the person who can trace its provenance from the author, through storage, and to your device. This is very convenient for social media platforms — reliance on unsigned data means that they are needed. There has to be a single trustworthy custodian in order for unsigned data to work. The same is true of search results on Google; you don't know that search results are any good unless Google says they are.\n\nWhat signed data gives us is the ability to know that something is true without having to trust anyone. If I create a note on Nostr and use my private key to sign it, anyone can verify the signature using the hash of the event and my public key (which is attached to the event). This lets them know that the event was created by the person who has access to my private key, i.e., me.\n\nA Nostr event can thus be sent over an untrusted communication channel without the recipient losing the ability to know that it was me who signed it. As long as they know my public key, I can email a Nostr event, I can send a Nostr event over a peer-to-peer communication or over Bluetooth or over the LAN, or I can print it up and send it by mail. No intermediary can stop me without securing a monopoly on my communication.\n\n### Publicity Technology\n\nThe business model that fuels today's social media platforms is predicated on the capture of user data for their exclusive monetization. The user has become the product. Our data is used in a focused way to create targeted advertisements, or in the aggregate to understand and anticipate user behavior.\n\nSigned data solves only half of this problem — it actually *worsens* the problem to the extent that data is public and accessible to anyone who wants to analyze it for patterns. Designing digital identity also has an incredible amount of complexity involved, and must be approached with caution. From Philip Sheldrake's essay, [Human identity: the number one challenge in computer science](https://generative-identity.org/human-identity-the-number-one-challenge-in-computer-science/):\n\n> Put starkly, many millions of people have been excluded, persecuted, and murdered with the assistance of prior identity architectures, and no other facet of information technology smashes into the human condition in quite the same way as digital identity[...] This should give anyone involved in digital identity cause to consider the emergent (i.e. unplanned) consequences of their work.\n\nWhen designing systems that make use of digital identity, it's important to work from a conception of identity not as *objective*, but as *subjective* — that is, defined not by a set of static attributes, but by the dialectical contexts and relationships the person behind the identity participates in. The former kind of identity allows others to *act upon* the identity; the latter allows the person who own the identity *to act.*\n\nCryptographic identity doesn't automatically make this distinction, but can be used in either way. If the goal is user empowerment, a system of identity that is crafted to protect the digital freedoms of the user must be carefully designed.\n\nBecause identity is intended to be shared in a social setting, Nostr is not really \"privacy technology\". Rather, Nostr is \"publicity technology\".\n\nWhen you create an event and you send it to untrusted custodians (particularly if left unprotected by access controls or encryption) you are advertising something about yourself to the entire world. All the data included in an event and all the metadata that can be harvested by observers and middlemen points back to you.\n\nThis is suitable for Twitter-like use cases (although user privacy is a concern even in a broadcast social media context), but always has to be considered when building products on Nostr. For users, it's best to use a VPN and Tor in combination with Nostr if you're concerned about privacy. Even so, in the aggregate signed data can still be collected and used to understand both individual users and entire social clusters.\n\n### Dis-intermediating Data\n\nWith that in mind, signed data does help reduce the capture of user attention by dis-intermediating content delivery. The current business model of social media platforms is predicated on the attention users give the platform, which is maximized by designs which stimulate \"engagement\", the creation and consumption of digital content.\n\nThe old way of doing this was through centralized content production. A business would create content — for example, movies, magazines, or podcasts — and present it to users for their consumption. Of course, it was a lot easier to directly monetize this content because it was both high quality and protected by intellectual property laws.\n\nOn social media, content is not produced by the platform, but by users. This introduces a second side to engagement — users not only consume, but also produce content. This keeps them even more engaged, and provides even more information about them to the platform.\n\nWhen content is signed, it can no longer be captured by the platform (even if it is still visible to the platform). The result is that platforms lose the ability to enforce their monopoly on user attention. As a result of signed data, user attention can be diverted to other platforms that host a copy of the data. Nostr takes this effect even further by decoupling data storage and user interaction — relays store notes, but clients mediate user interactions.\n\nOn Nostr, clients can be more aligned with users, since they can only capture user attention to the extent that their *functionality* is what's valuable to the user, not the *data* they have access to.\n\nThe ability users have on an open network to leave a platform without losing all their data or their social graph is called [credible exit](https://newsletter.squishy.computer/p/credible-exit). This is the opposite of \"vendor lock-in\", which occurs when platforms make it difficult to leave them. The export features social platforms offer are nearly useless because they break all the links in your social graph. But if all your social data was signed and the social graph was open, it would be quite easy to leave.\n\nSocial media companies can still exist in a world of signed data, but they will have to offer a real value proposition to their users in order to retain them. This means that they'll be more likely to serve their users rather than extract as much value as possible from them.\n\nWhether open source software wins out or for-profit companies start building on Nostr, signed data weakens platforms' hold on their users and realigns the interests of social media platforms with those of their users. And while I think there's still room for skepticism about the effects of social media in general on people and communities, removing lock-in fixes a lot of existing perverse incentives in the system.\n","sig":"3ba6bb0e2936a32ede0703d6bf2c61803a0e548d8a8f98543af9e0e3dcf136bdca9fdc948a9d33d8ed667d38f419655c0ecf5c3b69dee947e331b309617f7eeb"}"###,
            
            // Source author
            ###"{"kind":0,"id":"c03f02424aaa39d37c90639f14f479f711a0977882f34124bce66b67cfbb5ede","pubkey":"97c70a44366a6535c145b333f973ea86dfdc2d7a99da618c40c64705ad98e322","created_at":1759166374,"tags":[["client","Coracle","31990:97c70a44366a6535c145b333f973ea86dfdc2d7a99da618c40c64705ad98e322:1685968093690"]],"content":"{\"lnurl\":\"lnurl1dp68gurn8ghj7em9w3skccne9e3k7tewwajkcmpdddhx7amw9akxuatjd3cz76r0v3kxymmy8s5283\",\"name\":\" hodlbod\",\"display_name\":\"\",\"picture\":\"https://hbr.coracle.social/9d20c2f4e4e5bc3914c02acf08b56742139508df833c3c98c72bda23c2b76409.jpg\",\"about\":\"Christian Bitcoiner and developer of coracle.social. Learn more at info.coracle.social.\\n\\nIf you can't tell the difference between me and a scammer, use a nostr client with web of trust support.\",\"website\":\"stuff.coracle.social\",\"nip05\":\"hodlbod@coracle.social\",\"banner\":\"https://hbr.coracle.social/571c66854bdba58bc77def7b0fcfe2f7b8109a35d7952888a9e4381b9791cec4.jpg\",\"lud16\":\"hodlbod@getalby.com\"}","sig":"592c17f916a11c556addc17866ff8336fb75096afb212529685e8a7e2b3448ba4854cdf6b3f2b896a11bf62bb97f65edd343531b29b3de17f257e2070ec4e1a8"}"###,
            
            // Highlight author
            ###"{"pubkey":"6e468422dfb74a5738702a8823b9b28168abab8655faacb6853cd0ee15deee93","content":"{\"name\":\"Gigi\",\"nip05\":\"dergigi.com\",\"about\":\"Not doing DMs, except for fiatjaf. Aspiring Saunameister. Babysitting AIs on the side.\",\"lud16\":\"dergigi@primal.net\",\"display_name\":\"Gigi\",\"picture\":\"https://dergigi.com/assets/images/avatars/09.png\",\"banner\":\"https://cdn.nostr.build/i/0aeb7560c271bbb1cef00760989acd9dd3f37bdc42b37852eecb0d0b70a3e862.jpg\",\"website\":\"https://dergigi.com\",\"pronouns\":\"up/only\"}","id":"4304d1d377e46b99c08dd77cdac46c4a5043f063a7aa77cf85e1773804c81017","sig":"51899c86bfb37c5ed7719afba245fe4f27e043e5f983ac07a47a3c6ee29108223b087e7d4533c390fac0365f12cb56b552bfba8067d14ecdc6f16e09e87fbacf","tags":[["alt","User profile for Gigi"],["name","Gigi"],["display_name","Gigi"],["picture","https://dergigi.com/assets/images/avatars/09.png"],["banner","https://cdn.nostr.build/i/0aeb7560c271bbb1cef00760989acd9dd3f37bdc42b37852eecb0d0b70a3e862.jpg"],["website","https://dergigi.com"],["pronouns","up/only"],["about","Not doing DMs, except for fiatjaf. Aspiring Saunameister. Babysitting AIs on the side."],["nip05","dergigi.com"],["lud16","dergigi@primal.net"]],"kind":0,"created_at":1759223094}"###
            
        ])
    }) {
        // Preview highlight
        let testHighlight = testNRPost(###"{"sig":"6c119d31fc17d79ce405db9641179d96aec70917df8241f817363348f633c6c6c21a7159c42323450086eccce78fb116140ad286d82e694c48325e1edc93e9e1","pubkey":"6e468422dfb74a5738702a8823b9b28168abab8655faacb6853cd0ee15deee93","kind":9802,"content":"On Nostr, clients can be more aligned with users, since they can only capture user attention to the extent that their functionality is what's valuable to the user, not the data they have access to.","tags":[["a","30023:97c70a44366a6535c145b333f973ea86dfdc2d7a99da618c40c64705ad98e322:1757962925051"],["alt","Highlight created by Boris. read.withboris.com"],["p","97c70a44366a6535c145b333f973ea86dfdc2d7a99da618c40c64705ad98e322"],["zap","6e468422dfb74a5738702a8823b9b28168abab8655faacb6853cd0ee15deee93","wss://relay.damus.io","50"],["zap","29dea8672f44ed164bfc83db3da5bd472001af70307f42277674cbc64d33013e","wss://relay.damus.io","2.1"],["zap","97c70a44366a6535c145b333f973ea86dfdc2d7a99da618c40c64705ad98e322","wss://relay.damus.io","27.0"]],"id":"ab1455fab41fb6d2a7785bd77a45c3015388506cae6ed4511f67b4f21e1bed43","created_at":1760141439}"###)
        VStack {
            PostRowDeletable(nrPost: testHighlight)
                .padding(10)
            Spacer()
        }
    }
}
