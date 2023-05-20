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
                        if let event = events.first {
                            DataProvider.shared().bg.perform {
                                let nrPost = NRPost(event: event, withReplies: true)
                                
                                DispatchQueue.main.async {
                                    self.nrPost = nrPost
                                }
                            }
                        }
                    }
            }
            else {
                Text("Trying to fetch...").onAppear {
                    // .REQ
                    print("🟢 NoteById.onAppear no event so REQ.1: \(id)")
                    sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEventAndReferences(id: id)))
                }
            }
        }
    }
}

struct PostDetailView: View {
    let nrPost:NRPost
    var navTitleHidden:Bool = false
    @State var didLoad = false
    
    init(nrPost: NRPost, navTitleHidden: Bool = false) {
        self.nrPost = nrPost
        self.navTitleHidden = navTitleHidden
    }
    
    var body: some View {
        GeometryReader{ geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    PostAndParent(nrPost: nrPost, geoHeight: geometry.size.height, navTitleHidden:navTitleHidden)
                        .onAppear {
                            guard !didLoad else { return }
                            didLoad = true
                            // TODO: FIX: THIS DOESNT WORK IF PARENTS ARE STILL LOADING
                            proxy.scrollTo(nrPost.id, anchor: .top)
                        }
                        .navigationTitle(nrPost.replyToId != nil ? "Thread" : "Post")
                        .navigationBarTitleDisplayMode(.inline)
                        .navigationBarHidden(navTitleHidden)
                }
            }
        }
    }
}


// Renders reply, and parent
// the parent is another PostAndParent
// so it recursively renders up to the root
struct PostAndParent: View {
    var sp:SocketPool = .shared
    @ObservedObject var nrPost:NRPost
//    @ObservedObject var event:Event
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var dim:DIMENSIONS
    
    var navTitleHidden:Bool = false
    
    var isParent = false
    var connect:ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    var geoHeight:CGFloat
    let INDENT = DIMENSIONS.POST_ROW_PFP_WIDTH + (DIMENSIONS.POST_ROW_PFP_HPADDING*2)
    let THREAD_LINE_OFFSET = 34.0
    @ObservedObject var settings:SettingsStore = .shared
    @State private var timerTask: Task<Void, Never>?
    @State var didLoad = false
    
    init(nrPost: NRPost, isParent:Bool = false, geoHeight:CGFloat = CGFloat.zero, navTitleHidden:Bool = false, connect:ThreadConnectDirection? = nil) {
        self.nrPost = nrPost
//        self.event = nrPost.event
        self.isParent = isParent
        self.geoHeight = geoHeight
        self.navTitleHidden = navTitleHidden
        self.connect = connect
    }
    
