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
struct ContentRenderer: View { // VIEW things
    @Environment(\.theme) private var theme
    @Environment(\.nxViewingContext) private var nxViewingContext
    @EnvironmentObject private var dim: DIMENSIONS
    private let nrPost: NRPost
    private let isDetail: Bool
    private let fullWidth: Bool
    private let availableWidth: CGFloat
    private let forceAutoload: Bool
    private var zoomableId: String
    @StateObject private var childDIM: DIMENSIONS
    @Binding var showMore: Bool
    @State private var contentElements: [ContentElement]
    
    init(nrPost: NRPost, showMore: Binding<Bool>, isDetail: Bool = false, fullWidth: Bool = false, availableWidth: CGFloat, forceAutoload: Bool = false, zoomableId: String = "Default") {
        self.isDetail = isDetail
        self.nrPost = nrPost
        self.fullWidth = fullWidth
        self.availableWidth = availableWidth
        _contentElements = State(wrappedValue: isDetail ? nrPost.contentElementsDetail : nrPost.contentElements)
        _showMore = showMore
        self.forceAutoload = forceAutoload
        self.zoomableId = zoomableId
        _childDIM = StateObject(wrappedValue: DIMENSIONS.embeddedDim(availableWidth: availableWidth))
    }
    
    private var shouldAutoload: Bool {
        return !nrPost.isNSFW && (forceAutoload || SettingsStore.shouldAutodownload(nrPost) || nxViewingContext.contains(.screenshot))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(contentElements) { element in
                switch element {
                case .nrPost(let nrPost):
                    KindResolver(nrPost: nrPost, fullWidth: fullWidth, hideFooter: true, isDetail: false, isEmbedded: true)
                        .environmentObject(childDIM)
                        .padding(.vertical, 10)

                case .nevent1(let identifier):
                    NEventView(identifier: identifier, fullWidth: fullWidth, forceAutoload: shouldAutoload)
                        .environmentObject(childDIM)
//                        .debugDimensions("NEventView")
                        .padding(.vertical, 10)
//                        .withoutAnimation()
//                        .transaction { t in t.animation = nil }
                    
                case .naddr1(let identifier):
                    NaddrView(naddr1: identifier.bech32string, fullWidth: fullWidth)
//                        .frame(minHeight: 75)
                        .environmentObject(childDIM)
//                        .debugDimensions("NEventView")
                        .padding(.vertical, 10)
//                        .withoutAnimation()
//                        .transaction { t in t.animation = nil }
                    
                case .npub1(let npub):
                    if let pubkey = hex(npub) {
                        ProfileCardByPubkey(pubkey: pubkey)
                            .padding(.vertical, 10)
//                            .withoutAnimation()
//                            .transaction { t in t.animation = nil }
                    }
                    else {
                        EmptyView()
                    }
                    
                case .nprofile1(let identifier):
                    NProfileView(identifier: identifier)
                    
                case .note1(let noteId):
                    if let noteHex = hex(noteId) {
                        EmbedById(id: noteHex, fullWidth: fullWidth, forceAutoload: shouldAutoload)
//                            .frame(minHeight: 75)
                            .environmentObject(childDIM)
//                            .debugDimensions("QuoteById.note1")
                            .padding(.vertical, 10)
//                            .withoutAnimation()
//                            .transaction { t in t.animation = nil }
                            .onTapGesture {
                                guard !nxViewingContext.contains(.preview) else { return }
                                guard !isDetail else { return }
                                navigateTo(nrPost, context: childDIM.id)
                            }
                    }
                    else {
                        EmptyView()
                    }
                    
                case .noteHex(let hex):
                    EmbedById(id: hex, fullWidth: fullWidth, forceAutoload: shouldAutoload)
//                        .frame(minHeight: 75)
                        .environmentObject(childDIM)
//                        .debugDimensions("QuoteById.noteHex")
                        .padding(.vertical, 10)
//                        .withoutAnimation()
//                        .transaction { t in t.animation = nil }
                        .onTapGesture {
                            guard !nxViewingContext.contains(.preview) else { return }
                            guard !isDetail else { return }
                            navigateTo(nrPost, context: childDIM.id)
                        }
                    
                case .code(let code): // For text notes
                    Text(verbatim: code)
                        .font(.system(.body, design: .monospaced))
                        .onTapGesture {
                            guard !nxViewingContext.contains(.preview) else { return }
                            guard !isDetail else { return }
                            navigateTo(nrPost, context: childDIM.id)
                        }
                    
                case .text(let attributedStringWithPs): // For text notes
//                    Color.red
//                        .frame(height: 50)
//                        .debugDimensions("ContentRenderer.availableWidth \(availableWidth)", alignment: .topLeading)
//                    Text(verbatim: attributedStringWithPs.input)
//                        .font(.system(.body, design: .monospaced))
//                        .onTapGesture {
//                            guard !isDetail else { return }
//                            navigateTo(nrPost, context: childDIM.id)
//                        }
                    NRContentTextRenderer(attributedStringWithPs: attributedStringWithPs, showMore: $showMore, availableWidth: availableWidth, isDetail: isDetail, primaryColor: theme.primary, accentColor: theme.accent, onTap: {
                            guard !nxViewingContext.contains(.preview) else { return }
                            guard !isDetail else { return }
                            navigateTo(nrPost, context: childDIM.id)
                    })
                    .equatable()
                    
                case .md(let markdownContentWithPs): // For long form articles
                    NRContentMarkdownRenderer(markdownContentWithPs: markdownContentWithPs, maxWidth: availableWidth)
                        .onTapGesture {
                            guard !nxViewingContext.contains(.preview) else { return }
                            guard !isDetail else { return }
                            navigateTo(nrPost, context: childDIM.id)
                        }
                    
                case .lnbc(let text):
                    LightningInvoice(invoice: text)
                        .padding(.vertical, 10)
                    
                case .cashu(let text):
                    CashuTokenView(token: text)
                        .padding(.vertical, 10)
                    
                case .video(let mediaContent):
                    EmbeddedVideoView(
                        url: mediaContent.url,
                        pubkey: nrPost.pubkey,
                        nrPost: nrPost,
                        availableWidth: availableWidth + (fullWidth ? 20 : 0),
                        autoload: shouldAutoload
                    )
                    .padding(.horizontal, fullWidth ? -10 : 0)
                    .padding(.vertical, 10)
                    
                case .image(let galleryItem):
//                    Color.red
//                        .frame(height: 30)
//                        .debugDimensions("ContentRenderer.availableWidth \(availableWidth)", alignment: .topLeading)
                    MediaContentView(
                        galleryItem: galleryItem,
                        availableWidth: availableWidth + (fullWidth ? +20 : 0),
                        placeholderAspect: 4/3,
                        maxHeight: isDetail ? 4000 : DIMENSIONS.MAX_MEDIA_ROW_HEIGHT,
                        contentMode: .fit,
                        galleryItems: nrPost.galleryItems,
                        autoload: shouldAutoload,
                        isNSFW: nrPost.isNSFW,
                        generateIMeta: nxViewingContext.contains(.preview),
                        zoomableId: zoomableId
                    )
                    .padding(.horizontal, fullWidth ? -10 : 0)
                    .padding(.vertical, 10)
                    // Todo: scale: UIScreen.main.scale ?
                    // fullWidth || isDetail --->
                    // .padding(.horizontal, fullWidth ? -10 : 0)
                    // nrPost.pubkey autoload
                    //  contentPadding: nrPost.kind == 30023 ? 10 : 0
                    //  imageUrls: nrPost.imageUrls
                    // no full width no detial -> .frame(width: max(25, scaledDimensions.width), height: max(25,scaledDimensions.height))
                    
                case .linkPreview(let url):
                    LinkPreviewView(url: url, autoload: shouldAutoload)
                        .padding(.vertical, 10)
//                        .withoutAnimation()
//                        .transaction { t in t.animation = nil }
                    
                case .postPreviewImage(let postedImageMeta): // no full width for previews, its broken
                    if postedImageMeta.type == .gif {
                        GIFImage(data: postedImageMeta.data, isPlaying: .constant(true))
                            .scaledToFill()
                            .frame(width: availableWidth, height: availableWidth / postedImageMeta.aspect, alignment: .center)
                            .contentShape(Rectangle())
                            .padding(.vertical, 10)
                    }
                    else if let imageData = postedImageMeta.uiImage {
                        Image(uiImage: imageData)
                            .resizable()
                            .scaledToFill()
                            .frame(width: availableWidth, height: availableWidth / postedImageMeta.aspect, alignment: .center)
                            .padding(.vertical, 10)
                    }
                    else {
                        Color.secondary
                            .frame(width: availableWidth)
                            .padding(.vertical, 10)
                    }
                    
                case .postPreviewVideo(let postedVideoMeta):
                    if let thumbnail = postedVideoMeta.thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 600)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .center)
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
                        .onTapGesture {
                            guard !nxViewingContext.contains(.preview) else { return }
                            guard !isDetail else { return }
                            navigateTo(nrPost, context: childDIM.id)
                        }
                }
            }
        }
        .onChange(of: showMore) { [oldValue = self.showMore] newValue in
            if newValue && !oldValue {
                withAnimation {
                    self.contentElements = self.nrPost.contentElementsDetail
                }
            }
        }
        .onAppear {
            childDIM.id = dim.id
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
                    ContentRenderer(nrPost: nrPost, showMore: .constant(true), availableWidth: UIScreen.main.bounds.width)
                }
            }
        }
    }
}

#Preview("Content Renderer 2") {
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
                    ContentRenderer(nrPost: nrPost, showMore: .constant(true), availableWidth: UIScreen.main.bounds.width)
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
                    ContentRenderer(nrPost: nrPost, showMore: .constant(true), availableWidth: UIScreen.main.bounds.width)
                }
            }
        }
    }
}


func scaledToFit(_ dimensions: CGSize, scale screenScale: Double, maxWidth: Double, maxHeight: Double) -> CGSize {
    let pointWidth = Double(dimensions.width / screenScale)
    let pointHeight = Double(dimensions.height / screenScale)
    
    let widthRatio = min(maxWidth / pointWidth,1)
    let heightRatio = min(maxHeight / pointHeight,1)
    let fittingScale = min(widthRatio, heightRatio)
    
    return CGSize(width: pointWidth * fittingScale, height: pointHeight * fittingScale)
}
