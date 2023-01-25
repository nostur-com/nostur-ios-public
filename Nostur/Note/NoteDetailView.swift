//
//  MessageDetailView.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/01/2023.
//

import SwiftUI

// A Note and its replies, shown when tapping on a NoteRow
struct NoteDetailView: View {
    
    @EnvironmentObject var cm:ConnectionManager
    
    var id:String
    
    @FetchRequest
    var events:FetchedResults<Event>
    
    @FetchRequest
    var responses:FetchedResults<Event>
    
    init(id:String) {
        self.id = id
        
        _events = FetchRequest(
            sortDescriptors: [],
            predicate: NSPredicate(format: "id == %@", id)
        )
        
        _responses = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
            predicate: NSPredicate(format: "replyToId == %@ AND kind == 1", id)
        )
    }
    
    var body: some View {
        if (events.first != nil) {
            NoteDetailViewInner(event:events.first!, responses:responses)
        }
        else {
            Text("Note event not found... should fetch here").onAppear {
                // .REQ
            }
        }
    }
}

// A Note and its repies, shown when tapping on a NoteRow
struct NoteDetailViewInner: View {
    
    var event:Event
    var responses:FetchedResults<Event>
    
    var tweet : Tweet = Tweet()

    @EnvironmentObject var cm:ConnectionManager
    @EnvironmentObject var accountState:AccountState
    
    // ALL CONTACTS FOR P TAGS KEY TO USERNAME
    @FetchRequest(
        sortDescriptors: [],
        animation: .none)
    var contacts:FetchedResults<Contact>
    
    @FetchRequest(
        sortDescriptors: [],
        animation: .none)
    var authors:FetchedResults<Contact>
    
    func contact(byPubkey:String?) -> Contact? {
        guard byPubkey != nil else {
            return nil
        }
        return contacts.first(where: { ($0.pubkey != nil) && $0.pubkey == byPubkey})
    }
    
    func allContactPubkeys() -> Set<String> {
        return Set(contacts.map { $0.pubkey! })
    }
    
    @FetchRequest(
        sortDescriptors: [],
        animation: .none)
    var rootAndItsReplies:FetchedResults<Event>
    
    init(event: Event, responses: FetchedResults<Event>) {
        self.event = event
        self.responses = responses
        
        _authors = FetchRequest(
            sortDescriptors: [],
            predicate: NSPredicate(format: "pubkey == %@", event.pubkey!)
        )
        
        if (event.replyToRootId != nil) {
            _rootAndItsReplies = FetchRequest(
                sortDescriptors: [SortDescriptor(\Event.created_at, order: .forward)],
                predicate: NSPredicate(format: "kind == 1 AND (id == %@ OR replyToId == %@) AND (created_at < %d)", event.replyToRootId!, event.replyToRootId!, event.created_at)
            )
        }
    }
    
    
    var body: some View {
        ScrollView {
            VStack {
                // Parent Tweet
                
                if (event.replyToRootId != nil) {
                    ForEach(rootAndItsReplies, id:\.self) { event in
                        NoteRowView(event: event)
                    }
                }
                
                if (event.replyToId != nil) {
                    NoteRowView(id: event.replyToId!)
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
                    
                    HStack {
                        if (authors.first != nil) {
                            NavigationLink(value: ContactPath(key: event.pubkey!), label: {
                                ProfilePicView(pubkey: event.pubkey!, contact:authors.first)
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
                                
                                HStack(spacing:2) {
                                    Text(authors.first?.authorName ?? "Anon") // Name
                                        .font(.system(size: 14))
                                        .fontWeight(.bold)
                                    
                                    if tweet.isVerified { // Verification check
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundColor(.blue)
                                            .font(.system(size: 13))
                                    }
                                    Spacer()
                                }
                                
                                HStack {
                                    Text("@\(authors.first?.username ?? event.authorKey)") // Username
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                
                            }//.border(.red)
                        }
                        
                        NoteMenuView(event: event, author: authors.first)
                    }
//                    .background(.red)
                    // "Replying to"
                    if (event.replyToId != nil) {
                        HStack {
                            Text("Replying to @\(String(event.replyToId!.prefix(5)))")
                            Spacer()
                        }
                    }
                    // Tweet
                    HStack {
                        NoteTextRenderView(event: event, allContacts: contacts.reversed())
//                        Text(event.noteText)
//                            .textSelection(.enabled)
                            .font(.system(size: 18))//.border(.red)
                        Spacer()
                    }.padding(.vertical,5)
                        
                }.padding(10)
                
                
                Divider()

                // Footer
                HStack { // Footer stats
                    Spacer()
                    Button(action: {
                        // Handle retweet action
                    }) {
                        HStack {
                            Image(systemName: "message")
                            Text("\(responses.count)")
                        }.frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
                    }
    //                Spacer()
                    Button(action: {
                        // Handle retweet action
                    }) {
                        HStack {
                            Image(systemName: "arrow.2.squarepath")
                            Text("\(event.mentions)")
                        }.frame(maxWidth: .infinity, alignment: .center).font(.system(size: 14))
                    }
    //                Spacer()
                    Button(action: {
                        // Handle like action
                    }) {
                        HStack {
                            Image(systemName: "heart")
                            Text("\(event.likes)")
                        }.frame(maxWidth: .infinity, alignment: .trailing).font(.system(size: 14))
                    }
                    
                    
                    Button {
                        if (accountState.isBookmarked(event)) {
                            accountState.removeBookmark(event)
                        }
                        else {
                            accountState.addBookmark(event)
                        }
                    } label: {
                        if (accountState.isBookmarked(event)) {
                            Label("", systemImage: "bookmark.fill").foregroundColor(.orange)
                        }
                        else {
                            Label("", systemImage: "bookmark")
                        }
                    }.frame(maxWidth: .infinity, alignment: .trailing).font(.system(size: 14))
                    
                    
                    Spacer()
                }.foregroundColor(.gray)
                    .padding(10)
                
                LazyVStack {
                    ForEach (responses, id:\.id) { event in
                        NoteRowView(event: event)
                    }
                }
                Spacer()
            }
        }
        .onAppear {
            
            print("onAPEAAR)")
            if (responses.count == 0) {
                return
            }
            
            print("onAPEAffffffR)")
            // all known pubkeys SET
            let allContactPubkeys = allContactPubkeys()
            let responsesPubkeys:Set<String> = Set(responses.map { $0.pubkey! })
            
            // .REQ meta for all responses
            let pubkeysToRequest = responsesPubkeys.subtracting(allContactPubkeys)
            
            print("onAPEAdfsfdsdsdsdAR) \(pubkeysToRequest.count)")
            
            if (pubkeysToRequest.count > 0) {
                cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: Array(pubkeysToRequest), limit: 200)))
            }

            // SET A is NOT in B
            //cm.REQ
            
        }
    }
}

struct NoteDetailView_Previews: PreviewProvider {
    
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
        
        NoteDetailView(id: "cae92f22295c2109a4596a373caeaa706bd140e4a71419722014f223ae681bce")
            .withPreviewEnvironment()
        
    }
}