    var body: some View {
        let _ = Self._printChanges()
        VStack {
            // MARK: PARENT NOTE
            // We have the event: replyTo_ = already .replyTo or lazy fetched with .replyToId
            if let replyTo = nrPost.replyTo {
                if replyTo.deletedById == nil {
                    let connect:ThreadConnectDirection? = replyTo.replyToId != nil ? .both : .bottom
                    PostAndParent(nrPost: replyTo, isParent: true, connect: connect)
                        .background(alignment: .leading) {
                            Color("LightGray")
                                .frame(width: 2)
                                .offset(x: THREAD_LINE_OFFSET, y: 62)
                                .opacity(connect == .bottom || connect == .both ? 1 : 0)
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
                else {
                    Text("_Post deleted by author_")
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
//                        req(RM.getEvent(id: replyToId))
                    }
                    .onDisappear {
                        timerTask?.cancel()
                        timerTask = nil
                    }
            }
            // OUR (DETAIL) REPLY:
            // MARK: DETAIL NOTE
            VStack(alignment: .leading, spacing: 3) {
                if nrPost.deletedById == nil {
                    
                    HStack(alignment:.top, spacing:0) {
                        PFP(pubkey: nrPost.pubkey, nrContact: nrPost.contact, size: 50)
                            .frame(width: DIMENSIONS.POST_ROW_PFP_WIDTH, height: 50)
                            .padding(.horizontal, DIMENSIONS.POST_ROW_PFP_HPADDING)
                            .onTapGesture {
                                navigateTo(ContactPath(key: nrPost.pubkey))
                            }
                        
                        VStack(alignment:.leading, spacing:0) {
                            HStack {
                                NoteHeaderView(nrPost: nrPost, singleLine: isParent)
                                Spacer()
                                EventPrivateNoteToggle(nrPost: nrPost)
                                NoteMenuView(nrPost: nrPost)
                            }
                            .padding(.trailing, 10)
                            if isParent {
//                                ReplyingToFragmentView(nrPost: nrPost)
//                                    .padding(.vertical, 3)
                                switch nrPost.kind {
                                    case 9802:
                                        HighlightRenderer(nrPost: nrPost)
                                        .padding(.trailing, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
                                    case 1,6,9734:
                                        ContentRenderer(nrPost: nrPost, isDetail: true, availableWidth: dim.availablePostDetailRowImageWidth())
                                            .padding(.trailing, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                navigateTo(nrPost)
                                            }
                                    case 1063:
                                        NoteTextRenderView(nrPost: nrPost)
                                    default:
                                        Label("kind \(Double(nrPost.kind).clean) type not (yet) supported", systemImage: "exclamationmark.triangle.fill")
                                            .centered()
                                            .frame(maxWidth: .infinity)
                                            .background(Color("LightGray").opacity(0.2))
                                        ContentRenderer(nrPost: nrPost, isDetail: true, availableWidth: dim.availablePostDetailRowImageWidth())
                                            .padding(.trailing, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                navigateTo(nrPost)
                                            }
                                }
                            }
                        }
                    }

                    if !isParent {
//                        ReplyingToFragmentView(nrPost: nrPost)
//                            .padding(.bottom, 3)
//                            .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING)
                        switch nrPost.kind {
                            case 9802:
                                HighlightRenderer(nrPost: nrPost)
                                .padding(.top, 3)
                                .padding(.bottom, 10)
                                .padding(.horizontal, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
                            case 1,6,9734:
                                ContentRenderer(nrPost: nrPost, isDetail: true, fullWidth: settings.fullWidthImages, availableWidth: settings.fullWidthImages ? dim.listWidth : dim.availablePostDetailImageWidth())
                                    .padding(.top, 3)
                                    .padding(.bottom, 10)
                                    .padding(.horizontal, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
//                                    .contentShape(Rectangle())
//                                    .onTapGesture {
//                                        navigateTo(nrPost)
//                                    }
                            case 1063:
                                if let fileMetadata = nrPost.fileMetadata {
                                    Kind1063(nrPost, fileMetadata: fileMetadata, availableWidth: settings.fullWidthImages ? dim.listWidth : dim.availablePostDetailImageWidth())
                                    .padding(.horizontal, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
                                }
                            default:
                                Label("kind \(Double(nrPost.kind).clean) type not (yet) supported", systemImage: "exclamationmark.triangle.fill")
                                    .centered()
                                    .frame(maxWidth: .infinity)
                                    .background(Color("LightGray").opacity(0.2))
                                ContentRenderer(nrPost: nrPost, isDetail: true, fullWidth: settings.fullWidthImages, availableWidth: settings.fullWidthImages ? dim.listWidth : dim.availablePostDetailImageWidth())
                                    .padding(.top, 3)
                                    .padding(.bottom, 10)
                                    .padding(.horizontal, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
//                                    .contentShape(Rectangle())
//                                    .onTapGesture {
//                                        navigateTo(nrPost)
//                                    }
                        }
                    }
                    
                    if (isParent && settings.rowFooterEnabled) {
                        FooterFragmentView(nrPost: nrPost)
                            .padding(.leading, INDENT)
                            .padding(.vertical, 5)
                            .padding(.trailing, 10)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                navigateTo(nrPost)
                            }
                    }
                    else if (!isParent) {
                        DetailFooterFragment(nrPost: nrPost)
                            .padding(.leading, isParent ? INDENT : DIMENSIONS.POST_ROW_HPADDING)
                        FooterFragmentView(nrPost: nrPost)
                            .padding(.vertical, 5)
                            .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING)
                        Divider()
                    }
                }
                else {
                    Text("_Post deleted by \(nrPost.anyDisplayName)_")
                        .hCentered()
                }
                
                if (!isParent) {
                    // MARK: REPLIES TO OUR MAIN NOTE
                    LazyVStack {
                        ForEach (nrPost.replies
                            .sorted(by: { $0.created_at < $1.created_at } )
                            .filter({ nrPost in
                            if ns.account != nil {
                                return !(Set(ns.account!.blockedPubkeys_)).contains(nrPost.pubkey)
                            }
                            else {
                                return true
                            }
                        })
                                 // newest at bottom
                            .sorted(by: { $0.created_at < $1.created_at })
                                 // following first
                            .sorted(by: { ns.isFollowing($0.pubkey) && !ns.isFollowing($1.pubkey) })
                                 // OP first even more first.
                            .sorted(by: { $0.pubkey == nrPost.pubkey && $1.pubkey != nrPost.pubkey })
                                 , id:\.self) { nrPost in
                            
                            PostRowDeletable(nrPost: nrPost, hideFooter: false, isReply:true)
                                .id(nrPost.id)
                                .onAppear {
                                    if (nrPost.missingPs.count > 0) {
                                        EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "PostDetailView.002")
                                        QueuedFetcher.shared.enqueue(pTags: nrPost.missingPs)
                                    }
                                }
                                .onDisappear {
                                    if (nrPost.missingPs.count > 0) {
                                        QueuedFetcher.shared.dequeue(pTags: nrPost.missingPs)
                                    }
                                }
                            Divider()
                        }
                    }
                    .animation(Animation.spring(), value: nrPost.replies)
                    
                    // If there are less than 5 replies, put some empty space so our detail note is at top of screen
                    if (nrPost.replies.count < 5) {
                        let height = geoHeight - 280
                        Rectangle().frame(width: 100, height: (height < 280 ? 400 : height))
                            .background(.clear)
                            .foregroundColor(.clear)
                    }
                    
                    Spacer()
                }
                
            }
            .id(nrPost.id)
            .padding(.vertical, 10)
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                if (nrPost.missingPs.count > 0) {
                    EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "PostDetailView.003")
                    QueuedFetcher.shared.enqueue(pTags: nrPost.missingPs)
                }

                nrPost.loadReplyTo()
                
                if (!isParent) {
                    nrPost.loadReplies()

                    // Fix replyTo if we already have it?
//                    fixReplyToIfWeAlreadyHaveIt(event)
                    
                    // Here, because do all at import is slow?
                    
//                    fixIfWeHavePointingToAlreadyInCache(nrPost.mainEvent)
                    
                    EventRelationsQueue.shared.addAwaitingEvent(nrPost.event)
                    
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
            .onDisappear {
                if (nrPost.missingPs.count > 0) {
                    QueuedFetcher.shared.dequeue(pTags: nrPost.missingPs)
                }
            }
        }
    }
    
//    func fixReplyToIfWeAlreadyHaveIt(_ openedEvent:Event) {
//        if openedEvent.replyTo_ == nil && openedEvent.replyToId != nil {
//            // IF WE ALREADY HAVE THE PARENT, ADD OUR NEW EVENT IN THE REPLIES
//            if let replyTo = try? Event.fetchEvent(id: openedEvent.replyToId!, context: viewContext) {
//                openedEvent.objectWillChange.send()
//                openedEvent.replyTo = replyTo
//
//                replyTo.objectWillChange.send()
//                replyTo.addToReplies(openedEvent)
//                //                replyTo.repliesCount += 1 // TODO: Count again here?? or we already counted ??
//            }
//        }
//
//        // IF THE THERE IS A ROOT, AND ITS NOT THE SAME AS THE REPLY TO
//        // DO THE SAME AS WITH THE REPLY BEFORE
//        if (openedEvent.replyToRootId != openedEvent.replyToId) { // If reply root is same as reply, dont double add.
//            if (openedEvent.replyToId == nil) { // IF IT HAS ONLY A ROOT REPLY, NO NORMAL REPLY: THEN REPLYTOROOT = REPLYTO
//                openedEvent.replyToId = openedEvent.replyToRootId
//
//                // IF WE ALREADY HAVE THE PARENT, ADD OUR NEW EVENT IN THE REPLIES
//                if let replyToRoot = try? Event.fetchEvent(id: openedEvent.replyToRootId!, context: viewContext) {
//                    openedEvent.objectWillChange.send()
//                    openedEvent.replyTo = replyToRoot // NO REPLYTO, SO REPLYTOROOT IS THE REPLYTO
//
//                    replyToRoot.objectWillChange.send()
//                    replyToRoot.addToReplies(openedEvent)
//                    //                    replyToRoot.repliesCount += 1 // TODO: Count again here?? or we already counted ??
//                }
//            }
//        }
//    }
    
//    func fixIfWeHavePointingToAlreadyInCache(_ openedEvent:Event) {
//        let pointingToEventReq = NSFetchRequest<Event>(entityName: "Event")
//        //        pointingToEventReq.predicate = NSPredicate(format: "(kind IN {1,6} AND  (replyToId == %@ OR replyToRootId == %@ OR firstQuoteId == %@)", openedEvent.id, openedEvent.id, openedEvent.id)
//        pointingToEventReq.predicate = NSPredicate(format: "kind IN {1,6,9802,7,9375} AND %@ IN {replyToId,replyToRootId,firstQuoteId,reactionToId,zappedEventId}", openedEvent.id)
//        // TODO: NEED 6 ALSO OR NOT?
//        //            pointingToEventReq.predicate = NSPredicate(format: "kind IN {1,6} AND %@ IN {replyToId,replyToRootId,firstQuoteId}", savedEvent.id)
//        pointingToEventReq.sortDescriptors = []
//        var reloadReplies = false
//        if let pointingToEvents = try? viewContext.fetch(pointingToEventReq) {
//            for event in pointingToEvents {
//                if (event.replyToId != nil) && (event.replyToId == openedEvent.id) {
//                    reloadReplies = true
//                    event.replyTo = openedEvent
//                }
//                if (event.replyToRootId != nil) && (event.replyToRootId == openedEvent.id) {
//                    reloadReplies = true
//                    event.replyToRoot = openedEvent
//                }
//                if (event.firstQuoteId != nil) && (event.firstQuoteId == openedEvent.id) {
//                    event.firstQuote = openedEvent
//                }
//                if (event.reactionToId != nil) && (event.reactionToId == openedEvent.id) {
//                    event.reactionTo = openedEvent
//                }
//                if (event.zappedEventId != nil) && (event.zappedEventId == openedEvent.id) {
//                    event.zappedEvent = openedEvent
//                }
//            }
//            if reloadReplies {
//                nrPost.loadReplies()
//            }
//        }
//    }
}

struct DetailFooterFragment: View {
    @ObservedObject var nrPost:NRPost
    
    
    var body: some View {
        Divider()
        HStack(spacing: 20) {
            Text("**\(nrPost.mentionsCount)** reposts")//.onTapGesture { }
            
            NavigationLink(value: ViewPath.NoteReactions(id: nrPost.id)) {
                Text("**\(nrPost.likesCount)** reactions")
            }
            NavigationLink(value: ViewPath.NoteZaps(id: nrPost.id)) {
                Text("**\(nrPost.zapsCount)** zaps")
            }
        
            Spacer()
        }
        .foregroundColor(.gray)
        .padding(5)
        .font(.system(size: 14))
        Divider()
    }
}

struct Kind1063detail_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            if let kind1063 = PreviewFetcher.fetchNRPost("ac0c2960db29828ee4a818337ea56df990d9ddd9278341b96c9fb530b4c4dce8") {
                PostDetailView(nrPost:kind1063)
            }
        }
        .withPreviewEnvironment()
    }
}

struct Kind1063detailQuoted_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            if let kind1063q = PreviewFetcher.fetchNRPost("71a965d8e8546f8927cea23ad865a429dbec0215f36c5e0edad2323eb00f4851") {
                PostDetailView(nrPost:kind1063q)
            }
        }
        .withPreviewEnvironment()
    }
}

