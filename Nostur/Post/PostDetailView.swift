//
//  PostDetailView.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/02/2023.
//

import SwiftUI
import CoreData
import NavigationBackport

struct NoteById: View {
    @EnvironmentObject private var themes: Themes
    public let id: String
    public var navTitleHidden: Bool = false
    @StateObject private var vm = FetchVM<NRPost>(timeout: 2.5, debounceTime: 0.05)
    
    var body: some View {
        switch vm.state {
        case .initializing, .loading, .altLoading:
            ProgressView()
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .center)
                .onAppear { [weak vm] in
                    let fetchParams: FetchVM.FetchParams = (
                        prio: true,
                        req: { [weak vm] taskId in
                            bg().perform {
                                guard let vm else { return }
                                if let event = try? Event.fetchEvent(id: self.id, context: bg()) {
                                    vm.ready(NRPost(event: event, withFooter: false))
                                }
                                else {
                                    req(RM.getEvent(id: self.id, subscriptionId: taskId))
                                }
                            }
                        },
                        onComplete: { [weak vm] relayMessage, event in
                            guard let vm else { return }
                            if let event = event {
                                vm.ready(NRPost(event: event, withFooter: false))
                            }
                            else if let event = try? Event.fetchEvent(id: self.id, context: bg()) {
                                vm.ready(NRPost(event: event, withFooter: false))
                            }
                            else if [.initializing, .loading].contains(vm.state) {
                                // try search relays
                                vm.altFetch()
                            }
                            else {
                                vm.timeout()
                            }
                        },
                        altReq: { taskId in
                            // Try search relays
                            req(RM.getEvent(id: self.id, subscriptionId: taskId), relayType: .SEARCH)
                        }
                    )
                    vm?.setFetchParams(fetchParams)
                    vm?.fetch()
                }
        case .ready(let nrPost):
            if nrPost.kind == 30023 {
                ArticleView(nrPost, isDetail: true, fullWidth: SettingsStore.shared.fullWidthImages, hideFooter: false, theme: themes.theme)
            }
            else {
                PostDetailView(nrPost: nrPost, navTitleHidden: navTitleHidden)
            }
        case .timeout:
            Text("Unable to fetch")
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .center)
        case .error(let error):
            Text(error)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

struct PostDetailView: View {
    @EnvironmentObject private var themes: Themes
    private let nrPost: NRPost
    private var navTitleHidden: Bool = false
    @State private var didLoad = false
    @State private var didScroll = false
    
    init(nrPost: NRPost, navTitleHidden: Bool = false) {
        self.nrPost = nrPost
        self.navTitleHidden = navTitleHidden
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 10) { // 10 for space between (parents+detail) and replies
                        PostAndParent(nrPost: nrPost,  navTitleHidden:navTitleHidden)
                        
                            // Around parents + detail (not replies)
                            .padding(10)
                            .background(themes.theme.background)
                        
                        if (nrPost.kind == 443) {
                            Text("Comments on \(nrPost.fastTags.first(where: { $0.0 == "r" } )?.1.replacingOccurrences(of: "https://", with: "") ?? "...")")
                                .fontWeightBold()
                                .navigationTitle("Comments on \(nrPost.fastTags.first(where: { $0.0 == "r" } )?.1.replacingOccurrences(of: "https://", with: "") ?? "...")")
                                
                        }
                        
                        // MARK: REPLIES TO OUR MAIN POST
                        if (nrPost.kind == 443) {
                            // SPECIAL HANDLING FOR WEBSITE COMMENTS
                            WebsiteComments(nrPost: nrPost)
                        }
                        else {
                            // NORMAL REPLIES TO A POST
                            ThreadReplies(nrPost: nrPost)
                        }
                    }
                    .background(themes.theme.listBackground)
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
                .onAppear {
                    guard !didLoad else { return }
                    didLoad = true
                    
                    // If we navigated to this post by opening it from an embedded
                    nrPost.footerAttributes.loadFooter()
                    // And maybe we don't have parents so:
                    nrPost.loadParents()
                    
                }
                .onReceive(receiveNotification(.scrollToDetail)) { notification in
                    guard !didScroll else { return }
                    let detailId = notification.object as! String
                    didScroll = true
                    withAnimation {
                        proxy.scrollTo(detailId, anchor: .top)
                    }
                }
                .navigationTitleIf(nrPost.kind != 443, title: nrPost.replyToId != nil ? String(localized:"Thread", comment:"Navigation title when viewing a Thread") : String(localized:"Post.noun", comment: "Navigation title when viewing a Post"))
                          
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarHidden(navTitleHidden)
            }
        }
            .nosturNavBgCompat(themes: themes)
            .background(themes.theme.listBackground)
    }
}

