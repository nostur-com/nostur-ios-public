////
////  ParentPost.swift
////  Nostur
////
////  Created by Fabian Lachman on 11/03/2025.
////
//
//import SwiftUI
//
//struct ParentPost: View {
//    @ObservedObject private var nrPost: NRPost
//    @ObservedObject private var postRowDeletableAttributes: PostRowDeletableAttributes
//    @ObservedObject private var pfpAttributes: PFPAttributes
//    @ObservedObject private var settings: SettingsStore = .shared
//    @EnvironmentObject private var dim: DIMENSIONS
//    @EnvironmentObject private var themes: Themes
//    private let INDENT = DIMENSIONS.POST_ROW_PFP_WIDTH + DIMENSIONS.POST_PFP_SPACE
//    private var connect:ThreadConnectDirection? = nil
//    @State private var showMiniProfile = false
//    @State private var didStart = false
//    private var forceAutoload: Bool = false
//    
//    init(nrPost: NRPost, connect: ThreadConnectDirection? = nil, forceAutoload: Bool = false) {
//        self.nrPost = nrPost
//        self.postRowDeletableAttributes = nrPost.postRowDeletableAttributes
//        self.pfpAttributes = nrPost.pfpAttributes
//        self.connect = connect
//        self.forceAutoload = forceAutoload
//    }
//    
//    private var shouldAutoload: Bool {
//        return !nrPost.isNSFW && (forceAutoload || SettingsStore.shouldAutodownload(nrPost))
//    }
//    
//    var body: some View {
//        VStack(spacing: 0) {
//            if postRowDeletableAttributes.blocked {
//                HStack {
//                    Text("_Post from blocked account hidden_", comment: "Message shown when a post is from a blocked account")
//                    Button(String(localized: "Reveal", comment: "Button to reveal a blocked a post")) { nrPost.blocked = false }
//                        .buttonStyle(.bordered)
//                }
//                .padding(.leading, 8)
//                .overlay(
//                    RoundedRectangle(cornerRadius: 8)
//                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
//                )
//                .padding(.vertical, 20)
//            }
//            else {
//                ZStack(alignment: .topLeading) {
//                    VStack(spacing: 0) {
//                        HStack(alignment:.top, spacing: 10) {
//                            ZappablePFP(pubkey: nrPost.pubkey, pfpAttributes: pfpAttributes, size: DIMENSIONS.POST_ROW_PFP_WIDTH, zapEtag: nrPost.id)
//                                .frame(width: DIMENSIONS.POST_ROW_PFP_WIDTH, height: 50)
//                                .onTapGesture {
//                                    if !IS_APPLE_TYRANNY {
//                                        if let nrContact = nrPost.contact {
//                                            navigateTo(nrContact)
//                                        }
//                                        else {
//                                            navigateTo(ContactPath(key: nrPost.pubkey))
//                                        }
//                                    }
//                                    else {
//                                        withAnimation {
//                                            showMiniProfile = true
//                                        }
//                                    }
//                                }
//                                .overlay(alignment: .topLeading) {
//                                    if (showMiniProfile) {
//                                        GeometryReader { geo in
//                                            Color.clear
//                                                .onAppear {
//                                                    sendNotification(.showMiniProfile,
//                                                                     MiniProfileSheetInfo(
//                                                                        pubkey: nrPost.pubkey,
//                                                                        contact: nrPost.contact,
//                                                                        zapEtag: nrPost.id,
//                                                                        location: geo.frame(in: .global).origin
//                                                                     )
//                                                    )
//                                                    showMiniProfile = false
//                                                }
//                                        }
//                                        .frame(width: 10)
//                                        .zIndex(100)
//                                        .transition(.asymmetric(insertion: .scale(scale: 0.4), removal: .opacity))
//                                        .onReceive(receiveNotification(.dismissMiniProfile)) { _ in
//                                            showMiniProfile = false
//                                        }
//                                    }
//                                }
//                            
//                            VStack(alignment:.leading, spacing: 3) {
//                                HStack(alignment: .top) {
//                                    NRPostHeaderContainer(nrPost: nrPost, singleLine: true)
//                                    Spacer()
//                                    EventPrivateNoteToggle(nrPost: nrPost)
//                                    LazyNoteMenuButton(nrPost: nrPost)
//                                        .offset(y: -5)
//                                }
//                                
//                                // We don't show "Replying to.." unless we can't fetch the parent
//                                if nrPost.replyTo == nil && nrPost.replyToId != nil {
//                                    ReplyingToFragmentView(nrPost: nrPost, theme: themes.theme)
//                                    //                                .padding(.trailingx, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
//                                }
//                                
//                                switch nrPost.kind {
//                                case 20:
//                                    if let imageUrl = nrPost.imageUrls.first {
//                                        let iMeta: iMetaInfo? = findImeta(nrPost.fastTags, url: imageUrl.absoluteString) // TODO: More to NRPost.init?
//                                        VStack {
//                                            MediaContentView(
//                                                media: MediaContent(
//                                                    url: imageUrl,
//                                                    dimensions: iMeta?.size,
//                                                    blurHash: iMeta?.blurHash
//                                                ),
//                                                availableWidth: dim.listWidth,
//                                                placeholderHeight: dim.listWidth * (iMeta?.aspect ?? 1.0),
//                                                maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT,
//                                                contentMode: .fill,
//                                                imageUrls: nrPost.imageUrls,
//                                                autoload: shouldAutoload
//                                            )
//                                            .padding(.top, 10)
//                                            .padding(.horizontal, -10)
//                                            .overlay(alignment: .bottomTrailing) {
//                                                if nrPost.imageUrls.count > 1 {
//                                                    Text("\(nrPost.imageUrls.count - 1) more")
//                                                        .fontWeightBold()
//                                                        .foregroundColor(.white)
//                                                        .padding(5)
//                                                        .background(.black)
//                                                        .allowsHitTesting(false)
//                                                }
//                                            }
//                                            
//                                            ContentRenderer(nrPost: nrPost, isDetail: true, availableWidth: dim.listWidth - 80, theme: themes.theme, didStart: $didStart)
//                                                .padding(.vertical, 10)
//                                        }
//                                    }
//                                    else {
//                                        EmptyView()
//                                    }
//                                case 30023:
//                                    ArticleView(nrPost, isDetail: false, fullWidth: settings.fullWidthImages, hideFooter: false, theme: themes.theme)
//                                        .padding(.horizontal, -10) // padding is all around (detail+parents) if article is parent we need to negate the padding
//                                        .padding(.bottom, 10)
//                                        .background(Color(.secondarySystemBackground))
//                                case 9802: // highlight
//                                    HighlightRenderer(nrPost: nrPost, theme: themes.theme)
//                                        .padding(.vertical, 10)
//                                    //                                .padding(.trailingx, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
//                                case 1,6,9734: // text, repost, zap request
//                                    ContentRenderer(nrPost: nrPost, isDetail: false, availableWidth: dim.listWidth - 80, theme: themes.theme, didStart: $didStart)
//                                    //                                .padding(.trailingx, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
//                                case 1063: // File Metadata
//                                    NoteTextRenderView(nrPost: nrPost, fullWidth: settings.fullWidthImages, theme: themes.theme)
//                                case 99999:
//                                    let title = nrPost.eventTitle ?? "Untitled"
//                                    if let eventUrl = nrPost.eventUrl {
//                                        VideoEventView(title: title, url: eventUrl, summary: nrPost.eventSummary, imageUrl: nrPost.eventImageUrl, autoload: true, theme: themes.theme, availableWidth: dim.listWidth - 80)
//                                            .padding(.vertical, 10)
//                                    }
//                                    else {
//                                        EmptyView()
//                                }
//                                default:
//                                    UnknownKindView(nrPost: nrPost, theme: themes.theme)
//                                        .padding(.vertical, 10)
//                                }
//                            }
//                        }
//                        
//                        if (settings.rowFooterEnabled) {
//                            CustomizableFooterFragmentView(nrPost: nrPost, theme: themes.theme)
//                                .padding(.leading, INDENT)
//                                .padding(.vertical, 5)
//                            //                        .padding(.trailingx, 10)
//                        }
//                    }
//                }
//                .background(alignment:.topLeading) {
//                    ZStack(alignment: .topLeading) {
//                        themes.theme.lineColor
//                            .frame(width: 1, height: 20)
//                            .offset(x: THREAD_LINE_OFFSET, y: -10)
//                            .opacity(connect == .top || connect == .both ? 1 : 0)
//                        themes.theme.lineColor
//                            .frame(width: 1)
//                            .offset(x: THREAD_LINE_OFFSET)
//                            .opacity(connect == .bottom || connect == .both ? 1 : 0)
//                    }
//                    .onTapGesture {
//                        navigateTo(nrPost)
//                    }
//                }
//            }
//        }
//        // tapGesture is in PostAndParent()
//    }
//}
