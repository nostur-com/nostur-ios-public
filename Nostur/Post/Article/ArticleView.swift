//
//  ArticleView.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/06/2023.
//

import SwiftUI
import MarkdownUI

struct ArticleView: View {
    @EnvironmentObject private var theme:Theme
    @EnvironmentObject private var dim:DIMENSIONS
    @ObservedObject private var article:NRPost
    private var isParent = false
    private var isDetail:Bool = false
    private var fullWidth:Bool = false
    private var hideFooter:Bool = false
    private var navTitleHidden:Bool = false
    
    init(_ article:NRPost, isParent:Bool = false, isDetail:Bool = false, fullWidth:Bool = false, hideFooter:Bool = false, navTitleHidden:Bool = false) {
        self.article = article
        self.isParent = isParent
        self.isDetail = isDetail
        self.fullWidth = fullWidth
        self.hideFooter = hideFooter
        self.navTitleHidden = navTitleHidden
    }
    
    private let WORDS_PER_MINUTE:Double = 200.0
    
    private var minutesToRead:Int {
        let wordCount = (article.content ?? "").split(separator: " ").count
        return Int(ceil(Double(wordCount) / WORDS_PER_MINUTE))
    }
    
    @State private var showMiniProfile = false
    @State private var didLoad = false
    