extension View {
    @ViewBuilder
    func navigationTitleIf(_ condition: Bool, title: String) -> some View {
        if condition {
            self.navigationTitle(title)
        }
        else {
            self
        }
    }
}

let THREAD_LINE_OFFSET = 24.0

// Renders reply, and parent
// the parent is another PostAndParent
// so it recursively renders up to the root
struct PostAndParent: View {
    @EnvironmentObject private var themes:Themes
    @ObservedObject private var nrPost:NRPost
    @EnvironmentObject private var dim:DIMENSIONS
    
    private var navTitleHidden:Bool = false
    
    private var isParent = false
    private var connect:ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    private let INDENT = DIMENSIONS.POST_ROW_PFP_WIDTH + DIMENSIONS.POST_PFP_SPACE
    
    @ObservedObject private var settings:SettingsStore = .shared
    @State private var timerTask: Task<Void, Never>?
    @State private var didLoad = false
    @State private var didFetchParent = false
    
    init(nrPost: NRPost, isParent:Bool = false, navTitleHidden:Bool = false, connect:ThreadConnectDirection? = nil) {
        self.nrPost = nrPost
        self.isParent = isParent
        self.navTitleHidden = navTitleHidden
        self.connect = connect
    }
    
    var body: some View {
//        let _ = Self._printChanges()
        VStack(spacing: 10) {
            // MARK: PARENT NOTE
            // We have the event: replyTo_ = already .replyTo or lazy fetched with .replyToId
            if let replyTo = nrPost.replyTo {
                if replyTo.deletedById == nil {
                    switch replyTo.kind {
                    case 9735:
                        if let zap = replyTo.mainEvent, let zapFrom = zap.zapFromRequest {
                            ZapReceipt(sats: zap.naiveSats, receiptPubkey: zap.pubkey, fromPubkey: zapFrom.pubkey, from: zapFrom)
                        }
                    case 0,3,4,5,7,1984,9734,30009,8,30008:
                        KnownKindView(nrPost: replyTo, theme: themes.theme)
                        
                    case 30023:
                        ArticleView(replyTo, isParent:true, isDetail: true, fullWidth: true, theme: themes.theme)
                            .padding(.horizontal, -10) // padding is all around (detail+parents) if article is parent we need to negate the padding
                            .background(Color(.secondarySystemBackground))
                        
                    case 443:
                        URLView(nrPost: replyTo, theme: themes.theme)
                            .navigationTitle("Comments on \(nrPost.fastTags.first(where: { $0.0 == "r" } )?.1.replacingOccurrences(of: "https://", with: "") ?? "...")")
                        
                        Text("Comments on \(replyTo.fastTags.first(where: { $0.0 == "r" } )?.1.replacingOccurrences(of: "https://", with: "") ?? "...")")
                            .fontWeightBold()
                            .padding(.top, 10)
                            .padding(.bottom, 10)
                            .frame(maxWidth: .infinity)
                            .background(themes.theme.listBackground)
                            .padding(.horizontal, -10)
                        
                        HStack(spacing: 0) {
                            self.replyButton
                                .foregroundColor(themes.theme.footerButtons)
                                .padding(.leading, 10)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard let event = nrPost.event else { return }
                                    sendNotification(.createNewReply, EventNotification(event: event))
                                }
                            Spacer()
                        }
                        .padding(.bottom, 15)
                        .background(themes.theme.listBackground)
                        .padding(.top, -10)
                        .padding(.horizontal, -10)
                    default:
                        let connect:ThreadConnectDirection? = replyTo.replyToId != nil ? .both : .bottom
                        PostAndParent(nrPost: replyTo, isParent: true, connect: connect)
//                            .padding(10)
                            .background(themes.theme.background)
                    }
                }
                else {
                    Text("_Post deleted by author_", comment: "Message shown when a post is deleted")
                        .hCentered()
                }
            }
            else if let replyToId = nrPost.replyToId {
                CenteredProgressView()
                    .onAppear {
                        guard !didFetchParent else { return }
                        didFetchParent = true
                        
                        bg().perform {
                            EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "PostDetailView.001")
                        }
                        QueuedFetcher.shared.enqueue(id: replyToId)
                        
                        timerTask = Task {
                            do {
                                try await Task.sleep(nanoseconds: UInt64(4) * NSEC_PER_SEC)
                                if nrPost.replyTo == nil {
                                    // try search relays
                                    req(RM.getEvent(id: replyToId), relayType: .SEARCH)
                                    // try relay hint
                                    fetchEventFromRelayHint(replyToId, fastTags: nrPost.fastTags)
                                }
                            }
                            catch { }
                        }
                    }
                    .background(themes.theme.background)
                    .onDisappear {
                        timerTask?.cancel()
                        timerTask = nil
                    }
            }
            // OUR (DETAIL) REPLY:
            // MARK: DETAIL NOTE
            VStack(alignment: .leading, spacing: 0) {
                if nrPost.deletedById == nil {
                    switch nrPost.kind {
                    case 0,3,4,5,7,1984,9734,9735,30009,8,30008:
                        KnownKindView(nrPost: nrPost, hideFooter: true, theme: themes.theme)
                        DetailFooterFragment(nrPost: nrPost)
                            .padding(.top, 10)
                        CustomizableFooterFragmentView(nrPost: nrPost, isDetail: true, theme: themes.theme)
                            .padding(.vertical, 5)
                            .preference(key: TabTitlePreferenceKey.self, value: nrPost.anyName)
                    case 443:
                        URLView(nrPost: nrPost, theme: themes.theme)
                    default:
                        if isParent {
                            ParentPost(nrPost: nrPost, connect:connect)
                                .fixedSize(horizontal: false, vertical: true) // Needed or we get whitespace, equal height posts
                                .background(
                                    themes.theme.background
                                        .onTapGesture {
                                            navigateTo(nrPost)
                                        }
                                )
                        }
                        else if nrPost.isRepost { // who opens a repost in detail?
                            Repost(nrPost: nrPost, hideFooter: false, missingReplyTo: false, connect: .none, fullWidth: false, isReply: false, isDetail: true, grouped: false, theme: themes.theme)
                        }
                        else {
                            DetailPost(nrPost: nrPost)
                                .fixedSize(horizontal: false, vertical: true) // Needed or we get whitespace, equal height posts
                                .id(nrPost.id)
                                .padding(.top, 10) // So the focused post is not glued to top after scroll, so you can still see .replyTo connecting line
                                .preference(key: TabTitlePreferenceKey.self, value: nrPost.anyName)
                        }
                    }
                }
                else {
                    Text("_Post deleted by \(nrPost.anyName)_", comment: "Message shown when a post is deleted by (name)")
                        .hCentered()
                }
            }
            .id(nrPost.id)
            .onAppear {
                guard !nrPost.plainTextOnly else { L.og.info("plaintext enabled, probably spam") ; return }
                guard !didLoad else { return }
                didLoad = true
                nrPost.loadReplyTo()
                
                bg().perform {
                    EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "PostDetailView.003")
                    if (!nrPost.missingPs.isEmpty) {
                        QueuedFetcher.shared.enqueue(pTags: nrPost.missingPs)
                    }
                    
                    if (!isParent) {
                        
                        // Fetch all related (e and p.kind=0)
                        // (the events and contacts mentioned in this DETAIL NOTE.
                        if let message = RequestMessage.getFastTags(nrPost.fastTags) {
                            req(message)
                        }
                        
                        // Fetch all that reference this detail note (Replies, zaps, reactions)
                        req(RM.getEventReferences(ids: [nrPost.id], subscriptionId: "DETAIL-"+UUID().uuidString))
                        // REAL TIME UPDATES FOR POST DETAIL
                        req(RM.getEventReferences(ids: [nrPost.id], subscriptionId: "REALTIME-DETAIL", since: NTimestamp(date: Date.now)))
                        
                        if let replyToRootId = nrPost.replyToRootId {
                            // Fetch all that reference the root note
                            // to build the thread, maybe kind=1 is enough, or all...?
                            req(RM.getEventReferences(ids: [replyToRootId], subscriptionId: "ROOT-"+UUID().uuidString, kinds:[1]))
                        }
                    }
                }
            }
            .onDisappear {
                bg().perform {
                    if (!nrPost.missingPs.isEmpty) {
                        QueuedFetcher.shared.dequeue(pTags: nrPost.missingPs)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var replyButton: some View {
        Image("ReplyIcon")
        Text("Add comment")
    }
}

struct ParentPost: View {
    @ObservedObject private var nrPost:NRPost
    @ObservedObject private var postRowDeletableAttributes:NRPost.PostRowDeletableAttributes
    @ObservedObject private var settings:SettingsStore = .shared
    @EnvironmentObject private var dim:DIMENSIONS
    @EnvironmentObject private var themes:Themes
    private let INDENT = DIMENSIONS.POST_ROW_PFP_WIDTH + DIMENSIONS.POST_PFP_SPACE
    private var connect:ThreadConnectDirection? = nil
    @State private var showMiniProfile = false
    @State private var didStart = false
    
    init(nrPost: NRPost, connect: ThreadConnectDirection? = nil) {
        self.nrPost = nrPost
        self.postRowDeletableAttributes = nrPost.postRowDeletableAttributes
        self.connect = connect
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if postRowDeletableAttributes.blocked {
                HStack {
                    Text("_Post from blocked account hidden_", comment: "Message shown when a post is from a blocked account")
                    Button(String(localized: "Reveal", comment: "Button to reveal a blocked a post")) { nrPost.blocked = false }
                        .buttonStyle(.bordered)
                }
                .padding(.leading, 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .padding(.vertical, 20)
            }
            else {
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        HStack(alignment:.top, spacing: 10) {
                            ZappablePFP(pubkey: nrPost.pubkey, contact: nrPost.contact, size: DIMENSIONS.POST_ROW_PFP_WIDTH, zapEtag: nrPost.id)
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
                            
                            VStack(alignment:.leading, spacing: 3) {
                                HStack(alignment: .top) {
                                    NoteHeaderView(nrPost: nrPost, singleLine: true)
                                    Spacer()
                                    EventPrivateNoteToggle(nrPost: nrPost)
                                    LazyNoteMenuButton(nrPost: nrPost)
                                        .offset(y: -5)
                                }
                                
                                // We don't show "Replying to.." unless we can't fetch the parent
                                if nrPost.replyTo == nil && nrPost.replyToId != nil {
                                    ReplyingToFragmentView(nrPost: nrPost, theme: themes.theme)
                                    //                                .padding(.trailingx, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
                                }
                                
                                switch nrPost.kind {
                                case 30023:
                                    ArticleView(nrPost, isDetail: false, fullWidth: settings.fullWidthImages, hideFooter: false, theme: themes.theme)
                                        .padding(.horizontal, -10) // padding is all around (detail+parents) if article is parent we need to negate the padding
                                        .padding(.bottom, 10)
                                        .background(Color(.secondarySystemBackground))
                                case 9802: // highlight
                                    HighlightRenderer(nrPost: nrPost, theme: themes.theme)
                                        .padding(.vertical, 10)
                                    //                                .padding(.trailingx, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
                                case 1,6,9734: // text, repost, zap request
                                    ContentRenderer(nrPost: nrPost, isDetail: false, availableWidth: dim.availablePostDetailRowImageWidth() - 20, theme: themes.theme, didStart: $didStart)
                                    //                                .padding(.trailingx, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
                                case 1063: // File Metadata
                                    NoteTextRenderView(nrPost: nrPost, theme: themes.theme)
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
                            }
                        }
                        
                        if (settings.rowFooterEnabled) {
                            CustomizableFooterFragmentView(nrPost: nrPost, theme: themes.theme)
                                .padding(.leading, INDENT)
                                .padding(.vertical, 5)
                            //                        .padding(.trailingx, 10)
                        }
                    }
                }
                .background(alignment:.topLeading) {
                    ZStack(alignment: .topLeading) {
                        themes.theme.lineColor.opacity(0.2)
                            .frame(width: 2, height: 20)
                            .offset(x: THREAD_LINE_OFFSET, y: -10)
                            .opacity(connect == .top || connect == .both ? 1 : 0)
                        themes.theme.lineColor.opacity(0.2)
                            .frame(width: 2)
                            .offset(x: THREAD_LINE_OFFSET)
                            .opacity(connect == .bottom || connect == .both ? 1 : 0)
                    }
                    .onTapGesture {
                        navigateTo(nrPost)
                    }
                }
            }
        }
        // tapGesture is in PostAndParent()
    }
}

struct DetailPost: View {
    @ObservedObject public var nrPost:NRPost
    
    @EnvironmentObject private var themes:Themes
    @EnvironmentObject private var dim:DIMENSIONS
    @ObservedObject private var settings:SettingsStore = .shared
    @State private var showMiniProfile = false
    @State private var didStart = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment:.top, spacing: 10) {
                ZappablePFP(pubkey: nrPost.pubkey, contact: nrPost.contact, size: DIMENSIONS.POST_ROW_PFP_WIDTH, zapEtag: nrPost.id, forceFlat: nrPost.isScreenshot)
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
                                .opacity(0.2)
                                .frame(width: 2, height: 30)
                                .offset(y: -20)
                        }
                    }
                
                VStack(alignment:.leading, spacing: 3) {
                    HStack(alignment: .top) {
                        NoteHeaderView(nrPost: nrPost, singleLine: false)
                        Spacer()
                        EventPrivateNoteToggle(nrPost: nrPost)
                        LazyNoteMenuButton(nrPost: nrPost)
                    }
                }
            }
            .onAppear {
                guard nrPost.parentPosts.count > 0 else { return } // don't scroll if we already the root
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
                    ContentRenderer(nrPost: nrPost, isDetail: true, fullWidth: settings.fullWidthImages, availableWidth: settings.fullWidthImages ? dim.listWidth : (dim.availablePostDetailImageWidth() - (20)), theme: themes.theme, didStart: $didStart)
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

#Preview("Kind1063detail") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadKind1063()
    }) {
        NBNavigationStack {
            if let kind1063 = PreviewFetcher.fetchNRPost("ac0c2960db29828ee4a818337ea56df990d9ddd9278341b96c9fb530b4c4dce8") {
                PostDetailView(nrPost:kind1063)
            }
        }
    }
}

