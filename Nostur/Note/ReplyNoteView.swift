//
//  ReplyNoteView.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/02/2023.
//

import SwiftUI

struct NoteById: View {

    @EnvironmentObject var sp:SocketPool

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
            ReplyNoteView(event: events.first!)
                .onAppear {
                    
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

struct ReplyNoteView: View {
    
    @ObservedObject var event:Event // OUR MAIN NOTE (NOT ROOT)

    var body: some View {
        GeometryReader{ geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    ReplyAndParentView(event: event, geoHeight: geometry.size.height)
                        .onAppear {
                            proxy.scrollTo(event.id)
                        }
                }
            }
        }
    }
}


// Renders reply, and parent
// the parent is another ReplyAndParentView
// so it recursively renders up to the root
struct ReplyAndParentView: View {
    
    @EnvironmentObject var sp:SocketPool
    @ObservedObject var event:Event
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var nav:NavigationModel

    @FetchRequest
    var taggedContacts:FetchedResults<Contact>
    
    var isParent = false
    var geoHeight:CGFloat
    let INDENT = 60.0
    
    init(event: Event, isParent:Bool = false, geoHeight:CGFloat = CGFloat.zero) {
        self.event = event
        self.isParent = isParent
        self.geoHeight = geoHeight
        let pubkeys = event.contactPubkeys()
        
        _taggedContacts = FetchRequest(
            sortDescriptors: [],
            predicate: NSPredicate(format: "pubkey IN %@", pubkeys!)
        )
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
                ReplyAndParentView(event: event.replyTo!, isParent: true)
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
                        NoteTextRenderView(event: event, taggedContacts: Array(taggedContacts), useLinelimit: false)
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
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
                        DetailFooterFragment(event: event)
                            .padding(.leading, isParent ? INDENT : 0)
                        FooterFragment(event: event)
                            .padding(.leading, isParent ? INDENT : 0)
                    }
                    else {
                        FooterFragment(event: event)
                        Divider()
                        
                        // REPLIES TO OUR MAIN NOTE
                        LazyVStack {
                            ForEach (Array(event.replies ?? []), id:\.self) { event in
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
                        if let message = RequestMessage.getTags(event.tags_) {
                            sp.sendMessage(ClientMessage(type: .REQ, message: message))
                        }
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
    
    var body: some View {
        HStack {
            Text("**\(event.mentionsCount)** reposts").onTapGesture { }
            
            Text("**\(event.likesCount)** reactions").onTapGesture { }
            Text("**\(event.zapsCount)** zaps").onTapGesture { }
            
            Spacer()
        }
        .foregroundColor(.gray)
        .padding(.trailing, 5)
        .font(.system(size: 14))
    }
}

struct ReplyAndParentView_Previews: PreviewProvider {
    static var previews: some View {
        let lastReply = PreviewFetcher.fetchEvent("72c8419dbed6381c3a0ae3df5feeeb19f25dae450efb8cb1aebf5201a7f7a8f0")
        
        ReplyNoteView(event: lastReply!)
            .withPreviewEnvironment()
        
        let rootWithReplies = PreviewFetcher.fetchEvent("bc45f59a5f740399ecfbdb38709ad08988797cf56004530b8122125c76f481bd")
        
        ReplyNoteView(event: rootWithReplies!)
            .withPreviewEnvironment()
        
    }
}
