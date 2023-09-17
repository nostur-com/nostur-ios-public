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
    let nrPost:NRPost
    let isDetail:Bool
    let fullWidth:Bool
    let availableWidth:CGFloat
    let contentElements:[ContentElement]
    
    init(nrPost: NRPost, isDetail:Bool = false, fullWidth:Bool = false, availableWidth:CGFloat) {
        self.isDetail = isDetail
        self.nrPost = nrPost
        self.fullWidth = fullWidth
        self.availableWidth = availableWidth
        self.contentElements = isDetail ? nrPost.contentElementsDetail : nrPost.contentElements
    }
    
    var body: some View {
        VStack(alignment:.leading, spacing: 0) {
            ForEach(contentElements) { contentElement in
                switch contentElement {
                case .nrPost(let nrPost):
                        EmbeddedPost(nrPost)
                        .frame(minHeight: 75)
                        .transaction { t in t.animation = nil }
                        .environmentObject(DIMENSIONS.embeddedDim(availableWidth: availableWidth))
//                        .fixedSize(horizontal: false, vertical: true)
//                        .debugDimensions("EmbeddedPost")
                        .padding(.vertical, 10)
                case .nevent1(let identifier):
                        NEventView(identifier: identifier)
                        .frame(minHeight: 75)
                        .transaction { t in t.animation = nil }
                        .environmentObject(DIMENSIONS.embeddedDim(availableWidth: availableWidth))
//                        .debugDimensions("NEventView")
                        .padding(.vertical, 10)
                case .npub1(let npub):
                    if let pubkey = hex(npub) {
                        ProfileCardByPubkey(pubkey: pubkey)
                            .transaction { t in t.animation = nil }
                            .padding(.vertical, 10)
                    }
                case .nprofile1(let identifier):
                    NProfileView(identifier: identifier)
                        .transaction { t in t.animation = nil }
                case .note1(let noteId):
                    if let noteHex = hex(noteId) {
                        QuoteById(id: noteHex)
                            .frame(minHeight: 75)
                            .transaction { t in t.animation = nil }
                            .environmentObject(DIMENSIONS.embeddedDim(availableWidth: availableWidth))
                            .padding(.vertical, 10)
                            .onTapGesture {
                                guard !isDetail else { return }
                                navigateTo(nrPost)
                            }
                    }
                    else {
                        EmptyView()
                    }
                case .noteHex(let hex):
                    QuoteById(id: hex)
                        .frame(minHeight: 75)
                        .transaction { t in t.animation = nil }
                        .environmentObject(DIMENSIONS.embeddedDim(availableWidth: availableWidth))
                        .padding(.vertical, 10)
                        .onTapGesture {
                            guard !isDetail else { return }
                            navigateTo(nrPost)
                        }
                case .code(let code): // For text notes
                    Text(verbatim: code)
                        .font(.system(.body, design: .monospaced))
                        .onTapGesture {
                            guard !isDetail else { return }
                            navigateTo(nrPost)
                        }
                case .text(let attributedStringWithPs): // For text notes
                    NRContentTextRenderer(attributedStringWithPs: attributedStringWithPs, isDetail:isDetail)
                        .onTapGesture {
                            guard !isDetail else { return }
                            navigateTo(nrPost)
                        }
                case .md(let markdownContentWithPs): // For long form articles
                    NRContentMarkdownRenderer(markdownContentWithPs: markdownContentWithPs)
                        .onTapGesture {
                            guard !isDetail else { return }
                            navigateTo(nrPost)
                        }
                case .lnbc(let text):
                    LightningInvoice(invoice: text, nrPost:nrPost)
                        .padding(.vertical, 10)
                case .video(let mediaContent):
                    if let dimensions = mediaContent.dimensions {
                        // for video, dimensions are points not pixels? Scale set to 1.0 always
                        let scaledDimensions = Nostur.scaledToFit(dimensions, scale: 1.0, maxWidth: availableWidth, maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
                        
                        #if DEBUG
//                        Text(".video.availableWidth (SD): \(Int(availableWidth))\ndim:\(dimensions.debugDescription)\nSD: \(scaledDimensions.debugDescription)")
//                            .frame(maxWidth: .infinity)
//                            .background(.red)
//                            .foregroundColor(.white)
//                            .debugDimensions()
                        #endif
                        
                        NosturVideoViewur(url: mediaContent.url, pubkey: nrPost.pubkey, height:scaledDimensions.height, videoWidth: availableWidth, isFollowing:nrPost.following, contentPadding: nrPost.kind == 30023 ? 10 : 0)
//                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: scaledDimensions.width, height: scaledDimensions.height)
                            .padding(.horizontal, fullWidth ? -10 : 0)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    else {

                        #if DEBUG
//                        Text(".video.availableWidth: \(Int(availableWidth))")
//                            .frame(maxWidth: .infinity)
//                            .background(.red)
//                            .foregroundColor(.white)
//                            .debugDimensions()
                        #endif
                        
                        NosturVideoViewur(url: mediaContent.url, pubkey: nrPost.pubkey, videoWidth: availableWidth, isFollowing:nrPost.following, contentPadding: nrPost.kind == 30023 ? 10 : 0)
//                            .frame(maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
                            .padding(.horizontal, fullWidth ? -10 : 0)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    
                case .image(let mediaContent):
                    if let dimensions = mediaContent.dimensions {
                        let scaledDimensions = Nostur.scaledToFit(dimensions, scale: UIScreen.main.scale, maxWidth: availableWidth, maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)

                        #if DEBUG
//                        Text(".image.availableWidth (SD): \(Int(availableWidth))\ndim:\(dimensions.debugDescription)\nSD: \(scaledDimensions.debugDescription)")
//                            .frame(maxWidth: .infinity)
//                            .background(.red)
//                            .foregroundColor(.white)
//                            .debugDimensions()
                        #endif
                        
                        SingleMediaViewer(url: mediaContent.url, pubkey: nrPost.pubkey, height:scaledDimensions.height, imageWidth: availableWidth, fullWidth: fullWidth, autoload: (nrPost.following || !SettingsStore.shared.restrictAutoDownload), contentPadding: nrPost.kind == 30023 ? 10 : 0)
//                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: scaledDimensions.width, height: scaledDimensions.height)
                            .clipped()
                            .padding(.horizontal, fullWidth ? -10 : 0)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    else {

                        #if DEBUG
//                        Text(".image.availableWidth: \(Int(availableWidth))")
//                            .frame(maxWidth: .infinity)
//                            .background(.red)
//                            .foregroundColor(.white)
//                            .debugDimensions()
                        #endif
                        
                        SingleMediaViewer(url: mediaContent.url, pubkey: nrPost.pubkey, height:DIMENSIONS.MAX_MEDIA_ROW_HEIGHT, imageWidth: availableWidth, fullWidth: fullWidth, autoload: (nrPost.following || !SettingsStore.shared.restrictAutoDownload), contentPadding: nrPost.kind == 30023 ? 10 : 0)
                            .padding(.horizontal, fullWidth ? -10 : 0)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                case .linkPreview(let url):
                    // TODO: do no link preview if restrictAutoDownload...
                    LinkPreviewView(url: url)
                        .padding(.vertical, 10)
                case .postPreviewImage(let uiImage):
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 600)
                        .padding(.top, 10)
                        .frame(maxWidth: .infinity, alignment: .center)
                default:
                    EmptyView()
                        .onTapGesture {
                            guard !isDetail else { return }
                            navigateTo(nrPost)
                        }
                }
            }
        }
        .transaction { t in
            t.animation = nil
        }
    }
}

struct QuoteById: View {
    let id:String
    
    @FetchRequest
    var events:FetchedResults<Event>
    
    @State var nrPost:NRPost?
    
    init(id:String) {
        self.id = id
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "id == %@", id)
        fr.fetchLimit = 1
        _events = FetchRequest(fetchRequest: fr)
    }
    
    var body: some View {
        VStack {
            if let event = events.first {
                if let nrPost = nrPost {
                    if nrPost.kind == 30023 {
                        ArticleView(nrPost, hideFooter: true)
                            .padding(20)
                            .background(
                                Color(.secondarySystemBackground)
                                    .cornerRadius(15)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 15)
                                    .stroke(.regularMaterial, lineWidth: 1)
                            )
//                            .debugDimensions("QuoteById.ArticleView")
                    }
                    else {
                        QuotedNoteFragmentView(nrPost: nrPost)
//                            .debugDimensions("QuoteById.QuotedNoteFragmentView")
                    }
                }
                else {
                    Color.clear
                        .frame(height: 150)
                        .task {
                            DataProvider.shared().bg.perform {
                                if let eventBG = event.toBG() {
                                    let nrPost = NRPost(event: eventBG)
                                    
                                    DispatchQueue.main.async {
                                        self.nrPost = nrPost
                                    }
                                }
                            }
                        }
                }
            }
            else {
                ProgressView()
                    .hCentered()
                    .frame(height: 150)
                    .onAppear {
                        L.og.info("🟢 Fetching for QuotedNoteFragmentView \(id)")
                        req(RM.getEventAndReferences(id: id))
                    }
            }
        }
//        .transaction { transaction in
//            transaction.animation = nil
//            transaction.disablesAnimations = true
//        }
    }
}


#Preview("Content Renderer 1") {
    let _ = ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
    return PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadMedia()
        pe.parseMessages([
            ###"["EVENT","1",{"pubkey":"9989500413fb756d8437912cc32be0730dbe1bfc6b5d2eef759e1456c239f905","content":"Watch out for the Jazz attack, be glad your not a squirrel 🐿️ https://nostr.build/av/40cc2c4a2d33e3e082766765ec4f7cea1de8b442cae5b01cf779829762947a63.mov ","id":"473f85cb559d5d8866e7c3ffef536c67323ef44fe2d08d4bef42d82d9f868879","created_at":1692538971,"sig":"0b6d7640814bd5f4b39c4d4cd72ceebaf380775e0682f4667fa7e97a925223bb2f495ba59304485518f55761d29f8abeea8727595ad2fa5f9ad5c5b26ec962eb","kind":1,"tags":[["e","0ffa41f84eb1e66b3b10b8b3f91f55fcca67d46995236568ac22bba2433b397d"],["e","013b859a0dba4ae29a35a19a4cd5ae27b30311537325c9d9e83ef996e2e36968"],["p","0155373ac79b7ffb0f586c3e68396f9e82d46f7afe7016d46ed9ca46ba3e1bed"],["p","e844b39d850acbb13bba1a20057250fe6b3deff5f1ecc95b6a99dc35adafb6a2"],["imeta","url https://nostr.build/av/40cc2c4a2d33e3e082766765ec4f7cea1de8b442cae5b01cf779829762947a63.mov","blurhash eVE:nYtOaxoeof4fWFbGj[j[Nra#ofkBWBXft5j[a#axaQbHj?a#of","dim 720x1280"]]}]"###])
    }) {
        SmoothListMock {
                if let nrPost = PreviewFetcher.fetchNRPost("473f85cb559d5d8866e7c3ffef536c67323ef44fe2d08d4bef42d82d9f868879") {
                    Box {
                        ContentRenderer(nrPost: nrPost, availableWidth: UIScreen.main.bounds.width)
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
        SmoothListMock {
                if let nrPost = PreviewFetcher.fetchNRPost("9b34fd9a53398fb51493d68ecfd0d64ff922d0cdf5ffd8f0ffab46c9a3cf54e3") {
                    Box {
                        ContentRenderer(nrPost: nrPost, availableWidth: UIScreen.main.bounds.width)
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
        SmoothListMock {
                if let nrPost = PreviewFetcher.fetchNRPost("102177a51af895883e9256b70b2caff6b9ef90230359ee20f6dc7851ec9e5d5a") {
                    Box {
                        ContentRenderer(nrPost: nrPost, availableWidth: UIScreen.main.bounds.width)
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


struct EmbeddedPost: View {
    let nrPost:NRPost
    @ObservedObject var prd:NRPost.PostRowDeletableAttributes
    
    init(_ nrPost:NRPost) {
        self.nrPost = nrPost
        self.prd = nrPost.postRowDeletableAttributes
    }
    
    var body: some View {
        VStack {
            if prd.blocked {
                HStack {
                    Text("_Post from blocked account hidden_", comment: "Message shown when a post is from a blocked account")
                    Button(String(localized: "Reveal", comment: "Button to reveal a blocked a post")) { nrPost.blocked = false }
                        .buttonStyle(.bordered)
                }
                .padding(.leading, 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .hCentered()
            }
            else if nrPost.kind == 30023 {
                ArticleView(nrPost, hideFooter: true)
                    .padding(20)
                    .background(
                        Color(.secondarySystemBackground)
                            .cornerRadius(15)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(.regularMaterial, lineWidth: 1)
                    )
//                    .debugDimensions("EmbeddedPost.QuotedNoteFragmentView")
            }
            else {
                QuotedNoteFragmentView(nrPost: nrPost)
//                    .debugDimensions("EmbeddedPost.QuotedNoteFragmentView")
            }
        }
    }
}
