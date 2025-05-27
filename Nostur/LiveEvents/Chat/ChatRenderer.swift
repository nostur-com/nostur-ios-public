//
//  ChatRenderer.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/07/2024.
//

import SwiftUI

struct ChatRenderer: View { // VIEW things
    private var theme: Theme
    private let nrChat: NRChatMessage
    
    private let availableWidth: CGFloat
    private let contentElements: [ContentElement]
    private let forceAutoload: Bool

    private var zoomableId: String
    @StateObject private var childDIM: DIMENSIONS
    
    init(nrChat: NRChatMessage, availableWidth: CGFloat, forceAutoload: Bool = false, theme: Theme, zoomableId: String = "Default") {
        self.nrChat = nrChat
        self.availableWidth = availableWidth
        self.contentElements = nrChat.contentElementsDetail
        self.forceAutoload = forceAutoload
        self.theme = theme
        self.zoomableId = zoomableId
        _childDIM = StateObject(wrappedValue: DIMENSIONS.embeddedDim(availableWidth: availableWidth, isScreenshot: false))
    }
    
    private var shouldAutoload: Bool {
        return !nrChat.isNSFW  && (forceAutoload || SettingsStore.shouldAutodownload(nrChat))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(contentElements.indices, id:\.self) { index in
                switch contentElements[index] {
                case .nrPost(let nrPost):
                    KindResolver(nrPost: nrPost, fullWidth: true, hideFooter: true, isDetail: false, isEmbedded: true, forceAutoload: shouldAutoload, theme: theme)
                        .frame(maxWidth: max(600, availableWidth))
//                        .frame(minHeight: 75)
                        .environmentObject(childDIM)
                    //                        .fixedSize(horizontal: false, vertical: true)
//                        .debugDimensions("EmbeddedPost")
                        .padding(.vertical, 10)
                        .id(index)
//                        .withoutAnimation()
//                        .transaction { t in t.animation = nil }
                case .nevent1(let identifier):
                    NEventView(identifier: identifier, forceAutoload: shouldAutoload, theme: theme)
                        .frame(maxWidth: max(600, availableWidth))
//                        .frame(minHeight: 75)
                        .environmentObject(childDIM)
//                        .debugDimensions("NEventView")
                        .padding(.vertical, 10)
                        .id(index)
//                        .withoutAnimation()
//                        .transaction { t in t.animation = nil }
                case .npub1(let npub):
                    if let pubkey = hex(npub) {
                        ProfileCardByPubkey(pubkey: pubkey, theme: theme)
                            .frame(maxWidth: max(600, availableWidth))
                            .padding(.vertical, 10)
                            .id(index)
//                            .withoutAnimation()
//                            .transaction { t in t.animation = nil }
                    }
                    else {
                        EmptyView()
                            .id(index)
                    }
                case .nprofile1(let identifier):
                    NProfileView(identifier: identifier)
                        .frame(maxWidth: max(600, availableWidth))
                        .id(index)
//                        .transaction { t in t.animation = nil }
                case .note1(let noteId):
                    if let noteHex = hex(noteId) {
                        EmbedById(id: noteHex, forceAutoload: shouldAutoload, theme: theme)
                            .frame(maxWidth: max(600, availableWidth))
//                            .frame(minHeight: 75)
                            .environmentObject(childDIM)
//                            .debugDimensions("QuoteById.note1")
                            .padding(.vertical, 10)
//                            .withoutAnimation()
//                            .transaction { t in t.animation = nil }
                            .onTapGesture {
                                navigateTo(NotePath(id: noteHex), context: "Default")
                            }
                            .id(index)
                    }
                    else {
                        EmptyView()
                            .id(index)
                    }
                case .noteHex(let hex):
                    EmbedById(id: hex, forceAutoload: shouldAutoload, theme: theme)
                        .frame(maxWidth: max(600, availableWidth))
//                        .frame(minHeight: 75)
                        .environmentObject(childDIM)
//                        .debugDimensions("QuoteById.noteHex")
                        .padding(.vertical, 10)
//                        .withoutAnimation()
//                        .transaction { t in t.animation = nil }
                        .onTapGesture {
                            navigateTo(NotePath(id: hex), context: "Default")
                        }
                        .id(index)
                case .code(let code): // For text notes
                    Text(verbatim: code)
                        .font(.system(.body, design: .monospaced))
                        .id(index)
                case .text(let attributedStringWithPs): // For text notes
//                    Color.red
//                        .frame(height: 50)
//                        .debugDimensions("ContentRenderer.availableWidth \(availableWidth)", alignment: .center)
                    NRContentTextRenderer(attributedStringWithPs: attributedStringWithPs, availableWidth: availableWidth, isDetail: true, primaryColor: theme.primary, accentColor: theme.accent)
                        .equatable()
                        .id(index)
                case .md(let markdownContentWithPs): // For long form articles
                    NRContentMarkdownRenderer(markdownContentWithPs: markdownContentWithPs, theme: theme, maxWidth: availableWidth)
                        .id(index)
                case .lnbc(let text):
                    LightningInvoice(invoice: text, theme: theme)
                        .frame(maxWidth: max(600, availableWidth))
                        .padding(.vertical, 10)
                        .id(index)
                case .cashu(let text):
                    CashuTokenView(token: text, theme: theme)
                        .frame(maxWidth: max(600, availableWidth))
                        .padding(.vertical, 10)
                        .id(index)
                case .video(let mediaContent):
                    EmbeddedVideoView(url: mediaContent.url, pubkey: nrChat.pubkey, availableWidth: availableWidth, autoload: shouldAutoload, theme: theme)
                case .image(let galleryItem):
                    MediaContentView(
                        galleryItem: galleryItem,
                        availableWidth: availableWidth,
                        placeholderAspect: 4/3,
                        maxHeight: 450.0,
                        contentMode: .fit,
                        autoload: shouldAutoload,
                        isNSFW: nrChat.isNSFW,
                        zoomableId: zoomableId
                    )
                    .padding(.vertical, 10)
                case .linkPreview(let url):
                    LinkPreviewView(url: url, autoload: shouldAutoload, theme: theme)
                        .frame(maxWidth: max(600, availableWidth))
                        .padding(.vertical, 10)
                        .id(index)
//                        .withoutAnimation()
//                        .transaction { t in t.animation = nil }
                    
                case .postPreviewImage(let postedImageMeta):
                    if let uiImage = postedImageMeta.uiImage {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 600)
                            .padding(.top, 10)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .id(index)
                    }
                    else {
                        Color.secondary
                            .frame(maxWidth: 600)
                            .padding(.top, 10)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .id(index)
                    }
                case .postPreviewVideo(let postedVideoMeta):
                    if let thumbnail = postedVideoMeta.thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 600)
                            .padding(.top, 10)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .id(index)
                            .overlay(alignment: .center) {
                                Image(systemName:"play.circle")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 80, height: 80)
//                                        .centered()
                                    .contentShape(Rectangle())
                            }
                    }
                    else {
                        EmptyView()
                    }
                default:
                    EmptyView()
                        .id(index)
                }
            }
        }
        .transaction { t in
            t.animation = nil
        }
    }
}


