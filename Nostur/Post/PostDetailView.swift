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
        VStack {
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
                    PostAndParent(nrPost: nrPost,  navTitleHidden:navTitleHidden)
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
}

let THREAD_LINE_OFFSET = 34.0

// Renders reply, and parent
// the parent is another PostAndParent
// so it recursively renders up to the root
struct PostAndParent: View {
    var sp:SocketPool = .shared
    @ObservedObject var nrPost:NRPost
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var dim:DIMENSIONS
    
    var navTitleHidden:Bool = false
    
    var isParent = false
    var connect:ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    var geoHeight:CGFloat
    let INDENT = DIMENSIONS.POST_ROW_PFP_WIDTH + (DIMENSIONS.POST_ROW_PFP_HPADDING*2)
    
    @ObservedObject var settings:SettingsStore = .shared
    @State private var timerTask: Task<Void, Never>?
    @State var didLoad = false
    
    init(nrPost: NRPost, isParent:Bool = false, geoHeight:CGFloat = CGFloat.zero, navTitleHidden:Bool = false, connect:ThreadConnectDirection? = nil) {
        self.nrPost = nrPost
        self.isParent = isParent
        self.geoHeight = geoHeight
        self.navTitleHidden = navTitleHidden
        self.connect = connect
    }
    
    var body: some View {
//        let _ = Self._printChanges()
        VStack(spacing:0) {
            // MARK: PARENT NOTE
            // We have the event: replyTo_ = already .replyTo or lazy fetched with .replyToId
            if let replyTo = nrPost.replyTo {
                if replyTo.deletedById == nil {
                    
                    if replyTo.kind == 30023 {
                        ArticleView(replyTo, isParent:true, isDetail: true, fullWidth: true)
                    }
                    else {
                        let connect:ThreadConnectDirection? = replyTo.replyToId != nil ? .both : .bottom
                        PostAndParent(nrPost: replyTo, isParent: true, connect: connect)
                            .background(alignment: .leading) {
                                ZStack(alignment: .leading) {
                                    Color.systemBackground
                                    Color("LightGray")
                                        .frame(width: 2)
                                        .offset(x: THREAD_LINE_OFFSET, y: 62)
                                        .opacity(connect == .bottom || connect == .both ? 1 : 0)
                                }
                            }
                            .background(alignment:.topLeading) {
                                Color.systemBackground
                                    .frame(width: DIMENSIONS.ROW_PFP_SPACE - 10)
                                    .padding(.top, DIMENSIONS.POST_ROW_PFP_HEIGHT + 20)
                                    .onTapGesture {
                                        navigateTo(replyTo)
                                    }
                            }
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
                    .background(Color.systemBackground)
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
//                            .background(Color.systemBackground)
                    }
                    else {
                        DetailPost(nrPost: nrPost)
                            .id(nrPost.id)
                            .background(Color.systemBackground)
                            .preference(key: TabTitlePreferenceKey.self, value: nrPost.anyName)
                    }
                }
                else {
                    Text("_Post deleted by \(nrPost.anyName)_", comment: "Message shown when a post is deleted by (name)")
                        .hCentered()
                }
                
                if (!isParent) {
                    // MARK: REPLIES TO OUR MAIN NOTE
                    ThreadReplies(nrPost: nrPost)
                    
                    // If there are less than 5 replies, put some empty space so our detail note is at top of screen
                    if (nrPost.replies.count < 5) {
                        let height = geoHeight - 280
                        Rectangle().frame(height: (height < 280 ? 400 : height))
                            .background(Color("ListBackground"))
                            .foregroundColor(Color("ListBackground"))
                    }
                    
//                    Spacer()
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
            .padding(.top, nrPost.replyTo == nil ? 10.0 : 0)
            .background(Color.systemBackground)
//            .frame(width: 400)
        }
    }
}

struct ParentPost: View {
    @ObservedObject var nrPost:NRPost
    @ObservedObject var settings:SettingsStore = .shared
    @EnvironmentObject var dim:DIMENSIONS
    let INDENT = DIMENSIONS.POST_ROW_PFP_WIDTH + (DIMENSIONS.POST_ROW_PFP_HPADDING*2)
    var connect:ThreadConnectDirection? = nil
    @State var showMiniProfile = false
    
    var body: some View {
        if nrPost.blocked {
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
            HStack(alignment:.top, spacing:0) {
                ZappablePFP(pubkey: nrPost.pubkey, contact: nrPost.contact?.mainContact, size: DIMENSIONS.POST_ROW_PFP_WIDTH, zapEtag: nrPost.id)
                    .frame(width: DIMENSIONS.POST_ROW_PFP_WIDTH, height: 50)
                    .onTapGesture {
                        if !IS_APPLE_TYRANNY {
                            navigateTo(ContactPath(key: nrPost.pubkey))
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
                                                            contact: nrPost.contact?.mainContact,
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
                    .padding(.horizontal, DIMENSIONS.POST_ROW_PFP_HPADDING)
                
                VStack(alignment:.leading, spacing:0) {
                    HStack {
                        NoteHeaderView(nrPost: nrPost, singleLine: true)
                        Spacer()
                        EventPrivateNoteToggle(nrPost: nrPost)
                        LazyNoteMenuButton(nrPost: nrPost)
                    }
                    .padding(.trailing, 10)
                    
                    // We don't show "Replying to.." unless we can't fetch the parent
                    if nrPost.replyTo == nil && nrPost.replyToId != nil {
                        ReplyingToFragmentView(nrPost: nrPost)
                            .padding(.trailing, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
                    }
                    
                    switch nrPost.kind {
                    case 30023:
                        ArticleView(nrPost, isDetail: false, fullWidth: settings.fullWidthImages, hideFooter: false)
                            .padding(.bottom, 10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 15)
                                    .stroke(.regularMaterial, lineWidth: 1)
                            )
                            .padding(.bottom, 10)
                    case 9802: // highlight
                        HighlightRenderer(nrPost: nrPost)
                            .padding(.trailing, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
                    case 1,6,9734: // text, repost, zap request
                        ContentRenderer(nrPost: nrPost, isDetail: true, availableWidth: dim.availablePostDetailRowImageWidth() - 20)
                            .padding(.trailing, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                navigateTo(nrPost)
                            }
                    case 1063: // File Metadata
                        NoteTextRenderView(nrPost: nrPost)
                    default:
                        Label(String(localized:"kind \(Double(nrPost.kind).clean) type not (yet) supported", comment: "Message shown when a post kind (X) is not yet supported"), systemImage: "exclamationmark.triangle.fill")
                            .centered()
                            .frame(maxWidth: .infinity)
                            .background(Color("LightGray").opacity(0.2))
                        ContentRenderer(nrPost: nrPost, isDetail: true, availableWidth: dim.availablePostDetailRowImageWidth() - 20 )
                            .padding(.trailing, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                navigateTo(nrPost)
                            }
                    }
                }
            }
            .background(alignment:.leading) {
                ZStack(alignment: .leading) {
                    Color.systemBackground
                    Color("LightGray")
                        .frame(width: 2)
                        .offset(x: THREAD_LINE_OFFSET, y: 50)
                        .opacity(connect == .bottom || connect == .both ? 1 : 0)
                }
                .onTapGesture {
                    navigateTo(nrPost)
                }
                
    //            Color.systemBackground
    //                .frame(width: INDENT)
    //                .onTapGesture {
    //                    navigateTo(nrPost)
    //                }
            }
        
            if (settings.rowFooterEnabled) {
                FooterFragmentView(nrPost: nrPost)
                    .padding(.leading, INDENT)
                    .padding(.vertical, 5)
                    .padding(.trailing, 10)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        navigateTo(nrPost)
                    }
            }
        }
    }
}

struct DetailPost: View {
    @ObservedObject var nrPost:NRPost
    @ObservedObject var settings:SettingsStore = .shared
    @EnvironmentObject var dim:DIMENSIONS
    @State var showMiniProfile = false
    
    var body: some View {
        HStack(alignment:.top, spacing:0) {
            ZappablePFP(pubkey: nrPost.pubkey, contact: nrPost.contact?.mainContact, size: DIMENSIONS.POST_ROW_PFP_WIDTH, zapEtag: nrPost.id)
                .frame(width: DIMENSIONS.POST_ROW_PFP_WIDTH, height: 50)
                .padding(.horizontal, DIMENSIONS.POST_ROW_PFP_HPADDING)
//                .padding(.top, nrPost.replyToId != nil ? 0 : 10)
                .onTapGesture {
                    if !IS_APPLE_TYRANNY {
                        navigateTo(ContactPath(key: nrPost.pubkey))
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
                                                        contact: nrPost.contact?.mainContact,
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
            
            VStack(alignment:.leading, spacing:0) {
                HStack {
                    NoteHeaderView(nrPost: nrPost, singleLine: false)
                    Spacer()
                    EventPrivateNoteToggle(nrPost: nrPost)
                    LazyNoteMenuButton(nrPost: nrPost)
                }
                .padding(.trailing, 10)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                sendNotification(.scrollToDetail, nrPost.id)
            }
        }
        
        // We don't show "Replying to.." unless we can't fetch the parent
        if nrPost.replyTo == nil && nrPost.replyToId != nil {
            ReplyingToFragmentView(nrPost: nrPost)
                .padding(.horizontal, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
        }
    
        switch nrPost.kind {
        case 30023:
            ArticleView(nrPost, isDetail: true, fullWidth: settings.fullWidthImages, hideFooter: false)
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(.regularMaterial, lineWidth: 1)
                )
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
                    .padding(.top, 10)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
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
                .background(Color("LightGray").opacity(0.2))
            ContentRenderer(nrPost: nrPost, isDetail: true, fullWidth: settings.fullWidthImages, availableWidth: settings.fullWidthImages ? dim.listWidth : dim.availablePostDetailImageWidth())
                .padding(.top, 3)
                .padding(.bottom, 10)
                .padding(.horizontal, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
        }
        
        DetailFooterFragment(nrPost: nrPost)
            .padding(.leading, DIMENSIONS.POST_ROW_HPADDING)
            .background(Color.systemBackground)
        FooterFragmentView(nrPost: nrPost)
            .padding(.top, 5)
            .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING)
            .padding(.bottom, 5)
            .background(Color.systemBackground)
            .roundedCorner(10, corners: [.bottomLeft, .bottomRight])
            .background(Color("ListBackground"))
            .preference(key: TabTitlePreferenceKey.self, value: nrPost.anyName)
        
        
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
        }) {
            NavigationStack {
                if let xx = PreviewFetcher.fetchNRPost("a4508aa658b12d51a56613c51da096d7791eb207d3b11407089c633ff73f668d") {
                    PostDetailView(nrPost: xx)
                }
            }
        }
    }
}

struct ReplyAndParentView2_Previews: PreviewProvider {
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


struct ReplyAndParentView3_Previews: PreviewProvider {
    static var previews: some View {
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
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
        }) {
            NavigationStack {
                if let matt = PreviewFetcher.fetchNRPost("e593fc759291a691cd0127643a0b9fac9d92613952845e207eb24332937c59d9") {
                    
                    PostDetailView(nrPost: matt)
                }
            }
        }
    }
}
