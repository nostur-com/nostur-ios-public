//
//  Kind1Both.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/08/2024.
//

import SwiftUI

struct Kind1Both: View {
    private var theme: Theme
    @EnvironmentObject private var dim: DIMENSIONS
    @ObservedObject private var settings: SettingsStore = .shared
    private let nrPost: NRPost
    @ObservedObject private var pfpAttributes: PFPAttributes
    
    private let hideFooter: Bool // For rendering in NewReply
    private let missingReplyTo: Bool // For rendering in thread
    private var connect: ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    private let isReply: Bool // is reply on PostDetail
    private let isDetail: Bool
    private let fullWidth: Bool
    private let grouped: Bool
    private let forceAutoload: Bool
    @State private var didStart = false
    
    private let THREAD_LINE_OFFSET = 24.0
    
    private var imageWidth: CGFloat {
        // FULL WIDTH IS OFF
        
        // LIST OR LIST PARENT
        if !isDetail { return fullWidth ? (dim.listWidth - 20) : dim.availableNoteRowWidth }
        
        // DETAIL
        if isDetail && !isReply { return fullWidth ? dim.availablePostDetailRowImageWidth() : dim.availablePostDetailImageWidth() }
        
        // DETAIL PARENT OR REPLY
        return dim.availablePostDetailRowImageWidth()
    }
    
    private var isOlasGeneric: Bool { (nrPost.kind == 1 && (nrPost.kTag ?? "") == "20") }
    
    @State var showMiniProfile = false
    
    init(nrPost: NRPost, hideFooter: Bool = true, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil, isReply: Bool = false, isDetail: Bool = false, fullWidth: Bool, grouped: Bool = false, forceAutoload: Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.pfpAttributes = nrPost.pfpAttributes
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.isReply = isReply
        self.fullWidth = fullWidth
        self.isDetail = isDetail
        self.grouped = grouped
        self.theme = theme
        self.forceAutoload = forceAutoload
    }
    
    var body: some View {
        if fullWidth || nrPost.kind == 20 || isOlasGeneric {
            self.fullWidthView
        }
        else {
            self.normalView
        }
    }
    
    private var shouldAutoload: Bool {
        return !nrPost.isNSFW && (forceAutoload || SettingsStore.shouldAutodownload(nrPost))
    }
    
