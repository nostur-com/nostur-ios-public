//
//  ReplyNoteView.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/02/2023.
//

import SwiftUI

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
                ProgressView().onAppear {
                    print("🤩🤩 🦋🦋 Fetching .replyTo \(event.replyToId!) ")
                    sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEvent(id: event.replyToId!)))
                }
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
                }//.padding(10)
                .background(MaybeThreadLine(isParent: isParent))
                .onTapGesture {
                    nav.navigateTo(event)
                }
                .onAppear {
                    if (event.contact == nil) {
                        sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: event.pubkey!)))
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
