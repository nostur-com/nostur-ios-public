//
//  PostDetailView.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/02/2023.
//

import SwiftUI
import CoreData

struct NoteById: View {
    
    let sp:SocketPool = .shared
    
    var id:String
    
    @FetchRequest
    var events:FetchedResults<Event>
    
    @State var nrPost:NRPost? = nil
    
    init(id:String) {
        self.id = id
        
        _events = FetchRequest(
            sortDescriptors: [],
            predicate: NSPredicate(format: "id == %@", id)
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if let nrPost {
                PostDetailView(nrPost: nrPost)
            }
            else if (events.first != nil) {
                ProgressView()
                    .task {
                        if let event = events.first, let bgEvent = event.toBG() {
                            DataProvider.shared().bg.perform {
                                let nrPost = NRPost(event: bgEvent, withReplies: true)
                                
                                DispatchQueue.main.async {
                                    self.nrPost = nrPost
                                }
                            }
                        }
                    }
            }
            else {
                Text("Trying to fetch...", comment: "Message shown when trying to fetch a post")
                    .onAppear {
                        L.og.info("🟢 NoteById.onAppear no event so REQ.1: \(id)")
                        req(RM.getEventAndReferences(id: id))
                    }
            }
        }
    }
}

struct PostDetailView: View {
    @EnvironmentObject var theme:Theme
    let nrPost:NRPost
    var navTitleHidden:Bool = false
    @State var didLoad = false
    @State var didScroll = false
    
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
                            .background(theme.background)
                        
                            
                        
                        // MARK: REPLIES TO OUR MAIN NOTE
                        ThreadReplies(nrPost: nrPost)
                    }
                    .background(theme.listBackground)
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
                }
                .onReceive(receiveNotification(.scrollToDetail)) { notification in
                    guard !didScroll else { return }
                    let detailId = notification.object as! String
                    didScroll = true
                    withAnimation {
                        proxy.scrollTo(detailId, anchor: .top)
                    }
                }
                .navigationTitle(nrPost.replyToId != nil ? String(localized:"Thread", comment:"Navigation title when viewing a Thread") : String(localized:"Post.noun", comment: "Navigation title when viewing a Post"))
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarHidden(navTitleHidden)
            }
        }
    }
}

let THREAD_LINE_OFFSET = 24.0

// Renders reply, and parent
// the parent is another PostAndParent
// so it recursively renders up to the root
struct PostAndParent: View {
    @EnvironmentObject var theme:Theme
    var sp:SocketPool = .shared
    @ObservedObject var nrPost:NRPost
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var dim:DIMENSIONS
    
    var navTitleHidden:Bool = false
    
    var isParent = false
    var connect:ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    let INDENT = DIMENSIONS.POST_ROW_PFP_WIDTH + DIMENSIONS.POST_PFP_SPACE
    
    @ObservedObject var settings:SettingsStore = .shared
    @State private var timerTask: Task<Void, Never>?
    @State var didLoad = false
    
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
                    
