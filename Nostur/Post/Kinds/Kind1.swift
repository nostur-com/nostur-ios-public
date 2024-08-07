//
//  Kind1.swift
//  Same as Kind1Default.swift but for full width images
//  TODO: Need to make just a flag on Kind1 and remove this
//  Nostur
//
//  Created by Fabian Lachman on 11/05/2023.
//

import SwiftUI

// Note Full width
struct Kind1: View {
    @EnvironmentObject private var dim: DIMENSIONS
    @ObservedObject private var pfpAttributes: PFPAttributes
    @ObservedObject var settings:SettingsStore = .shared
    
    private let nrPost: NRPost
    private let hideFooter: Bool // For rendering in NewReply
    private let missingReplyTo: Bool // For rendering in thread
    private var connect: ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    private let isReply: Bool // is reply of PostDetail
    private let isDetail: Bool
    private let grouped: Bool
    private let forceAutoload: Bool
    private var theme: Theme
    @State private var didStart = false
    
    init(nrPost: NRPost, hideFooter: Bool = true, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil, isReply: Bool = false, isDetail: Bool = false, grouped:Bool = false, forceAutoload: Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.pfpAttributes = nrPost.pfpAttributes
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.isReply = isReply
        self.isDetail = isDetail
        self.grouped = grouped
        self.forceAutoload = forceAutoload
        self.theme = theme
    }
    
    let THREAD_LINE_OFFSET = 34.0
    
    var imageWidth: CGFloat {
        // FULL WIDTH IS ON
        
        // LIST OR LIST PARENT
        if !isDetail { return dim.listWidth - 20 }
        
        // DETAIL
        if isDetail && !isReply { return dim.availablePostDetailRowImageWidth() }
        
        // DETAIL PARENT OR REPLY
        return dim.availablePostDetailRowImageWidth()
    }
    
    @State var showMiniProfile = false
    
    var body: some View {
        
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                ZappablePFP(pubkey: nrPost.pubkey, contact: pfpAttributes.contact, size: DIMENSIONS.POST_ROW_PFP_WIDTH, zapEtag: nrPost.id, forceFlat: nrPost.isScreenshot)
                    .frame(width: 50, height: 50)
                    .onTapGesture {
                        withAnimation {
                            showMiniProfile = true
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if (showMiniProfile) {
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear {
                                        sendNotification(.showMiniProfile,
                                                         MiniProfileSheetInfo(
                                                            pubkey: nrPost.pubkey,
                                                            contact: nrPost.contact,
                                                            zapEtag: nrPost.id,
                                                            location: geo.frame(in: .global).origin
                                                         )
                                        )
                                        showMiniProfile = false
                                    }
                            }
                            .frame(width: 10)
                            .zIndex(100)
                            .transition(.asymmetric(insertion: .scale(scale: 0.4), removal: .opacity))
                            .onReceive(receiveNotification(.dismissMiniProfile)) { _ in
                                showMiniProfile = false
                            }
                        }
                    }
                NRPostHeaderContainer(nrPost: nrPost, singleLine: false)
                Spacer()
                LazyNoteMenuButton(nrPost: nrPost)
            }
            VStack(alignment:.leading, spacing: 3) {// Post container
                if missingReplyTo {
                    ReplyingToFragmentView(nrPost: nrPost, theme: theme)
                }
                if let fileMetadata = nrPost.fileMetadata {
                    Kind1063(nrPost, fileMetadata:fileMetadata, availableWidth: imageWidth, fullWidth: true, forceAutoload: forceAutoload, theme: theme, didStart: $didStart)
                }
                else {
                    if let subject = nrPost.subject {
                        Text(subject)
                            .fontWeight(.bold)
                            .lineLimit(3)
                        
                    }
                    if imageWidth < 75 { // Probably too many embeds in embeds in embeds in embeds, no space left
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    else if (nrPost.kind != 1) && (nrPost.kind != 6) {
                        AnyKind(nrPost, hideFooter: hideFooter, theme: theme)
                    }                    
                    else if (isDetail) {
                        ContentRenderer(nrPost: nrPost, isDetail: isDetail, fullWidth: true, availableWidth: imageWidth, forceAutoload: forceAutoload, theme: theme, didStart: $didStart)
                    }
                    else {
//                        Color.pink
//                            .frame(height: 50)
//                            .debugDimensions("Kind1")
                        ContentRenderer(nrPost: nrPost, isDetail: isDetail, fullWidth: true, availableWidth: imageWidth, forceAutoload: forceAutoload, theme: theme, didStart: $didStart)
                            .fixedSize(horizontal: false, vertical: true) // <-- this or child .fixedSizes will try to render outside frame and cutoff (because clipped() below)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: nrPost.sizeEstimate.rawValue, maxHeight: didStart ? 800 : 500, alignment: .top)
                            .clipped()
                        // Debug size estimate
//                            .overlay(alignment: .top) {
//                                VStack {
//                                    let est = switch nrPost.sizeEstimate {
//                                    case .large:
//                                        "large"
//                                    case .medium:
//                                        "medium"
//                                    case .small:
//                                        "small"
//                                    }
//                                    Text(est)
//                                        .background(.red)
//                                        .foregroundColor(.white)
//                                    if let weights = nrPost.previewWeights {
//                                        Text(weights.weight.rounded().description)
//                                    }
//                                }
//                            }
                        if (nrPost.previewWeights?.moreItems ?? false) {
                            ReadMoreButton(nrPost: nrPost)
                                .hCentered()
                        }
                    }
                }
                if (!hideFooter && settings.rowFooterEnabled) {
                    CustomizableFooterFragmentView(nrPost: nrPost, theme: theme)
                        .background(nrPost.kind == 30023 ? theme.secondaryBackground : theme.background)
                        .drawingGroup(opaque: true)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: isDetail ? 8800 : DIMENSIONS.POST_MAX_ROW_HEIGHT, alignment: .topLeading)
            .clipped()
        }
    }
}

struct Kind1_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadPosts()
        }) {
            SmoothListMock {
                Box {
                    if let nrPost = PreviewFetcher.fetchNRPost() {
                        VStack(spacing: 0) {
                            Kind1(nrPost: nrPost, theme: Themes.default.theme)
                            CustomizableFooterFragmentView(nrPost: nrPost, isDetail: false, theme: Themes.default.theme)
                        }
                    }
                }
            }
        }
    }
}
