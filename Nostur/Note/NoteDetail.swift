//
//  MessageDetailView.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/01/2023.
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
            NoteDetail(event: events.first!)
        }
        else {
            Text("Trying to fetch...").onAppear {
                // .REQ
                print("🟢 NoteById.onAppear no event so REQ.1: \(id)")
                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEvent(id: id)))
            }
        }
    }
}



// A Note and its repies, shown when tapping on a NoteRow
struct NoteDetail: View {
    
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var sp:SocketPool
    @EnvironmentObject var ns:NosturState
    
    @ObservedObject var event:Event // @ObserverdObject + objectWillChange.send() in Imported is needed!
//    var event:Event // TODO: Need @ObservedObject here or not?
    
    @FetchRequest
    var taggedContacts:FetchedResults<Contact>
    
    let tweet:Tweet = Tweet(hasThread: false) // Todo
    
    init(event: Event) {
        self.event = event
        let pubkeys = event.contactPubkeys()        
        
        _taggedContacts = FetchRequest(
            sortDescriptors: [],
            predicate: NSPredicate(format: "pubkey IN %@", pubkeys!)
        )
    }
    
    func rootRepliesUntilThisEvent() -> [Event] {
        guard event.replyToRoot != nil else {
            return []
        }
        return event.replyToRoot!.replies?
            .filter { $0.created_at < event.created_at }
            .filter { $0 != event.replyTo } // Also dont should duplicate .replyTo
        ?? []
    }
    
    var body: some View {
        
        GeometryReader{ geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack {
                        
                        if (1 == 1) {
                        
                        // Parent root note and other replies to it
                        if (event.replyToRoot != nil) && (event.replyToRoot != event.replyTo) {
                            if (event.replyToRoot!.replyTo != nil) {
                                // uhm how are we going to turtles all the way up this thing?
                                // for now just manual hack until here
                                NoteRowView(event: event.replyToRoot!.replyTo!)
                            }

                            // ROOT NOTE
                            NoteRowView(event: event.replyToRoot!)
                            // REPLIES TO ROOT, UNTIL CURRENT NOTE
                            ForEach(rootRepliesUntilThisEvent(), id:\.self) { event in
                                NoteRowView(event: event)
                            }
                        }
                        else if (event.replyToRootId != nil) && (event.replyToId != event.replyToRootId) {
                            ProgressView().onAppear {
                                print("🤩🤩 🦋🦋 Fetching .replyToRoot \(event.replyToRootId!) ")
                                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEvent(id: event.replyToRootId!)))
                                // TODO: CHECK IF NOT ALREADY FETCHED BY EARLIER VIEWS
                            }
                        }
                        
                        // Our reply to
                        if (event.replyTo != nil) {
                            NoteRowView(event: event.replyTo!)
                        }
                        else if (event.replyToId != nil) {
                            ProgressView().onAppear {
                                print("🤩🤩 🦋🦋 Fetching .replyTo \(event.replyToId!) ")
                                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEvent(id: event.replyToId!)))
                                // TODO: CHECK IF NOT ALREADY FETCHED BY EARLIER VIEWS
                            }
                        }
                        
                        }
                        
                        VStack {
                            // Retweeted header
                            if tweet.retweetedByName != "" {
                                HStack { // retweet header
                                    // Retweet icon
                                    Image(systemName:"arrow.2.squarepath")
                                        .font(.system(size: 12, weight: .heavy))
                                    //                    .shadow(color: .gray, radius: 2, x: 3, y: 3)
                                        .foregroundColor(.secondary)
                                    //                    .scaleEffect(0.7)
                                        .frame(maxWidth:50, alignment: .trailing)
                                    Text("\(tweet.retweetedByName) Retweeted")
                                        .font(
                                            .system(size: 12)
                                            .weight(.heavy)
                                        )
                                    //                    .font(.system(size: 12, weight: .heavy))
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    // Retweeter name
                                    
                                }.padding(.leading, 10)
                            }
                            
                            // PFP | NAME/USERNAME/AGO
                            HStack {
                                if (event.contact != nil) {
                                    NavigationLink(value: ContactPath(key: event.pubkey!), label: {
                                        ProfilePicView(pubkey: event.pubkey!, contact:event.contact!)
                                            .frame(width:50, height:50)
                                            .clipShape(Circle())
                                    })
                                }
                                else {
                                    NavigationLink(value: ContactPath(key: event.pubkey!), label: {
                                        ProfilePicView(pubkey: event.pubkey!)
                                            .frame(width:50, height:50)
                                            .clipShape(Circle())
                                    })
                                }
                                
                                // name and username
                                HStack {
                                    VStack {
                                        // name + verified
                                        HStack(spacing:2) {
                                            Text(event.contact?.authorName ?? "Anon") // Name
                                                .font(.system(size: 14))
                                                .fontWeight(.bold)
                                            
                                            if tweet.isVerified { // Verification check
                                                Image(systemName: "checkmark.seal.fill")
                                                    .foregroundColor(.blue)
                                                    .font(.system(size: 13))
                                            }
                                            Spacer()
                                        }
                                        // username
                                        HStack {
                                            Text("@\(event.contact?.username ?? event.authorKey)") // Username
                                                .font(.system(size: 14))
                                                .foregroundColor(.secondary)
                                            Spacer()
                                        }
                                    }
                                }
                                
                                NoteMenu(event: event)
                            }
                            .id("NoteAnchorID")
                            
                            HStack {
                                ReplyingToFragment(event: event)
                                Spacer()
                            }
                            
                            // Tweet
                            HStack {
                                NoteTextRenderView(event: event, taggedContacts: Array(taggedContacts), useLinelimit: false)
                                        .foregroundColor(.primary)
                                        .textSelection(.enabled)
                                        .font(.system(size: 18))
                                Spacer()
                            }.padding(.vertical,5)
                            
                            if (event.firstQuoteId != nil) {
                                if (event.firstQuote != nil) {
                                    QuotedNoteFragment(event: event.firstQuote!)
                                }
                                else {
                                    ProgressView().onAppear {
                                        sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEvent(id: event.firstQuoteId!)))
                                    }
                                }
                            }
                            
                            DetailFooterFragment(event: event)
                        }.padding(10)
                    
                        Divider()
                                            
                    }
                    .foregroundColor(.gray)
                    .padding(10)
                        
                    LazyVStack {
                        ForEach (Array(event.replies ?? []), id:\.self) { event in
                            NoteRowView(event: event)
                        }
                    }
                    
                    // If there are less than 5 replies, put some empty space so our detail note is at top of screen
                    if (1 == 1) && (event.replies?.count ?? 0 < 5) {
                        let height = geometry.size.height - 280
                        Rectangle().frame(width: 100, height: (height < 280 ? 400 : height))
                            .background(.clear)
                            .foregroundColor(.clear)
                    }
                    
                    Spacer()
                }
                .onAppear {
                    proxy.scrollTo("NoteAnchorID")
                }