#Preview("zap?") {
    PreviewContainer({ pe in
        pe.parseMessages([
            ###"["EVENT","uno",{"kind":0,"id":"f2d31919d4fdde4aa78ee53b6241b97ce3821083e5501d2b948cfdc37fea4775","pubkey":"a80fc4a78634ee26aabcac951b4cfd7b56ae18babd33c5afdcf6bed6dc80ebd1","created_at":1721274103,"tags":[["alt","User profile for The Uno"]],"content":"{\"name\":\"The Uno\",\"nip05\":\"Uno@UnoDog.Site\",\"about\":\"That Bitcoin Dog From the Internet. \\n\\nDrinking Coffee, Building Websites, Videos, Memes, Yapping. \\n🤙🐕🫡👍\",\"lud16\":\"uno@primal.net\",\"display_name\":\"The Uno\",\"picture\":\"https://image.nostr.build/38e9e5f658ac184be7462bf76f4e915b0446a538987c03b77c0ddf0c376aa4c3.jpg\",\"banner\":\"https://image.nostr.build/68d5c31278731a64a8eea159e2633eb01a40872bf906a64369f48c94c1e7cbbb.gif\",\"website\":\"izap.lol/uno\"}","sig":"b3c043fce704ff85b7c58415622f9910f463da2478b46c20ce3fb73586c7347d32810244ebd970e272ecbdcd02923eff28792094e2c6bf2ffa32764c2096c3ae"}]"###
        ])
    }) {
        let text = ###"["EVENT","-DB-CHAT-",{"kind":9735,"id":"fe39f2a9e40c74c646c488c2fde28fd3c7b98259d8f78374180d760a9c394521","pubkey":"79f00d3f5a19ec806189fcab03c1be4ff81d18ee4f653c88fac41fe03570f432","created_at":1721668394,"tags":[["p","e2ccf7cf20403f3f2a4a55b328f0de3be38558a7d5f33632fdaaefc726c1c8eb"],["a","30311:cf45a6ba1363ad7ed213a078e710d24115ae721c9b47bd1ebf4458eaefb4c2a5:82d27633-1dd1-4b38-8f9d-f6ab9b31fc83"],["P","a80fc4a78634ee26aabcac951b4cfd7b56ae18babd33c5afdcf6bed6dc80ebd1"],["bolt11","lnbc210n1pnfayegpp5yrvtf665x38c8rt7f5layl2u3rtg55dp7x335reysy0wf2d9r9yqhp5cf3g9q6paxapge24m4sp6a79xtelnugu67867nkj6ea0ran0smnqcqzzsxqyz5vqsp5u0u6n9skdzjc2q2733903lr4vamsjh0slkqh0q7p4yvc7zz3mjfq9qxpqysgq3gu88vndglqh7sqgq2qjhc976ekm9rarpvl7u5z6ndky8srzar7k6jpm8stndsux4qq0t8cvpgfhkcf967ppxlymj4dv8lapdv842qsp0wu6x2"],["preimage","8d31a3b794f60336ae5633857a23f40f22b02a196dad41183df30976ec279269"],["description","{\"id\":\"8b915daffe7d42de39264f34678ee5477856ec8f782d399f91a05d8b47ab8e69\",\"pubkey\":\"a80fc4a78634ee26aabcac951b4cfd7b56ae18babd33c5afdcf6bed6dc80ebd1\",\"content\":\"Michael Jackson\",\"kind\":9734,\"created_at\":1721668389,\"tags\":[[\"a\",\"30311:cf45a6ba1363ad7ed213a078e710d24115ae721c9b47bd1ebf4458eaefb4c2a5:82d27633-1dd1-4b38-8f9d-f6ab9b31fc83\"],[\"amount\",\"21000\"],[\"p\",\"e2ccf7cf20403f3f2a4a55b328f0de3be38558a7d5f33632fdaaefc726c1c8eb\"],[\"relays\",\"wss://relay.snort.social\",\"wss://nos.lol\",\"wss://relay.damus.io\",\"wss://nostr.wine\"]],\"sig\":\"685fe75defe72e7f9b5e024eeed70a0c4e28aa3a1a4e456a445dbc32811102dafc229a2da4c6a90e91ca83071877e4fac39d7809f7dbbb958764b6373fe5cc06\"}"]],"content":"Michael Jackson","sig":"05d8330c69b646d0b40f5e603dc0565a6dfea13355fb154193f0e0a7b36b9435e08734703578b9b8530c77ac7a25dd47955953b8804d52ffd2a0149c633c4fae"}]"###
        if let message = try? RelayMessage.parseRelayMessage(text: text, relay: "wss://memory"),
           let nEvent = message.event {
            let nrChat: NRChatMessage = NRChatMessage(nEvent: nEvent)
            ChatRow(content: .chatMessage(nrChat), theme: Themes.default.theme)
        }
    }
}

