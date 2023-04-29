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
    
    init(id:String) {
        self.id = id
        
        _events = FetchRequest(
            sortDescriptors: [],
            predicate: NSPredicate(format: "id == %@", id)
        )
    }
    
    var body: some View {
        if (events.first != nil) {
            PostDetailView(vPost: events.first!.toVPost()!)
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

struct PostDetailView: View {
    let vPost:VPost
    var navTitleHidden:Bool = false
    
    init(vPost: VPost, navTitleHidden: Bool = false) {
        self.vPost = vPost
        self.navTitleHidden = navTitleHidden
    }
    
    var body: some View {
        GeometryReader{ geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    PostAndParent(vPost: vPost, geoHeight: geometry.size.height, navTitleHidden:navTitleHidden)
                        .onAppear {
                            proxy.scrollTo(vPost.id)
                        }
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
    let vPost:VPost
    @ObservedObject var event:Event
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
    
    init(vPost: VPost, isParent:Bool = false, geoHeight:CGFloat = CGFloat.zero, navTitleHidden:Bool = false, connect:ThreadConnectDirection? = nil) {
        self.vPost = vPost
        self.event = vPost.event
        self.isParent = isParent
        self.geoHeight = geoHeight
        self.navTitleHidden = navTitleHidden
        self.connect = connect
    }
    
    var body: some View {
        VStack {
            // MARK: PARENT NOTE
            // IF MISSING, FETCH IT
            if (event.replyTo == nil && event.replyToId != nil) {
                CenteredProgressView()
                    .onAppear {
                        sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEvent(id: event.replyToId!)))
                    }
            }
            // PARENT: IF AVAILABLE, RENDER IT
            else if (event.replyTo != nil) {
                if event.replyTo!.deletedById == nil {
                    let connect:ThreadConnectDirection? = event.replyTo!.replyToId != nil ? .both : .bottom
                    PostAndParent(vPost: event.replyTo!.toVPost()!, isParent: true, connect: connect)
//                        .background(.red)
                        .background(alignment: .leading) {
                            Color("LightGray")
                                .frame(width: 2)
                                .offset(x: THREAD_LINE_OFFSET, y: 62)
                                .opacity(connect == .bottom || connect == .both ? 1 : 0)
                            //                                .zIndex(1)
                        }
                }
                else {
                    Text("_Post deleted by author_")
                        .hCentered()
                }
            }
            // OUR (DETAIL) REPLY:
            // MARK: DETAIL NOTE
            VStack(alignment: .leading, spacing: 3) {
                if event.deletedById == nil {
                    
                    HStack(alignment:.top, spacing:0) {
                        NavigationLink(value: ContactPath(key: event.pubkey), label: {
                            PFP(pubkey: event.pubkey, pictureUrl: event.contact?.picture, size: 50, isFollowing: vPost.following)
                                .frame(width: DIMENSIONS.POST_ROW_PFP_WIDTH, height: 50)
                                .background(alignment: .top, content: {
                                    Color("LightGray")
                                        .frame(width: 2, height: 200)
                                        .offset(x:0, y: -20)
                                        .opacity(connect == .top || connect == .both ? 1 : 0)
                                    //                                        .zIndex(1)
                                })
                                .id(vPost.id)
                                .padding(.horizontal, DIMENSIONS.POST_ROW_PFP_HPADDING)
                        })
                        VStack(alignment:.leading, spacing:0) {
                            HStack {
                                NoteHeaderView(vPost: vPost, singleLine: isParent)
                                Spacer()
                                EventPrivateNoteToggle(event: event)
                                NoteMenuView(vPost: vPost)
                            }
                            .padding(.trailing, 10)
                            if isParent {
//                                ReplyingToFragmentView(vPost: vPost)
//                                    .padding(.vertical, 3)
                                if vPost.isHighlight {
                                    HighlightRenderer(vPost: vPost)
                                    .padding(.trailing, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
                                }
                                else {
                                    ContentRenderer(vPost: vPost, isDetail: true, availableWidth: dim.availablePostDetailRowImageWidth())
                                        .padding(.trailing, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
                                }
                            }
                        }
                    }

                    if !isParent {
//                        ReplyingToFragmentView(vPost: vPost)
//                            .padding(.bottom, 3)
//                            .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING)
                        if vPost.isHighlight {
                            HighlightRenderer(vPost: vPost)
                            .padding(.top, 3)
                            .padding(.bottom, 10)
                            .padding(.horizontal, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
                        }
                        else {
                            ContentRenderer(vPost: vPost, isDetail: true, fullWidth: settings.fullWidthImages, availableWidth: settings.fullWidthImages ? dim.listWidth : dim.availablePostDetailImageWidth())
                                .padding(.top, 3)
                                .padding(.bottom, 10)
                                .padding(.horizontal, settings.fullWidthImages ? 0 : DIMENSIONS.POST_ROW_HPADDING)
                        }
//                            .background(.orange)
                    }
                    
                    if (isParent && settings.rowFooterEnabled) {
                        FooterFragmentView(vPost: vPost)
                            .padding(.leading, INDENT)
                            .padding(.vertical, 5)
                            .padding(.trailing, 10)
                    }
                    else if (!isParent) {
                        DetailFooterFragment(event: event)
                            .padding(.leading, isParent ? INDENT : DIMENSIONS.POST_ROW_HPADDING)
                        FooterFragmentView(vPost: vPost)
                            .padding(.vertical, 5)
                            .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING)
                        Divider()
                    }
                }
                else {
                    Text("_Post deleted by \(vPost.displayName)_")
                        .hCentered()
                }
                
                if (!isParent) {
                    // MARK: REPLIES TO OUR MAIN NOTE
                    LazyVStack {
                        ForEach (event.replies_.filter({ event in
                            if ns.account != nil {
                                return !(Set(ns.account!.blockedPubkeys_)).contains(event.pubkey)
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
                            .sorted(by: { $0.pubkey == event.pubkey && $1.pubkey != event.pubkey })
                                 , id:\.self) { event in
                            
                            if let vPost = event.toVPost() {
                                NoteRow(vPost: vPost, hideFooter: false, isReply:true)
//                                    .background(.orange)
                                    .onTapGesture { navigateTo(vPost) }
                            }
                            Divider()
                        }
                    }
                    
                    // If there are less than 5 replies, put some empty space so our detail note is at top of screen
                    if (event.replies?.count ?? 0 < 5) {
                        let height = geoHeight - 280
                        Rectangle().frame(width: 100, height: (height < 280 ? 400 : height))
                            .background(.clear)
                            .foregroundColor(.clear)
                    }
                    
                    Spacer()
                }
                
            }
            .padding(.vertical, 10)
//            .padding(.horizontal, !isParent ? 10 : 20)
            .onTapGesture {
                if (isParent) {
                    navigateTo(vPost)
                }
            }
            .onAppear {
                if (event.contact == nil) {
                    // TODO: Still needed? or below sp.send is already taking care of this?
                    sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: event.pubkey)))
                }
                
                if (!isParent) {
                    
                    // Fix replyTo if we already have it?
                    fixReplyToIfWeAlreadyHaveIt(event)
                    
                    // Here, because do all at import is slow?
                    //                        fixIfWeHavePointingToAlreadyInCache(event)
                    
                    
                    // Fetch all related (e and p.kind=0)
                    // (the events and contacts mentioned in this DETAIL NOTE.
                    if let message = RequestMessage.getTags(event.tags()) {
                        sp.sendMessage(ClientMessage(type: .REQ, message: message))
                    }
                    
                    // Fetch all that reference this detail note (Replies, zaps, reactions)
                    sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEventReferences(ids: [event.id])))
                    
                    
                    if (event.replyToRootId != nil) {
                        
                        // FEtch all that reference the root note
                        // to build the thread, maybe kind=1 is enough, or all...?
                        sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEventReferences(ids: [event.replyToRootId!], kinds: [1])))
                    }
                    
                    // OR??
                    //                        /sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEventAndReferences(id: id)))
                }
            }
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(navTitleHidden)
    }
    
    func fixReplyToIfWeAlreadyHaveIt(_ openedEvent:Event) {
        if openedEvent.replyTo == nil && openedEvent.replyToId != nil {
            // IF WE ALREADY HAVE THE PARENT, ADD OUR NEW EVENT IN THE REPLIES
            if let replyTo = try? Event.fetchEvent(id: openedEvent.replyToId!, context: viewContext) {
                openedEvent.objectWillChange.send()
                openedEvent.replyTo = replyTo
                
                replyTo.objectWillChange.send()
                replyTo.addToReplies(openedEvent)
                //                replyTo.repliesCount += 1 // TODO: Count again here?? or we already counted ??
            }
        }
        
        // IF THE THERE IS A ROOT, AND ITS NOT THE SAME AS THE REPLY TO
        // DO THE SAME AS WITH THE REPLY BEFORE
        if (openedEvent.replyToRootId != openedEvent.replyToId) { // If reply root is same as reply, dont double add.
            if (openedEvent.replyToId == nil) { // IF IT HAS ONLY A ROOT REPLY, NO NORMAL REPLY: THEN REPLYTOROOT = REPLYTO
                openedEvent.replyToId = openedEvent.replyToRootId
                
                // IF WE ALREADY HAVE THE PARENT, ADD OUR NEW EVENT IN THE REPLIES
                if let replyToRoot = try? Event.fetchEvent(id: openedEvent.replyToRootId!, context: viewContext) {
                    openedEvent.objectWillChange.send()
                    openedEvent.replyTo = replyToRoot // NO REPLYTO, SO REPLYTOROOT IS THE REPLYTO
                    
                    replyToRoot.objectWillChange.send()
                    replyToRoot.addToReplies(openedEvent)
                    //                    replyToRoot.repliesCount += 1 // TODO: Count again here?? or we already counted ??
                }
            }
        }
    }
    
    func fixIfWeHavePointingToAlreadyInCache(_ openedEvent:Event) {
        let pointingToEventReq = NSFetchRequest<Event>(entityName: "Event")
        //        pointingToEventReq.predicate = NSPredicate(format: "(kind IN {1,6} AND  (replyToId == %@ OR replyToRootId == %@ OR firstQuoteId == %@)", openedEvent.id, openedEvent.id, openedEvent.id)
        pointingToEventReq.predicate = NSPredicate(format: "kind IN {1,6,9802} AND %@ IN {replyToId,replyToRootId,firstQuoteId}", openedEvent.id)
        // TODO: NEED 6 ALSO OR NOT?
        //            pointingToEventReq.predicate = NSPredicate(format: "kind IN {1,6} AND %@ IN {replyToId,replyToRootId,firstQuoteId}", savedEvent.id)
        pointingToEventReq.sortDescriptors = []
        if let pointingToEvents = try? viewContext.fetch(pointingToEventReq) {
            for event in pointingToEvents {
                if (event.replyToId != nil) && (event.replyToId == openedEvent.id) {
                    event.objectWillChange.send()
                    event.replyTo = openedEvent
                }
                if (event.replyToRootId != nil) && (event.replyToRootId == openedEvent.id) {
                    event.objectWillChange.send()
                    event.replyToRoot = openedEvent
                }
                if (event.firstQuoteId != nil) && (event.firstQuoteId == openedEvent.id) {
                    event.objectWillChange.send()
                    event.firstQuote = openedEvent
                }
            }
        }
    }
}

struct DetailFooterFragment: View {
    @ObservedObject var event:Event
    
    
    var body: some View {
        Divider()
        HStack(spacing: 20) {
            Text("**\(event.mentionsCount)** reposts")//.onTapGesture { }
            
            NavigationLink(value: ViewPath.NoteReactions(event: event)) {
                Text("**\(event.likesCount)** reactions")
            }
                           
            NavigationLink(value: ViewPath.NoteZaps(event: event)) {
                Text("**\(event.zapsCount)** zaps")
            }
        
            Spacer()
        }
        .foregroundColor(.gray)
        .padding(5)
        .font(.system(size: 14))
        Divider()
    }
}


struct ReplyAndParentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            
            if let xx = PreviewFetcher.fetchVPost("a4508aa658b12d51a56613c51da096d7791eb207d3b11407089c633ff73f668d") {
                PostDetailView(vPost: xx)
            }
            if let yt2 = PreviewFetcher.fetchVPost("0000014de66e08882bd36b6b7b551a774f85fe752a18070dc8658d7776db7e69") {
                PostDetailView(vPost: yt2)
            }
            
            if let yt = PreviewFetcher.fetchVPost("c7b4ef377ee4f6d71f6f59bc6bad607acb9c7c3675e3c0b2ca0ad2442b133e49") {
                PostDetailView(vPost: yt)
            }
            
            if let v = PreviewFetcher.fetchVPost("bb15e6165180d31c36b6c3e0baf082eeb949aa473c59e37eaa8e2bb29dc46422") {
                PostDetailView(vPost: v)
            }
            
            if let lastReply = PreviewFetcher.fetchVPost("2026c6b0f0d887aa76cc60f0b3050fe940c8eca9eb479391acb493bb40e4d964") {
                PostDetailView(vPost: lastReply)
            }
            
            if let rootWithReplies = PreviewFetcher.fetchVPost("6f74b952991bb12b61de7c5891706711e51c9e34e9f120498d32226f3c1f4c81") {
                PostDetailView(vPost: rootWithReplies)
            }
            
            
            
            if let v = PreviewFetcher.fetchVPost("c0d76c3c968775a62ca1dea28a73e1fc86d121e8e5e17f2e35aaad1436075f51") {
                PostDetailView(vPost: v)
                
            }
        }
        .withPreviewEnvironment()
    }
}


