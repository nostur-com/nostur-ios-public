//
//  ReplyNoteView.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/02/2023.
//

import SwiftUI
import LightningDevKit

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
            NoteDetail(event: events.first!)
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

struct NoteDetail: View {
    
    @ObservedObject var event:Event // OUR MAIN NOTE (NOT ROOT)

    var body: some View {
        GeometryReader{ geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    NoteAndParent(event: event, geoHeight: geometry.size.height)
                        .onAppear {
                            proxy.scrollTo(event.id)
                        }
                }
            }
        }
//        .toolbar(.hidden, for: .navigationBar)
    }
}


// Renders reply, and parent
// the parent is another ReplyAndParentView
// so it recursively renders up to the root
struct NoteAndParent: View {
    
//    @EnvironmentObject var sp:SocketPool
    var sp:SocketPool = .shared
    @ObservedObject var event:Event
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
//    @EnvironmentObject var nav:NavigationModel
    var nav:NavigationModel = .shared

//    @FetchRequest
//    var taggedContacts:FetchedResults<Contact>
    
    var isParent = false
    var geoHeight:CGFloat
    let INDENT = 60.0
    
    enum type {
        case note
        case lightningInvoice
    }
    
    let type:NoteRowView.type
    
    init(event: Event, isParent:Bool = false, geoHeight:CGFloat = CGFloat.zero) {
        self.event = event
        self.isParent = isParent
        self.geoHeight = geoHeight
//        let pubkeys = event.contactPubkeys()
//
//        _taggedContacts = FetchRequest(
//            sortDescriptors: [],
//            predicate: NSPredicate(format: "pubkey IN %@", pubkeys!)
//        )
        if event.noteText.prefix(4).lowercased() == "lnbc" && Invoice.fromStr(s: event.noteText).getValue() != nil {
            self.type = .lightningInvoice
        }
        else {
            self.type = .note
        }
    }
    
    var body: some View {
        VStack {
            // PARENT: IF MISSING, FETCH IT
            if (event.replyTo == nil && event.replyToId != nil) {
                
                ProgressView()
//                // TODO: FETCH ALL AT START WITH #E INSTEAD OF HERE?
//                    .onAppear {
//                    print("🤩🤩 🦋🦋 Fetching .replyTo \(event.replyToId!) ")
//                    sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEvent(id: event.replyToId!)))
//                }
            }
            // PARENT: IF AVAILABLE, RENDER IT
            else if (event.replyTo != nil) {
                NoteAndParent(event: event.replyTo!, isParent: true)
            }
            // OUR (DETAIL) REPLY:
            
            VStack(alignment: .leading, spacing: 3) {
                    // PFP | NAME/USERNAME/AGO
                    HStack {
                        NavigationLink(value: ContactPath(key: event.pubkey!), label: {
                            ProfilePic(event: event)
                                .frame(width:50, height:50)
                                .clipShape(Circle())
                        })
                        
                        VStack(alignment: .leading) { // name + reply + context menu
                            NoteHeader(event:event, singleLine: isParent)
                            if (isParent) {
                                ReplyingToFragment(event: event)
                            }
                        }//.background(.red)
                        Spacer()
                        NoteMenu(event: event)
                    }//.background(.yellow)
                    .id(event.id)
                    
                    if (!isParent) {
                        HStack {
                            ReplyingToFragment(event: event)
                            Spacer()
                        }
                    }
                    
                    HStack {
                        
                        switch self.type {
                            case .lightningInvoice:
                                LightningInvoice(invoice: event.noteText)
//                                        .onAppear {
//                                            withAnimation(.easeInOut(duration: 2.0)) {
//                                                backgroundColor = Color(uiColor: .systemBackground)
//                                            }
//                                        }
                            default:
                                NoteTextRenderView(event: event, useLinelimit: false)
                                        .foregroundColor(.primary)
                                        .textSelection(.enabled)
//                                    .onTapGesture { nav.navigateTo(event) }
//                                        .onAppear {
//                                            withAnimation(.easeInOut(duration: 2.0)) {
//                                                backgroundColor = Color(uiColor: .systemBackground)
//                                            }
//                                        }
                        }
                        
                        
//                                .font(.system(size: 18))
//                        Spacer()
                    }//.background(.pink)
                //.padding(.vertical,5)
                        .padding(.leading, isParent ? INDENT : 0)
                        
                    
                    if (event.firstQuoteId != nil) {
                        if (event.firstQuote != nil) {
                            QuotedNoteFragment(event: event.firstQuote!)
                                .padding(.leading, isParent ? INDENT : 0)
                        }
                        else {
                            ProgressView()
                                .padding(.leading, isParent ? INDENT : 0)
                                .onAppear {
                                    // TODO: CAN FETCH WITH #E OR NO?
                                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEvent(id: event.firstQuoteId!)))
                            }
                        }
                    }
                    
                    if (isParent) {
                        FooterFragment(event: event)
                            .padding(.leading, isParent ? INDENT : 0)
                    }
                    else {
                        DetailFooterFragment(event: event)
                            .padding(.leading, isParent ? INDENT : 0)
                        FooterFragment(event: event)
                        Divider()
                        
                        // REPLIES TO OUR MAIN NOTE
                        LazyVStack {
                            ForEach (event.replies_, id:\.self) { event in
                                NoteRowView(event: event)
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
                    nav.navigateTo(event)
                }
                .onAppear {
                    if (event.contact == nil) {
                        // TODO: Still needed? or below sp.send is already taking care of this?
                        sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: event.pubkey!)))
                    }
                    
                    if (!isParent) {
                        // Fetch all related (e and p.kind=0)
                        // (the events and contacts mentioned in this DETAIL NOTE.
                        if let message = RequestMessage.getTags(event.tags()) {
                            sp.sendMessage(ClientMessage(type: .REQ, message: message))
                        }
                        
                        // Fetch all that reference this detail note (Replies, zaps, reactions)
                        sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEventReferences(ids: [event.id!])))
                        
                        
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
        let lastReply = PreviewFetcher.fetchEvent("2026c6b0f0d887aa76cc60f0b3050fe940c8eca9eb479391acb493bb40e4d964")

        if (lastReply != nil) {
            NoteDetail(event: lastReply!)
                .withPreviewEnvironment()
        }
        
        let rootWithReplies = PreviewFetcher.fetchEvent("6f74b952991bb12b61de7c5891706711e51c9e34e9f120498d32226f3c1f4c81")
        
        if (rootWithReplies != nil) {
            NoteDetail(event: rootWithReplies!)
                .withPreviewEnvironment()
        }
        
        let noteWithAsingleMention = PreviewFetcher.fetchEvent("c0d76c3c968775a62ca1dea28a73e1fc86d121e8e5e17f2e35aaad1436075f51")
        
        if (noteWithAsingleMention != nil) {
            NoteDetail(event: noteWithAsingleMention!)
                .withPreviewEnvironment()
        }
        
    }
}
