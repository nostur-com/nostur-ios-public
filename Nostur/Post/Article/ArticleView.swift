//
//  ArticleView.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/06/2023.
//

import SwiftUI
import MarkdownUI
import NavigationBackport
import NostrEssentials

struct ArticleView: View {
    @Environment(\.theme) private var theme
    @Environment(\.nxViewingContext) private var nxViewingContext
    @Environment(\.containerID) private var containerID
    @Environment(\.availableWidth) private var availableWidth
    @ObservedObject private var article: NRPost
    @ObservedObject private var nrContact: NRContact

    private var isDetail: Bool = false
    private var fullWidth: Bool = false
    private var hideFooter: Bool = false
    private var navTitleHidden: Bool = false
    private var forceAutoload: Bool
    
    init(_ article: NRPost, isDetail: Bool = false, fullWidth: Bool = false, hideFooter: Bool = false, navTitleHidden: Bool = false, forceAutoload: Bool = false) {
        self.article = article
        self.nrContact = article.contact
        self.isDetail = isDetail
        self.fullWidth = fullWidth
        self.hideFooter = hideFooter
        self.navTitleHidden = navTitleHidden
        self.forceAutoload = forceAutoload
    }
    
    private let WORDS_PER_MINUTE: Double = 200.0
    
    private var minutesToRead: Int {
        let wordCount = (article.content ?? "").split(separator: " ").count
        return Int(ceil(Double(wordCount) / WORDS_PER_MINUTE))
    }
    
    @State private var showMiniProfile = false
    @State private var didLoad = false
    
    private var shouldAutoload: Bool { // Only for non-detail view. On detail we force show images.
        !article.isNSFW && (forceAutoload || SettingsStore.shouldAutodownload(article) || nxViewingContext.contains(.screenshot))
    }
    
    var body: some View {
        if isDetail {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(article.eventTitle ?? "")
                            .font(.custom("Charter-Black", size: 28))
                        Spacer()
                        PostMenuButton(nrPost: article, theme: theme)
                    }
                    .padding(.vertical, 10)
                    
                    if let mostRecentId = article.mostRecentId {
                        OpenLatestUpdateMessage {
                            navigateTo(ArticlePath(id: mostRecentId, navigationTitle: article.eventTitle ?? "Article"), context: containerID)
                        }
                        .padding(.vertical, 10)
                    }
                    else if article.flags == "is_update" {
                        Text("Last updated: \(article.createdAt.formatted())")
                            .italic()
                            .padding(.vertical, 10)
                    }
                    
                    HStack {
                        ZappablePFP(pubkey: article.pubkey, size: DIMENSIONS.POST_ROW_PFP_WIDTH, zapEtag: article.id, forceFlat: nxViewingContext.contains(.screenshot))
                            .onTapGesture {
                                navigateToContact(pubkey: article.pubkey, nrContact: article.contact, context: containerID)
                            }
                        VStack(alignment: .leading) {
                            
                            HStack {
                                Text(nrContact.anyName)
                                    .foregroundColor(.primary)
                                    .fontWeight(.bold)
                                    .lineLimit(1)
                                    .layoutPriority(2)
                                    .onTapGesture {
                                        navigateToContact(pubkey: nrContact.pubkey, nrContact: nrContact, context: containerID)
                                    }
                                
                                if nrContact.nip05verified, let nip05 = nrContact.nip05 {
                                    NostrAddress(nip05: nip05, shortened: nrContact.anyName.lowercased() == nrContact.nip05nameOnly?.lowercased())
                                        .layoutPriority(3)
                                }
                            }
                            .onAppear {
                                guard nrContact.metadata_created_at == 0 else { return }
                                bg().perform {
                                    EventRelationsQueue.shared.addAwaitingEvent(article.event, debugInfo: "ArticleView.001")
                                    QueuedFetcher.shared.enqueue(pTag: article.pubkey)
                                }
                            }
                            .onDisappear {
                                guard nrContact.metadata_created_at == 0 else { return }
                                QueuedFetcher.shared.dequeue(pTag: article.pubkey)
                            }
                    
                            HStack {
                                if minutesToRead > 0 {
                                    Text("\(minutesToRead) min read")
                                    Text("·")
                                }
                                Text((article.eventPublishedAt ?? article.createdAt).formatted(date: .abbreviated, time: .omitted))
                            }
                            .lineLimit(1)
                            .foregroundColor(Color.secondary)
                        }
                    }
                    .font(Font.custom("Charter", size: 22))
                    .padding(.vertical, 10)
                    
                    if let eventImageUrl = article.eventImageUrl {
                        //                        Text("imageWidth: \(availableWidth.description)")
                        MediaContentView(
                            galleryItem: GalleryItem(url: eventImageUrl, pubkey: article.pubkey, eventId: article.id),
                            availableWidth: availableWidth,
                            placeholderAspect: 2/1,
                            contentMode: .fit,
                            upscale: true,
                            autoload: true // is detail so we can force true
                        )
                        .padding(.vertical, 10)
                        .padding(.horizontal, -20)
                    }
                    
                    ContentRenderer(nrPost: article, showMore: .constant(true), isDetail: true, fullWidth: true, forceAutoload: true)
                        .padding(.vertical, 10)
                    
                    if !hideFooter {
                        CustomizableFooterFragmentView(nrPost: article, theme: theme)
                            .background(theme.secondaryBackground)
                            .drawingGroup(opaque: true)
                            .padding(.vertical, 10)
                    }
                }
                .padding(20)
                
