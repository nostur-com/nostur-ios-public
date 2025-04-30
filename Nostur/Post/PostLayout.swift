//
//  PostLayout.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/03/2025.
//

import SwiftUI

struct PostLayout<Content: View, TitleContent: View>: View {
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
    private let forceAutoload: Bool
    private let isItem: Bool  // true to put more emphasis on the item when it is not a text post
    
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

    private let content: Content
    private let titleContent: TitleContent
    
    
    init(nrPost: NRPost, hideFooter: Bool = true, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil, isReply: Bool = false, isDetail: Bool = false, fullWidth: Bool = true, forceAutoload: Bool = false, isItem: Bool = false, theme: Theme, @ViewBuilder content: () -> Content, @ViewBuilder title: () -> TitleContent) {
        self.nrPost = nrPost
        self.pfpAttributes = nrPost.pfpAttributes
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.isReply = isReply
        self.fullWidth = fullWidth
        self.isDetail = isDetail
        self.theme = theme
        self.forceAutoload = forceAutoload
        self.isItem = isItem
        self.content = content()
        self.titleContent = title()
    }
    
    var body: some View {
        //        #if DEBUG
        //        let _ = Self._printChanges()
        //        #endif
        if isDetail || fullWidth {
            fullWidthLayout
        }
        else {
            normalLayout
        }
    }
    
    @ViewBuilder
    private var normalLayout: some View {
        HStack(alignment: .top, spacing: 10) {
            if !isItem {
                regularPFP
            }
            
            VStack(alignment: .leading, spacing: 3) { // Post container
                if isItem {
                    titleContent
                }
                else {
                    HStack(alignment: .top) { // name + reply + context menu
                        NRPostHeaderContainer(nrPost: nrPost)
                        Spacer()
                        LazyNoteMenuButton(nrPost: nrPost)
                    }
                }
                
                content
                
                if isItem {
                    bottomAuthorInfo
                }
                // No need for DetailFooterFragment here because .isDetail will always be in .fullWidthLayout
                
                if (!hideFooter && settings.rowFooterEnabled) && !isItem { // also no footer for items (only in Detail)
                    CustomizableFooterFragmentView(nrPost: nrPost, theme: theme, isItem: isItem)
                        .background(nrPost.kind == 30023 ? theme.secondaryBackground : theme.listBackground)
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
    private var fullWidthLayout: some View {
        VStack(spacing: 10) {
            
            HStack(alignment: .center, spacing: 10) {
                if isItem {
                    titleContent
                }
                else {
                    regularPFP
                    NRPostHeaderContainer(nrPost: nrPost, singleLine: false)
                }
                
                if !isItem || isDetail {
                    Spacer()
                    LazyNoteMenuButton(nrPost: nrPost)
                }
            }
            
            VStack(alignment:.leading, spacing: 3) {// Post container
                
                content
                
                if isItem {
                    bottomAuthorInfo
                }
                
                if isDetail {
                    DetailFooterFragment(nrPost: nrPost)
                        .padding(.top, 10)
                }
                
                if isDetail || ((!hideFooter && settings.rowFooterEnabled) && !isItem) {
                    CustomizableFooterFragmentView(nrPost: nrPost, isDetail: true, theme: theme, isItem: isItem)
                        .background(nrPost.kind == 30023 ? theme.secondaryBackground : theme.listBackground)
                        .drawingGroup(opaque: true)
                }
            }
        }
    }
    
    
    @ViewBuilder
    private var regularPFP: some View {
        if SettingsStore.shared.enableLiveEvents && LiveEventsModel.shared.livePubkeys.contains(nrPost.pubkey) {
            LiveEventPFP(pubkey: nrPost.pubkey, pfpAttributes: pfpAttributes, size: DIMENSIONS.POST_ROW_PFP_WIDTH, forceFlat: nrPost.isScreenshot)
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
                        if liveEvent.isLiveKit && (IS_CATALYST || IS_IPAD) { // Always do nests in tab on ipad/desktop
                            navigateTo(liveEvent)
                        }
                        else {
                            // LOAD NEST
                            if liveEvent.isLiveKit {
                                LiveKitVoiceSession.shared.activeNest = liveEvent
                            }
                            // ALREADY PLAYING IN .OVERLAY, TOGGLE TO .DETAILSTREAM
                            else if AnyPlayerModel.shared.nrLiveEvent?.id == liveEvent.id {
                                AnyPlayerModel.shared.viewMode = .detailstream
                            }
                            // LOAD NEW .DETAILSTREAM
                            else {
                                Task {
                                    await AnyPlayerModel.shared.loadLiveEvent(nrLiveEvent: liveEvent, availableViewModes: [.detailstream, .overlay, .audioOnlyBar])
                                }
                            }
                        }
                    }
                }
        }
        else {
            ZappablePFP(pubkey: nrPost.pubkey, pfpAttributes: pfpAttributes, size: DIMENSIONS.POST_ROW_PFP_WIDTH, zapEtag: nrPost.id, zapAtag: nrPost.aTag, forceFlat: nrPost.isScreenshot)
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
    }
    
    @ViewBuilder
    private var itemPFP: some View { // No live event animation for item PFP
        ZappablePFP(pubkey: nrPost.pubkey, pfpAttributes: pfpAttributes, size: 20.0, zapEtag: nrPost.id, zapAtag: nrPost.aTag, forceFlat: nrPost.isScreenshot)
            .frame(width: 20.0, height: 20.0)
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
    
    
    @ViewBuilder
    private var bottomAuthorInfo: some View {
        HStack(spacing: 3) {
            Spacer()
            
            Text("by")
                .foregroundColor(theme.secondary)
                .padding(.trailing, 5)
            
            itemPFP
            
            if let contact = nrPost.contact {
                Text(contact.anyName)
                    .foregroundColor(.primary)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .layoutPriority(2)
                    .onTapGesture {
                        navigateTo(contact)
                    }
                
                if contact.nip05verified, let nip05 = contact.nip05 {
                    NostrAddress(nip05: nip05, shortened: contact.anyName.lowercased() == contact.nip05nameOnly.lowercased())
                        .layoutPriority(3)
                }
            }
            else {
                Text(nrPost.anyName)
                    .onAppear {
                        bg().perform {
                            EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "ArticleView.001")
                            QueuedFetcher.shared.enqueue(pTag: nrPost.pubkey)
                        }
                    }
                    .onDisappear {
                        QueuedFetcher.shared.dequeue(pTag: nrPost.pubkey)
                    }
            }
        }
        .padding(.vertical, 10)
        .lineLimit(1)
    }
}

// Makes optional title possible in: PostLayout { } title: { }

extension PostLayout where TitleContent == EmptyView {
    
    init(nrPost: NRPost, hideFooter: Bool = true, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil, isReply: Bool = false, isDetail: Bool = false, fullWidth: Bool = true, forceAutoload: Bool = false, isItem: Bool = false, theme: Theme, @ViewBuilder content: () -> Content) {
     
        self.init(nrPost: nrPost, hideFooter: hideFooter, missingReplyTo: missingReplyTo, connect: connect, isReply: isReply, isDetail: isDetail, fullWidth: fullWidth, forceAutoload: forceAutoload, isItem: isItem, theme: theme, content: content, title: { EmptyView() })
        
    }
}