    @ViewBuilder
    private var normalView: some View {
//        #if DEBUG
//        let _ = Self._printChanges()
//        #endif
        HStack(alignment: .top, spacing: 10) {
            if SettingsStore.shared.enableLiveEvents && LiveEventsModel.shared.livePubkeys.contains(nrPost.pubkey) {
                LiveEventPFP(pubkey: nrPost.pubkey, nrContact: pfpAttributes.contact, size: DIMENSIONS.POST_ROW_PFP_WIDTH, forceFlat: nrPost.isScreenshot)
                    .frame(width: DIMENSIONS.POST_ROW_PFP_DIAMETER, height: DIMENSIONS.POST_ROW_PFP_DIAMETER)
                    .background(alignment: .top) {
                        if connect == .top || connect == .both {
                            theme.lineColor
                                .frame(width: 1, height: 20)
                                .offset(x: -0.5, y: -10)
                        }
                    }
                    .onTapGesture {
                        if let liveEvent = LiveEventsModel.shared.nrLiveEvents.first(where: { $0.pubkey == nrPost.pubkey || $0.participantsOrSpeakers.map { $0.pubkey }.contains(nrPost.pubkey) }) {
                            if IS_CATALYST {
                                navigateTo(liveEvent)
                            }
                            else {
                                Task { @MainActor in
                                    LiveKitVoiceSession.shared.activeNest = liveEvent
                                }
                            }
                        }
                    }
            }
            else {
                ZappablePFP(pubkey: nrPost.pubkey, contact: pfpAttributes.contact, size: DIMENSIONS.POST_ROW_PFP_WIDTH, zapEtag: nrPost.id, forceFlat: nrPost.isScreenshot)
                    .frame(width: DIMENSIONS.POST_ROW_PFP_DIAMETER, height: DIMENSIONS.POST_ROW_PFP_DIAMETER)
                    .background(alignment: .top) {
                        if connect == .top || connect == .both {
                            theme.lineColor
                                .frame(width: 1, height: 20)
                                .offset(x: -0.5, y: -10)
                        }
                    }
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
                                                            contact: pfpAttributes.contact,
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
            }


            VStack(alignment: .leading, spacing: 3) { // Post container
                HStack(alignment: .top) { // name + reply + context menu
                    NRPostHeaderContainer(nrPost: nrPost)
                    Spacer()
                    LazyNoteMenuButton(nrPost: nrPost)
                }
//                .frame(height: 21.0)
//                .background(nrPost.kind == 30023 ? theme.secondaryBackground : theme.background)
//                .drawingGroup(opaque: true)
//                .debugDimensions()
                if missingReplyTo {
                    ReplyingToFragmentView(nrPost: nrPost, theme: theme)
                }
                if let fileMetadata = nrPost.fileMetadata {
                    Kind1063(nrPost, fileMetadata:fileMetadata, availableWidth: imageWidth, theme: theme, didStart: $didStart)
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
                        AnyKind(nrPost, hideFooter: hideFooter, autoload: shouldAutoload, imageWidth: dim.availableNoteRowImageWidth(), theme: theme)
                    }
                    else if (isDetail) {
                        ContentRenderer(nrPost: nrPost, isDetail: isDetail, fullWidth: fullWidth, availableWidth: imageWidth, forceAutoload: forceAutoload, theme: theme, didStart: $didStart)
                            .frame(maxWidth: .infinity, alignment:.leading)
                    }
                    else {
//                        ZStack(alignment: .bottom) {
                            ContentRenderer(nrPost: nrPost, isDetail: isDetail, fullWidth: fullWidth, availableWidth: imageWidth, forceAutoload: forceAutoload, theme: theme, didStart: $didStart)
                                .fixedSize(horizontal: false, vertical: true) // <-- this or child .fixedSizes will try to render outside frame and cutoff (because clipped() below)
                                .frame(maxWidth: .infinity, alignment: .leading)
    //                            .frame(height: 500, alignment: .top)
    //                            .fixedSize(horizontal: false, vertical: true)
                                .frame(minHeight: nrPost.sizeEstimate.rawValue, maxHeight: !IS_IPHONE && didStart ? 750 : 450, alignment: .top)
                                .clipped()
                            
                            
                            // Fade bottom instead of hard clip. disabled because not accurate enough
//                            if nrPost.sizeEstimate == .large && !didStart {
//                                // Fade effect
//                               LinearGradient(
//                                gradient: Gradient(colors: [.clear, theme.background.opacity(0.35), theme.background.opacity(0.75), theme.background.opacity(0.95)]),
//                                   startPoint: .top,
//                                   endPoint: .bottom
//                               )
//                               .frame(height: 30) // Adjust the height of the fade effect
//                               .edgesIgnoringSafeArea(.bottom)
//                            }
//                        }
                        
                            // Debug size estimate
//                            .overlay(alignment: .topTrailing) {
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
                                .padding(.vertical, 5)
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
        }
        .background(alignment: .leading) {
            if connect == .bottom || connect == .both {
                theme.lineColor
                    .frame(width: 1)
                    .offset(x: THREAD_LINE_OFFSET, y: 20)
            }
        }
    }
    
    @ViewBuilder
    private var fullWidthView: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                if SettingsStore.shared.enableLiveEvents && LiveEventsModel.shared.livePubkeys.contains(nrPost.pubkey) {
                    LiveEventPFP(pubkey: nrPost.pubkey, nrContact: pfpAttributes.contact, size: DIMENSIONS.POST_ROW_PFP_WIDTH, forceFlat: nrPost.isScreenshot)
                        .onTapGesture {
                            if let liveEvent = LiveEventsModel.shared.nrLiveEvents.first(where: { $0.pubkey == nrPost.pubkey || $0.participantsOrSpeakers.map { $0.pubkey }.contains(nrPost.pubkey) }) {
                                if IS_CATALYST {
                                    navigateTo(liveEvent)
                                }
                                else {
                                    Task { @MainActor in
                                        LiveKitVoiceSession.shared.activeNest = liveEvent
                                    }
                                }
                            }
                        }
                }
                else {
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
                    else if ((nrPost.kind != 1) && (nrPost.kind != 6)) || (isOlasGeneric) {
                        AnyKind(nrPost, hideFooter: hideFooter, autoload: shouldAutoload, imageWidth: imageWidth, theme: theme)
                    }
                    else if (isDetail) {
                        ContentRenderer(nrPost: nrPost, isDetail: isDetail, fullWidth: fullWidth, availableWidth: imageWidth, forceAutoload: forceAutoload, theme: theme, didStart: $didStart)
                    }
                    else {
//                        Color.pink
//                            .frame(height: 50)
//                            .debugDimensions("Kind1")
                        ContentRenderer(nrPost: nrPost, isDetail: isDetail, fullWidth: fullWidth, availableWidth: imageWidth, forceAutoload: forceAutoload, theme: theme, didStart: $didStart)
                            .fixedSize(horizontal: false, vertical: true) // <-- this or child .fixedSizes will try to render outside frame and cutoff (because clipped() below)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: nrPost.sizeEstimate.rawValue, maxHeight: !IS_IPHONE && didStart ? 800 : 500, alignment: .top)
                            .clipBottom(height: !IS_IPHONE && didStart ? 800 : 500)
//                            .clipped()
                        // Debug size estimate
//                            .overlay(alignment: .topTrailing) {
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
//                                        .background(.red.opacity(0.6))
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
//            .fixedSize(horizontal: false, vertical: true) // <-- need this or no?
            .frame(maxHeight: isDetail ? 8800 : DIMENSIONS.POST_MAX_ROW_HEIGHT, alignment: .topLeading)
//            .clipped()
        }
    }
}


extension View {
    func clipBottom(height: CGFloat) -> some View {
        self.mask(
            VStack {
                Rectangle()
                    .padding(.horizontal, -10)
                    .frame(height: height)
                // Full view rectangle
                Spacer() // Clip height, adjust as needed
            }
        )
    }
}