#Preview("Kind1063detailQuoted") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadKind1063()
    }) {
        NBNavigationStack {
            if let kind1063q = PreviewFetcher.fetchNRPost("71a965d8e8546f8927cea23ad865a429dbec0215f36c5e0edad2323eb00f4851") {
                PostDetailView(nrPost:kind1063q)
            }
        }
    }
}

#Preview("ReplyAndParentView") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.parseMessages([
            ###"["EVENT","485cefc1-2f85-402e-a136-691557f322c8",{"content":"https://youtube.com/shorts/cZenQR8tgV8?feature=share\n\nIf even _she_ is speaking out about Canada's new bill C-11, it's bad. She's a 100% mainstream comedian who got her start during lockdown.","created_at":1680327426,"id":"5988f18416a6d2702a61df9dedc318f18d0d5778a020464222138edab386eee7","kind":1,"pubkey":"ccaa58e37c99c85bc5e754028a718bd46485e5d3cb3345691ecab83c755d48cc","sig":"efad8bf0580ee6a36f6ebd48ab3fba940d9fdc5d5fcf866b6d609ac52c1b24a7acb16277890ea770a8d4328018c1ec7b7ef84e7ffa19b8f9929a36300adc4b33","tags":[["r","https://youtube.com/shorts/cZenQR8tgV8?feature=share"]]}]"###,
            ###"["EVENT","16dbd7e2-af00-4c7d-9258-f5413d75b95f",{"content":"The fact thay she thinks an “amendment to protect digital creators” makes the bill ok is so childishly naive it hurts. ","created_at":1680333364,"id":"5e80b08b76e81e549c4554e161dfeb67a09da859e4706a989876a5ec42016d9a","kind":1,"pubkey":"b9e76546ba06456ed301d9e52bc49fa48e70a6bf2282be7a1ae72947612023dc","sig":"5c31c120473800d878a5391ad2055b20404a4d97d20c08116f0931737559aea7d8e26febf64f4e24385c637d1e8b84ede32ca498a75190b0aaaba3821ac1bd3a","tags":[["e","5988f18416a6d2702a61df9dedc318f18d0d5778a020464222138edab386eee7"],["p","ccaa58e37c99c85bc5e754028a718bd46485e5d3cb3345691ecab83c755d48cc"]]}]"###,
            ###"["EVENT","a2533e43-5968-40dd-a986-131e839cbb84",{"content":"Her being publicly against it at all is a win. And the amendment was cancelled.","created_at":1680333872,"id":"a4508aa658b12d51a56613c51da096d7791eb207d3b11407089c633ff73f668d","kind":1,"pubkey":"ccaa58e37c99c85bc5e754028a718bd46485e5d3cb3345691ecab83c755d48cc","sig":"a1a46a31a1d11175cfc8452210b436d731f3b8615254ec51063f4124a250cc544e40ab54899b243f7637c5778f093d869a6b9f54e1e30f9b9245c07d6df37b9f","tags":[["e","5988f18416a6d2702a61df9dedc318f18d0d5778a020464222138edab386eee7"],["e","5e80b08b76e81e549c4554e161dfeb67a09da859e4706a989876a5ec42016d9a"],["p","ccaa58e37c99c85bc5e754028a718bd46485e5d3cb3345691ecab83c755d48cc"],["p","b9e76546ba06456ed301d9e52bc49fa48e70a6bf2282be7a1ae72947612023dc"]]}]"###])
    }) {
        NBNavigationStack {
            if let xx = PreviewFetcher.fetchNRPost("a4508aa658b12d51a56613c51da096d7791eb207d3b11407089c633ff73f668d") {
                PostDetailView(nrPost: xx)
            }
        }
    }
}

