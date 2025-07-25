//
//  KindResolver.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/05/2023.
//

import SwiftUI

struct KindResolver: View {
    @Environment(\.theme) private var theme
    @Environment(\.nxViewingContext) private var nxViewingContext
    public let nrPost: NRPost
    public var fullWidth: Bool = false
    public var hideFooter: Bool = false // For rendering in NewReply
    public var missingReplyTo: Bool = false // For rendering in thread
    public var isReply: Bool = false
    public var isDetail: Bool = false
    public var isEmbedded: Bool = false
    public var connect: ThreadConnectDirection? = nil
    public var forceAutoload: Bool = false // To override auto downloaded of reposted post using pubkey of reposter
    
    private var shouldAutoload: Bool {
        return !nrPost.isNSFW && (forceAutoload || SettingsStore.shouldAutodownload(nrPost) || nxViewingContext.contains(.screenshot))
    }
    
    var body: some View {
//        #if DEBUG
//        let _ = Self._printChanges()
//        #endif
        switch nrPost.kind {
            
        case 0: // .kind 0 happens somehow when events are deleted (Core Data) but still on screen, so not actually kind:0 but missing event, refetch event as workaround:
            EmbedById(id: nrPost.id, fullWidth: fullWidth, forceAutoload: shouldAutoload)
        
        case 3,4,5,7,1984,9734,30009,8,30008:
            // We don't expect to show these, but anyone can quote or reply to any event so we still need to show something
            OtherKnownKinds(nrPost: nrPost, hideFooter: hideFooter)
                .onAppear { self.enqueue() }
                .onDisappear { self.dequeue() }
        case 443:
            Kind443(nrPost: nrPost)
            // TODO: .navigationTitle should be somewhere else, only if isDetail
//                .navigationTitle("Comments on \(nrPost.fastTags.first(where: { $0.0 == "r" } )?.1.replacingOccurrences(of: "https://", with: "") ?? "...")")
            if isDetail {
                
                Text("Comments on \(nrPost.fastTags.first(where: { $0.0 == "r" } )?.1.replacingOccurrences(of: "https://", with: "") ?? "...")")
                    .fontWeightBold()
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity)
                    .background(theme.listBackground)
                    .padding(.horizontal, -10)
                
//                HStack(spacing: 0) {
//                    self.replyButton
//                        .foregroundColor(theme.footerButtons)
//                        .padding(.leading, 10)
//                        .padding(.vertical, 5)
//                        .contentShape(Rectangle())
//                        .onTapGesture {
//                            sendNotification(.createNewReply, ReplyTo(nrPost: nrPost))
//                        }
//                    Spacer()
//                }
//                .padding(.bottom, 15)
//                .background(theme.listBackground)
//                .padding(.top, -10)
//                .padding(.horizontal, -10)
            }
        case 9735: // TODO: need to check
            if let zap = nrPost.nxZap {
                NxZapReceipt(sats: zap.sats, receiptPubkey: zap.receiptPubkey, fromPubkey: zap.fromPubkey, nrZapFrom: zap.nrZapFrom)
                    .onAppear { self.enqueue() }
                    .onDisappear { self.dequeue() }
            }
            
        case 9802:
            Kind9802(nrPost: nrPost, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect, isDetail: isDetail, isEmbedded: isEmbedded, fullWidth: fullWidth, forceAutoload: shouldAutoload)
                .onAppear { self.enqueue() }
                .onDisappear { self.dequeue() }
            
        case 30311:
            if let liveEvent = nrPost.nrLiveEvent {
                if isEmbedded {
                    LiveEventRowView(nrPost: nrPost, liveEvent: liveEvent, fullWidth: fullWidth, hideFooter: hideFooter, forceAutoload: forceAutoload)
                        .onAppear { self.enqueue() }
                        .onDisappear { self.dequeue() }
                }
                else if isDetail {
                    LiveEventDetail(liveEvent: liveEvent)
                        .onAppear { self.enqueue() }
                        .onDisappear { self.dequeue() }
                }
                else {
                    PostLayout(nrPost: nrPost, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect, isReply: isReply, isDetail: isDetail, fullWidth: true, forceAutoload: forceAutoload, isItem: true) {
                        LiveEventRowView(nrPost: nrPost, liveEvent: liveEvent, fullWidth: fullWidth, hideFooter: hideFooter, forceAutoload: forceAutoload)
                            .onAppear { self.enqueue() }
                            .onDisappear { self.dequeue() }
                    }
                }
            }
        case 30023:
            Kind30023(nrPost: nrPost, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect, isDetail: isDetail, isEmbedded: isEmbedded, fullWidth: fullWidth, forceAutoload: shouldAutoload)
                .onAppear { self.enqueue() }
                .onDisappear { self.dequeue() }
        case 1063:
            if canRender1063(nrPost), let fileMetadata = nrPost.fileMetadata {
                Kind1063(nrPost: nrPost, fileMetadata: fileMetadata, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect, isDetail: isDetail, isEmbedded: isEmbedded, fullWidth: fullWidth, forceAutoload: shouldAutoload)
                    .onAppear { self.enqueue() }
                    .onDisappear { self.dequeue() }
            }
            else {
                UnknownKind(nrPost: nrPost, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect, isDetail: isDetail, isEmbedded: isEmbedded, fullWidth: fullWidth, forceAutoload: shouldAutoload)
                    .onAppear { self.enqueue() }
                    .onDisappear { self.dequeue() }
            }
        case 20:
            Kind20(nrPost: nrPost, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect, isDetail: isDetail, isEmbedded: isEmbedded, fullWidth: fullWidth, forceAutoload: shouldAutoload)
                .onAppear { self.enqueue() }
                .onDisappear { self.dequeue() }
            
        case 99999: // Disabled and let NIP-89 handle it for now
            let title = nrPost.eventTitle ?? "Untitled"
            if let eventUrl = nrPost.eventUrl {
                VideoEventView(title: title, url: eventUrl, summary: nrPost.eventSummary, imageUrl: nrPost.eventImageUrl, autoload: true)
                    .padding(.vertical, 10)
                    .onAppear { self.enqueue() }
                    .onDisappear { self.dequeue() }
            }
            else {
                UnknownKind(nrPost: nrPost, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect, isDetail: isDetail, isEmbedded: isEmbedded, fullWidth: fullWidth, forceAutoload: shouldAutoload)
                    .onAppear { self.enqueue() }
                    .onDisappear { self.dequeue() }
            }
            
        case 30000,39089:
            Kind30000(nrPost: nrPost, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect, isDetail: isDetail, isEmbedded: isEmbedded, fullWidth: fullWidth, forceAutoload: shouldAutoload)
                .onAppear { self.enqueue() }
                .onDisappear { self.dequeue() }
        
        case 1:
            Kind1(nrPost: nrPost, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect, isDetail: isDetail, isEmbedded: isEmbedded, fullWidth: fullWidth || (nrPost.kTag ?? "" == "20" && nrPost.galleryItems.count > 0), forceAutoload: shouldAutoload)
                .onAppear { self.enqueue() }
                .onDisappear { self.dequeue() }
            
        default:
            UnknownKind(nrPost: nrPost, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect, isDetail: isDetail, isEmbedded: isEmbedded, fullWidth: fullWidth, forceAutoload: shouldAutoload)
                .onAppear { self.enqueue() }
                .onDisappear { self.dequeue() }
            
        }
    }
    
    
    @ViewBuilder
    private var replyButton: some View {
        Image("ReplyIcon")
        Text("Add comment")
    }
    
