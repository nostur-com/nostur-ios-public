//
//  MessageDetailView.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/01/2023.
//

import SwiftUI

// A Note and its repies, shown when tapping on a NoteRow
struct NoteDetailView: View {
    
    @EnvironmentObject var cm:ConnectionManager
    
    var note:Note
    
    @FetchRequest
    var responses:FetchedResults<Event>
    
    init(_ note:Note) {
        self.note = note
        
        _responses = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
            predicate: NSPredicate(format: "replyToId == %@ AND kind == 1", note.id)
        )
    }
    
    var body: some View {
        NoteDetailViewInner(note:Note(event:note.event, responses:responses.reversed(), contact: note.contact))
    }
}

// A Note and its repies, shown when tapping on a NoteRow
struct NoteDetailViewInner: View {
    var tweet : Tweet = Tweet()
    let note:Note
    @EnvironmentObject var cm:ConnectionManager
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)],
        animation: .none)
    var contacts:FetchedResults<Contact>
    
    func contact(byPubkey:String?) -> Contact? {
        guard byPubkey != nil else {
            return nil
        }
        return contacts.first(where: { ($0.pubkey != nil) && $0.pubkey == byPubkey})
    }
    
    func allContactPubkeys() -> Set<String> {
        return Set(contacts.map { $0.pubkey! })
    }
    
    
    var body: some View {
        ScrollView {
            VStack {
                // Parent Tweet
                
                
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
                        if (note.contact != nil) {
                            NavigationLink(value: note.contact, label: {
                                ProfilePicView(pubkey: note.publicKey, contact:note.contact)
                                    .frame(width:50, height:50)
                                    .clipShape(Circle())
                            })
                        }
                        else {
                            NavigationLink(value: note.publicKey, label: {
                                ProfilePicView(pubkey: note.publicKey)
                                    .frame(width:50, height:50)
                                    .clipShape(Circle())
                            })
                        }
                        // name and username
                        
                        HStack {
                            VStack {
                                
                                HStack(spacing:2) {
                                    Text(note.authorName) // Name
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
                                    Text("@\(note.username)") // Username
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                
                            }//.border(.red)
                        }
                        
                        NoteMenuView(note)
                    }
//                    .background(.red)
                    // "Replying to"
                    if (note.event.replyToId != nil) {
                        HStack {
                            Text("Replying to @\(String(note.event.replyToId!.prefix(5)))")
                            Spacer()
                        }
                    }
                    // Tweet
                    HStack {
                        Text(note.noteText)
                            .textSelection(.enabled)
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
                            Text("\(note.responses?.count ?? 0)")
                        }.frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
                    }
    //                Spacer()
                    Button(action: {
                        // Handle retweet action
                    }) {
                        HStack {
                            Image(systemName: "arrow.2.squarepath")
                            Text("\(note.event.mentions)")
                        }.frame(maxWidth: .infinity, alignment: .center).font(.system(size: 14))
                    }
    //                Spacer()
                    Button(action: {
                        // Handle like action
                    }) {
                        HStack {
                            Image(systemName: "heart")
                            Text("\(note.event.likes)")
                        }.frame(maxWidth: .infinity, alignment: .trailing).font(.system(size: 14))
                    }
                    Spacer()
                }.foregroundColor(.gray)
                    .padding(10)
                
                // Replies TODO
                
                if (note.responses != nil) {
                    LazyVStack {
                        ForEach (note.responses!, id:\.id) { row in
                            NoteRowView(note:Note(event:row))
                        }
                    }
                }
                
                // Finished
                Spacer()
            }
        }
        .onAppear {
            
            print("onAPEAAR)")
            if (note.responses == nil) {
                return
            }
            
            print("onAPEAffffffR)")
            // all known pubkeys SET
            let allContactPubkeys = allContactPubkeys()
            let responsesPubkeys:Set<String> = Set(note.responses!.map { $0.pubkey! })
            
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

// FOR PREVIEW
struct NoteDetailViewWrapper: View {
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)],
        predicate: NSPredicate(format: "pubkey == %@", "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"),
        animation: .none)
    var contacts:FetchedResults<Contact>

    // note.id 6f74b952991bb12b61de7c5891706711e51c9e34e9f120498d32226f3c1f4c81
    // pubkey: 5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
        predicate: NSPredicate(format: "id == %@", "6f74b952991bb12b61de7c5891706711e51c9e34e9f120498d32226f3c1f4c81"),
        animation: .none)
    var events: FetchedResults<Event>

    // note.id 6f74b952991bb12b61de7c5891706711e51c9e34e9f120498d32226f3c1f4c81
    // pubkey: 5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
        predicate: NSPredicate(format: "replyToId == %@", "6f74b952991bb12b61de7c5891706711e51c9e34e9f120498d32226f3c1f4c81"),
        animation: .none)
    var responses: FetchedResults<Event>
    
    var body: some View {
        
        VStack {
            NoteDetailViewInner(note:Note(event:events.first!, responses:responses.reversed(), contact: contacts.first))
        }
    }
}

struct NoteDetailView_Previews: PreviewProvider {
    static var previews: some View {
        
        NoteDetailViewWrapper()
            .withPreviewEnvironment()
        
    }
}
