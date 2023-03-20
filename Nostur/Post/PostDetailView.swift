//
//  PostDetailView.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/02/2023.
//

import SwiftUI
import LightningDevKit
import CoreData

struct NoteById: View {

//    @EnvironmentObject var sp:SocketPool
    var sp:SocketPool = .shared

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
            PostDetailView(vPost: events.first!.toVPost())
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
    @EnvironmentObject var nav:NavigationModel
    var navTitleHidden:Bool = false
    
    var isParent = false
    var geoHeight:CGFloat
    let INDENT = 60.0
    
    enum type {
        case note
        case lightningInvoice
    }
    
    let type:NoteRow.type
    
    init(vPost: VPost, isParent:Bool = false, geoHeight:CGFloat = CGFloat.zero, navTitleHidden:Bool = false) {
        self.vPost = vPost
        self.event = vPost.event
        self.isParent = isParent
        self.geoHeight = geoHeight
        self.navTitleHidden = navTitleHidden
        if vPost.event.noteText.prefix(4).lowercased() == "lnbc" && Invoice.fromStr(s: vPost.event.noteText).getValue() != nil {
            self.type = .lightningInvoice
        }
        else {
            self.type = .note
        }
    }
    
    var body: some View {
        VStack {
            // MARK: PARENT NOTE
            // IF MISSING, FETCH IT
            if (event.replyTo == nil && event.replyToId != nil) {
                
                CenteredProgressView()
//                // TODO: FETCH ALL AT START WITH #E INSTEAD OF HERE?
//                    .onAppear {
//                    print("🤩🤩 🦋🦋 Fetching .replyTo \(event.replyToId!) ")
//                    sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEvent(id: event.replyToId!)))
//                }
            }
            // PARENT: IF AVAILABLE, RENDER IT
            else if (event.replyTo != nil) {
                PostAndParent(vPost: event.replyTo!.toVPost(), isParent: true)
            }
            // OUR (DETAIL) REPLY:
            // MARK: DETAIL NOTE
            VStack(alignment: .leading, spacing: 3) {
                    // PFP | NAME/USERNAME/AGO
                    HStack {
                        NavigationLink(value: ContactPath(key: event.pubkey), label: {
                            PFP(pubkey: event.pubkey, pictureUrl: event.contact?.picture, size: 50)
                        })
                        
                        VStack(alignment: .leading) { // name + reply + context menu
                            NoteHeaderView(vPost: vPost, singleLine: isParent)
                            if (isParent) {
                                ReplyingToFragmentView(vPost: vPost)
                            }
                        }//.background(.red)
                        Spacer()
                        EventPrivateNoteToggle(event: event)
                        NoteMenuView(vPost: vPost)
                    }//.background(.yellow)
                    .id(event.id)
                    
                    if (!isParent) {
                        HStack {
                            ReplyingToFragmentView(vPost: vPost)
                            Spacer()
                        }
                    }
                    
                    VStack(alignment:.leading) {
                        
                        switch self.type {
                            case .lightningInvoice:
                                LightningInvoice(invoice: event.noteText)
                            default:
                                NoteTextRenderView(vPost: vPost, useLinelimit: false)
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                                    .onTapGesture { nav.navigateTo(vPost) }
                                ImageViewer(imgUrls: vPost.imageUrls, pubkey: event.pubkey)
                        }
                    }
                    .padding(.leading, isParent ? INDENT : 0)
                        
                // MARK: QUOTED NOTE IN DETAIL NOTE
                    if (event.firstQuoteId != nil) {
                        if (vPost.event.firstQuote != nil) {
                            QuotedNoteFragmentView(vPost: event.firstQuote!.toVPost())
                                .padding(.leading, isParent ? INDENT : 0)
                        }
                        else {
                            CenteredProgressView()
                                .padding(.leading, isParent ? INDENT : 0)
                                .onAppear {
                                    // TODO: CAN FETCH WITH #E OR NO?
                                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEvent(id: event.firstQuoteId!)))
                            }
                        }
                    }
                    
                    if (isParent) {
                        FooterFragmentView(event: event)
                            .padding(.leading, isParent ? INDENT : 0)
                            .padding(.vertical, 5)
                            .padding(.trailing, 5)
                        Divider()
                    }
                    else {
                        DetailFooterFragment(event: event)
                            .padding(.leading, isParent ? INDENT : 0)
                        FooterFragmentView(event: vPost.event)
                            .padding(.vertical, 5)
                        Divider()
                        
                        // MARK: REPLIES TO OUR MAIN NOTE
                        LazyVStack {
                            ForEach (event.replies_.filter({ event in
                                    if ns.account != nil {
                                        return !(Set(ns.account!.blockedPubkeys_)).contains(event.pubkey)
                                    }
                                    else {
                                        return true
                                    }
                                }), id:\.self) { event in
                                    NoteRow(vPost: event.toVPost(), hideFooter: false)
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
                .padding(!isParent ? 10 : 0)
                .background(MaybeThreadLine(isParent: isParent))
                .onTapGesture {
                    if (isParent) {
                        nav.navigateTo(vPost)
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
            
//            Spacer()
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
        pointingToEventReq.predicate = NSPredicate(format: "kind IN {1,6} AND %@ IN {replyToId,replyToRootId,firstQuoteId}", openedEvent.id)
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

struct MaybeThreadLine: View {
    var isParent:Bool

    var body: some View {
        if (isParent) {
            HStack {
                Rectangle().frame(width: 1).foregroundColor(.gray).opacity(0.5)
                    .padding(.leading, 25)
                Spacer()
            }
        }
    }
}

struct DetailFooterFragment: View {
    @ObservedObject var event:Event
    @EnvironmentObject var nav:NavigationModel

    var body: some View {
        Divider()
        HStack(spacing: 20) {
            Text("**\(event.mentionsCount)** reposts").onTapGesture { }

            Text("**\(event.likesCount)** reactions").onTapGesture {
                nav.navigateTo(ViewPath.NoteReactions(event: event))
            }
            Text("**\(event.zapsCount)** zaps").onTapGesture {
                nav.navigateTo(ViewPath.NoteZaps(event: event))
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
        let lastReply = PreviewFetcher.fetchVPost("2026c6b0f0d887aa76cc60f0b3050fe940c8eca9eb479391acb493bb40e4d964")

        if (lastReply != nil) {
            PostDetailView(vPost: lastReply!)
                .withPreviewEnvironment()
        }
        
        let rootWithReplies = PreviewFetcher.fetchVPost("6f74b952991bb12b61de7c5891706711e51c9e34e9f120498d32226f3c1f4c81")
        
        if (rootWithReplies != nil) {
            PostDetailView(vPost: rootWithReplies!)
                .withPreviewEnvironment()
        }
        
        let noteWithAsingleMention = PreviewFetcher.fetchVPost("c0d76c3c968775a62ca1dea28a73e1fc86d121e8e5e17f2e35aaad1436075f51")
        
        if (noteWithAsingleMention != nil) {
            PostDetailView(vPost: noteWithAsingleMention!)
                .withPreviewEnvironment()
        }
        
    }
}
