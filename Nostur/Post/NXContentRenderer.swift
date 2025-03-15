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
    public var theme: Theme
    
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
    
    init(availableWidth: CGFloat, fullWidthImages: Bool, theme: Theme, viewType: ViewingContextType) {
        self.availableWidth = availableWidth
        self.fullWidthImages = fullWidthImages
        self.theme = theme
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
    case ready(DIMENSIONS)
}

// Renders embeds (VIEWS), not links (in TEXT)
struct NXContentRenderer: View { // VIEW things
    @EnvironmentObject private var vc: ViewingContext
    public let nxEvent: NXEvent
    public let contentElements: [ContentElement]
    @Binding var didStart: Bool
    public var forceAutoload: Bool = false
    
    @State private var viewState: NXContentRendererViewState = .loading
    
    private var shouldAutoload: Bool {
        return !nxEvent.isNSFW && (forceAutoload || SettingsStore.shouldAutodownload(nxEvent))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch viewState {
            case .loading:
                ProgressView()
                    .onAppear {
                        viewState = .ready(DIMENSIONS.embeddedDim(
                            availableWidth: vc.availableWidth,
                            isScreenshot: vc.isScreenshot)
                        )
                    }
            case .ready(let childDIM):
                ForEach(contentElements.indices, id:\.self) { index in
                    switch contentElements[index] {
                    case .nrPost(let nrPost):
                        KindResolver(nrPost: nrPost, fullWidth: vc.fullWidthImages, hideFooter: true, isDetail: false, isEmbedded: true, forceAutoload: shouldAutoload, theme: vc.theme)
//                        EmbeddedPost(nrPost, fullWidth: vc.fullWidthImages, forceAutoload: shouldAutoload, theme: vc.theme)
    //                        .frame(minHeight: 75)
                            .environmentObject(childDIM)
                        //                        .fixedSize(horizontal: false, vertical: true)
    //                        .debugDimensions("EmbeddedPost")
                            .padding(.vertical, 10)
                            .id(index)
    //                        .withoutAnimation()
    //                        .transaction { t in t.animation = nil }
                    case .nevent1(let identifier):
                        NEventView(identifier: identifier, fullWidth: vc.fullWidthImages, forceAutoload: shouldAutoload, theme: vc.theme)
    //                        .frame(minHeight: 75)
                            .environmentObject(childDIM)
    //                        .debugDimensions("NEventView")
                            .padding(.vertical, 10)
                            .id(index)
    //                        .withoutAnimation()
    //                        .transaction { t in t.animation = nil }
                    case .npub1(let npub):
                        if let pubkey = hex(npub) {
                            ProfileCardByPubkey(pubkey: pubkey, theme: vc.theme)
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
                            EmbedById(id: noteHex, fullWidth: vc.fullWidthImages, forceAutoload: shouldAutoload, theme: vc.theme)
    //                            .frame(minHeight: 75)
                                .environmentObject(childDIM)
    //                            .debugDimensions("QuoteById.note1")
                                .padding(.vertical, 10)
    //                            .withoutAnimation()
    //                            .transaction { t in t.animation = nil }
                                .onTapGesture {
                                    guard !vc.isDetail else { return }
    //                                navigateTo(nrPost) // TODO
                                }
                                .id(index)
                        }
                        else {
                            EmptyView()
                                .id(index)
                        }
                    case .noteHex(let hex):
                        EmbedById(id: hex, fullWidth: vc.fullWidthImages, forceAutoload: shouldAutoload, theme: vc.theme)
    //                        .frame(minHeight: 75)
                            .environmentObject(childDIM)
    //                        .debugDimensions("QuoteById.noteHex")
                            .padding(.vertical, 10)
    //                        .withoutAnimation()
    //                        .transaction { t in t.animation = nil }
                            .onTapGesture {
                                guard !vc.isDetail else { return }
    //                            navigateTo(nrPost) // TODO
                            }
                            .id(index)
                    case .code(let code): // For text notes
                        Text(verbatim: code)
                            .font(.system(.body, design: .monospaced))
                            .onTapGesture {
                                guard !vc.isDetail else { return }
    //                            navigateTo(nrPost) // TODO
                            }
                            .id(index)
                    case .text(let attributedStringWithPs): // For text notes
                        NRContentTextRenderer(attributedStringWithPs: attributedStringWithPs, availableWidth: vc.availableWidth, isScreenshot: vc.isScreenshot, isDetail: vc.isDetail, isPreview: vc.isPreview, primaryColor: vc.theme.primary, accentColor: vc.theme.accent)
                            .equatable()
                            .onTapGesture {
                                guard !vc.isDetail else { return }
                                //                            navigateTo(nrPost) // TODO
                            }
                            .id(index)
                    case .md(let markdownContentWithPs): // For long form articles
                        NRContentMarkdownRenderer(markdownContentWithPs: markdownContentWithPs, theme: vc.theme, maxWidth: vc.availableWidth)
                            .onTapGesture {
                                guard !vc.isDetail else { return }
    //                            navigateTo(nrPost) // TODO
                            }
                            .id(index)
                    case .lnbc(let text):
                        LightningInvoice(invoice: text, theme: vc.theme)
                            .padding(.vertical, 10)
                            .id(index)
                    case .cashu(let text):
                        CashuTokenView(token: text, theme: vc.theme)
                            .padding(.vertical, 10)
                            .id(index)
                    case .video(let mediaContent):
                        EmbeddedVideoView(url: mediaContent.url, pubkey: nxEvent.pubkey, availableWidth: vc.availableWidth + (vc.fullWidthImages ? 20 : 0), autoload: shouldAutoload, theme: vc.theme, didStart: $didStart)
                            .padding(.horizontal, vc.fullWidthImages ? -10 : 0)

                    case .image(let mediaContent):
                        if let dimensions = mediaContent.dimensions {
                            let scaledDimensions = Nostur.scaledToFit(dimensions, scale: UIScreen.main.scale, maxWidth: vc.availableWidth, maxHeight: vc.isDetail ? 5000.0 : DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
    #if DEBUG
    //                                                Text(".image.availableWidth (SD): \(Int(availableWidth))\ndim:\(dimensions.debugDescription)\nSD: \(scaledDimensions.debugDescription)")
    //                                                    .frame(maxWidth: .infinity)
    //                                                    .background(.red)
    //                                                    .foregroundColor(.white)
    //                                                    .debugDimensions()
    #endif


                            if vc.fullWidthImages || vc.isDetail {
                                SingleMediaViewer(url: mediaContent.url, pubkey: nxEvent.pubkey, height: scaledDimensions.height, imageWidth: vc.availableWidth, fullWidth: vc.fullWidthImages, autoload: shouldAutoload, contentPadding: nxEvent.kind == 30023 ? 10 : 0, theme: vc.theme, scaledDimensions: scaledDimensions, imageUrls: nxEvent.imageUrls)
                                    .background {
                                        if SettingsStore.shared.lowDataMode {
                                            vc.theme.lineColor.opacity(0.2)
                                        }
                                    }
                                    .padding(.horizontal, vc.fullWidthImages ? -10 : 0)
    //                                .debugDimensions("smv")
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity, alignment: SettingsStore.shared.lowDataMode ? .leading : .center)
    //                                .debugDimensions("smv.frame")
                                    .id(index)
        //                            .withoutAnimation()
        //                            .transaction { t in t.animation = nil }
                            }
                            else {
                                SingleMediaViewer(url: mediaContent.url, pubkey: nxEvent.pubkey, height: scaledDimensions.height, imageWidth: vc.availableWidth, fullWidth: vc.fullWidthImages, autoload: shouldAutoload, contentPadding: nxEvent.kind == 30023 ? 10 : 0, theme: vc.theme, scaledDimensions: scaledDimensions, imageUrls: nxEvent.imageUrls)
    //                                .fixedSize(horizontal: false, vertical: true)
                                    .frame(width: max(25, scaledDimensions.width), height: max(25,scaledDimensions.height))
        //                            .debugDimensions("sd.image \(scaledDimensions.width)x\(scaledDimensions.height)")
                                    .background {
                                        if SettingsStore.shared.lowDataMode {
                                            vc.theme.lineColor.opacity(0.2)
                                        }
                                    }
                                    .padding(.horizontal, vc.fullWidthImages ? -10 : 0)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity, alignment: SettingsStore.shared.lowDataMode ? .leading : .center)
                                    .id(index)
        //                            .withoutAnimation()
        //                            .transaction { t in t.animation = nil }
                            }


                        }
                        else {

    #if DEBUG
                            //                        Text(".image.availableWidth: \(Int(availableWidth))")
                            //                            .frame(maxWidth: .infinity)
                            //                            .background(.red)
                            //                            .foregroundColor(.white)
                            //                            .debugDimensions()
    #endif

                                MediaContentView(
                                    media: mediaContent,
                                    availableWidth: vc.availableWidth - (nxEvent.kind == 30023 ? 10 : 0),
                                    placeholderHeight: 300,
                                    maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT,
                                    contentMode: .fill,
                                    imageUrls: nxEvent.imageUrls,
                                    upscale: true,
                                    autoload: shouldAutoload
                                )
    //                            .debugDimensions("image")
                                .padding(.horizontal, vc.fullWidthImages ? -10 : 0)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: SettingsStore.shared.lowDataMode ? .leading : .center)
    //                            .debugDimensions("image.frame")
                                .id(index)
    //                            .background(Color.yellow)
    //                            .withoutAnimation()
    //                            .transaction { t in t.animation = nil }
                        }
                    case .linkPreview(let url):
                        LinkPreviewView(url: url, autoload: shouldAutoload, theme: vc.theme)
                            .padding(.vertical, 10)
                            .id(index)
    //                        .withoutAnimation()
    //                        .transaction { t in t.animation = nil }
                    case .postPreviewImage(let postedImageMeta):
                        Image(uiImage: postedImageMeta.imageData)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 600)
                            .padding(.top, 10)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .id(index)
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
                            .onTapGesture {
                                guard !vc.isDetail else { return }
                                //                            navigateTo(nrPost) // TODO
                            }
                            .id(index)
                    }
                }
            }
        }
    }
}


#Preview {
    
    let viewingContext = ViewingContext(availableWidth: 200, fullWidthImages: true, theme: Themes.default.theme, viewType: .row)
    
    let nxEvent = NXEvent(pubkey: "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e", kind: 1)
    let attributedStringWithPs: AttributedStringWithPs = AttributedStringWithPs(input: "Hello!", output: NSAttributedString(string: "Hello!"), pTags: [])
    let contentElements: [ContentElement] = [ContentElement.text(attributedStringWithPs)]
    
    return NXContentRenderer(nxEvent: nxEvent, contentElements: contentElements, didStart: .constant(false))
        .environmentObject(viewingContext)
}