    private func enqueue() {
        if !nrPost.missingPs.isEmpty {
            bg().perform {
                EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "KindResolver.001")
                QueuedFetcher.shared.enqueue(pTags: nrPost.missingPs)
            }
        }
    }
    
    private func dequeue() {
        if !nrPost.missingPs.isEmpty {
            QueuedFetcher.shared.dequeue(pTags: nrPost.missingPs)
        }
    }
}

struct KindResolver_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.parseMessages([
                ###"["EVENT","916495e3-d98d-417e-929d-4ed4694a2b8a",{"content":"{\"banner\":\"https://media.giphy.com/media/hAb5yLCOJn7NK/source.gif\",\"website\":\"https://21ideas.org/\",\"reactions\":true,\"damus_donation\":1,\"lud16\":\"21ideas@getalby.com\",\"picture\":\"https://nostr.build/i/p/nostr.build_2234d34b3e590e20d8ab2342b01d8b979e620ef9ae263e1605b2f10a6180a22a.gif\",\"nip05\":\"tony@bitcoin-herald.org\",\"display_name\":\"Tony\",\"about\":\"Bitcoin learner & educator  \\n\\nDevoted to promoting censorship resistant protocols.  \\n\\nhttps://habla.news contributor  \\n\\nhttps://bitcoin-herald.org chief editor\\n\\nAbout: https://tony.21ideas.org/\",\"name\":\"Tony\"}","created_at":1687248694,"id":"938a46c919252f0badbcf5a5c8d8b11f731238a650476e6e590ea1e826e659e0","kind":0,"pubkey":"7f5c2b4e48a0e9feca63a46b13cdb82489f4020398d60a2070a968caa818d75d","sig":"307e910b933eedf466d3aa1ccab43487482cafff15438ecf667808faabc12c4d20412e8f16f9f2b867dd0071ec137b6c4ec36213886e6f3a493a2c691b52e334","tags":[]}]"###,
                ###"["EVENT","83cfe081-043d-45fa-9a3c-fdbe0dfe959d",{"content":"{\"banner\":\"https://upload.wikimedia.org/wikipedia/commons/b/b4/The_Sun_by_the_Atmospheric_Imaging_Assembly_of_NASA%27s_Solar_Dynamics_Observatory_-_20100819.jpg\",\"website\":\"\",\"lud06\":\"LNURL1DP68GURN8GHJ7AMPD3KX2AR0VEEKZAR0WD5XJTNRDAKJ7TNHV4KXCTTTDEHHWM30D3H82UNVWQHHW6TWDE5KUEMZD3HHWEM4DCURVNYWCP4\",\"reactions\":false,\"damus_donation\":100,\"picture\":\"https://nostr.build/i/p/nostr.build_6b9909bccf0f4fdaf7aacd9bc01e4ce70dab86f7d90395f2ce925e6ea06ed7cd.jpeg\",\"lud16\":\"jackjack@getalby.com\",\"display_name\":\"\",\"about\":\"bitcoin & chill\",\"name\":\"jack\"}","created_at":1684229244,"id":"ac6866af0c5e25fbfec3b6ce7badef73da2fc13ec05962d68c0ffa03861cc097","kind":0,"pubkey":"82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2","sig":"58fd210e85517c67a15c21227503a1a7afbf716a204ff4e2e81cca13a822ea9d72c34688f123a0b3b421d0426a29cee6a4b6fb8349eab1242ba46483271c350c","tags":[]}]"###,
                ###"["EVENT","a0371053-be5d-4e73-aadd-ff632f026c10",{"content":"{\"name\":\"fiatjaf\",\"about\":\"conditional chaining is a shitcoin\",\"picture\":\"https://fiatjaf.com/static/favicon.jpg\",\"nip05\":\"_@fiatjaf.com\",\"lud16\":\"fiatjaf@zbd.gg\"}","created_at":1686845608,"id":"ce89466a29e09ffdd458f1b219f055b15006a56e24e33a40dbb378836c89b0e3","kind":0,"pubkey":"3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d","sig":"459325e116b1ce8d6bfc68a6466ff4ac4acea28230f425cde594b8cafa4422b98b2a964621a0d2563c8f962975e429145b8dbb9d180cdf90cbd73df03756993a","tags":[]}]"###,
                ###"["EVENT","WHAT",{"content":"The current plan consists in giving out money not for specific tasks, but for general open-source efforts that seem to be worth it according to my own completely arbitrary and subjective judgment and hand out microbounties to these.\n\nThe idea is that people will give a little more priority working on Nostr things that they already wanted to because they have a chance of getting a microbounty for it while if they work on another side project like a rollercoaster building game they don’t have that chance (although rollercoaster building games have other advantages).\n\nHere is a list of themes that I currently think are worth exploring more, to serve as an inspiration:\nThemes\n\n- Microapps (Nostr apps that do only one thing and do it well), for example:\n  * An app for just publishing things and reading replies\n  * An app for just managing your contacts\n  * An app for just reading threads\n- Native apps instead of web\n- Pull requests that add these nice features to existing clients instead of making a new client\n- New use cases besides “social” but that still deliver interoperability and standardized behavior between clients\n- Bonus points if these new use cases can be interacted with with from the “social” clients in some way, e.g.\n  * if you do webpage comments on Nostr you can see and interact with these from social clients as normal posts\n  * If you do wikipedia on Nostr you can comment on these articles from social clients\n- Usable tricks to secure keys that can still work in practice, some stupid examples:\n  * A client (or addition to existing clients) that stores encrypted Nostr on the user’s Google Drive and the decryption key for that on a custom server\n  * An integrated multisig server that signs stuff upon request\n- Relay discovery\n  * Because we should not assume everybody will always be in all relays or that clients will talk to all relays all the time forever\n- Making existing things\n  * Prettier\n  * Faster\n- Non-public relays use cases\n\n\n# Bounties given\n\n## June 2023\n  - **BOUNTY**: Sepher: 2,000,000 - a webapp for making lists of anything: https://pinstr.app/\n  - **BOUNTY**: Kieran: 10,000,000 - implement gossip algorithm on Snort, implement all the other nice things: manual relay selection, following hints etc.\n  - Mattn: 5,000,000 - a myriad of projects and contributions to Nostr projects: https://github.com/search?q=owner%3Amattn+nostr&type=code\n  - **BOUNTY**: lynn: 1,000,000 - a simple and clean git nostr CLI written in Go, compatible with William's original git-nostr-tools; and implement threaded comments on https://github.com/fiatjaf/nocomment.\n  - Jack Chakany: 5,000,000 - https://github.com/jacany/nblog\n  - **BOUNTY**: Dan: 2,000,000 - https://metadata.nostr.com/\n\n## April 2023\n  - **BOUNTY**: Blake Jakopovic: 590,000 - event deleter tool, NIP dependency organization\n  - **BOUNTY**: koalasat: 1,000,000 - display relays\n  - **BOUNTY**: Mike Dilger: 4,000,000 - display relays, follow event hints (Gossip)\n  - **BOUNTY**: kaiwolfram: 5,000,000 - display relays, follow event hints, choose relays to publish (Nozzle)\n  - Daniele Tonon: 3,000,000 - Gossip\n  - bu5hm4nn: 3,000,000 - Gossip\n  - **BOUNTY**: hodlbod: 4,000,000 - display relays, follow event hints\n\n## March 2023\n  - Doug Hoyte: 5,000,000 sats - https://github.com/hoytech/strfry\n  - Alex Gleason: 5,000,000 sats - https://gitlab.com/soapbox-pub/mostr\n  - verbiricha: 5,000,000 sats - https://badges.page/, https://habla.news/\n  - talvasconcelos: 5,000,000 sats - https://migrate.nostr.com, https://read.nostr.com, https://write.nostr.com/\n  - **BOUNTY**: Gossip model: 5,000,000 - https://camelus.app/\n  - **BOUNTY**: Gossip model: 5,000,000 - https://github.com/kaiwolfram/Nozzle\n  - **BOUNTY**: Bounty Manager: 5,000,000 - https://nostrbounties.com/\n## February 2023\n - styppo: 5,000,000 sats - https://hamstr.to/\n - sandwich: 5,000,000 sats - https://nostr.watch/\n - **BOUNTY**: Relay-centric client designs: 5,000,000 sats https://bountsr.org/design/2023/01/26/relay-based-design.html\n  - **BOUNTY**: Gossip model on https://coracle.social/: 5,000,000 sats\n  - Nostrovia Podcast: 3,000,000 sats - https://nostrovia.org/\n  - **BOUNTY**: Nostr-Desk / Monstr: 5,000,000 sats - https://github.com/alemmens/monstr\n  - Mike Dilger: 5,000,000 sats - https://github.com/mikedilger/gossip\n\n## January 2023\n  - ismyhc: 5,000,000 sats - https://github.com/Galaxoid-Labs/Seer\n  - Martti Malmi: 5,000,000 sats - https://iris.to/\n  - Carlos Autonomous: 5,000,000 sats - https://github.com/BrightonBTC/bija\n  - Koala Sat: 5,000,000 - https://github.com/KoalaSat/nostros\n  - Vitor Pamplona: 5,000,000 - https://github.com/vitorpamplona/amethyst\n  - Cameri: 5,000,000 - https://github.com/Cameri/nostream\n\n##  December 2022\n  - William Casarin: 7 BTC - splitting the fund\n  - pseudozach: 5,000,000 sats - https://nostr.directory/\n  - Sondre Bjellas: 5,000,000 sats - https://notes.blockcore.net/\n  - Null Dev: 5,000,000 sats - https://github.com/KotlinGeekDev/Nosky\n  - Blake Jakopovic: 5,000,000 sats - https://github.com/blakejakopovic/nostcat, https://github.com/blakejakopovic/nostreq and https://github.com/blakejakopovic/NostrEventPlayground ","created_at":1687269218,"id":"21b3bd3c5eec98bba15aa0fd32f24f18a0540e70c18ed1ac4f156d41ffc17ce6","kind":30023,"pubkey":"3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d","sig":"3d2f958d7b34847d06833b1b8868507f6b343cb3f8fc4864d4b7c57b5025992f956c65cf56de5cdb3a22ef4703deee9f96e3ea67822b6dcb496ff1a252898a7f","tags":[["d","fd6dc37c"],["title","The fiatjaf Nostr fund"],["summary","Reports on how Jack's money is being spent by fiatjaf, previously at https://docs.google.com/document/d/10xKQIO969GoNnAEnoMgJky69lG-_TslnqO4uIfioi1Y/edit#"],["published_at","1687268345"],["t","nostr"],["t","fund"],["t","bounties"]]}]"###,
                ###"["EVENT","WHAT",{"content":"\n---\n\n_This guide is available in:_\n\n* French: nostr:naddr1qqxnzd3cxyunqvfhxy6rvwfjqyghwumn8ghj7mn0wd68ytnhd9hx2tcpzamhxue69uhhyetvv9ujumn0wd68ytnzv9hxgtcpvemhxue69uhkv6tvw3jhytnwdaehgu3wwa5kuef0dec82c33xpshw7ntde4xwdtjx4kxz6nwwg6nxdpn8phxgcmedfukcem3wdexuun5wy6kwunnxsun2a35xfckxdnpwaek5dp409enw0mzwfhkzerrv9ehg0t5wf6k2qgawaehxw309a6ku6tkv4e8xefwdehhxarjd93kstnvv9hxgtczyzd9w67evpranzz2jw4m9wcygcyjhxsmcae6g5s58el5vhjnsa6lgqcyqqq823cmvvp6c thanks to nostr:npub1nftkhktqglvcsj5n4wetkpzxpy4e5x78wwj9y9p70ar9u5u8wh6qsxmzqs \n* Chinese: nostr:naddr1qqxnzd3cx5urvwfe8qcr2wfhqyxhwumn8ghj7mn0wvhxcmmvqy28wumn8ghj7un9d3shjtnyv9kh2uewd9hszrrhwden5te0vfexytnfduq35amnwvaz7tmwdaehgu3wdaexzmn8v4cxjmrv9ejx2aspzamhxue69uhhyetvv9ujucm4wfex2mn59en8j6gpzpmhxue69uhkummnw3ezuamfdejszxrhwden5te0wfjkccte9eekummjwsh8xmmrd9skcqg4waehxw309ajkgetw9ehx7um5wghxcctwvsq35amnwvaz7tmjv4kxz7fwdehhxarjvaexzurg9ehx2aqpr9mhxue69uhhqatjv9mxjerp9ehx7um5wghxcctwvsq3jamnwvaz7tmwdaehgu3w0fjkyetyv4jjucmvda6kgqgjwaehxw309ac82unsd3jhqct89ejhxqgkwaehxw309ashgmrpwvhxummnw3ezumrpdejqz8rhwden5te0dehhxarj9ekh2arfdeuhwctvd3jhgtnrdakszpmrdaexzcmvv5pzpnydquh0mnr8dl96c98ke45ztmwr2ah9t6mcdg4fwhhqxjn2qfktqvzqqqr4gu086qme thanks to nostr:npub1ejxswthae3nkljavznmv66p9ahp4wmj4adux525htmsrff4qym9sz2t3tv\n* Swedish: nostr:naddr1qqxnzd3cxcerjvekxy6nydpeqyvhwumn8ghj7un9d3shjtnwdaehgunfvd5zumrpdejqzxthwden5te0wp6hyctkd9jxztnwdaehgu3wd3skueqpz4mhxue69uhkummnw3ezu6twdaehgcfwvd3sz9thwden5te0dehhxarj9ekkjmr0w5hxcmmvqyt8wumn8ghj7un9d3shjtnwdaehgu3wvfskueqpzpmhxue69uhkummnw3ezuamfdejszenhwden5te0ve5kcar9wghxummnw3ezuamfdejj7mnsw43rzvrpwaaxkmn2vu6hydtvv94xuu34xv6rxwrwv33hj6ned3nhzumjdee8guf4vae8xdpex4mrgvn3vvmxzamndg6r27tnxulkyun0v9jxxctnws7hgun4v5q3vamnwvaz7tmzd96xxmmfdejhytnnda3kjctvqyd8wumn8ghj7un9d3shjtn0wfskuem9wp5kcmpwv3jhvqg6waehxw309aex2mrp0yhxummnw3e8qmr9vfejucm0d5q3camnwvaz7tm4de5hvetjwdjjumn0wd68y6trdqhxcctwvsq3camnwvaz7tmwdaehgu3wd46hg6tw09mkzmrvv46zucm0d5q32amnwvaz7tm9v3jkutnwdaehgu3wd3skueqprpmhxue69uhhyetvv9ujumn0wd68yct5dyhxxmmdqgszet26fp26yvp8ya49zz3dznt7ungehy2lx3r6388jar0apd9wamqrqsqqqa28jcf869 thanks to nostr:npub19jk45jz45gczwfm22y9z69xhaex3nwg47dz84zw096xl6z62amkqj99rv7\n* Russian: nostr:naddr1qqxnzd3cxg6nyvehxgurxdfkqyvhwumn8ghj7un9d3shjtnwdaehgunfvd5zumrpdejqzxthwden5te0wp6hyctkd9jxztnwdaehgu3wd3skueqpz4mhxue69uhkummnw3ezu6twdaehgcfwvd3sz9thwden5te0dehhxarj9ekkjmr0w5hxcmmvqyt8wumn8ghj7un9d3shjtnwdaehgu3wvfskueqpzpmhxue69uhkummnw3ezuamfdejszenhwden5te0ve5kcar9wghxummnw3ezuamfdejj7mnsw43rzvrpwaaxkmn2vu6hydtvv94xuu34xv6rxwrwv33hj6ned3nhzumjdee8guf4vae8xdpex4mrgvn3vvmxzamndg6r27tnxulkyun0v9jxxctnws7hgun4v5q3vamnwvaz7tmzd96xxmmfdejhytnnda3kjctvqyd8wumn8ghj7un9d3shjtn0wfskuem9wp5kcmpwv3jhvqg6waehxw309aex2mrp0yhxummnw3e8qmr9vfejucm0d5q3camnwvaz7tm4de5hvetjwdjjumn0wd68y6trdqhxcctwvsq3camnwvaz7tmwdaehgu3wd46hg6tw09mkzmrvv46zucm0d5q32amnwvaz7tm9v3jkutnwdaehgu3wd3skueqprpmhxue69uhhyetvv9ujumn0wd68yct5dyhxxmmdqgs87hptfey2p607ef36g6cnekuzfz05qgpe34s2ypc2j6x24qvdwhgrqsqqqa286qva9x by yours truly 💜\n\n---\n\nHello, fellow Nostrich! \n\nNostr is a brand new phenomenon and there are a few steps that will make your onboarding much smoother and your experience much richer.\n\n## 👋 Welcome\n\nSince you are reading this, it’s safe to assume that you already joined Nostr by downloading an app (e.g. [Damus](https://damus.io/), [Amethyst](https://play.google.com/store/apps/details?id=com.vitorpamplona.amethyst&hl=en&gl=US), [Plebstr](https://plebstr.com/)) for your mobile device or opening a Nostr web client (e.g. [snort.social](https://snort.social/), [Nostrgram](https://nostrgram.co/), [Iris](https://iris.to/)). It is important for a newcomer to follow the steps suggested by the app of your choice – the welcoming procedure provides all the basics, and you won’t have to do much more tuning unless you really want to. If you’ve stumbled upon this post, but don’t have a Nostr “account” yet, you can follow [this simple step-by-step guide](https://worldtravelambitions.notion.site/worldtravelambitions/How-to-Set-Up-Nostr-Using-GetAlby-and-Snort-social-c3fabb2ecc8d465dba0e73a3f1c2558a) by nostr:npub1cly0v30agkcfq40mdsndzjrn0tt76ykaan0q6ny80wy034qedpjsqwamhz -- `npub1cly0v30agkcfq40mdsndzjrn0tt76ykaan0q6ny80wy034qedpjsqwamhz`.\n\n---\n\n## 🤙 Have fun\n\nNostr is built to ensure people can connect, get heard, and have fun along the way. This is the whole point (obviously, there is a plethora of serious use cases, such as being a tool for freedom fighters and whistleblowers, but that deserves a separate article), so if you feel like anything feels burdensome, please reach out to the more experienced nostriches and we will be happy to help. Interacting with Nostr is not hard at all, but it has a few peculiarities when compared to traditional platforms, so it’s ok (and encouraged) to ask questions. \n\nHere’s an _unofficial_ list of Nostr ambassadors who will be happy to help you get onboard:\n\nnostr:naddr1qqg5ummnw3ezqstdvfshxumpv3hhyuczypl4c26wfzswnlk2vwjxky7dhqjgnaqzqwvdvz3qwz5k3j4grrt46qcyqqq82vgwv96yu\n\n_All the nostriches on the list were also awarded a [Nostr Ambassador](https://lnshort.it/nostr-ambassadors) badge that will make it easy for you to find, verify and follow them_\n\n---\n\n## ⚡️ Enable Zaps\n\nZaps are one of the first differences one may notice after joining Nostr. They allow Nostr users to instantly send value and support creation of useful and fun content. This is possible thanks to Bitcoin and Lightning Network. These decentralized payment protocols let you instantly send some sats (the smallest unit on the Bitcoin network) just as easily as liking someone’s post on traditional social media platforms. We call this model Value-4-Value and you can find more about this ultimate monetization model here: [https://dergigi.com/value/](https://dergigi.com/value/) \n\nCheck out [this note](https://lnshort.it/what-are-zaps/) by nostr:npub18ams6ewn5aj2n3wt2qawzglx9mr4nzksxhvrdc4gzrecw7n5tvjqctp424 that is a great intro to what zaps are.\n\nYou should enable Zaps even if you do not consider yourself a content creator – people **will** find some of your notes valuable and might want to send you some sats. The easiest way to start receiving value on Nostr onley takes a couple steps:\n\n**0** Download [Wallet of Satoshi](https://www.walletofsatoshi.com/) [^1] (probably the best choice for those who are new to Bitcoin and Lightning) for your mobile device [^2]\n**1** Tap “Receive”\n**2** Tap the Lightning Address you see on the screen (the string which looks like an email address) to copy it to the clipboard.\n![wos2](https://nostr.build/p/nb5751.png)\n**3** Paste the copied address into the corresponding field in your Nostr client (the field may say “Bitcoin Lightning Address”, “LN Address” or anything along those lines depending on the app you are using). \n![paste](https://nostr.build/p/nb5752.png)\n\n---\n\n## 📫 Get a Nostr address\n\nNostr address, often referred to as a “NIP-05 identifier” by the Nostr OGs, looks like an email and: \n\n🔍 Helps you make your account easy to discover and share \n✔️ Serves as a verification you are a human\n\n---\n\nHere's an example of a Nostr address: [Tony@nostr.21ideas.org](nostr:npub10awzknjg5r5lajnr53438ndcyjylgqsrnrtq5grs495v42qc6awsj45ys7)\n![nip-05](https://nostr.build/p/nb5756.png)\n _It's easy to memorize and later paste into any Nostr app to find the corresponding user._\n\n---\n\nTo get a Nostr address you can use a free service like [Nostr Check](https://nostrcheck.me/) (by nostr:npub138s5hey76qrnm2pmv7p8nnffhfddsm8sqzm285dyc0wy4f8a6qkqtzx624) or a paid one like [Nostr Plebs](https://nostrplebs.com/) (by nostr:npub18ams6ewn5aj2n3wt2qawzglx9mr4nzksxhvrdc4gzrecw7n5tvjqctp424). Both offer different perks, and it's up to you to decide which one to use. Another way of getting a Nostr address is using a browser extension. Find out more about this approach [here](https://blog.getalby.com/the-2-minute-alby-guide-to-nostr/)) .   \n\n---\n\n## 🙇‍♀️ Learn the basics\n\nUnder the hood Nostr is very different from traditional social platforms, so getting a basic understanding of what it is about will be beneficial for any newcomer. Don’t get me wrong, I’m not suggesting you should learn a programming language or technical details of the protocol. I’m implying that seeing a bigger picture and understanding the difference between Nostr and Twitter / Medium / Reddit will help a lot. For example, there are no passwords and logins, you have private and public keys instead. I won’t go deep into that, ‘cause there is a handful of exhaustive resources that will help you grokk Nostr. All of the ones worthy your attention are gathered [on this neatly organized landing page](https://www.bevstr.com/Nostr/) prepared by nostr:npub12gu8c6uee3p243gez6cgk76362admlqe72aq3kp2fppjsjwmm7eqj9fle6 with 💜\n\n![bevstr](https://nostr.build/p/nb5847.png)\n_Info provided by the mentioned resources will also help you secure your Nostr keys (i.e. your account), so it’s important to have a look._\n\n---\n\n## 🤝 Connect\n\nAbility to connect with brilliant [^3] people is what makes Nostr special. Here everyone can get heard and no one can get excluded. There are a few simple ways to find interesting people on Nostr:\n\n* **Find people you follow on Twitter**: [**https://www.nostr.directory/**](https://www.nostr.directory/) is a great tool for that.\n* **Follow people followed by people you trust**: Visit a profile of a person who shares your interests, check the list of people they follow and connect with them.\n\n![gigi](https://nostr.build/p/nb5377.png)\n\n* **Visit Global Feed**: Every Nostr client (a Nostr app, if you will) has a tab that lets you switch to the Global Feed, which aggregates all the notes from all Nostr users. Simply follow people you find interesting (be patient though – you might run into a decent amount of spam).\n\n![global](https://nostr.build/p/nb5376.png)\n\n---\n\n## 🗺️ Explore\n\nThe mentioned 5 steps are a great start that will massively improve your experience, but there’s so much more to discover and enjoy! Nostr is not a Twitter replacement, its possibilities are only limited by imagination. \n\n![nostr-apps](https://nostr.build/p/nb5848.png)\n\nHave a look at the list of fun and useful Nostr projects:\n\n* [**https://nostrapps.com/**](https://www.nostrapps.com/) a list of Nostr apps\n* [**https://nostrplebs.com/**](https://nostrplebs.com/) – get your NIP-05 and other Nostr perks (paid)\n* [**https://nostrcheck.me/**](https://nostrcheck.me/) – Nostr address, media uploads, relay \n* [**https://nostr.build/**](https://nostr.build/) – upload and manage media (and more)\n* [**https://nostr.band/**](https://nostr.band/) – Nostr network and user info\n* [**https://zaplife.lol/**](https://zaplife.lol/) – zapping stats\n* [**https://nostrit.com/**](https://nostrit.com/) – schedule notes \n* [**https://nostrnests.com/**](https://nostrnests.com/) – Twitter Spaces 2.0  \n* [**https://nostryfied.online/**](https://nostryfied.online/) - back up your Nostr info\n* [**https://www.wavman.app/**](https://www.wavman.app/) - Nostr music player\n\n---\n\n## 📻 Relays\n\nAfter getting acquainted with Nostr make sure to check out my quick guide on Nostr relays: [https://lnshort.it/nostr-relays](https://lnshort.it/nostr-relays). It’s not the topic to worry about at the very beginning of your journey, but is definitely important to dive into later on. \n\n***\n\n## 📱 Nostr on mobile\n\nSmooth Nostr experience on mobile devices is feasible. This guide will help you seamlessly log in, post, zap, and more within Nostr web applications on your smartphone: [https://lnshort.it/nostr-mobile](https://lnshort.it/nostr-mobile)\n\n***\n\n*Thanks for reading and see you on the other side of the rabbit hole.*\n\nnostr:npub10awzknjg5r5lajnr53438ndcyjylgqsrnrtq5grs495v42qc6awsj45ys7\n\n***\n\n[^1]: there are [many more wallets that support lightning addresses](https://lightningaddress.com/) and you are free to chose the one you prefer\n[^2]: do not forget to return to the wallet and back up your account\n[^3]: one of such brilliant nostriches is nostr:npub1fl7pr0azlpgk469u034lsgn46dvwguz9g339p03dpetp9cs5pq5qxzeknp , who designed the logo used on this guide's cover image.)","created_at":1686750000,"id":"d97ce1c71282699576d12b879f9e2a2b9580c70c0b0c7ca6e8a98251524b4819","kind":30023,"pubkey":"7f5c2b4e48a0e9feca63a46b13cdb82489f4020398d60a2070a968caa818d75d","sig":"e78efb25a5378bb7a687017ff7fda7ce6df95616920fc99b03e2d1461d1196a4b6feba0d00cfa65f8ee51b0a6e62ac62f8bee2d7f02d27247f4d664da3059ebc","tags":[["d","1681492751274"],["title","Welcome to Nostr"],["summary","A few steps that will make your Nostr onboarding smoother"],["published_at","1681495414"],["t","welcome"],["t","newcomers"],["t","nostr"],["t","basics"],["t","lightning"],["image","https://nostr.build/p/nb5759.png"]]}]"###,
                ###"["EVENT","WHAT",{"content":"There’s a lot of conversation around the #TwitterFiles. Here’s my take, and thoughts on how to fix the issues identified.\n\nI’ll start with the principles I’ve come to believe…based on everything I’ve learned and experienced through my past actions as a Twitter co-founder and lead:\n\n1. Social media must be resilient to corporate and government control.\n2. Only the original author may remove content they produce.\n3. Moderation is best implemented by algorithmic choice.\n\nThe Twitter when I led it and the Twitter of today do not meet any of these principles. This is my fault alone, as I completely gave up pushing for them when an activist entered our stock in 2020. I no longer had hope of achieving any of it as a public company with no defense mechanisms (lack of dual-class shares being a key one). I planned my exit at that moment knowing I was no longer right for the company.\n\nThe biggest mistake I made was continuing to invest in building tools for us to manage the public conversation, versus building tools for the people using Twitter to easily manage it for themselves. This burdened the company with too much power, and opened us to significant outside pressure (such as advertising budgets). I generally think companies have become far too powerful, and that became completely clear to me with our suspension of Trump’s account. As I’ve said before, we did the right thing for the public company business at the time, but the wrong thing for the internet and society. Much more about this here: https://twitter.com/jack/status/1349510769268850690\n\nI continue to believe there was no ill intent or hidden agendas, and everyone acted according to the best information we had at the time. Of course mistakes were made. But if we had focused more on tools for the people using the service rather than tools for us, and moved much faster towards absolute transparency, we probably wouldn’t be in this situation of needing a fresh reset (which I am supportive of). Again, I own all of this and our actions, and all I can do is work to make it right.\n\nBack to the principles. Of course governments want to shape and control the public conversation, and will use every method at their disposal to do so, including the media. And the power a corporation wields to do the same is only growing. It’s critical that the people have tools to resist this, and that those tools are ultimately owned by the people. Allowing a government or a few corporations to own the public conversation is a path towards centralized control.\n\nI’m a strong believer that any content produced by someone for the internet should be permanent until the original author chooses to delete it. It should be always available and addressable. Content takedowns and suspensions should not be possible. Doing so complicates important context, learning, and enforcement of illegal activity. There are significant issues with this stance of course, but starting with this principle will allow for far better solutions than we have today. The internet is trending towards a world were storage is “free” and infinite, which places all the actual value on how to discover and see content.\n\nWhich brings me to the last principle: moderation. I don’t believe a centralized system can do content moderation globally. It can only be done through ranking and relevance algorithms, the more localized the better. But instead of a company or government building and controlling these solely, people should be able to build and choose from algorithms that best match their criteria, or not have to use any at all. A “follow” action should always deliver every bit of content from the corresponding account, and the algorithms should be able to comb through everything else through a relevance lens that an individual determines. There’s a default “G-rated” algorithm, and then there’s everything else one can imagine.\n\nThe only way I know of to truly live up to these 3 principles is a free and open protocol for social media, that is not owned by a single company or group of companies, and is resilient to corporate and government influence. The problem today is that we have companies who own both the protocol and discovery of content. Which ultimately puts one person in charge of what’s available and seen, or not. This is by definition a single point of failure, no matter how great the person, and over time will fracture the public conversation, and may lead to more control by governments and corporations around the world. \n\nI believe many companies can build a phenomenal business off an open protocol. For proof, look at both the web and email. The biggest problem with these models however is that the discovery mechanisms are far too proprietary and fixed instead of open or extendable. Companies can build many profitable services that complement rather than lock down how we access this massive collection of conversation. There is no need to own or host it themselves.\n\nMany of you won’t trust this solution just because it’s me stating it. I get it, but that’s exactly the point. Trusting any one individual with this comes with compromises, not to mention being way too heavy a burden for the individual. It has to be something akin to what bitcoin has shown to be possible. If you want proof of this, get out of the US and European bubble of the bitcoin price fluctuations and learn how real people are using it for censorship resistance in Africa and Central/South America.\n\nI do still wish for Twitter, and every company, to become uncomfortably transparent in all their actions, and I wish I forced more of that years ago. I do believe absolute transparency builds trust. As for the files, I wish they were released Wikileaks-style, with many more eyes and interpretations to consider. And along with that, commitments of transparency for present and future actions. I’m hopeful all of this will happen. There’s nothing to hide…only a lot to learn from. The current attacks on my former colleagues could be dangerous and doesn’t solve anything. If you want to blame, direct it at me and my actions, or lack thereof.\n\nAs far as the free and open social media protocol goes, there are many competing projects: @bluesky is one with the AT Protocol, nostr another, Mastodon yet another, Matrix yet another…and there will be many more. One will have a chance at becoming a standard like HTTP or SMTP. This isn’t about a “decentralized Twitter.” This is a focused and urgent push for a foundational core technology standard to make social media a native part of the internet. I believe this is critical both to Twitter’s future, and the public conversation’s ability to truly serve the people, which helps hold governments and corporations accountable. And hopefully makes it all a lot more fun and informative again.\n\n💸🛠️🌐\nTo accelerate open internet and protocol work, I’m going to open a new category of #startsmall grants: “open internet development.” It will start with a focus of giving cash and equity grants to engineering teams working on social media and private communication protocols, bitcoin, and a web-only mobile OS. I’ll make some grants next week, starting with $1mm/yr to Signal. Please let me know other great candidates for this money.","created_at":1681241813,"id":"d3f509e5eb6dd06f96d4797969408f5f9c90e9237f012f83130b1fa592b26433","kind":30023,"pubkey":"82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2","sig":"60010f2f4fa1ee9925df787a7914fe4e44fcf7c0b56767c078f9632d07e74da149f782491d0a6759f3f2dd128daad8b911b2ef6e50b658460aa8d1c258afd78b","tags":[["d","1681236782798"],["title","a native internet protocol for social media"],["summary",""],["published_at","1681237340"],["image","https://upload.wikimedia.org/wikipedia/commons/b/b4/The_Sun_by_the_Atmospheric_Imaging_Assembly_of_NASA%27s_Solar_Dynamics_Observatory_-_20100819.jpg"]]}]"###
            ])
            pe.loadPosts()
        }) {
            PreviewFeed {
                if let article = PreviewFetcher.fetchNRPost("21b3bd3c5eec98bba15aa0fd32f24f18a0540e70c18ed1ac4f156d41ffc17ce6") {
                    Box {
                        PostRowDeletable(nrPost: article)
                    }
                }
                if let nrPost = PreviewFetcher.fetchNRPost() {
                    Box {
                        PostRowDeletable(nrPost: nrPost)
                    }
                }
                if let article = PreviewFetcher.fetchNRPost("d3f509e5eb6dd06f96d4797969408f5f9c90e9237f012f83130b1fa592b26433") {
                    Box {
                        PostRowDeletable(nrPost: article)
                    }
                }
                Spacer()
            }
            .background(Themes.default.theme.listBackground)
        }
    }
}
