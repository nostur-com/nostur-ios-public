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
struct NoteRowView: View {
    
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var cm:ConnectionManager
    
    // NoteRowView(event: event) - PREFERRED
    var event:Event? = nil
    
    // NoteRowView(id: noteId) - ALTERNATIVE
    var id:String? = nil
    @State var fetchedEvent:Event? = nil
    
    @State var eventNotInCache = false

    init(event: Event) {
        self.event = event
    }
    
    init(id: String) {
        self.id = id
    }
    
    func fetchEvent() {
        viewContext.perform {
            let r = Event.fetchRequest()
            r.predicate = NSPredicate(format: "id == %@", self.id!)
            fetchedEvent = try! r.execute().first
            if (fetchedEvent == nil) {
                eventNotInCache = true
            }
        }
    }
    
    var body: some View {
        if (event != nil) { // EVENT PASSED FROM CALLER
            NoteRowViewInner(event: event!)
        }
        else if (fetchedEvent != nil) { // EVENT FETCHED FROM CORE DATA
            NoteRowViewInner(event: fetchedEvent!)
        }
        else {
            Text("Unable to find event")
                .onAppear {
                    if (event == nil && fetchedEvent == nil) {
                        fetchEvent()
                    }
                }
                .onChange(of:eventNotInCache) { newValue in
                    if (newValue) {
                        cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEvent(id: id!)))
                    }
                }
        }
    }
}

struct NoteRowViewInner: View {
    
    var event:Event
    
    @FetchRequest(
        sortDescriptors: [],
        animation: .none)
    var authors:FetchedResults<Contact>
    
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var cm:ConnectionManager
    @EnvironmentObject var accountState:AccountState
    
    let tweet:Tweet = Tweet(hasThread: false) // Todo
    
    @FetchRequest(
        sortDescriptors: [],
        animation: .none)
    var allContacts:FetchedResults<Contact>
    
//    func contact(byPubkey:String?) -> Contact? {
//        guard byPubkey != nil && allContacts != nil else {
//            return nil
//        }
//        return allContacts!.first(where: { ($0.pubkey != nil) && $0.pubkey == byPubkey})
//    }
    
    init(event: Event) {
        self.event = event
        
        _authors = FetchRequest(
            sortDescriptors: [],
            predicate: NSPredicate(format: "pubkey == %@", event.pubkey!)
        )
    }
    
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
            
            NavigationLink(value: NotePath(id: event.id!), label: {
                VStack (alignment: .leading) { // Vstack for retweeted thread
                HStack(alignment: .top) { // Tweet
                    NavigationLink(value: NotePath(id: event.id!), label: {
                        VStack { // profile image + thread line
                            // profile image
                            if (authors.first != nil) {
                                NavigationLink(value: ContactPath(key: event.pubkey!), label: {
                                    ProfilePicView(pubkey: event.pubkey!, contact:authors.first)
                                        .frame(maxWidth:50, maxHeight:50)
                                        .clipShape(Circle())
                                })
                            }
                            else {
                                NavigationLink(value: ContactPath(key: event.pubkey!), label: {
                                    ProfilePicView(pubkey: event.pubkey!, contact:authors.first)
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
                                //                                Spacer()
                            }
                        }.padding(.leading, 10)
                    })
                    
                    VStack(alignment: .leading, spacing: 3) { // Tweet container
                        HStack { // name + reply + context menu
                            
                            NavigationLink(value: NotePath(id: event.id!), label: {
                                VStack(alignment: .leading) { // Name + menu "replying to"
                                    HStack(spacing:2) {
                                        Text(authors.first?.authorName ?? "Anom") // Name
                                            .font(.system(size: 14))
                                            .foregroundColor(.primary)
                                            .fontWeight(.bold)
                                            .lineLimit(1)
                                        
                                        if tweet.isVerified { // Verification check
                                            Image(systemName: "checkmark.seal.fill")
                                                .foregroundColor(.blue)
                                                .font(.system(size: 13))
                                        }
                                        
                                        Text("@\(authors.first?.username ?? event.authorKey) · \(event.ago)") //
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    if (event.replyToId != nil) {
                                        Text("Replying to @\(String(event.replyToId!.prefix(5)))")
                                            .foregroundColor(.secondary)
                                            .font(.system(size: 13))
                                            .fontWeight(.light)
                                    }
                                }
                            })
                            
                            Spacer()
                            
                            NoteMenuView(event: event)
//                                .background(.red)
                        }
                        
                        NoteTextRenderView(event:event, allContacts: allContacts.reversed()).multilineTextAlignment(TextAlignment.leading)
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
                        
                        HStack { // Footer stats
                            Button(action: {
                                // Handle retweet action
                            }) {
                                HStack {
                                    Image(systemName: "message")
                                    Text("\(event.replies)")
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
                            
                            Button(action: {
                                // Handle like action
                            }) {
                                HStack {
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
                                    }
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
                            
                            ProfilePicView(pubkey: event.pubkey!, contact: authors.first)
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
            if (authors.first == nil) {
                print("☎️ note.contact == nil -> REQ metadata for pubkey \(event.pubkey!)")
                
                cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: event.pubkey!)))
            }
        }
    }
}

struct NoteMenuView : View {
    var event:Event
    var author:Contact?
    
    var noteIdHex:String { get { event.id ?? "00000" } }
    var noteId:String { get { event.noteId } }
    var username:String {
        get {
            author?.username ?? String(event.pubkey!.prefix(5))
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

struct NoteView_Previews: PreviewProvider {

    static var previews: some View {
    
        // #[2]
        // 115eab2976aee4ca562d83ea6b1d805c6d4e0acf54fe2e6a4e1a62f73c2850cc
        
        // #[0]
        // 1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0
        
        // note.id 6f74b952991bb12b61de7c5891706711e51c9e34e9f120498d32226f3c1f4c81
        // pubkey: 5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0
        
        let event = PreviewFetcher.fetchEvent("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
        
        NoteRowView(event: event!)
            .withPreviewEnvironment()
    }
}