                    if replyTo.kind == 30023 {
                        ArticleView(replyTo, isParent:true, isDetail: true, fullWidth: true)
                            .padding(.horizontal, -10) // padding is all around (detail+parents) if article is parent we need to negate the padding
                            .background(Color(.secondarySystemBackground))
                    }
                    else {
                        let connect:ThreadConnectDirection? = replyTo.replyToId != nil ? .both : .bottom
                        PostAndParent(nrPost: replyTo, isParent: true, connect: connect)
//                            .padding(10)
                            .background(theme.background)
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
                        guard !didLoad else { return }
                        didLoad = true
                        timerTask = Task {
                            try? await Task.sleep(for: .seconds(4))
                            fetchEventFromRelayHint(replyToId, fastTags: nrPost.fastTags)
                        }
                        EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "PostDetailView.001")
                        QueuedFetcher.shared.enqueue(id: replyToId)
                    }
                    .background(theme.background)
                    .onDisappear {
                        timerTask?.cancel()
                        timerTask = nil
                    }
            }
            // OUR (DETAIL) REPLY:
            // MARK: DETAIL NOTE
            VStack(alignment: .leading, spacing: 0) {
                if nrPost.deletedById == nil {
                    if isParent {
                        ParentPost(nrPost: nrPost, connect:connect)
                            .background(
                                theme.background
                                    .onTapGesture {
                                        navigateTo(nrPost)
                                    }
                            )
                    }
                    else {
                        DetailPost(nrPost: nrPost)
                            .id(nrPost.id)
                            .padding(.top, 10) // So the focused post is not glued to top after scroll, so you can still see .replyTo connecting line
                            .preference(key: TabTitlePreferenceKey.self, value: nrPost.anyName)
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
                
                DataProvider.shared().bg.perform {
                    EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "PostDetailView.003")
                    if (!nrPost.missingPs.isEmpty) {
                        QueuedFetcher.shared.enqueue(pTags: nrPost.missingPs)
                    }
                    
                    if (!isParent) {
                        
                        // Fetch all related (e and p.kind=0)
                        // (the events and contacts mentioned in this DETAIL NOTE.
                        if let message = RequestMessage.getFastTags(nrPost.fastTags) {
                            sp.sendMessage(ClientMessage(type: .REQ, message: message))
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
                DataProvider.shared().bg.perform {
                    if (!nrPost.missingPs.isEmpty) {
                        QueuedFetcher.shared.dequeue(pTags: nrPost.missingPs)
                    }
                }
            }
        }
    }
}

struct ParentPost: View {
    @ObservedObject var nrPost:NRPost
    @ObservedObject var postRowDeletableAttributes:NRPost.PostRowDeletableAttributes
    @ObservedObject var settings:SettingsStore = .shared
    @EnvironmentObject var dim:DIMENSIONS
    @EnvironmentObject var theme:Theme
    let INDENT = DIMENSIONS.POST_ROW_PFP_WIDTH + DIMENSIONS.POST_PFP_SPACE
    var connect:ThreadConnectDirection? = nil
    @State var showMiniProfile = false
    
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
                            ReplyingToFragmentView(nrPost: nrPost)
//                                .padding(.trailingx, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
                        }
                        
                        switch nrPost.kind {
                        case 30023:
                            ArticleView(nrPost, isDetail: false, fullWidth: settings.fullWidthImages, hideFooter: false)
                                .padding(.horizontal, -10) // padding is all around (detail+parents) if article is parent we need to negate the padding
                                .padding(.bottom, 10)
                                .background(Color(.secondarySystemBackground))
                        case 9802: // highlight
                            HighlightRenderer(nrPost: nrPost)
                                .padding(.vertical, 10)
//                                .padding(.trailingx, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
                        case 1,6,9734: // text, repost, zap request
                            ContentRenderer(nrPost: nrPost, isDetail: false, availableWidth: dim.availablePostDetailRowImageWidth() - 20)
//                                .padding(.trailingx, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
                        case 1063: // File Metadata
                            NoteTextRenderView(nrPost: nrPost)
                        default:
                            Label(String(localized:"kind \(Double(nrPost.kind).clean) type not (yet) supported", comment: "Message shown when a post kind (X) is not yet supported"), systemImage: "exclamationmark.triangle.fill")
                                .centered()
                                .frame(maxWidth: .infinity)
                                .background(theme.lineColor.opacity(0.2))
                            ContentRenderer(nrPost: nrPost, isDetail: false, availableWidth: dim.availablePostDetailRowImageWidth() - 20 )
//                                .padding(.trailingx, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
                        }
                    }
                }
                .background(alignment:.leading) {
                    ZStack(alignment: .leading) {
                        theme.background
                        theme.lineColor.opacity(0.2)
                            .frame(width: 2)
                            .offset(x: THREAD_LINE_OFFSET, y: 50)
                            .opacity(connect == .bottom || connect == .both ? 1 : 0)
                    }
                    .onTapGesture {
                        navigateTo(nrPost)
                    }
                }
            
                if (settings.rowFooterEnabled) {
                    FooterFragmentView(nrPost: nrPost)
                        .padding(.leading, INDENT)
                        .padding(.vertical, 5)
//                        .padding(.trailingx, 10)
                }
            }
        }
        // tapGesture is in PostAndParent()
    }
}

struct DetailPost: View {
    @EnvironmentObject var theme:Theme
    @ObservedObject var nrPost:NRPost
    @ObservedObject var settings:SettingsStore = .shared
    @EnvironmentObject var dim:DIMENSIONS
    @State var showMiniProfile = false
    
