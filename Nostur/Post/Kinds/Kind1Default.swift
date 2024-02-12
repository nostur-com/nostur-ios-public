//
//  Kind1Default.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/05/2023.
//

import SwiftUI

// Note 1 default (not full-width)
struct Kind1Default: View {
    private var theme:Theme
    @EnvironmentObject private var dim:DIMENSIONS
    @ObservedObject private var settings:SettingsStore = .shared
    private let nrPost:NRPost
    @ObservedObject private var pfpAttributes: NRPost.PFPAttributes
    
    private let hideFooter:Bool // For rendering in NewReply
    private let missingReplyTo:Bool // For rendering in thread
    private var connect:ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    private let isReply:Bool // is reply on PostDetail
    private let isDetail:Bool
    private let grouped:Bool
    private let forceAutoload:Bool
    @State private var didStart = false
    
    init(nrPost: NRPost, hideFooter:Bool = true, missingReplyTo:Bool = false, connect:ThreadConnectDirection? = nil, isReply:Bool = false, isDetail:Bool = false, grouped:Bool = false, forceAutoload:Bool = false, theme:Theme) {
        self.nrPost = nrPost
        self.pfpAttributes = nrPost.pfpAttributes
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.isReply = isReply
        self.isDetail = isDetail
        self.grouped = grouped
        self.theme = theme
        self.forceAutoload = forceAutoload
    }
    
    private let THREAD_LINE_OFFSET = 24.0
    
    private var imageWidth:CGFloat {
        // FULL WIDTH IS OFF
        
        // LIST OR LIST PARENT
        if !isDetail { return dim.availableNoteRowImageWidth() }
        
        // DETAIL
        if isDetail && !isReply { return dim.availablePostDetailImageWidth() }
        
        // DETAIL PARENT OR REPLY
        return dim.availablePostDetailRowImageWidth()
    }
    
    @State var showMiniProfile = false
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        HStack(alignment: .top, spacing: 10) {
            ZappablePFP(pubkey: nrPost.pubkey, contact: pfpAttributes.contact, size: DIMENSIONS.POST_ROW_PFP_WIDTH, zapEtag: nrPost.id, forceFlat: nrPost.isScreenshot)
                .frame(width: DIMENSIONS.POST_ROW_PFP_DIAMETER, height: DIMENSIONS.POST_ROW_PFP_DIAMETER)
                .background(alignment: .top) {
                    if connect == .top || connect == .both {
                        theme.lineColor
                            .opacity(0.2)
                            .frame(width: 2, height: 20)
                            .offset(x:0, y: -10)
//                            .transaction { t in
//                                t.animation = nil
//                            }
                    }
                }
//                .withoutAnimation() // seems to fix flying PFPs
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
//                .withoutAnimation()
//                .transaction { t in
//                    t.animation = nil
//                }
                if missingReplyTo {
                    ReplyingToFragmentView(nrPost: nrPost, theme: theme)
//                        .withoutAnimation()
//                        .transaction { t in
//                            t.animation = nil
//                        }
                }
                if let fileMetadata = nrPost.fileMetadata {
                    Kind1063(nrPost, fileMetadata:fileMetadata, availableWidth: imageWidth, theme: theme, didStart: $didStart)
//                        .withoutAnimation()
//                        .transaction { transaction in
//                            transaction.animation = nil
//                        }
                }
                else {
                    if let subject = nrPost.subject {
                        Text(subject)
                            .fontWeight(.bold)
                            .lineLimit(3)
//                            .withoutAnimation()
//                            .transaction { t in
//                                t.animation = nil
//                            }
                    }
                    if imageWidth < 75 { // Probably too many embeds in embeds in embeds in embeds, no space left
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    else if (nrPost.kind != 1) && (nrPost.kind != 6) {
                        AnyKind(nrPost, theme: theme)
                    }
                    else if (isDetail) {
                        ContentRenderer(nrPost: nrPost, isDetail:isDetail, fullWidth: false, availableWidth: imageWidth, forceAutoload: forceAutoload, theme: theme, didStart: $didStart)
                            .frame(maxWidth: .infinity, alignment:.leading)
                    }
                    else {
                        ContentRenderer(nrPost: nrPost, isDetail:isDetail, fullWidth: false, availableWidth: imageWidth, forceAutoload: forceAutoload, theme: theme, didStart: $didStart)
                            .frame(maxWidth: .infinity, alignment:.leading)
                            .frame(maxHeight: didStart ? 750 : 450, alignment: .top)
                            .clipped()
                        
                        if (nrPost.previewWeights?.moreItems ?? false) {
                            ReadMoreButton(nrPost: nrPost)
                                .padding(.vertical, 5)
//                                .withoutAnimation()
                                .hCentered()
                        }
                    }
                }
                if (!hideFooter && settings.rowFooterEnabled) {
                    CustomizableFooterFragmentView(nrPost: nrPost, theme: theme)
                        .background(nrPost.kind == 30023 ? theme.secondaryBackground : theme.background)
                        .drawingGroup(opaque: true)
//                        .withoutAnimation()
//                        .transaction { t in
//                            t.animation = nil
//                        }
                }
            }
        }
        .background(alignment: .leading) {
            if connect == .bottom || connect == .both {
                theme.lineColor
                    .frame(width: 2)
                    .opacity(0.2)
                    .offset(x: THREAD_LINE_OFFSET, y: 20)
//                    .withoutAnimation()
//                    .transaction { t in
//                        t.animation = nil
//                    }
            }
        }
    }
}

struct Kind1Default_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
        }) {
            SmoothListMock {
                if let nrPost = PreviewFetcher.fetchNRPost("da3f7863d634b2020f84f38bd3dac5980794715702e85c3f164e49ebe5dc98cc") {
                    Box {
                        Kind1Default(nrPost: nrPost, hideFooter: false, theme: Themes.default.theme)
                    }
                }
                
                if let nrPost = PreviewFetcher.fetchNRPost() {
                    Box {
                        Kind1Default(nrPost: nrPost, hideFooter: false, theme: Themes.default.theme)
                    }
                }
            }
            .withSheets()
        }
    }
}