                if (!nxViewingContext.contains(.postParent)) {
                    ThreadReplies(nrPost: article)
                        .environment(\.nxViewingContext, [.selectableText, .postReply, .detailPane])
                }
            }
            .background(Color(.secondarySystemBackground))
            .preference(key: TabTitlePreferenceKey.self, value: article.eventTitle ?? "")
            .onAppear {  // Similar to PostDetail/PostAndParent
                guard !didLoad else { return }
                didLoad = true
                
                bg().perform {
                    EventRelationsQueue.shared.addAwaitingEvent(article.event, debugInfo: "ArticleView - isDetail")
                    if (!article.missingPs.isEmpty) {
                        QueuedFetcher.shared.enqueue(pTags: article.missingPs)
                    }
                    
                    // Fetch all related (e and p.kind=0)
                    // (the events and contacts mentioned in this DETAIL NOTE.
                    if let message = RequestMessage.getFastTags(article.fastTags) {
                        req(message)
                    }
                    
                    // Fetch all that reference this detail note (Replies, zaps, reactions) - E:
                    req(RM.getEventReferences(ids: [article.id], subscriptionId: "DETAIL-"+UUID().uuidString))
                    // Same but use the a-tag (proper) // TODO: when other clients handle replies to ParaReplaceEvents properly we can remove the old E fetching
                    
                    req(RM.getPREventReferences(aTag: article.aTag, subscriptionId: "ROOT-"+UUID().uuidString))
                        
                    
                    
                    // REAL TIME UPDATES FOR ARTICLE DETAIL
                    req(RM.getEventReferences(ids: [article.id], subscriptionId: "REALTIME-DETAIL", since: NTimestamp(date: Date.now)))
                    
                    // Same but use the a-tag (proper) // TODO: when other clients handle replies to ParaReplaceEvents properly we can remove the old E fetching
                    req(RM.getPREventReferences(aTag: article.aTag, subscriptionId: "REALTIME-DETAIL-A", since: NTimestamp(date: Date.now)))
                    
                    // Fetch A direct or sub 1111 (new commments style)
                    nxReq(
                        Filters(
                            kinds: [1111,1244],
                            tagFilter: TagFilter(tag: "A", values: [article.aTag]),
                            limit: 500
                        ),
                        subscriptionId: "DETAIL-"+UUID().uuidString
                    )
                    
                    // Fetch A direct or sub 1111(new commments style) - REAL TIME UPDATES
                    nxReq(
                        Filters(
                            kinds: [1111,1244],
                            tagFilter: TagFilter(tag: "A", values: [article.aTag]),
                            since: NTimestamp(date: Date.now).timestamp
                        ),
                        subscriptionId: "REALTIME-DETAIL-22",
                    )
                }
            }
            .onDisappear {
                bg().perform {
                    if (!article.missingPs.isEmpty) {
                        QueuedFetcher.shared.dequeue(pTags: article.missingPs)
                    }
                }
            }
            .navigationBarHidden(navTitleHidden)
        }
        else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment:.top, spacing: 0) {
                    Text(article.eventTitle ?? "")
                        .font(.custom("Charter-Black", size: 24))
                        .lineLimit(5)
                    Spacer()
                    PostMenuButton(nrPost: article, theme: theme)
                }
                .padding(.bottom, 10)
                
                if let image = article.eventImageUrl {
                    MediaContentView(
                        galleryItem: GalleryItem(url: image, pubkey: article.pubkey, eventId: article.id),
                        availableWidth: availableWidth,
                        placeholderAspect: 2/1,
                        contentMode: .fit,
                        upscale: true,
                        autoload: shouldAutoload
                    )
                    .padding(.horizontal, -20) // on article preview always use full width style
                    .padding(.vertical, 10)
                }
                
                if let summary = article.eventSummary, !summary.isEmpty {
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
                else if let content = article.content, !content.isEmpty {
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
                            ZappablePFP(pubkey: article.pubkey, contact: article.contact, size: 25.0, zapEtag: article.id, forceFlat: nxViewingContext.contains(.screenshot))
                                .onTapGesture {
                                    guard !nxViewingContext.contains(.preview) else { return }
                                    navigateToContact(pubkey: article.pubkey, nrContact: article.contact, context: containerID)
                                }
                            
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
                                        EventRelationsQueue.shared.addAwaitingEvent(article.event, debugInfo: "ArticleView.001")
                                        QueuedFetcher.shared.enqueue(pTag: article.pubkey)
                                    }
                                }
                                .onDisappear {
                                    guard nrContact.metadata_created_at == 0 else { return }
                                    QueuedFetcher.shared.dequeue(pTag: article.pubkey)
                                }
                            
                            if nrContact.nip05verified, let nip05 = nrContact.nip05 {
                                NostrAddress(nip05: nip05, shortened: nrContact.anyName.lowercased() == nrContact.nip05nameOnly?.lowercased())
                                    .layoutPriority(3)
                            }

                            if minutesToRead > 0 {
                                Text("\(minutesToRead) min read")
                                Text("·")
                            }
                            Text((article.eventPublishedAt ?? article.createdAt).formatted(date: .abbreviated, time: .omitted))
                        }
                        .font(.custom("Charter", size: 18))
                        .padding(.vertical, 10)
                        .lineLimit(1)
                        .foregroundColor(Color.secondary)
                        
                        VStack {
                            HStack {
                                Spacer()
                                PFP(pubkey: article.pubkey, nrContact: article.contact, size: 25, forceFlat: nxViewingContext.contains(.screenshot))
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
                                            EventRelationsQueue.shared.addAwaitingEvent(article.event, debugInfo: "ArticleView.001")
                                            QueuedFetcher.shared.enqueue(pTag: article.pubkey)
                                        }
                                    }
                                    .onDisappear {
                                        guard nrContact.metadata_created_at == 0 else { return }
                                        QueuedFetcher.shared.dequeue(pTag: article.pubkey)
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
                                Text((article.eventPublishedAt ?? article.createdAt).formatted(date: .abbreviated, time: .omitted))
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
                            PFP(pubkey: article.pubkey, nrContact: article.contact, size: 25, forceFlat: nxViewingContext.contains(.screenshot))
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
                                    bg().perform {
                                        EventRelationsQueue.shared.addAwaitingEvent(article.event, debugInfo: "ArticleView.001")
                                        QueuedFetcher.shared.enqueue(pTag: article.pubkey)
                                    }
                                }
                                .onDisappear {
                                    QueuedFetcher.shared.dequeue(pTag: article.pubkey)
                                }
                        }
                        HStack {
                            Spacer()
                            if minutesToRead > 0 {
                                Text("\(minutesToRead) min read")
                                Text("·")
                            }
                            Text((article.eventPublishedAt ?? article.createdAt).formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                    .font(.custom("Charter", size: 18))
                    .padding(.vertical, 10)
                    .lineLimit(1)
                    .foregroundColor(Color.secondary)
                }
                
                if !hideFooter {
                    CustomizableFooterFragmentView(nrPost: article, theme: theme)
                        .background(theme.secondaryBackground)
                        .drawingGroup(opaque: true)
                }
            }