struct ReplyAndParentView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            if let xx = PreviewFetcher.fetchNRPost("a4508aa658b12d51a56613c51da096d7791eb207d3b11407089c633ff73f668d") {
                PostDetailView(nrPost: xx)
            }
        }
        .withPreviewEnvironment()
    }
}

struct ReplyAndParentView2_Previews: PreviewProvider {
    static var previews: some View {

        NavigationStack {
            if let yt2 = PreviewFetcher.fetchNRPost("0000014de66e08882bd36b6b7b551a774f85fe752a18070dc8658d7776db7e69") {
                PostDetailView(nrPost: yt2)
            }

        }
        .withPreviewEnvironment()
    }
}


struct ReplyAndParentView3_Previews: PreviewProvider {
    static var previews: some View {

        NavigationStack {

            
            if let yt = PreviewFetcher.fetchNRPost("c7b4ef377ee4f6d71f6f59bc6bad607acb9c7c3675e3c0b2ca0ad2442b133e49") {
                ScrollView {
                    PostDetailView(nrPost: yt)
                }
            }
   
        }
        .withPreviewEnvironment()
    }
}


struct ReplyAndParentView4_Previews: PreviewProvider {
    static var previews: some View {

        NavigationStack {
  
            
            if let v = PreviewFetcher.fetchNRPost("bb15e6165180d31c36b6c3e0baf082eeb949aa473c59e37eaa8e2bb29dc46422") {
                PostDetailView(nrPost: v)
            }
 
        }
        .withPreviewEnvironment()
    }
}

