//
//  MessageView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI
import Nuke
import NukeUI

struct NoteView: View {
    
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var cm:ConnectionManager
    
    let tweet:Tweet = Tweet(hasThread: false) // Todo
    var note:Note
    
    var body: some View {
        VStack(spacing:2) { // A TWEET
            
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
            
            VStack (alignment: .leading) { // Vstack for retweeted thread
                HStack(alignment: .top) { // Tweet
                    NavigationLink(value: note, label: {
                        VStack { // profile image + thread line
                            // profile image
                            if (note.contact != nil) {
                                NavigationLink(value: ContactProfile(contact: note.contact!), label: {
                                    ProfilePicView(pubkey: note.publicKey, contact:note.contact)
                                        .frame(maxWidth:50, maxHeight:50)
                                        .clipShape(Circle())
                                })
                            }
                            else {
                                ProfilePicView(pubkey: note.publicKey)
                                    .frame(maxWidth:50, maxHeight:50)
                                    .clipShape(Circle())
                            }
                            // thread line
                            if tweet.hasThread {
                                HStack {
                                    //                                    Spacer()
                                    //                                    Rectangle().frame(width:1, height:.infinity)
                                    //                                        .foregroundColor(.gray)
                                    //                                    Spacer()
                                }.frame(maxWidth: 50)
                            }
                            else {
                                //                                Spacer()
                            }
                        }.padding(.leading, 10)
                    })
                    
                    VStack(alignment: .leading, spacing: 3) { // Tweet container
                        HStack { // name + reply + context menu
                            
                            NavigationLink(value:note, label: {
                                VStack(alignment: .leading) { // Name + menu "replying to"
                                    HStack(spacing:2) {
                                        Text(note.authorName) // Name
                                            .font(.system(size: 14))
                                            .foregroundColor(.primary)
                                            .fontWeight(.bold)
                                        
                                        if tweet.isVerified { // Verification check
                                            Image(systemName: "checkmark.seal.fill")
                                                .foregroundColor(.blue)
                                                .font(.system(size: 13))
                                        }
                                        
                                        Text("@\(note.username) · \(note.event.ago)") //
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    if (tweet.replyToUsername != "") {
                                        Text("Replying to @\(tweet.replyToUsername)")
                                            .foregroundColor(.secondary)
                                            .font(.system(size: 13))
                                            .fontWeight(.light)
                                    }
                                }
                            })
                            
                            Spacer()
                            
                            NoteMenuView(note)
                        }
                        
                        NavigationLink(value:note, label: {
                            Text(note.noteText).multilineTextAlignment(TextAlignment.leading)
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                        })
                        
                        if tweet.hasImage {
                            Image(tweet.imageName)
                                .resizable()
                                .cornerRadius(10)
                                .aspectRatio(contentMode: .fit)
                                .padding(.vertical, 10)
                        }
                        
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
                                }.frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
                            }
                            
                            Button(action: {
                                // Handle like action
                            }) {
                                HStack {
                                    Image(systemName: "heart")
                                    Text("\(tweet.likeCount)")
                                }.frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
                            }
                        }.foregroundColor(.gray)
                            .padding(.top, 3)
                    }.padding(.trailing, 10).padding(.bottom, 5)
                }
                if tweet.hasThread {
                    HStack { // "Show this thread"
                        ZStack {
                            Rectangle().frame(maxWidth: 50, maxHeight: 25).foregroundColor(.clear)
                            //                            Image(tweet.profileImageName).resizable().scaledToFit()
                            //                                .clipShape(Circle())
                            //                                .shadow(color: .gray, radius: 1.0)
                            //                                .frame(maxWidth:25, maxHeight:25)
                            
                            ProfilePicView(pubkey: note.publicKey, contact: note.contact)
                                .frame(maxWidth:25, maxHeight:25)
                            
                        }.padding(.leading, 10)
                        Text("Show this thread").font(.system(size: 14))
                    }
                }
            }
            Divider()
        }
        .onAppear {
            // should fetch setMetaData if
            // No Contact
            // Contact updated_at is very old
            // followed contact meta data refresh should be updated at app wake up probably
            if (note.contact == nil) {
                print("☎️ note.contact == nil -> REQ metadata for pubkey \(note.publicKey)")
                cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: note.publicKey)))
            }
        }
    }
}

struct NoteMenuView : View {
    var note:Note
    init(_ note:Note) {
        self.note = note
    }
    var body: some View {
        Menu {
            Button {
                UIPasteboard.general.string = note.id
            } label: {
                Label("Copy note id \(note.id)", systemImage: "doc.on.clipboard")
            }
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
}

// FOR PREVIEW
struct NoteViewWrapper: View {
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)],
        predicate: NSPredicate(format: "pubkey == %@", "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"),
        animation: .none)
    var contacts:FetchedResults<Contact>
    
    @FetchRequest(fetchRequest:Event.textNotes())
    var events: FetchedResults<Event>
    
    var body: some View {
        
        VStack {
            Text("event content: \(events.first!.content ?? "xx")")
            Text("contact pubkey: \(contacts.first!.name ?? "xx")")
            
            
            NoteView(note:Note(event:events.first!, contact: contacts.first))
        }
    }
}


struct NoteView_Previews: PreviewProvider {
    static var previews: some View {
        NoteViewWrapper()
            .environment(\.managedObjectContext,
                          PersistenceController.preview.container.viewContext)
    }
}
