//
//  Kind30023.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/08/2024.
//

import SwiftUI
import MarkdownUI
import NostrEssentials

struct Kind30023: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    @Environment(\.theme) private var theme: Theme
    @Environment(\.containerID) private var containerID
    @Environment(\.availableWidth) private var availableWidth
    @ObservedObject private var settings: SettingsStore = .shared
    private let nrPost: NRPost
    @ObservedObject private var nrContact: NRContact
    
    private let hideFooter: Bool // For rendering in NewReply
    private let missingReplyTo: Bool // For rendering in thread
    private var connect: ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    private let isReply: Bool // is reply on PostDetail
    private let isDetail: Bool
    private let isEmbedded: Bool
    private let fullWidth: Bool
    private let grouped: Bool
    private let forceAutoload: Bool

    @State private var didLoad = false
    
    private let THREAD_LINE_OFFSET = 24.0
    
    private var imageWidth: CGFloat {
        availableWidth - 20
    }
    
    @State var showMiniProfile = false
    
    init(nrPost: NRPost, hideFooter: Bool = true, missingReplyTo: Bool = false, connect: ThreadConnectDirection? = nil, isReply: Bool = false, isDetail: Bool = false, isEmbedded: Bool = false, fullWidth: Bool, grouped: Bool = false, forceAutoload: Bool = false) {
        self.nrPost = nrPost
        self.nrContact = nrPost.contact
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.isReply = isReply
        self.fullWidth = fullWidth
        self.isDetail = isDetail
        self.isEmbedded = isEmbedded
        self.grouped = grouped
        self.forceAutoload = forceAutoload
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
        return !nrPost.isNSFW && (forceAutoload || SettingsStore.shouldAutodownload(nrPost) || nxViewingContext.contains(.screenshot))
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
                        PostMenuButton(nrPost: nrPost)
                    }
                    .padding(.vertical, 10)
                    
                    if let mostRecentId = nrPost.mostRecentId {
                        OpenLatestUpdateMessage {
                            navigateTo(ArticlePath(id: mostRecentId, navigationTitle: nrPost.eventTitle ?? "Article"), context: containerID)
                        }
                        .padding(.vertical, 10)
                    }
                    else if nrPost.flags == "is_update" {
                        Text("Last updated: \(nrPost.createdAt.formatted())")
                            .italic()
                            .padding(.vertical, 10)
                    }
                    
                    HStack {
                        ZappablePFP(pubkey: nrPost.pubkey, contact: nrContact, size: DIMENSIONS.POST_ROW_PFP_WIDTH, zapEtag: nrPost.id, forceFlat: nxViewingContext.contains(.screenshot))
                            .onTapGesture {
                                navigateToContact(pubkey: nrPost.pubkey, nrContact: nrContact, nrPost: nrPost, context: containerID)
                            }
                        VStack(alignment: .leading) {
                            HStack {
                                Text(nrContact.anyName)
                                    .foregroundColor(.primary)
                                    .fontWeight(.bold)
                                    .lineLimit(1)
                                    .layoutPriority(2)
                                    .onTapGesture {
                                        navigateTo(nrContact, context: containerID)
                                    }
                                
                                if nrContact.nip05verified, let nip05 = nrContact.nip05 {
                                    NostrAddress(nip05: nip05, shortened: nrContact.anyName.lowercased() == nrContact.nip05nameOnly?.lowercased())
                                        .layoutPriority(3)
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
                        //                        Text("imageWidth: \(availableWidth.description)")
                        MediaContentView(
                            galleryItem: GalleryItem(url: eventImageUrl),
                            availableWidth: availableWidth,
                            placeholderAspect: 2/1,
                            contentMode: .fit,
                            upscale: true,
                            autoload: true // is detail so we can force true
                        )
                        .padding(.vertical, 10)
                        .padding(.horizontal, -20)
                    }
                    
                    ContentRenderer(nrPost: nrPost, showMore: .constant(true), isDetail: true, fullWidth: true, forceAutoload: true)
                        .padding(.vertical, 10)
                    
                    if !hideFooter {
                        CustomizableFooterFragmentView(nrPost: nrPost)
                            .background(theme.secondaryBackground)
                            .drawingGroup(opaque: true)
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
                    
                    
                    // Fetch A direct or sub 1111 (new commments style)
                    nxReq(
                        Filters(
                            kinds: [1111],
                            tagFilter: TagFilter(tag: "A", values: [nrPost.aTag]),
                            limit: 500
                        ),
                        subscriptionId: "DETAIL-"+UUID().uuidString
                    )
                    
                    // Fetch A direct or sub 1111(new commments style) - REAL TIME UPDATES
                    nxReq(
                        Filters(
                            kinds: [1111],
                            tagFilter: TagFilter(tag: "A", values: [nrPost.aTag]),
                            since: NTimestamp(date: Date.now).timestamp
                        ),
                        subscriptionId: "REALTIME-DETAIL-22"
                    )
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
                PostMenuButton(nrPost: nrPost)
            }
            .padding(.bottom, 10)
            
            if let image = nrPost.eventImageUrl {
                MediaContentView(
                    galleryItem: GalleryItem(url: image),
                    availableWidth: availableWidth,
                    placeholderAspect: 2/1,
                    contentMode: .fit,
                    upscale: true,
                    autoload: forceAutoload,
                    isNSFW: nrPost.isNSFW
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
                        ZappablePFP(pubkey: nrPost.pubkey, contact: nrContact, size: 25.0, zapEtag: nrPost.id, forceFlat: nxViewingContext.contains(.screenshot))
                            .onTapGesture {
                                guard !nxViewingContext.contains(.preview) else { return }
                                navigateToContact(pubkey: nrPost.pubkey, nrContact: nrContact, nrPost: nrPost, context: containerID)
                            }

                        Text(nrContact.anyName)
                            .foregroundColor(.primary)
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .layoutPriority(2)
                            .onTapGesture {
                                guard !nxViewingContext.contains(.preview) else { return }
                                navigateTo(nrContact, context: containerID)
                            }
                        
                        if nrContact.nip05verified, let nip05 = nrContact.nip05 {
                            NostrAddress(nip05: nip05, shortened: nrContact.anyName.lowercased() == nrContact.nip05nameOnly?.lowercased())
                                .layoutPriority(3)
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
                            PFP(pubkey: nrPost.pubkey, nrContact: nrPost.contact, size: 25, forceFlat: nxViewingContext.contains(.screenshot))
                            
                            Text(nrContact.anyName)
                                .foregroundColor(.primary)
                                .fontWeight(.bold)
                                .lineLimit(1)
                                .layoutPriority(2)
                                .onTapGesture {
                                    guard !nxViewingContext.contains(.preview) else { return }
                                    navigateToContact(pubkey: nrContact.pubkey, nrContact: nrContact, context: containerID)
                                }
                                .onAppear {
                                    guard nrContact.metadata_created_at == 0 else { return }
                                    bg().perform {
                                        EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "ArticleView.001")
                                        QueuedFetcher.shared.enqueue(pTag: nrPost.pubkey)
                                    }
                                }
                                .onDisappear {
                                    guard nrContact.metadata_created_at == 0 else { return }
                                    QueuedFetcher.shared.dequeue(pTag: nrPost.pubkey)
                                }
                            
                            if nrContact.nip05verified, let nip05 = nrContact.nip05 {
                                NostrAddress(nip05: nip05, shortened: nrContact.anyName.lowercased() == nrContact.nip05nameOnly?.lowercased())
                                    .layoutPriority(3)
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
                        PFP(pubkey: nrPost.pubkey, nrContact: nrPost.contact, size: 25, forceFlat: nxViewingContext.contains(.screenshot))
                        Text(nrContact.anyName)
                            .foregroundColor(.primary)
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .layoutPriority(2)
                            .onTapGesture {
                                guard !nxViewingContext.contains(.preview) else { return }
                                navigateToContact(pubkey: nrContact.pubkey, nrContact: nrContact, context: containerID)
                            }
                        
                        if nrContact.nip05verified, let nip05 = nrContact.nip05 {
                            NostrAddress(nip05: nip05, shortened: nrContact.anyName.lowercased() == nrContact.nip05nameOnly?.lowercased())
                                .layoutPriority(3)
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
                CustomizableFooterFragmentView(nrPost: nrPost)
                    .background(theme.secondaryBackground)
                    .drawingGroup(opaque: true)
            }
        }
//            .padding(20)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !nxViewingContext.contains(.preview) else { return }
            navigateTo(nrPost, context: containerID)
        }
    }

    private var minutesToRead: Int {
        let wordCount = (nrPost.content ?? "").split(separator: " ").count
        return Int(ceil(Double(wordCount) / WORDS_PER_MINUTE))
    }
    
    private let WORDS_PER_MINUTE: Double = 200.0
}