struct ReplyAndParentView5_Previews: PreviewProvider {
    static var previews: some View {

        NavigationStack {
     
            
            if let lastReply = PreviewFetcher.fetchNRPost("2026c6b0f0d887aa76cc60f0b3050fe940c8eca9eb479391acb493bb40e4d964") {
                PostDetailView(nrPost: lastReply)
            }

        }
        .withPreviewEnvironment()
    }
}

struct ReplyAndParentView6_Previews: PreviewProvider {
    static var previews: some View {

        NavigationStack {
            if let rootWithReplies = PreviewFetcher.fetchNRPost("6f74b952991bb12b61de7c5891706711e51c9e34e9f120498d32226f3c1f4c81") {
                PostDetailView(nrPost: rootWithReplies)
            }
        }
        .withPreviewEnvironment()
    }
}

struct ReplyAndParentView7_Previews: PreviewProvider {
    static var previews: some View {

        NavigationStack {
            if let v = PreviewFetcher.fetchNRPost("c0d76c3c968775a62ca1dea28a73e1fc86d121e8e5e17f2e35aaad1436075f51") {
                PostDetailView(nrPost: v)
            }
        }
        .withPreviewEnvironment()
    }
}

struct BetterReplies_Previews: PreviewProvider {
    static var previews: some View {

        NavigationStack {
            if let matt = PreviewFetcher.fetchNRPost("e593fc759291a691cd0127643a0b9fac9d92613952845e207eb24332937c59d9") {
                
                PostDetailView(nrPost: matt)
            }
        }
        .withPreviewEnvironment()
    }
}
