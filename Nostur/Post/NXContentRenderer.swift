//
//  NXContentRenderer.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/09/2024.
//

import SwiftUI

import Nuke
import NukeUI
import Combine

// WIP Rewrite where we remove Core Data "Event" as much as possible

class ViewingContext: ObservableObject {
    @Published public var availableWidth: CGFloat
    public var fullWidthImages: Bool
    
    public var viewType: ViewingContextType
    
    
    // Helpers
    public var isDetail: Bool {
        viewType == .detail
    }
    
    public var isScreenshot: Bool {
        viewType == .screenshot
    }
    
    public var isPreview: Bool {
        viewType == .screenshot
    }
    
    init(availableWidth: CGFloat, fullWidthImages: Bool, viewType: ViewingContextType) {
        self.availableWidth = availableWidth
        self.fullWidthImages = fullWidthImages
        self.viewType = viewType
    }
}

enum ViewingContextType {
    case row
    case detail
    case screenshot
    case preview
}

struct NXEvent {
    let pubkey: String
    let kind: Int
    
    public var imageUrls: [URL] = []
}

extension NXEvent {
    var isNSFW: Bool {
        return false
        // TODO... need to check tags
    }
}

enum NXContentRendererViewState {
    case loading
    case ready(CGFloat) // availableWidth
}

// Renders embeds (VIEWS), not links (in TEXT)
struct NXContentRenderer: View { // VIEW things
    @Environment(\.theme) public var theme
    @Environment(\.nxViewingContext) private var nxViewingContext
    @EnvironmentObject private var vc: ViewingContext
    public let nxEvent: NXEvent
    public let contentElements: [ContentElement]
    public var forceAutoload: Bool = false
    public var zoomableId: String = "Default"
    
    @State private var viewState: NXContentRendererViewState = .loading
    
    private var shouldAutoload: Bool {
        return !nxEvent.isNSFW && (forceAutoload || SettingsStore.shouldAutodownload(nxEvent) || nxViewingContext.contains(.screenshot))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch viewState {
            case .loading:
                ProgressView()
                    .onAppear {
                        viewState = .ready(vc.availableWidth)
                    }
            case .ready(let availableWidth):
                ForEach(contentElements.indices, id:\.self) { index in
                    switch contentElements[index] {
                    case .nrPost(let nrPost):
                        KindResolver(nrPost: nrPost, fullWidth: vc.fullWidthImages, hideFooter: true, isDetail: false, isEmbedded: true, forceAutoload: shouldAutoload)
                            .environment(\.availableWidth, availableWidth)
    //                        .debugDimensions("EmbeddedPost")
                            .padding(.vertical, 10)
                            .id(index)
    //                        .withoutAnimation()
    //                        .transaction { t in t.animation = nil }
                        
                    case .nevent1(let identifier):
                        NEventView(identifier: identifier, fullWidth: vc.fullWidthImages, forceAutoload: shouldAutoload)
    //                        .frame(minHeight: 75)
                            .environment(\.availableWidth, availableWidth)
    //                        .debugDimensions("NEventView")
                            .padding(.vertical, 10)
                            .id(index)
    //                        .withoutAnimation()
    //                        .transaction { t in t.animation = nil }
                    case .npub1(let npub):
                        if let pubkey = hex(npub) {
                            ProfileCardByPubkey(pubkey: pubkey)
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
                            .id(index)
    //                        .transaction { t in t.animation = nil }
                    case .note1(let noteId):
                        if let noteHex = hex(noteId) {
                            EmbedById(id: noteHex, fullWidth: vc.fullWidthImages, forceAutoload: shouldAutoload)
    //                            .frame(minHeight: 75)
                                .environment(\.availableWidth, availableWidth)
    //                            .debugDimensions("QuoteById.note1")
                                .padding(.vertical, 10)
                                .id(index)
                        }
                        else {
                            EmptyView()
                                .id(index)
                        }
                    case .noteHex(let hex):
                        EmbedById(id: hex, fullWidth: vc.fullWidthImages, forceAutoload: shouldAutoload)
    //                        .frame(minHeight: 75)
                            .environment(\.availableWidth, availableWidth)
    //                        .debugDimensions("QuoteById.noteHex")
                            .padding(.vertical, 10)
                            .id(index)
                    case .code(let code): // For text notes
                        Text(verbatim: code)
                            .font(.system(.body, design: .monospaced))
                            .id(index)
                    case .text(let attributedStringWithPs): // For text notes
                        NRContentTextRenderer(attributedStringWithPs: attributedStringWithPs, showMore: .constant(true), availableWidth: vc.availableWidth, isDetail: vc.isDetail, primaryColor: theme.primary, accentColor: theme.accent)
                            .equatable()
                            .id(index)
                    case .md(let markdownContentWithPs): // For long form articles
                        NRContentMarkdownRenderer(markdownContentWithPs: markdownContentWithPs, maxWidth: vc.availableWidth)
                            .id(index)
                    case .lnbc(let text):
                        LightningInvoice(invoice: text)
                            .padding(.vertical, 10)
                            .id(index)
                    case .cashu(let text):
                        CashuTokenView(token: text)
                            .padding(.vertical, 10)
                            .id(index)
                    case .video(let mediaContent):
                        EmbeddedVideoView(url: mediaContent.url, pubkey: nxEvent.pubkey , autoload: shouldAutoload)
                            .environment(\.availableWidth, availableWidth + (vc.fullWidthImages ? 20 : 0))
                            .padding(.horizontal, vc.fullWidthImages ? -10 : 0)

                    case .image(let galleryItem):
                        MediaContentView(
                            galleryItem: galleryItem,
                            availableWidth: vc.availableWidth,
                            placeholderAspect: 4/3,
                            maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT / 2,
                            contentMode: .fit,
                            autoload: shouldAutoload,
                            isNSFW: nxEvent.isNSFW,
                            zoomableId: zoomableId
                        )
                        .padding(.vertical, 10)
//                        .padding(.horizontal, vc.fullWidthImages ? -10 : 0)

                    case .linkPreview(let url):
                        LinkPreviewView(url: url, autoload: shouldAutoload)
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
                                .padding(.vertical, 10)
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
                                .padding(.vertical, 10)
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
        }
    }
}


#Preview {
    
    let viewingContext = ViewingContext(availableWidth: 200, fullWidthImages: true, viewType: .row)
    
    let nxEvent = NXEvent(pubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e", kind: 1)
    let attributedStringWithPs: AttributedStringWithPs = AttributedStringWithPs(input: "Hello!", output: NSAttributedString(string: "Hello!"), pTags: [])
    let contentElements: [ContentElement] = [ContentElement.text(attributedStringWithPs)]
    
    return NXContentRenderer(nxEvent: nxEvent, contentElements: contentElements)
        .environmentObject(viewingContext)
}
