//
//  ContentRenderer.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/03/2023.
//

import SwiftUI
import Nuke
import NukeUI
import Combine

// Renders embeds (VIEWS), not links (in TEXT)
struct DMContentRenderer: View { // VIEW things
    @Environment(\.openURL) private var openURL
    private let pubkey: String // author of balloon (message)
    private var theme: Theme
    private let availableWidth: CGFloat
    private let contentElements: [ContentElement]
    @State private var didStart = false
    @StateObject private var childDIM: DIMENSIONS
    private let isSentByCurrentUser: Bool
    
    init(pubkey: String, contentElements: [ContentElement] = [], availableWidth: CGFloat, theme: Theme, isSentByCurrentUser: Bool = false) {
        self.pubkey = pubkey
        self.availableWidth = availableWidth
        self.contentElements = contentElements
        self.theme = theme
        self.isSentByCurrentUser = isSentByCurrentUser
        _childDIM = StateObject(wrappedValue: DIMENSIONS.embeddedDim(availableWidth: availableWidth - 98, isScreenshot: false))
    }
    
    var body: some View {
        VStack(alignment:.leading, spacing: 0) {
            ForEach(contentElements) { contentElement in
                switch contentElement {
                case .nrPost(let nrPost):
                    KindResolver(nrPost: nrPost, fullWidth: false, hideFooter: true, isDetail: false, isEmbedded: true, forceAutoload: false, theme: theme)
                        .environmentObject(childDIM)
                        .padding(.vertical, 10)
                        .fixedSize(horizontal: false, vertical: true) // Needed or we get whitespace, equal height posts
                
                case .nevent1(let identifier):
                    NEventView(identifier: identifier, forceAutoload: false, theme: theme)
                        .environmentObject(childDIM)
                        .padding(.vertical, 10)
                        .fixedSize(horizontal: false, vertical: true) // Needed or we get whitespace, equal height posts
                
                case .npub1(let npub):
                    if let pubkey = hex(npub) {
                        ProfileCardByPubkey(pubkey: pubkey, theme: theme)
                            .padding(.vertical, 10)
                            .fixedSize(horizontal: false, vertical: true) // Needed or we get whitespace, equal height posts
                    }
                
                case .nprofile1(let identifier):
                    NProfileView(identifier: identifier)
                        .fixedSize(horizontal: false, vertical: true) // Needed or we get whitespace, equal height posts
                
                case .note1(let noteId):
                    if let noteHex = hex(noteId) {
                        EmbedById(id: noteHex, forceAutoload: true, theme: theme)
                            .environmentObject(childDIM)
                            .padding(.vertical, 10)
                            .fixedSize(horizontal: false, vertical: true) // Needed or we get whitespace, equal height posts
                            .onTapGesture {
                                self.openURL(URL(string: "nostur:e:\(noteHex)")!)
                            }
                    }
                    else {
                        EmptyView()
                    }
                case .noteHex(let hex):
                    EmbedById(id: hex, forceAutoload: true, theme: theme)
                        .environmentObject(childDIM)
                        .padding(.vertical, 10)
                        .fixedSize(horizontal: false, vertical: true) // Needed or we get whitespace, equal height posts
                        .onTapGesture {
                            self.openURL(URL(string: "nostur:e:\(hex)")!)
                        }
                    
                case .code(let code): // For text notes
                    Text(verbatim: code)
                        .font(.system(.body, design: .monospaced))
                        .fixedSize(horizontal: false, vertical: true) // Needed or we get whitespace, equal height posts
                    
                case .text(let attributedStringWithPs): // For text notes
                    NRContentTextRenderer(attributedStringWithPs: attributedStringWithPs, availableWidth: availableWidth - 130, isScreenshot: false, isDetail: true, primaryColor: isSentByCurrentUser ? .white : theme.primary, accentColor: isSentByCurrentUser ? .mint : theme.accent)
                        .equatable()
                        .environmentObject(childDIM)
                        .fixedSize(horizontal: false, vertical: true) // Needed or we get whitespace, equal height posts
                    
                case .md(let markdownContentWithPs): // For long form articles
                    NRContentMarkdownRenderer(markdownContentWithPs: markdownContentWithPs, theme: theme, maxWidth: availableWidth)
                        .fixedSize(horizontal: false, vertical: true) // Needed or we get whitespace, equal height posts
                    
                case .lnbc(let text):
                    LightningInvoice(invoice: text, theme: theme)
                        .padding(.vertical, 10)
                        .fixedSize(horizontal: false, vertical: true) // Needed or we get whitespace, equal height posts
                    
                case .cashu(let text):
                    CashuTokenView(token: text, theme: theme)
                        .padding(.vertical, 10)
                        .fixedSize(horizontal: false, vertical: true) // Needed or we get whitespace, equal height posts
                    
                case .video(let mediaContent):
                    EmbeddedVideoView(url: mediaContent.url, pubkey: pubkey, availableWidth: availableWidth, autoload: false, theme: theme, didStart: $didStart)
                    
                case .image(let mediaContent):
                    if let dimensions = mediaContent.dimensions {
                        let scaledDimensions = Nostur.scaledToFit(dimensions, scale: UIScreen.main.scale, maxWidth: availableWidth, maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)

                        SingleMediaViewer(url: mediaContent.url, pubkey: pubkey, height:scaledDimensions.height, imageWidth: availableWidth, fullWidth: false, autoload: false, contentPadding: 0, theme: theme)
                            .frame(width: max(25,scaledDimensions.width), height: max(25,scaledDimensions.height))
                            .background {
                                if SettingsStore.shared.lowDataMode {
                                    theme.lineColor.opacity(0.2)
                                }
                            }
                            .padding(.horizontal, 0)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: SettingsStore.shared.lowDataMode ? .leading : .center)
                            .fixedSize(horizontal: false, vertical: true) // Needed or we get whitespace, equal height posts
                    }
                    else {
                        SingleMediaViewer(url: mediaContent.url, pubkey: pubkey, height:DIMENSIONS.MAX_MEDIA_ROW_HEIGHT, imageWidth: availableWidth, fullWidth: false, autoload: false, contentPadding: 0, theme: theme)
                            .padding(.horizontal, 0)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: SettingsStore.shared.lowDataMode ? .leading : .center)
                            .fixedSize(horizontal: false, vertical: true) // Needed or we get whitespace, equal height posts
                    }
                case .linkPreview(let url):
                    LinkPreviewView(url: url, autoload: false, theme: theme, linkColor: isSentByCurrentUser ? .mint : theme.accent)
                        .padding(.vertical, 10)
                        .fixedSize(horizontal: false, vertical: true) // Needed or we get whitespace, equal height posts
                default:
                    EmptyView()
                }
            }
        }
    }
}