    var body: some View {
        if isDetail {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(article.articleTitle ?? "")
                            .font(.custom("Charter-Black", size: 28))
                        Spacer()
                        LazyNoteMenuButton(nrPost: article)
                    }
                    .padding(.vertical, 10)
                    
                    if let mostRecentId = article.mostRecentId {
                        OpenLatestUpdateMessage {
                            navigateTo(ArticlePath(id: mostRecentId, navigationTitle: article.articleTitle ?? "Article"))
                        }
                        .padding(.vertical, 10)
                    }
                    else if article.flags == "is_update" {
                        Text("Last updated: \(article.createdAt.formatted())")
                            .italic()
                            .padding(.vertical, 10)
                    }
                    
                    HStack {
                        ZappablePFP(pubkey: article.pubkey, contact: article.contact, size: DIMENSIONS.POST_ROW_PFP_WIDTH, zapEtag: article.id)
                            .onTapGesture {
                                if !IS_APPLE_TYRANNY {
                                    if let nrContact = article.pfpAttributes.contact {
                                        navigateTo(nrContact)
                                    }
                                    else {
                                        navigateTo(ContactPath(key: article.pubkey))
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
                                                                    pubkey: article.pubkey,
                                                                    contact: article.contact,
                                                                    zapEtag: article.id,
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
                            if let contact = article.contact {
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
                                Text(article.anyName)
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
                                if minutesToRead > 0 {
                                    Text("\(minutesToRead) min read")
                                    Text("·")
                                }
                                Text((article.articlePublishedAt ?? article.createdAt).formatted(date: .abbreviated, time: .omitted))
                            }
                            .lineLimit(1)
                            .foregroundColor(Color.secondary)
                        }
                    }
                    .font(Font.custom("Charter", size: 22))
                    .padding(.vertical, 10)
                    
                    if let image = article.articleImageURL {
                        //                        Text("imageWidth: \(dim.listWidth.description)")
                        SingleMediaViewer(url: image, pubkey: article.pubkey, imageWidth: dim.listWidth, fullWidth: true, autoload: true, contentPadding: 20, contentMode: .aspectFill, upscale: true)
                            .padding(.vertical, 10)
                        //                            .padding(.horizontal, -20)
                    }
                    
                    ContentRenderer(nrPost: article, isDetail: true, fullWidth: true, availableWidth: dim.listWidth)
                        .padding(.vertical, 10)
                    
                    if !hideFooter {
                        FooterFragmentView(nrPost: article)
                            .padding(.vertical, 10)
                    }
                }
                .padding(20)
                
                if (!isParent) {
                    ThreadReplies(nrPost: article)
                }
            }
            .background(Color(.secondarySystemBackground))
            .preference(key: TabTitlePreferenceKey.self, value: article.articleTitle ?? "")
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
                    req(RM.getPREventReferences(aTag: article.event.aTag, subscriptionId: "ROOT-"+UUID().uuidString))
                    
                    
                    // REAL TIME UPDATES FOR ARTICLE DETAIL
                    req(RM.getEventReferences(ids: [article.id], subscriptionId: "REALTIME-DETAIL", since: NTimestamp(date: Date.now)))
                    
                    // Same but use the a-tag (proper) // TODO: when other clients handle replies to ParaReplaceEvents properly we can remove the old E fetching
                    req(RM.getPREventReferences(aTag: article.event.aTag, subscriptionId: "REALTIME-DETAIL-A", since: NTimestamp(date: Date.now)))
                }
            }
            .onDisappear {
                bg().perform {
                    if (!article.missingPs.isEmpty) {
                        QueuedFetcher.shared.dequeue(pTags: article.missingPs)
                    }
                }
            }
            .simultaneousGesture(
                   DragGesture().onChanged({
                       if 0 < $0.translation.height {
                           sendNotification(.scrollingUp)
                       }
                       else if 0 > $0.translation.height {
                           sendNotification(.scrollingDown)
                       }
                   }))
            .navigationBarHidden(navTitleHidden)
        }
        else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment:.top, spacing: 0) {
                    Text(article.articleTitle ?? "")
                        .font(.custom("Charter-Black", size: 24))
                        .lineLimit(5)
                    Spacer()
                    LazyNoteMenuButton(nrPost: article)
                }
                .padding(.bottom, 10)
                
                if let image = article.articleImageURL {
                    SingleMediaViewer(url: image, pubkey: article.pubkey, imageWidth: dim.listWidth, fullWidth: true, autoload: (article.following || !SettingsStore.shared.restrictAutoDownload), contentMode: .aspectFill, upscale: true)
                        .frame(minHeight: 100)
                        .padding(.horizontal, -20) // on article preview always use full width style
                        .padding(.vertical, 10)
                }
                
                if let summary = article.articleSummary, !summary.isEmpty {
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
                
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Spacer()
                        ZappablePFP(pubkey: article.pubkey, contact: article.contact, size: 25.0, zapEtag: article.id)
                            .onTapGesture {
                                if !IS_APPLE_TYRANNY {
                                    if let nrContact = article.contact {
                                        navigateTo(nrContact)
                                    }
                                    else {
                                        navigateTo(ContactPath(key: article.pubkey))
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
                                                                    pubkey: article.pubkey,
                                                                    contact: article.contact,
                                                                    zapEtag: article.id,
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
                        if let contact = article.contact {
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
                            Text(article.anyName)
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
                        if minutesToRead > 0 {
                            Text("\(minutesToRead) min read")
                            Text("·")
                        }
                        Text((article.articlePublishedAt ?? article.createdAt).formatted(date: .abbreviated, time: .omitted))
                    }
                    .font(.custom("Charter", size: 18))
                    .padding(.vertical, 10)
                    .lineLimit(1)
                    .foregroundColor(Color.secondary)
                    
                    VStack {
                        HStack {
                            Spacer()
                            PFP(pubkey: article.pubkey, nrContact: article.contact, size: 25)
                            if let contact = article.contact {
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
                                Text(article.anyName)
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
                        }
                        HStack {
                            Spacer()
                            if minutesToRead > 0 {
                                Text("\(minutesToRead) min read")
                                Text("·")
                            }
                            Text((article.articlePublishedAt ?? article.createdAt).formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                    .font(.custom("Charter", size: 18))
                    .padding(.vertical, 10)
                    .lineLimit(1)
                    .foregroundColor(Color.secondary)
                }
                
                if !hideFooter {
                    FooterFragmentView(nrPost: article)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                navigateTo(article)
            }
        }
    }
}

struct ArticleCommentsPreview: View {
    let article:NRPost
    var body: some View {
        Text("PFP's here (max 10)")
            .onTapGesture {
                navigateTo(ArticleCommentsPath(article: article))
            }
    }
}

struct ArticleCommentsView: View {
    let article:NRPost
    var body: some View {
        ThreadReplies(nrPost: article)
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
                NavigationStack {
                    ArticleView(NRPost(event: article), isDetail: true)
                }
            }
            
            // Article with images (preview + inline, gifs)
            //            if let p = try? PreviewFetcher.fetchNRPost("b5637dfb45cf71e4f84bed9235cf7c57dd839c75459432b0d2394ed850f4301a")
            //            {
            //                NavigationStack {
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
            SmoothListMock {
                if let p = PreviewFetcher.fetchNRPost("12c29454fc1f995eb6e08a97f91dff37f891d1de130fbb333b5976f2cca99395") {
                    Box(nrPost: p) {
                        PostRowDeletable(nrPost: p, fullWidth: true)
                    }
                    
                    Box(nrPost: p) {
                        PostRowDeletable(nrPost: p)
                    }
                        
                }
            }
            
        }
    }
}

// - MARK: ARTICLE STUFF
extension Event {
    
    var articleId:String? {
        fastTags.first(where: { $0.0 == "d" })?.1
    }
    
    var articleTitle:String? {
        fastTags.first(where: { $0.0 == "title" })?.1
    }
    
    var articleSummary:String? {
        fastTags.first(where: { $0.0 == "summary" })?.1
    }
    
    var articlePublishedAt:Date? {
        if let p = fastTags.first(where: { $0.0 == "published_at" })?.1, let timestamp = TimeInterval(p) {
            if timestamp > 1000000000000 { // fix for buggy clients using microseconds for published_at
                return Date(timeIntervalSince1970: timestamp / 1000)
            }
            return Date(timeIntervalSince1970: timestamp)
        }
        return nil
    }
    
    var articleImage:String? {
        fastTags.first(where: { $0.0 == "image" })?.1
    }
}