//            .padding(20)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !nxViewingContext.contains(.preview) else { return }
                navigateTo(article, context: containerID)
            }
        }
    }
}

struct ArticleCommentsView: View {
    let article:NRPost
    var body: some View {
        ThreadReplies(nrPost: article)
            .environment(\.nxViewingContext, [.selectableText, .postReply, .detailPane])
    }
}

struct ArticleView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadArticles()
        }) {
            //            let test0 = "naddr1qqyxvepkv33nxdmrqgsrhuxx8l9ex335q7he0f09aej04zpazpl0ne2cgukyawd24mayt8grqsqqqa28qjqkz8"
            //            let test1 = "naddr1qqxnzd3cxyerxd3h8qerwwfcqgsgydql3q4ka27d9wnlrmus4tvkrnc8ftc4h8h5fgyln54gl0a7dgsrqsqqqa28qy28wumn8ghj7un9d3shjtnyv9kh2uewd9hszrthwden5te0dehhxtnvdakqvtl0f3"
            
            // Welcome to Nostr
            let test2 = "naddr1qqxnzd3cxy6rjv3hx5cnyde5qy88wumn8ghj7mn0wvhxcmmv9uq3uamnwvaz7tmwdaehgu3dwp6kytnhv4kxcmmjv3jhytnwv46z7qg3waehxw309ahx7um5wgh8w6twv5hszymhwden5te0danxvcmgv95kutnsw43z7qglwaehxw309ahx7um5wgkhyetvv9ujumn0ddhhgctjduhxxmmd9upzql6u9d8y3g8flm9x8frtz0xmsfyf7spq8xxkpgs8p2tge25p346aqvzqqqr4gukz494x"
            
            if let naddr = try? ShareableIdentifier(test2),
               let kind = naddr.kind,
               let pubkey = naddr.pubkey,
               let definition = naddr.eventId,
               let article = Event.fetchReplacableEvent(kind,
                                                             pubkey: pubkey,
                                                             definition: definition,
                                                             context: DataProvider.shared().viewContext)
            {
                NBNavigationStack {
                    ArticleView(NRPost(event: article), isDetail: true)
                }
            }
            
            // Article with images (preview + inline, gifs)
            //            if let p = try? PreviewFetcher.fetchNRPost("b5637dfb45cf71e4f84bed9235cf7c57dd839c75459432b0d2394ed850f4301a")
            //            {
            //                NBNavigationStack {
            //                    ArticleView(p, isDetail: true)
            //                }
            //            }
            
        }
    }
}