#Preview("Content Renderer 1") {
    let _ = ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
    return PreviewContainer({ pe in
//        pe.loadContacts()
//        pe.loadPosts()
        pe.loadMedia()
        pe.parseMessages([
            ###"["EVENT","1",{"pubkey":"9989500413fb756d8437912cc32be0730dbe1bfc6b5d2eef759e1456c239f905","content":"Watch out for the Jazz attack, be glad your not a squirrel 🐿️ https://nostr.build/av/40cc2c4a2d33e3e082766765ec4f7cea1de8b442cae5b01cf779829762947a63.mov ","id":"473f85cb559d5d8866e7c3ffef536c67323ef44fe2d08d4bef42d82d9f868879","created_at":1692538971,"sig":"0b6d7640814bd5f4b39c4d4cd72ceebaf380775e0682f4667fa7e97a925223bb2f495ba59304485518f55761d29f8abeea8727595ad2fa5f9ad5c5b26ec962eb","kind":1,"tags":[["e","0ffa41f84eb1e66b3b10b8b3f91f55fcca67d46995236568ac22bba2433b397d"],["e","013b859a0dba4ae29a35a19a4cd5ae27b30311537325c9d9e83ef996e2e36968"],["p","0155373ac79b7ffb0f586c3e68396f9e82d46f7afe7016d46ed9ca46ba3e1bed"],["p","e844b39d850acbb13bba1a20057250fe6b3deff5f1ecc95b6a99dc35adafb6a2"],["imeta","url https://nostr.build/av/40cc2c4a2d33e3e082766765ec4f7cea1de8b442cae5b01cf779829762947a63.mov","blurhash eVE:nYtOaxoeof4fWFbGj[j[Nra#ofkBWBXft5j[a#axaQbHj?a#of","dim 720x1280"]]}]"###])
    }) {
        PreviewFeed {
            if let nrPost = PreviewFetcher.fetchNRPost("473f85cb559d5d8866e7c3ffef536c67323ef44fe2d08d4bef42d82d9f868879") {
                Box {
                    ContentRenderer(nrPost: nrPost, availableWidth: UIScreen.main.bounds.width, theme: Themes.default.theme)
                }
            }
        }
    }
}

#Preview("Content Renderer  2") {
    let _ = ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
    return PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadMedia()
        pe.parseMessages([
            ###"["EVENT","1",{"pubkey":"9989500413fb756d8437912cc32be0730dbe1bfc6b5d2eef759e1456c239f905","content":"Watch out for the Jazz attack, be glad your not a squirrel 🐿️ https://nostr.build/av/40cc2c4a2d33e3e082766765ec4f7cea1de8b442cae5b01cf779829762947a63.mov ","id":"473f85cb559d5d8866e7c3ffef536c67323ef44fe2d08d4bef42d82d9f868879","created_at":1692538971,"sig":"0b6d7640814bd5f4b39c4d4cd72ceebaf380775e0682f4667fa7e97a925223bb2f495ba59304485518f55761d29f8abeea8727595ad2fa5f9ad5c5b26ec962eb","kind":1,"tags":[["e","0ffa41f84eb1e66b3b10b8b3f91f55fcca67d46995236568ac22bba2433b397d"],["e","013b859a0dba4ae29a35a19a4cd5ae27b30311537325c9d9e83ef996e2e36968"],["p","0155373ac79b7ffb0f586c3e68396f9e82d46f7afe7016d46ed9ca46ba3e1bed"],["p","e844b39d850acbb13bba1a20057250fe6b3deff5f1ecc95b6a99dc35adafb6a2"],["imeta","url https://nostr.build/av/40cc2c4a2d33e3e082766765ec4f7cea1de8b442cae5b01cf779829762947a63.mov","blurhash eVE:nYtOaxoeof4fWFbGj[j[Nra#ofkBWBXft5j[a#axaQbHj?a#of","dim 720x1280"]]}]"###])
    }) {
        PreviewFeed {
            if let nrPost = PreviewFetcher.fetchNRPost("9b34fd9a53398fb51493d68ecfd0d64ff922d0cdf5ffd8f0ffab46c9a3cf54e3") {
                Box {
                    ContentRenderer(nrPost: nrPost, availableWidth: UIScreen.main.bounds.width, theme: Themes.default.theme)
                }
            }
        }
    }
}