#Preview("YouTubePreviewInDetail") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
    }) {
        NBNavigationStack {
            if let yt2 = PreviewFetcher.fetchNRPost("0000014de66e08882bd36b6b7b551a774f85fe752a18070dc8658d7776db7e69") {
                PostDetailView(nrPost: yt2)
            }
            
        }
    }
}

#Preview("YouTubeInDetail") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.parseMessages([
            ###"["EVENT","e24e08cc-9e36-4a54-8a33-1d1fc84ae95c",{"content":"https://youtu.be/QU9kRF9tHPU","created_at":1681073179,"id":"c7b4ef377ee4f6d71f6f59bc6bad607acb9c7c3675e3c0b2ca0ad2442b133e49","kind":1,"pubkey":"82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2","sig":"2bec825a1db31653187d221b69965e992a28d5a0913aa286c89fa23606fc41f4ad7b146a4844a136ba2865566c958b509e544c6620e25f329f239a7be0d6f87b","tags":[]}]"###]
        )
    }) {
        NBNavigationStack {
            if let yt = PreviewFetcher.fetchNRPost("c7b4ef377ee4f6d71f6f59bc6bad607acb9c7c3675e3c0b2ca0ad2442b133e49") {
                ScrollView {
                    PostDetailView(nrPost: yt)
                }
            }
            
        }
    }
}

