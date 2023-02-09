//
//  MessageView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI
import CoreData
//import UIKit

// TODO: replying to trick:
// people.map(\.nameComponents).formatted(.list(memberStyle: .name(style:.short), type:.and)
// uitzoeken, from WWDC video

// A single note shown in a row in the MainTimelineView

// See old struct NoteRow. For some old thread layout stuff still.

struct NoteRowView: View {

    @Environment(\.managedObjectContext) var viewContext
    var sp:SocketPool = .shared
    @EnvironmentObject var nav:NavigationModel
//    @EnvironmentObject var ns:NosturState
    @ObservedObject var event:Event
    
    @FetchRequest
    var taggedContacts:FetchedResults<Contact>
    
    init(event: Event) {
        self.event = event
        let pubkeys:String? = nil

        if (pubkeys == nil) {
            _taggedContacts = FetchRequest(
                sortDescriptors: [],
                predicate: NSPredicate(value: false)
            )
        }
        else { // TODO: IS THIS SLOW OR NOT?
            _taggedContacts = FetchRequest(
                sortDescriptors: [],
                predicate: NSPredicate(format: "pubkey IN %@", pubkeys!)
            )
        }
    }
    
    var body: some View {
//        NavigationLink(value: event, label: {
                
            VStack (alignment: .leading) {
                HStack(alignment: .top) {
                    VStack {
                        ProfilePicView(pubkey: event.pubkey!, contact:event.contact)
                            .padding(.horizontal, 10)
                            .onTapGesture {
                                nav.navigateTo(ContactPath(key: event.pubkey!))
                            }
                    }//.background(.green)
                    
                    VStack(alignment:.leading) {// Tweet container
                        HStack { // name + reply + context menu
                            NoteHeader(event:event)
                        }//.frame(height: 40).border(.red)
                        
                        //                        NavigationLink(value: event, label: {
                        
                            NoteTextRenderView(event:event, taggedContacts:Array(taggedContacts))
//                            .onTapGesture {
//                                nav.navigateTo(event)
//                            }
                            
                            
                            
                        
                        //                        })//.border(.red)
                        
                        if (event.firstQuoteId != nil && event.firstQuote != nil) {
                            QuotedNoteFragment(event: event.firstQuote!)
                        }
                        else if (event.firstQuote != nil) {
                            ProgressView().onAppear {
                                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEvent(id: event.firstQuoteId!)))
                            }
                        }
                        
                        FooterFragment(event: event)//.border(.red)
                        
                    }//.border(.green)
                    .padding(.trailing, 10)
                    //                        .padding(.bottom, 5)
                }
            }
            .onTapGesture {
                nav.navigateTo(event)
            }

//        })
        .onAppear {
            // should fetch setMetaData if
            // No Contact
            // Contact updated_at is very old
            // followed contact meta data refresh should be updated at app wake up probably
            if (event.contact == nil) {
                print("🟢 NoteRow.onAppear event.contact == nil so: REQ.0:\(event.pubkey!)")
                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: event.pubkey!)))
            }
        }
//        .frame(minHeight: 140)//.border(.red)
        .padding(.vertical, 10)
//        .background(Color.random)
        
    }
}

struct NoteHeader: View {
    @EnvironmentObject var nav:NavigationModel
    var event:Event
    var body: some View {
//        NavigationLink(value: event, label: {
        
            VStack(alignment: .leading) { // Name + menu "replying to"
                HStack(spacing:2) {
                    Group {
                        Text(event.contact?.authorName ?? "Anon") // Name
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                            .fontWeight(.bold)
                            .lineLimit(1)
                        
                        Text("@\(event.contact?.username ?? event.authorKey) · \(event.ago)") //
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .onTapGesture {
                        nav.navigateTo(ContactPath(key: event.pubkey!))
                    }
                    Spacer()
                    Text(Date(timeIntervalSince1970: TimeInterval(event.created_at)), format: Date.VerbatimFormatStyle(format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)", timeZone: .current, calendar: .current))
                        .font(.system(size: 14))
                        .padding(.trailing, 5)
                }
                ReplyingToFragment(event: event)
            }
            
        
//        })
    }
}

struct NoteMenu: View {
    @EnvironmentObject var ns:NosturState
    @Environment(\.managedObjectContext) var viewContext
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
                if (event.contact == nil) {
                    let newContact = Contact(context: viewContext)
                    newContact.pubkey = event.pubkey!
                    newContact.updated_at = 0
                    ns.account?.addToBlockedContacts(newContact)
                    ns.account?.objectWillChange.send()
                }
                else {
                    ns.account?.addToBlockedContacts(event.contact!)
                    ns.account?.objectWillChange.send()
                }
                do { try viewContext.save() }
                catch {
                    print("Could not save after blocking contact \(error)")
                }
                
                
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

struct FooterFragment: View {
    //    @EnvironmentObject var accountState:AccountState
    @EnvironmentObject var ns:NosturState
    @Environment(\.managedObjectContext) var viewContext
    @ObservedObject var event:Event
    
    var body: some View {
        HStack {
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
                    //                        .frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
                }
                else {
                    Image(systemName: "bookmark")
                    //                        .frame(maxWidth: .infinity, alignment: .leading).font(.system(size: 14))
                }
            }
            
        }.foregroundColor(.gray)
            .padding(.trailing, 5)
            .font(.system(size: 14))
    }
}

struct NoteRowView_Previews: PreviewProvider {
    
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
        
        List {
            NoteRowView(event: event0!)
                .listRowInsets(EdgeInsets())
                
            NoteRowView(event: event1!)
                .listRowInsets(EdgeInsets())

            NoteRowView(event: event2!)
                .listRowInsets(EdgeInsets())

        }
        .listStyle(PlainListStyle())
        .withPreviewEnvironment()
    }
}