#Preview("Content Renderer 3") {
    let _ = ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
    return PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadMedia()
        pe.parseMessages([
            ###"["EVENT","1",{"pubkey":"9989500413fb756d8437912cc32be0730dbe1bfc6b5d2eef759e1456c239f905","content":"Watch out for the Jazz attack, be glad your not a squirrel 🐿️ https://nostr.build/av/40cc2c4a2d33e3e082766765ec4f7cea1de8b442cae5b01cf779829762947a63.mov ","id":"473f85cb559d5d8866e7c3ffef536c67323ef44fe2d08d4bef42d82d9f868879","created_at":1692538971,"sig":"0b6d7640814bd5f4b39c4d4cd72ceebaf380775e0682f4667fa7e97a925223bb2f495ba59304485518f55761d29f8abeea8727595ad2fa5f9ad5c5b26ec962eb","kind":1,"tags":[["e","0ffa41f84eb1e66b3b10b8b3f91f55fcca67d46995236568ac22bba2433b397d"],["e","013b859a0dba4ae29a35a19a4cd5ae27b30311537325c9d9e83ef996e2e36968"],["p","0155373ac79b7ffb0f586c3e68396f9e82d46f7afe7016d46ed9ca46ba3e1bed"],["p","e844b39d850acbb13bba1a20057250fe6b3deff5f1ecc95b6a99dc35adafb6a2"],["imeta","url https://nostr.build/av/40cc2c4a2d33e3e082766765ec4f7cea1de8b442cae5b01cf779829762947a63.mov","blurhash eVE:nYtOaxoeof4fWFbGj[j[Nra#ofkBWBXft5j[a#axaQbHj?a#of","dim 720x1280"]]}]"###])
    }) {
        PreviewFeed {
            if let nrPost = PreviewFetcher.fetchNRPost("102177a51af895883e9256b70b2caff6b9ef90230359ee20f6dc7851ec9e5d5a") {
                Box {
                    ContentRenderer(nrPost: nrPost, availableWidth: UIScreen.main.bounds.width, theme: Themes.default.theme)
                }
            }
        }
    }
}