    var body: some View {
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
                    .overlay(alignment: .top) {
                        if nrPost.replyToId != nil {
                            theme.lineColor
                                .opacity(0.2)
                                .frame(width: 2, height: 10)
                                .offset(y: -10)
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
                    sendNotification(.scrollToDetail, nrPost.id)
                }
            }
            
            // We don't show "Replying to.." unless we can't fetch the parent
            if nrPost.replyTo == nil && nrPost.replyToId != nil {
                ReplyingToFragmentView(nrPost: nrPost)
                    .padding(.top, 10)
            }
        
            switch nrPost.kind {
            case 30023:
                ArticleView(nrPost, isDetail: true, fullWidth: settings.fullWidthImages, hideFooter: false)
                    .background(Color(.secondarySystemBackground))
            case 9802:
                HighlightRenderer(nrPost: nrPost)
                    .padding(.top, 3)
                    .padding(.bottom, 10)
                    .padding(.horizontal, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
            case 1,6,9734:
                if nrPost.plainTextOnly {
                    NoteMinimalContentView(nrPost: nrPost, lineLimit: 350)
                }
                else {
                    ContentRenderer(nrPost: nrPost, isDetail: true, fullWidth: settings.fullWidthImages, availableWidth: settings.fullWidthImages ? dim.listWidth : (dim.availablePostDetailImageWidth() - (20)))
                        .padding(.vertical, 10)
                }
            case 1063:
                if let fileMetadata = nrPost.fileMetadata {
                    Kind1063(nrPost, fileMetadata: fileMetadata, availableWidth: settings.fullWidthImages ? dim.listWidth : dim.availablePostDetailImageWidth())
                        .padding(.horizontal, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
                }
            default:
                Label(String(localized:"kind \(Double(nrPost.kind).clean) type not (yet) supported", comment: "Message shown when a post kind (X) is not yet supported"), systemImage: "exclamationmark.triangle.fill")
                    .centered()
                    .frame(maxWidth: .infinity)
                    .background(theme.lineColor.opacity(0.2))
                ContentRenderer(nrPost: nrPost, isDetail: true, fullWidth: settings.fullWidthImages, availableWidth: settings.fullWidthImages ? dim.listWidth : dim.availablePostDetailImageWidth())
                    .padding(.top, 3)
                    .padding(.bottom, 10)
                    .padding(.horizontal, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
            }
            
            DetailFooterFragment(nrPost: nrPost)
                .padding(.top, 10)
            FooterFragmentView(nrPost: nrPost, isDetail: true)
                .padding(.vertical, 5)
                .preference(key: TabTitlePreferenceKey.self, value: nrPost.anyName)
        }
    }
}




struct Kind1063detail_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadKind1063()
        }) {
            NavigationStack {
                if let kind1063 = PreviewFetcher.fetchNRPost("ac0c2960db29828ee4a818337ea56df990d9ddd9278341b96c9fb530b4c4dce8") {
                    PostDetailView(nrPost:kind1063)
                }
            }
        }
    }
}

struct Kind1063detailQuoted_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
            pe.loadKind1063()
        }) {
            NavigationStack {
                if let kind1063q = PreviewFetcher.fetchNRPost("71a965d8e8546f8927cea23ad865a429dbec0215f36c5e0edad2323eb00f4851") {
                    PostDetailView(nrPost:kind1063q)
                }
            }
        }
    }
}

struct ReplyAndParentView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
            pe.parseMessages([
                ###"["EVENT","485cefc1-2f85-402e-a136-691557f322c8",{"content":"https://youtube.com/shorts/cZenQR8tgV8?feature=share\n\nIf even _she_ is speaking out about Canada's new bill C-11, it's bad. She's a 100% mainstream comedian who got her start during lockdown.","created_at":1680327426,"id":"5988f18416a6d2702a61df9dedc318f18d0d5778a020464222138edab386eee7","kind":1,"pubkey":"ccaa58e37c99c85bc5e754028a718bd46485e5d3cb3345691ecab83c755d48cc","sig":"efad8bf0580ee6a36f6ebd48ab3fba940d9fdc5d5fcf866b6d609ac52c1b24a7acb16277890ea770a8d4328018c1ec7b7ef84e7ffa19b8f9929a36300adc4b33","tags":[["r","https://youtube.com/shorts/cZenQR8tgV8?feature=share"]]}]"###,
                ###"["EVENT","16dbd7e2-af00-4c7d-9258-f5413d75b95f",{"content":"The fact thay she thinks an “amendment to protect digital creators” makes the bill ok is so childishly naive it hurts. ","created_at":1680333364,"id":"5e80b08b76e81e549c4554e161dfeb67a09da859e4706a989876a5ec42016d9a","kind":1,"pubkey":"b9e76546ba06456ed301d9e52bc49fa48e70a6bf2282be7a1ae72947612023dc","sig":"5c31c120473800d878a5391ad2055b20404a4d97d20c08116f0931737559aea7d8e26febf64f4e24385c637d1e8b84ede32ca498a75190b0aaaba3821ac1bd3a","tags":[["e","5988f18416a6d2702a61df9dedc318f18d0d5778a020464222138edab386eee7"],["p","ccaa58e37c99c85bc5e754028a718bd46485e5d3cb3345691ecab83c755d48cc"]]}]"###,
                ###"["EVENT","a2533e43-5968-40dd-a986-131e839cbb84",{"content":"Her being publicly against it at all is a win. And the amendment was cancelled.","created_at":1680333872,"id":"a4508aa658b12d51a56613c51da096d7791eb207d3b11407089c633ff73f668d","kind":1,"pubkey":"ccaa58e37c99c85bc5e754028a718bd46485e5d3cb3345691ecab83c755d48cc","sig":"a1a46a31a1d11175cfc8452210b436d731f3b8615254ec51063f4124a250cc544e40ab54899b243f7637c5778f093d869a6b9f54e1e30f9b9245c07d6df37b9f","tags":[["e","5988f18416a6d2702a61df9dedc318f18d0d5778a020464222138edab386eee7"],["e","5e80b08b76e81e549c4554e161dfeb67a09da859e4706a989876a5ec42016d9a"],["p","ccaa58e37c99c85bc5e754028a718bd46485e5d3cb3345691ecab83c755d48cc"],["p","b9e76546ba06456ed301d9e52bc49fa48e70a6bf2282be7a1ae72947612023dc"]]}]"###])
        }) {
            NavigationStack {
                if let xx = PreviewFetcher.fetchNRPost("a4508aa658b12d51a56613c51da096d7791eb207d3b11407089c633ff73f668d") {
                    PostDetailView(nrPost: xx)
                }
            }
        }
    }
}

