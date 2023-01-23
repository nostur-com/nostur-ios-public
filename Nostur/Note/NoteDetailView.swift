//
//  MessageDetailView.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/01/2023.
//

import SwiftUI

struct NoteDetailView: View {
    var tweet : Tweet = Tweet()
    let note:Note
    
    init(_ note:Note) {
        self.note = note
    }
    
    var body: some View {
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
                    // profile image
//                    Image(tweet.profileImageName).resizable().scaledToFit()
//                        .clipShape(Circle())
//                        .shadow(color: .gray, radius: 1.0)
//                        .frame(maxWidth:50, maxHeight:50)
                    
                    if (note.contact != nil) {
                        ProfilePicView(pubkey: note.publicKey, contact: note.contact!)
                            .frame(maxWidth:50, maxHeight:50)
                    }
                    else {
                        ProfilePicView(pubkey: note.publicKey)
                            .frame(maxWidth:50, maxHeight:50)
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
                    
                    Menu {
                        Button {
                            print("Unfollow @\(note.username)")
                        } label: {
                            Label("Unfollow @\(note.username)", systemImage: "person.fill.xmark")
                        }
                        Button {
                            print("Block @\(note.username)")
                        } label: {
                            Label("Block @\(note.username)", systemImage: "slash.circle")
                        }
                    } label: {
                        Text("···")
                            .foregroundColor(.secondary)
                            .padding(.top, 0)
                            .padding(.bottom, 10)
                            .padding(.leading, 20)
                            .padding(.trailing, 10)
                        
                    }
                }
                // "Replying to"
                if (tweet.replyToUsername != "") {
                    HStack {
                        Text("Replying to @\(tweet.replyToUsername)")//.border(.red)
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
                Button(action: {
                    // Handle retweet action
                }) {
                    HStack {
                        Image(systemName: "message")
                        Text("\(tweet.replyCount)")
                    }.frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
                }
                
                
                Button(action: {
                    // Handle retweet action
                }) {
                    HStack {
                        Image(systemName: "arrow.2.squarepath")
                        Text("\(tweet.retweetCount)")
                    }.frame(maxWidth: .infinity, alignment: .center).font(.system(size: 14))
                }
                
                Button(action: {
                    // Handle like action
                }) {
                    HStack {
                        Image(systemName: "heart")
                        Text("\(tweet.likeCount)")
                    }.frame(maxWidth: .infinity, alignment: .trailing).font(.system(size: 14))
                }
            }.foregroundColor(.gray)
                .padding(10)
            
            // Replies TODO
            
            if (note.responses != nil) {
                LazyVStack {
                    ForEach (note.responses!, id:\.id) { row in
//                        Text("1")
//                        Text("id: \(row.id ?? "") kind: \(row.kind) text:\(row.content ?? "")")
                        NoteView(note:Note(event:row))
                    }
                }
            }
            
            // Finished
            Spacer()
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
            NoteDetailView(Note(event:events.first!, responses:responses.reversed(), contact: contacts.first))
        }
    }
}

struct NoteDetailView_Previews: PreviewProvider {
    static var previews: some View {
        
        let accountState = AccountState(viewContext: EventsProvider.preview.container.viewContext)
        let cm = ConnectionManager()
        
        NoteDetailViewWrapper()
            .environment(\.managedObjectContext,
                          EventsProvider.preview.container.viewContext)
            .environmentObject(accountState)
            .environmentObject(cm)
    }
}
