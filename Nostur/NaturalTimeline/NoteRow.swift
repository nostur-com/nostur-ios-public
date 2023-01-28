//
//  MessageView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI
import Nuke
import NukeUI
import CoreData

// TODO: replying to trick:
// people.map(\.nameComponents).formatted(.list(memberStyle: .name(style:.short), type:.and)
// uitzoeken, from WWDC video

// A single note shown in a row in the MainTimelineView



struct NoteRow: View {
    
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
    
    var body: some View {
        
        
        VStack(spacing:2) { // A TW EET
            
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
            
            NavigationLink(value: event, label: {
                VStack (alignment: .leading) { // Vstack for retweeted thread
                    HStack(alignment: .top) { // Tweet
                        NavigationLink(value: event, label: {
                            VStack { // profile image + thread line
                                // profile image
                                if (event.contact != nil) {
                                    NavigationLink(value: ContactPath(key: event.pubkey!), label: {
                                        ProfilePicView(pubkey: event.pubkey!, contact:event.contact)
                                            .frame(maxWidth:50, maxHeight:50)
                                            .clipShape(Circle())
                                    })
                                }
                                else {
                                    NavigationLink(value: ContactPath(key: event.pubkey!), label: {
                                        ProfilePicView(pubkey: event.pubkey!, contact:event.contact)
                                            .frame(maxWidth:50, maxHeight:50)
                                            .clipShape(Circle())
                                    })
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
                                    
                                }
                            }.padding(.leading, 10)
                        })
                        
                        VStack(alignment: .leading, spacing: 3) { // Tweet container
                            HStack { // name + reply + context menu
                                
                                NavigationLink(value: event, label: {
                                    VStack(alignment: .leading) { // Name + menu "replying to"
                                        HStack(spacing:2) {
                                            Text(event.contact?.authorName ?? "Anon") // Name
                                                .font(.system(size: 14))
                                                .foregroundColor(.primary)
                                                .fontWeight(.bold)
                                                .lineLimit(1)
                                            
                                            if tweet.isVerified { // Verification check
                                                Image(systemName: "checkmark.seal.fill")
                                                    .foregroundColor(.blue)
                                                    .font(.system(size: 13))
                                            }
                                            
                                            Text("@\(event.contact?.username ?? event.authorKey) · \(event.ago)") //
                                                .font(.system(size: 14))
                                                .foregroundColor(.secondary)
                                        }
                                    
                                        ReplyingToFragment(event: event)
                                    }
                                })
                                
                                Spacer()
                                
                                // mmm diffucult to tap..
                                // maybe replace with .contextMenu
//                                NoteMenu(event: event)
                                //                                .background(.red)
                            }
                            
                            NoteTextRenderView(event:event, taggedContacts:Array(taggedContacts)).multilineTextAlignment(TextAlignment.leading)
                            //                        Text(event.noteText).multilineTextAlignment(TextAlignment.leading)
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                                .lineSpacing(3)
                                .padding(.vertical, 5)
                            
                            
                            if tweet.hasImage {
                                Image(tweet.imageName)
                                    .resizable()
                                    .cornerRadius(10)
                                    .aspectRatio(contentMode: .fit)
                                    .padding(.vertical, 10)
                            }
                            
                            Text(Date(timeIntervalSince1970: TimeInterval(event.created_at)).description)
                            
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
                                
                                ProfilePicView(pubkey: event.pubkey!, contact: event.contact)
                                    .frame(maxWidth:25, maxHeight:25)
                                
                            }.padding(.leading, 10)
                            Text("Show this thread").font(.system(size: 14))
                        }
                    }
                }
            })
            .frame(maxHeight: 1900)
            Divider()
        }
        .onAppear {
            // should fetch setMetaData if
            // No Contact
            // Contact updated_at is very old
            // followed contact meta data refresh should be updated at app wake up probably
            if (event.contact == nil) {
                print("🟢 NoteRow.onAppear event.contact == nil so: REQ.0:\(event.pubkey!)")
                cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: event.pubkey!)))
            }
        }
        
    }
}

struct NoteMenu: View {
    var event:Event
    
    var noteIdHex:String { get { event.id ?? "00000" } }
    var noteId:String { get { event.noteId } }
    var username:String {
        get {
            event.contact?.username ?? String(event.pubkey!.prefix(5))
        }
    }
    
    var body: some View {
        Menu {
            Button {
                UIPasteboard.general.string = noteId
            } label: {
                Label("Copy note id \(noteId)", systemImage: "doc.on.clipboard")
            }
            Button {
                UIPasteboard.general.string = noteIdHex
            } label: {
                Label("Copy note id hex \(noteIdHex))", systemImage: "doc.on.clipboard")
            }
            Button {
                print("Unfollow @\(username)")
            } label: {
                Label("Unfollow @\(username)", systemImage: "person.fill.xmark")
            }
            Button {
                print("Block @\(username)")
            } label: {
                Label("Block @\(username)", systemImage: "slash.circle")
            }
        } label: {
            Text("···")
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .padding(.top, 0)
                .padding(.bottom, 10)
                .padding(.leading, 20)
                .padding(.trailing, 10)
            
        }
    }
}

struct NoteRow_Previews: PreviewProvider {
    
    static var previews: some View {
        
        // #[2]
        // 115eab2976aee4ca562d83ea6b1d805c6d4e0acf54fe2e6a4e1a62f73c2850cc
        
        // #[0]
        // 1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0
        
        // note.id 6f74b952991bb12b61de7c5891706711e51c9e34e9f120498d32226f3c1f4c81
        // pubkey: 5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0
        
        // with youtube preview
        // id: 576375cd4a87e40f15a7842b43fe4a35651e89a34371b2a41ca79ca7dced1113
        
        // reply to unfetched contact
        // dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3
        
        // reply to known  contact
        // f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e
        
        let event0 = PreviewFetcher.fetchEvent("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
        
        let event1 = PreviewFetcher.fetchEvent("dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3")
        
        let event2 = PreviewFetcher.fetchEvent("f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e")
        
        VStack {
            NoteRow(event: event0!)
                .withPreviewEnvironment()
            NoteRow(event: event1!)
                .withPreviewEnvironment()
            NoteRow(event: event2!)
                .withPreviewEnvironment()
            Spacer()
        }
    }
}