struct YouTubePreviewInDetail_Previews: PreviewProvider {
    static var previews: some View {
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
        }) {
            NavigationStack {
                if let yt2 = PreviewFetcher.fetchNRPost("0000014de66e08882bd36b6b7b551a774f85fe752a18070dc8658d7776db7e69") {
                    PostDetailView(nrPost: yt2)
                }
                
            }
        }
    }
}

struct YouTubeInDetail_Previews: PreviewProvider {
    static var previews: some View {
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
            pe.parseMessages([
                ###"["EVENT","e24e08cc-9e36-4a54-8a33-1d1fc84ae95c",{"content":"https://youtu.be/QU9kRF9tHPU","created_at":1681073179,"id":"c7b4ef377ee4f6d71f6f59bc6bad607acb9c7c3675e3c0b2ca0ad2442b133e49","kind":1,"pubkey":"82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2","sig":"2bec825a1db31653187d221b69965e992a28d5a0913aa286c89fa23606fc41f4ad7b146a4844a136ba2865566c958b509e544c6620e25f329f239a7be0d6f87b","tags":[]}]"###]
            )
        }) {
            NavigationStack {
                if let yt = PreviewFetcher.fetchNRPost("c7b4ef377ee4f6d71f6f59bc6bad607acb9c7c3675e3c0b2ca0ad2442b133e49") {
                    ScrollView {
                        PostDetailView(nrPost: yt)
                    }
                }
                
            }
        }
    }
}


struct ReplyAndParentView4_Previews: PreviewProvider {
    static var previews: some View {
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
            pe.loadRepliesAndReactions()
        }) {
            NavigationStack {
                if let v = PreviewFetcher.fetchNRPost("bb15e6165180d31c36b6c3e0baf082eeb949aa473c59e37eaa8e2bb29dc46422") {
                    PostDetailView(nrPost: v)
                }
                
            }
        }
    }
}

struct ReplyAndParentView5_Previews: PreviewProvider {
    static var previews: some View {
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
            pe.loadRepliesAndReactions()
        }) {
            NavigationStack {
                if let lastReply = PreviewFetcher.fetchNRPost("2026c6b0f0d887aa76cc60f0b3050fe940c8eca9eb479391acb493bb40e4d964") {
                    PostDetailView(nrPost: lastReply)
                }
                
            }
        }
    }
}

struct ReplyAndParentView6_Previews: PreviewProvider {
    static var previews: some View {
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
            pe.loadRepliesAndReactions()
        }) {
            NavigationStack {
                if let rootWithReplies = PreviewFetcher.fetchNRPost("6f74b952991bb12b61de7c5891706711e51c9e34e9f120498d32226f3c1f4c81") {
                    PostDetailView(nrPost: rootWithReplies)
                }
            }
        }
    }
}

struct ReplyAndParentView7_Previews: PreviewProvider {
    static var previews: some View {
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
            pe.loadRepliesAndReactions()
        }) {
            NavigationStack {
                if let v = PreviewFetcher.fetchNRPost("c0d76c3c968775a62ca1dea28a73e1fc86d121e8e5e17f2e35aaad1436075f51") {
                    PostDetailView(nrPost: v)
                }
            }
        }
    }
}

struct BetterReplies_Previews: PreviewProvider {
    static var previews: some View {
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
            pe.loadRepliesAndReactions()
        }) {
            NavigationStack {
                if let matt = PreviewFetcher.fetchNRPost("e593fc759291a691cd0127643a0b9fac9d92613952845e207eb24332937c59d9") {
                    
                    PostDetailView(nrPost: matt)
                }
            }
        }
    }
}