struct HighlightRenderer: View {
    var vPost:VPost
    
    var body: some View {
        VStack {
            Text(vPost.event.content ?? "")
                .italic()
                .padding(20)
                .overlay(alignment:.topLeading) {
                    Image(systemName: "quote.opening")
                        .foregroundColor(Color.secondary)
                }
                .overlay(alignment:.bottomTrailing) {
                    Image(systemName: "quote.closing")
                        .foregroundColor(Color.secondary)
                }
            
            if let highlightAuthorPubkey = vPost.highlightAuthorPubkey {
                HStack {
                    Spacer()
                    PFP(pubkey: highlightAuthorPubkey, pictureUrl: vPost.highlightAuthorPicture, size: 20, isFollowing: vPost.highlightAuthorIsFollowing)
                    Text(vPost.highlightAuthorName ?? "Unknown")
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    navigateTo(ContactPath(key: highlightAuthorPubkey))
                }
                .padding(.trailing, 40)
            }
            HStack {
                Spacer()
                if let url = vPost.highlightUrl, let md = try? AttributedString(markdown:"[\(url)](\(url))") {
                    Text(md)
                        .lineLimit(1)
                        .font(.caption)
                }
            }
            .padding(.trailing, 40)
        }
        .padding(10)
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(.regularMaterial, lineWidth: 1)
        )
    }
}