#Preview("ReplyAndParent4") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadRepliesAndReactions()
    }) {
        NBNavigationStack {
            if let v = PreviewFetcher.fetchNRPost("bb15e6165180d31c36b6c3e0baf082eeb949aa473c59e37eaa8e2bb29dc46422") {
                PostDetailView(nrPost: v)
            }
            
        }
    }
}

#Preview("ReplyAndParent5") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadRepliesAndReactions()
    }) {
        NBNavigationStack {
            if let lastReply = PreviewFetcher.fetchNRPost("2026c6b0f0d887aa76cc60f0b3050fe940c8eca9eb479391acb493bb40e4d964") {
                PostDetailView(nrPost: lastReply)
            }
            
        }
    }
}

#Preview("ReplyAndParentView6_Previews") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadRepliesAndReactions()
    }) {
        NBNavigationStack {
            if let rootWithReplies = PreviewFetcher.fetchNRPost("6f74b952991bb12b61de7c5891706711e51c9e34e9f120498d32226f3c1f4c81") {
                PostDetailView(nrPost: rootWithReplies)
            }
        }
    }
}

#Preview("ReplyAndParentView7_Previews") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadRepliesAndReactions()
    }) {
        NBNavigationStack {
            if let v = PreviewFetcher.fetchNRPost("c0d76c3c968775a62ca1dea28a73e1fc86d121e8e5e17f2e35aaad1436075f51") {
                PostDetailView(nrPost: v)
            }
        }
    }
}

#Preview("BetterReplies_Previews") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadRepliesAndReactions()
    }) {
        NBNavigationStack {
            if let matt = PreviewFetcher.fetchNRPost("e593fc759291a691cd0127643a0b9fac9d92613952845e207eb24332937c59d9") {
                PostDetailView(nrPost: matt)
            }
        }
    }
}
