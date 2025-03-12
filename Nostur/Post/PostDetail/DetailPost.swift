//
//  DetailPost.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/03/2025.
//

import SwiftUI

struct DetailPost: View {
    @ObservedObject public var nrPost: NRPost
    @ObservedObject public var pfpAttributes: PFPAttributes
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var dim: DIMENSIONS
    @ObservedObject private var settings: SettingsStore = .shared
    @State private var showMiniProfile = false
    @State private var didStart = false
    
    init(nrPost: NRPost) {
        self.nrPost = nrPost
        self.pfpAttributes = nrPost.pfpAttributes
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment:.top, spacing: 10) {
                ZappablePFP(pubkey: nrPost.pubkey, pfpAttributes: pfpAttributes, size: DIMENSIONS.POST_ROW_PFP_WIDTH, zapEtag: nrPost.id, forceFlat: nrPost.isScreenshot)
                    .frame(width: DIMENSIONS.POST_ROW_PFP_WIDTH, height: 50)
                    .onTapGesture {
                        if !IS_APPLE_TYRANNY {
                            if let nrContact = nrPost.contact {
                                navigateTo(nrContact)
                            }
                            else {
                                navigateTo(ContactPath(key: nrPost.pubkey))
                            }
                        }
                        else {
                            withAnimation {
                                showMiniProfile = true
                            }
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
                    .background(alignment: .top) {
                        if nrPost.replyToId != nil {
                            themes.theme.lineColor
                                .frame(width: 1, height: 30)
                                .offset(x: -0.5, y: -20)
                        }
                    }
                
                VStack(alignment:.leading, spacing: 3) {
                    HStack(alignment: .top) {
                        NRPostHeaderContainer(nrPost: nrPost, singleLine: false)
                        Spacer()
                        EventPrivateNoteToggle(nrPost: nrPost)
                        LazyNoteMenuButton(nrPost: nrPost)
                    }
                }
            }
            .onAppear {
                guard nrPost.replyToId != nil else { return } // don't scroll if we already the root
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                    sendNotification(.scrollToDetail, nrPost.id)
                }
            }
            
            // We don't show "Replying to.." unless we can't fetch the parent
            if nrPost.replyTo == nil && nrPost.replyToId != nil {
                ReplyingToFragmentView(nrPost: nrPost, theme: themes.theme)
                    .padding(.top, 10)
            }
        
            switch nrPost.kind {
            case 20:
                VStack {
                    if nrPost.imageUrls.count > 1 {
                        ContentRenderer(nrPost: nrPost, isDetail: true, fullWidth: settings.fullWidthImages, availableWidth: dim.listWidth - 20, theme: themes.theme, didStart: $didStart)
                            .padding(.top, 10)
                    }
                    ForEach(nrPost.imageUrls.indices, id:\.self) { index in
                        let iMeta: iMetaInfo? = findImeta(nrPost.fastTags, url: nrPost.imageUrls[index].absoluteString) // TODO: More to NRPost.init?
                        
                        MediaContentView(
                            media: MediaContent(
                                url: nrPost.imageUrls[index],
                                dimensions: iMeta?.size,
                                blurHash: iMeta?.blurHash
                            ),
                            availableWidth: dim.listWidth,
                            placeholderHeight: dim.listWidth * (iMeta?.aspect ?? 1.0),
                            contentMode: .fill,
                            imageUrls: nrPost.imageUrls
                        )
                        .padding(.top, 10)
                        .padding(.horizontal, -10)
                    }
                    
                    if nrPost.imageUrls.count < 2 {
                        ContentRenderer(nrPost: nrPost, isDetail: true, fullWidth: settings.fullWidthImages, availableWidth: dim.listWidth - 20, theme: themes.theme, didStart: $didStart)
                            .padding(.vertical, 10)
                    }
                }
            case 30023:
                ArticleView(nrPost, isDetail: true, fullWidth: settings.fullWidthImages, hideFooter: false, theme: themes.theme)
                    .background(Color(.secondarySystemBackground))
            case 9802:
                HighlightRenderer(nrPost: nrPost, theme: themes.theme)
                    .padding(.top, 3)
                    .padding(.bottom, 10)
                    .padding(.horizontal, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
            case 1,6,9734:
                if nrPost.plainTextOnly {
                    NoteMinimalContentView(nrPost: nrPost, lineLimit: 350)
                }
                else {
//                    Text("case 1,6,9734: dim.listWidth: \(dim.listWidth - 20)")
                    ContentRenderer(nrPost: nrPost, isDetail: true, fullWidth: settings.fullWidthImages, availableWidth: dim.listWidth - 20, theme: themes.theme, didStart: $didStart)
                        .padding(.vertical, 10)
                }
            case 1063:
                if let fileMetadata = nrPost.fileMetadata {
                    Kind1063(nrPost, fileMetadata: fileMetadata, availableWidth: settings.fullWidthImages ? dim.listWidth : dim.availablePostDetailImageWidth(), theme: themes.theme)
                        .padding(.horizontal, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
                }
            case 99999:
                let title = nrPost.eventTitle ?? "Untitled"
                if let eventUrl = nrPost.eventUrl {
                    VideoEventView(title: title, url: eventUrl, summary: nrPost.eventSummary, imageUrl: nrPost.eventImageUrl, autoload: true, theme: themes.theme, availableWidth: dim.availablePostDetailImageWidth() - 20)
                        .padding(.vertical, 10)
                }
                else {
                    EmptyView()
            }
            default:
                UnknownKindView(nrPost: nrPost, theme: themes.theme)
                    .padding(.vertical, 10)
            }
            
            DetailFooterFragment(nrPost: nrPost)
                .padding(.top, 10)
            CustomizableFooterFragmentView(nrPost: nrPost, isDetail: true, theme: themes.theme)
                .padding(.vertical, 5)
                .preference(key: TabTitlePreferenceKey.self, value: nrPost.anyName)
        }
    }
}