struct Articles_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadArticles()
        }) {
            PreviewFeed {
                if let p = PreviewFetcher.fetchNRPost("12c29454fc1f995eb6e08a97f91dff37f891d1de130fbb333b5976f2cca99395") {
                    Box(nrPost: p) {
                        PostRowDeletable(nrPost: p, fullWidth: true, theme: Themes.default.theme)
                    }
                    
                    Box(nrPost: p) {
                        PostRowDeletable(nrPost: p, theme: Themes.default.theme)
                    }
                        
                }
            }
            
        }
    }
}

// - MARK: ARTICLE STUFF
extension Event {
    
    var eventId: String? {
        fastTags.first(where: { $0.0 == "d" })?.1
    }
    
    var eventTitle: String? {
        fastTags.first(where: { $0.0 == "title" })?.1
    }
    
    var eventSummary: String? {
        fastTags.first(where: { $0.0 == "summary" })?.1
    }
    
    var eventPublishedAt: Date? {
        if let p = fastTags.first(where: { $0.0 == "published_at" })?.1, let timestamp = TimeInterval(p) {
            if timestamp > 1000000000000 { // fix for buggy clients using microseconds for published_at
                return Date(timeIntervalSince1970: timestamp / 1000)
            }
            return Date(timeIntervalSince1970: timestamp)
        }
        return nil
    }
    
    var eventImage: String? {
        fastTags.first(where: { $0.0 == "image" })?.1
    }
    
    var eventThumb: String? {
        fastTags.first(where: { $0.0 == "thumb" })?.1
    }
    
    var eventUrl: String? {
        fastTags.first(where: { $0.0 == "url" })?.1
    }
}





