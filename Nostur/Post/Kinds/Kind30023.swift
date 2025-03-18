//
//  Kind30023.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/08/2024.
//

import SwiftUI
import MarkdownUI

struct Kind30023: View {
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
    private let isEmbedded: Bool
    private let fullWidth: Bool
    private let grouped: Bool
    private let forceAutoload: Bool
    @State private var didStart = false
    @State private var couldBeImposter: Int16 // TODO: this is here but also in NRPostHeaderContainer, need to clean up
    @State private var didLoad = false
    
    private let THREAD_LINE_OFFSET = 24.0
    
    private var imageWidth: CGFloat {
        dim.listWidth - 20
    }
    
    @State var showMiniProfile = false
    
    init(nrPost: NRPost, hideFooter: Bool = true, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil, isReply: Bool = false, isDetail: Bool = false, isEmbedded: Bool = false, fullWidth: Bool, grouped: Bool = false, forceAutoload: Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.pfpAttributes = nrPost.pfpAttributes
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.isReply = isReply
        self.fullWidth = fullWidth
        self.isDetail = isDetail
        self.isEmbedded = isEmbedded
        self.grouped = grouped
        self.theme = theme
        self.forceAutoload = forceAutoload
        self.couldBeImposter = nrPost.pfpAttributes.contact?.couldBeImposter ?? -1
    }
    
