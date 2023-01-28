//
//  MessageDetailView.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/01/2023.
//

import SwiftUI

struct NoteById: View {

    @EnvironmentObject var cm:ConnectionManager

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
                cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEvent(id: id)))
            }
        }
    }
}



// A Note and its repies, shown when tapping on a NoteRow
struct NoteDetail: View {
    
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var cm:ConnectionManager
    @EnvironmentObject var accountState:AccountState
    
    @ObservedObject var event:Event
    
    @FetchRequest
    var taggedContacts:FetchedResults<Contact>
    
    let tweet:Tweet = Tweet(hasThread: false) // Todo
    
    init(event: Event) {
        self.event = event
        let pubkeys = event.contactPubkeys()
        
        if (pubkeys == nil) {
            _taggedContacts = FetchRequest(
                sortDescriptors: [],
                predicate: NSPredicate(format: "FALSEPREDICATE")
            )
        }
        else {
            _taggedContacts = FetchRequest(
                sortDescriptors: [],
                predicate: NSPredicate(format: "pubkey IN %@", pubkeys!)
            )
        }
    }
    
    func rootRepliesUntilThisEvent() -> [Event] {
        guard event.replyToRoot != nil else {
            return []
        }
        return event.replyToRoot!.replies_
            .filter { $0.created_at < event.created_at }
            .filter { $0 != event.replyTo } // Also dont should duplicate .replyTo 
    }
    
    var body: some View {
        
        GeometryReader{ geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack {
                        // Parent root note and other replies to it
                        if (event.replyToRoot != nil) && (event.replyToRoot != event.replyTo) {
                            // ROOT NOTE
                            NoteRow(event: event.replyToRoot!)
                            // REPLIES TO ROOT, UNTIL CURRENT NOTE
                            ForEach(rootRepliesUntilThisEvent(), id:\.self) { event in
                                NoteRow(event: event)
                            }
                        }
                        
                        // Our reply to
                        if (event.replyTo != nil) {
                            NoteRow(event: event.replyTo!)
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
                                // TODO:
                                NoteTextRenderView(event: event, taggedContacts: Array(taggedContacts))
                                        .foregroundColor(.primary)
                                        .textSelection(.enabled)
                                        .font(.system(size: 18))
                                Spacer()
                            }.padding(.vertical,5)
                            
                        }.padding(10)
                        
                        
                        Divider()
                        
                        // Footer
                        HStack { // Footer stats
                            Button(action: {
                                // Handle retweet action
                            }) {
                                HStack {
                                    Image(systemName: "message")
                                    Text("\(event.repliesCount)")
                                }.frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
                            }
                            
                            
                            Button(action: {
                                // Handle retweet action
                            }) {
                                HStack {
                                    Image(systemName: "arrow.2.squarepath")
                                    Text("\(event.mentions)")
                                }.frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
                            }
                            
                            Button(action: {
                                // Handle like action
                            }) {
                                HStack {
                                    Image(systemName: "heart")
                                    Text("\(event.likes)")
                                }.frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
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
                                    Image(systemName: "bookmark.fill")
                                        .foregroundColor(.orange)
                                        .frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
                                }
                                else {
                                    Image(systemName: "bookmark")
                                        .frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
                                }
                            }
                            
                            //                            Toggle(isOn: isBookmarkedBinding) {
                            //                                Image(systemName: isBookmarked() ? "bookmark.fill" : "bookmark")
                            //                                    .foregroundColor( isBookmarked() ? .orange : .gray )
                            //                            }
                            //                            .toggleStyle(.button)
                            //                            .tint(.clear)
                            //                            .frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
                            //
                            
                        }.foregroundColor(.gray)
                        Spacer()
                        
                    }
                    .foregroundColor(.gray)
                    .padding(10)
                        
                    LazyVStack {
                        ForEach (Array(event.replies_), id:\.self) { event in
                            NoteRow(event: event)
                        }
                    }
                    
                    // If there are less than 5 replies, put some empty space so our detail note is at top of screen
                    if (event.replies_.count < 5) {
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