//                .ignoresSafeArea(edges: .top)
            }
        }
        .onAppear {
            
//            print("onAPEAAR)")
//            if (event.replies.count == 0) {
//                return
//            }
//            
//            print("onAPEAffffffR)")
            // all known pubkeys SET
//            let allContactPubkeys = allContactPubkeys()
//            let responsesPubkeys:Set<String> = Set(responses.map { $0.pubkey! })
            
            // .REQ meta for all responses
//            let pubkeysToRequest = responsesPubkeys.subtracting(allContactPubkeys)
            
//            print("onAPEAdfsfdsdsdsdAR) \(pubkeysToRequest.count)")
            
//            if (pubkeysToRequest.count > 0) {
//                cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: Array(pubkeysToRequest), limit: 200)))
//            }

            // SET A is NOT in B
            //cm.REQ
            
            
        }
    }
}

struct DetailFooterFragment: View {
    
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    @ObservedObject var event:Event
    
    var body: some View {
        VStack(alignment: .center) {
            HStack(alignment: .center) { // Footer stats
//                Spacer()
                Button {

                } label: {
                    Label("\(event.repliesCount)", systemImage: "message")
                }
                Spacer()
                Button {
                    
                } label: {
                    Label("\(event.mentions)", systemImage: "arrow.2.squarepath")
                }
                Spacer()
                if (event.liked) {
                    Label("\(event.likes)", systemImage: "heart.fill").foregroundColor(.red)
                }
                else {
                    Button {
                        if (ns.account != nil) {
                            print("💖💖💖💖💖💖💖💖💖💖💖💖💖💖")
                            event.liked = true
                            event.likes = event.likes + 1
                            ns.account?.addToLikes(event)
                            
                            // 1. create kind 7 event based on kind 1 event:    Event
                            let likeEvent = EventMessageBuilder.makeReactionEvent(reactingTo: event)
                            
                            // 2. sign that event with account keys             Account
                            guard let signedEvent = try? ns.signEvent(likeEvent) else {
                                print("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
                                return
                            }
                            
                            // 3. Save in core data                             NSManagedObjectContext
                            let savedEvent = Event.saveEvent(event: signedEvent, context: viewContext)
                            do {
                                try viewContext.save()
                            }
                            catch {
                                print("🔴🔴🔴🔴🔴 COULD NOT SAVE EVENT 🔴🔴🔴🔴🔴")
                                print(error)
                                return
                            }

                            // 4. publish that event                            SocketPool
                            print("Should send: \(NRelayMessage(event: savedEvent.toNEvent()).message)")
                            
                            print("💖💖💖💖💖💖💖💖💖💖💖💖💖💖")
                        }
                    } label: {
                        Label("\(event.likes)", systemImage: "heart")
                    }
                }
                Spacer()
                Button {
                    if (ns.isBookmarked(event)) {
                        ns.removeBookmark(event)
                    }
                    else {
                        ns.addBookmark(event)
                    }
                } label: {
                    if (ns.isBookmarked(event)) {
                        Image(systemName: "bookmark.fill")
                            .foregroundColor(.orange)
//                            .frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
                    }
                    else {
                        Image(systemName: "bookmark")
//                            .frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
                    }
                }
//                Spacer()
            }.foregroundColor(.gray)
        }
    }
}

struct NoteDetailViewX_Previews: PreviewProvider {
    
    static var previews: some View {
        
        // A reply note
        // cae92f22295c2109a4596a373caeaa706bd140e4a71419722014f223ae681bce
        // ..replying to: 77045e500913f9cf78a5e3e1c16137702046dbbe1cc84c5a2621bad69945eb42
        // ..and the root: 6f74b952991bb12b61de7c5891706711e51c9e34e9f120498d32226f3c1f4c81
        
        // #[2]
        // 115eab2976aee4ca562d83ea6b1d805c6d4e0acf54fe2e6a4e1a62f73c2850cc
        
        // #[0]
        // 1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0
        
        // note.id 6f74b952991bb12b61de7c5891706711e51c9e34e9f120498d32226f3c1f4c81
        // pubkey: 5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0
        
        let event = PreviewFetcher.fetchEvent("cae92f22295c2109a4596a373caeaa706bd140e4a71419722014f223ae681bce")
        
        NoteDetail(event: event!)
            .withPreviewEnvironment()
//            .padding(20)
        
    }
}