    var body: some View {
        if isEmbedded {
            self.embeddedView
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
        if isDetail {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(nrPost.eventTitle ?? "")
                            .font(.custom("Charter-Black", size: 28))
                        Spacer()
                        LazyNoteMenuButton(nrPost: nrPost)
                    }
                    .padding(.vertical, 10)
                    
                    if let mostRecentId = nrPost.mostRecentId {
                        OpenLatestUpdateMessage {
                            navigateTo(ArticlePath(id: mostRecentId, navigationTitle: nrPost.eventTitle ?? "Article"))
                        }
                        .padding(.vertical, 10)
                    }
                    else if nrPost.flags == "is_update" {
                        Text("Last updated: \(nrPost.createdAt.formatted())")
                            .italic()
                            .padding(.vertical, 10)
                    }
                    
                    HStack {
                        ZappablePFP(pubkey: nrPost.pubkey, pfpAttributes: nrPost.pfpAttributes, size: DIMENSIONS.POST_ROW_PFP_WIDTH, zapEtag: nrPost.id, forceFlat: dim.isScreenshot)
                            .onTapGesture {
                                if !IS_APPLE_TYRANNY {
                                    if let nrContact = nrPost.pfpAttributes.contact {
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
                        VStack(alignment: .leading) {
                            if let contact = nrPost.contact {
                                HStack {
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
                            HStack {
                                if minutesToRead > 0 {
                                    Text("\(minutesToRead) min read")
                                    Text("·")
                                }
                                Text((nrPost.eventPublishedAt ?? nrPost.createdAt).formatted(date: .abbreviated, time: .omitted))
                            }
                            .lineLimit(1)
                            .foregroundColor(Color.secondary)
                        }
                    }
                    .font(Font.custom("Charter", size: 22))
                    .padding(.vertical, 10)
                    
                    if let eventImageUrl = nrPost.eventImageUrl {
                        //                        Text("imageWidth: \(dim.listWidth.description)")
                        MediaContentView(
                            galleryItem: GalleryItem(url: eventImageUrl),
                            availableWidth: dim.listWidth,
                            placeholderAspect: 2/1,
                            contentMode: .fit,
                            upscale: true,
                            autoload: true // is detail so we can force true
                        )
                        .padding(.vertical, 10)
                        .padding(.horizontal, -20)
                    }
                    
                    ContentRenderer(nrPost: nrPost, isDetail: true, fullWidth: true, availableWidth: dim.listWidth, forceAutoload: true, theme: theme, didStart: $didStart)
                        .padding(.vertical, 10)
                    
                    if !hideFooter {
                        CustomizableFooterFragmentView(nrPost: nrPost, theme: theme)
                            .padding(.vertical, 10)
                    }
                }
                .padding(20)
            }
            .background(Color(.secondarySystemBackground))
            .preference(key: TabTitlePreferenceKey.self, value: nrPost.eventTitle ?? "")
            .onAppear {  // Similar to PostDetail/PostAndParent
                guard !didLoad else { return }
                didLoad = true
                
                bg().perform {
                    EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "ArticleView - isDetail")
                    if (!nrPost.missingPs.isEmpty) {
                        QueuedFetcher.shared.enqueue(pTags: nrPost.missingPs)
                    }
                    
                    // Fetch all related (e and p.kind=0)
                    // (the events and contacts mentioned in this DETAIL NOTE.
                    if let message = RequestMessage.getFastTags(nrPost.fastTags) {
                        req(message)
                    }
                    
                    // Fetch all that reference this detail note (Replies, zaps, reactions) - E:
                    req(RM.getEventReferences(ids: [nrPost.id], subscriptionId: "DETAIL-"+UUID().uuidString))
                    // Same but use the a-tag (proper) // TODO: when other clients handle replies to ParaReplaceEvents properly we can remove the old E fetching
                    
                    req(RM.getPREventReferences(aTag: nrPost.aTag, subscriptionId: "ROOT-"+UUID().uuidString))
                        
                    
                    
                    // REAL TIME UPDATES FOR ARTICLE DETAIL
                    req(RM.getEventReferences(ids: [nrPost.id], subscriptionId: "REALTIME-DETAIL", since: NTimestamp(date: Date.now)))
                    
                    // Same but use the a-tag (proper) // TODO: when other clients handle replies to ParaReplaceEvents properly we can remove the old E fetching
                    req(RM.getPREventReferences(aTag: nrPost.aTag, subscriptionId: "REALTIME-DETAIL-A", since: NTimestamp(date: Date.now)))
                }
            }
            .onDisappear {
                bg().perform {
                    if (!nrPost.missingPs.isEmpty) {
                        QueuedFetcher.shared.dequeue(pTags: nrPost.missingPs)
                    }
                }
            }
//            .navigationBarHidden(navTitleHidden)
        }
        else {
         
            smallContent
            
        }
    }
    
    @ViewBuilder
    private var embeddedView: some View {
        smallContent
            .padding(20)
            .background(
               Color(.secondarySystemBackground)
                .cornerRadius(15)
            )
            .overlay(
               RoundedRectangle(cornerRadius: 15)
                .stroke(.regularMaterial, lineWidth: 1)
            )

        
        
//            .padding(.horizontal, -10) // padding is all around (detail+parents) if article is parent we need to negate the padding
    }
    
    @ViewBuilder
    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment:.top, spacing: 0) {
                Text(nrPost.eventTitle ?? "")
                    .font(.custom("Charter-Black", size: 24))
                    .lineLimit(5)
                Spacer()
                LazyNoteMenuButton(nrPost: nrPost)
            }
            .padding(.bottom, 10)
            
            if let image = nrPost.eventImageUrl {
                MediaContentView(
                    galleryItem: GalleryItem(url: image),
                    availableWidth: dim.listWidth,
                    placeholderAspect: 2/1,
                    contentMode: .fit,
                    upscale: true,
                    autoload: forceAutoload
                )
                .padding(.horizontal, -20) // on article preview always use full width style
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .allowsHitTesting(false)
            }
            
            if let summary = nrPost.eventSummary, !summary.isEmpty {
                Markdown(String(summary.prefix(600)))
                    .lineLimit(15)
                    .markdownTextStyle() {
                        FontFamily(.custom("Charter"))
                        ForegroundColor(Color.primary)
                        FontSize(18)
                    }
                    .markdownTextStyle(\.link) {
                        ForegroundColor(theme.accent)
                    }
                    .markdownImageProvider(.noImage)
                    .markdownInlineImageProvider(.noImage)
                    .padding(.vertical, 10)
            }
            else if let content = nrPost.content, !content.isEmpty {
                Markdown(String(content.prefix(600)))
                    .lineLimit(15)
                    .markdownTextStyle() {
                        FontFamily(.custom("Charter"))
                        ForegroundColor(Color.primary)
                        FontSize(18)
                    }
                    .markdownTextStyle(\.link) {
                        ForegroundColor(theme.accent)
                    }
                    .markdownImageProvider(.noImage)
                    .markdownInlineImageProvider(.noImage)
                    .padding(.vertical, 10)
            }
            else {
                Text("")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            }
            
            if #available(iOS 16.0, *) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Spacer()
                        ZappablePFP(pubkey: nrPost.pubkey, pfpAttributes: nrPost.pfpAttributes, size: 25.0, zapEtag: nrPost.id, forceFlat: dim.isScreenshot)
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
                                        EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "nrPostView.001")
                                        QueuedFetcher.shared.enqueue(pTag: nrPost.pubkey)
                                    }
                                }
                                .onDisappear {
                                    QueuedFetcher.shared.dequeue(pTag: nrPost.pubkey)
                                }
                        }
                        if minutesToRead > 0 {
                            Text("\(minutesToRead) min read")
                            Text("·")
                        }
                        Text((nrPost.eventPublishedAt ?? nrPost.createdAt).formatted(date: .abbreviated, time: .omitted))
                    }
                    .font(.custom("Charter", size: 18))
                    .padding(.vertical, 10)
                    .lineLimit(1)
                    .foregroundColor(Color.secondary)
                    
                    VStack {
                        HStack {
                            Spacer()
                            PFP(pubkey: nrPost.pubkey, nrContact: nrPost.contact, size: 25, forceFlat: dim.isScreenshot)
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
                        HStack {
                            Spacer()
                            if minutesToRead > 0 {
                                Text("\(minutesToRead) min read")
                                Text("·")
                            }
                            Text((nrPost.eventPublishedAt ?? nrPost.createdAt).formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                    .font(.custom("Charter", size: 18))
                    .padding(.vertical, 10)
                    .lineLimit(1)
                    .foregroundColor(Color.secondary)
                }
            }
            else {
                VStack {
                    HStack {
                        Spacer()
                        PFP(pubkey: nrPost.pubkey, nrContact: nrPost.contact, size: 25, forceFlat: dim.isScreenshot)
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
                    HStack {
                        Spacer()
                        if minutesToRead > 0 {
                            Text("\(minutesToRead) min read")
                            Text("·")
                        }
                        Text((nrPost.eventPublishedAt ?? nrPost.createdAt).formatted(date: .abbreviated, time: .omitted))
                    }
                }
                .font(.custom("Charter", size: 18))
                .padding(.vertical, 10)
                .lineLimit(1)
                .foregroundColor(Color.secondary)
            }
            
            if !hideFooter {
                CustomizableFooterFragmentView(nrPost: nrPost, theme: theme)
            }
        }
//            .padding(20)
        .contentShape(Rectangle())
        .onTapGesture {
            navigateTo(nrPost)
        }
    }
    
    private func navigateToContact() {
        if let nrContact = nrPost.contact {
            navigateTo(nrContact)
        }
        else {
            navigateTo(ContactPath(key: nrPost.pubkey))
        }
    }
    
    private func navigateToPost() {
        navigateTo(nrPost)
    }
    
    private var minutesToRead: Int {
        let wordCount = (nrPost.content ?? "").split(separator: " ").count
        return Int(ceil(Double(wordCount) / WORDS_PER_MINUTE))
    }
    
    private let WORDS_PER_MINUTE: Double = 200.0
}
