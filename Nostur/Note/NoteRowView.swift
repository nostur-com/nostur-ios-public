//
//  MessageView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI
import CoreData
//import UIKit
import LightningDevKit

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
    var hideFooter = false // For rendering in NewReply
    
    enum type {
        case note
        case lightningInvoice
    }
    
    let type:NoteRowView.type
    
    var isRepost:Bool {
        get {
            if event.kind == 6 { return true }
            if (event.content != nil && event.content! == "#[0]") && (TagsHelpers(event.tags() ?? []).mentionEtags()?.count == 1) { return true }
            return false
        }
    }
    
    var eventOrRepost:Event {
        get {
            isRepost && event.firstQuote != nil ? event.firstQuote! : event
        }
    }
    
    static func isRepost(_ event:Event) -> Bool {
        if event.kind == 6 { return true }
        if (event.content != nil && event.content! == "#[0]") && (TagsHelpers(event.tags() ?? []).mentionEtags()?.count == 1) { return true }
        return false
    }
    
    init(event: Event, hideFooter:Bool = false) {
        self.event = event
        self.hideFooter = hideFooter
        
        let eventOrRepost = NoteRowView.isRepost(event) && event.firstQuote != nil ? event.firstQuote! : event
        let pubkeys = TagsHelpers(eventOrRepost.tags() ?? []).pTags().map { $0.pubkey }
        
        if (pubkeys.count == 0) {
            _taggedContacts = FetchRequest(
                sortDescriptors: [],
                predicate: NSPredicate(value: false)
            )
        }
        else { // TODO: IS THIS SLOW OR NOT?
            _taggedContacts = FetchRequest(
                sortDescriptors: [],
                predicate: NSPredicate(format: "pubkey IN %@", pubkeys)
            )
        }
        if event.noteText.prefix(4) == "lnbc" && Invoice.fromStr(s: event.noteText).getValue() != nil {
            self.type = .lightningInvoice
        }
        else {
            self.type = .note
        }
        
    }
    
    var body: some View {
        //        NavigationLink(value: event, label: {
        
        VStack (alignment: .leading) {
            if (isRepost) {
                HStack {
                    Image(systemName: "arrow.2.squarepath")
                    Text("\(event.name) reposted")
                }
                .onTapGesture {
                    nav.navigateTo(ContactPath(key: event.pubkey!))
                }
                .padding(.leading, 45)
            }
            HStack(alignment: .top) {
                VStack {
                    ProfilePic(event: eventOrRepost)
                        .padding(.horizontal, 10)
                        .onTapGesture {
                            nav.navigateTo(ContactPath(key: eventOrRepost.pubkey!))
                        }
                }
                
                VStack(alignment:.leading, spacing: 3) {// Tweet container
                    HStack { // name + reply + context menu
                        NoteHeader(event:eventOrRepost)
                    }
                    ReplyingToFragment(event: eventOrRepost)
                    
                    switch self.type {
                        case .lightningInvoice:
                            LightningInvoice(invoice: eventOrRepost.noteText)
                        default:
                            NoteTextRenderView(event:eventOrRepost, taggedContacts:Array(taggedContacts))
                                .onTapGesture { nav.navigateTo(eventOrRepost) }
                    }
                    
                
                    if (eventOrRepost.firstQuoteId != nil && eventOrRepost.firstQuote != nil) {
                        QuotedNoteFragment(event: eventOrRepost.firstQuote!)
                    }
                    else if (eventOrRepost.firstQuote != nil) {
                        ProgressView().onAppear {
                            sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEvent(id: eventOrRepost.firstQuoteId!)))
                        }
                    }
                    
                    if (!hideFooter) {
                        FooterFragment(event: eventOrRepost)//.border(.red)
                    }
                    
                }
                .padding(.trailing, 10)
                //                        .padding(.bottom, 5)
            }
        }
        .background(
            Color(.systemBackground)
                .onTapGesture { nav.navigateTo(eventOrRepost) }
        )

        
        //        })
        .onAppear {
            // should fetch setMetaData if
            // No Contact
            // Contact updated_at is very old
            // followed contact meta data refresh should be updated at app wake up probably
            if (event.contact == nil) {
                print("🟢 NoteRow.onAppear event.contact == nil so: REQ.0:\(eventOrRepost.pubkey!)")
                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: eventOrRepost.pubkey!)))
            }
        }
        //        .frame(minHeight: 140)//.border(.red)
        .padding(.vertical, 10)
        //        .background(Color.random)
        
    }
}

struct NoteHeader: View {
    @EnvironmentObject var nav:NavigationModel
    @ObservedObject var event:Event
    var singleLine:Bool = true
    
    var body: some View {
        //        NavigationLink(value: event, label: {
        
        VStack(alignment: .leading) { // Name + menu "replying to"
            HStack(spacing:2) {
                Group {
                    if (event.contact != nil) {
                        Text(event.contact!.authorName) // Name
                            .foregroundColor(.primary)
                            .fontWeight(.bold)
                            .lineLimit(1)
                    }
                    else {
                        Text("Anon") // Name
                            .foregroundColor(.primary)
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .redacted(reason: .placeholder)
                    }
                    
                    if (event.contact?.nip05veried ?? false) {
                        Image(systemName: "checkmark.seal.fill")
//                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                    }
                    
                    if (singleLine) {
                        Text("@\(event.contact?.username ?? event.authorKey) · \(event.ago)") //
    //                        .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .onTapGesture {
                    nav.navigateTo(ContactPath(key: event.pubkey!))
                }
                Spacer()
                Text(Date(timeIntervalSince1970: TimeInterval(event.created_at)), format: Date.VerbatimFormatStyle(format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)", timeZone: .current, calendar: .current))
//                    .font(.system(size: 14))
                    .padding(.trailing, 5)
            }
            if (!singleLine) {
                Text("@\(event.contact?.username ?? event.authorKey) · \(event.ago)") //
//                        .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
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
                do {
                    try viewContext.save()
                    sendNotification(.blockListUpdated, nil)
                }
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
    @EnvironmentObject var up:Unpublisher
    
    @State var unpublishLikeId:UUID? = nil
    
    @State var unpublishRepostId:UUID? = nil
    @State var unpublishOriginalId:UUID? = nil
    
    @State var showingNewReply = false
    
    var body: some View {
        HStack {
            
            HStack {
                Image(systemName: "message")
                Text("\(event.repliesCount)")
            }
            .background(Color(.systemBackground))
                .onTapGesture {
                    showingNewReply = true
                }
            Spacer()
                

            HStack {
                Image(systemName: "arrow.2.squarepath")
                Text("\(event.mentions)")
            }
            .background(Color(.systemBackground))
            .onTapGesture {
                if (ns.account != nil) {
                    print("🔄🔄🔄🔄🔄 REPOSTING 🔄🔄🔄")
//                    event.reposted = true
                    event.mentions = event.mentions + 1
//                    ns.account?.addToLikes(event)
                    
                    // 1. create kind 7 event based on kind 1 event:    Event
                    let repostEvent = EventMessageBuilder.makeRepost(original: event)
                    
                    // 2. sign that event with account keys             Account
                    guard let signedEvent = try? ns.signEvent(repostEvent) else {
                        print("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
                        return
                    }
                    
                    unpublishRepostId = up.publish(signedEvent)
                    unpublishOriginalId = up.publish(event.toNEvent())
                }
            }
            
            Spacer()
            
            // LIKE
            if (event.liked) {
                HStack {
                    Image(systemName: "heart.fill").foregroundColor(.red)
                    Text("\(event.likes)")
                }
                .background(Color(.systemBackground))
                .onTapGesture {
                    if unpublishLikeId != nil && up.cancel(unpublishLikeId!) {
                        event.liked = false
                    }
                }
            }
            else {
                HStack {
                    Image(systemName: "heart")
                    Text("\(event.likes)")
                }
                .background(Color(.systemBackground))
                .onTapGesture {
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
                        
                        unpublishLikeId = up.publish(signedEvent)
                        
                       
                    }
                }
                
            }
            Spacer()
            
            if (event.contact?.lud16 != nil) {
                LightningButton(contact:event.contact!, event: event)
                Spacer()
            }
            else {
                Color.clear.frame(width: 30, height: 15)
                Spacer()
            }
            
            // BOOKMARK
            if (ns.isBookmarked(event)) {
                Image(systemName: "bookmark.fill")
                    .foregroundColor(.orange)
                    .background(Color(.systemBackground))
                    .onTapGesture {
                        ns.removeBookmark(event)
                    }
            }
            else {
                Image(systemName: "bookmark")
                    .background(Color(.systemBackground))
                    .onTapGesture {
                        ns.addBookmark(event)
                    }
            }
            
        }
        .foregroundColor(.gray)
            .padding(.trailing, 5)
            .font(.system(size: 14))
            .sheet(isPresented: $showingNewReply) {
                NewReply(replyTo: event)
            }
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
        
        
        // TODO: find repost of 97a1a5dab19064061b45937c4e3523782d34608bd13278def9af4d5107ece65c
        // maybe: 7edef20143bb4df0c65dff3993bd9f7c5fb755fe6c8fa72cc847299afe52d8fa
        
        let event0 = PreviewFetcher.fetchEvent("21a1b8e4083c11eab8f280dc0c0bddf3837949df75662e181ad117bd0bd5fdf3")
//        let event0 = PreviewFetcher.fetchEvent("24ad21d57d59b03f4f9a8931f8bc4ccca84ed6ab257bf62cb84b0d04e0583118")
        
        let event1 = PreviewFetcher.fetchEvent("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
        
        let event2 = PreviewFetcher.fetchEvent("dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3")
        
        let event3 = PreviewFetcher.fetchEvent("d3b581761bab06fbe727b12b22c33c7b8768d7d9681b45cb6b1f4ad798496e14")
        
        let event4 = PreviewFetcher.fetchEvent("62459426eb9a1aff9bf1a87bba4238614d7b753c914ccd7884dac0aa36e853fe")
        
        let event5 = PreviewFetcher.fetchEvent("f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e")
        
        let event6 = PreviewFetcher.fetchEvent("7d96834f60c5411be97fe9e4b07e3221c56df531543a11a1d67ff81168033e8e")
        
        List {
            
//            NoteRowView(event: event0!)
//                .listRowInsets(EdgeInsets())
//
            NoteRowView(event: event1!)
                .listRowInsets(EdgeInsets())
//
            NoteRowView(event: event2!)
                .listRowInsets(EdgeInsets())
//
//            NoteRowView(event: event3!)
//                .listRowInsets(EdgeInsets())
//
//            NoteRowView(event: event4!)
//                .listRowInsets(EdgeInsets())
//
//            NoteRowView(event: event5!)
//                .listRowInsets(EdgeInsets())
            
            NoteRowView(event: event6!)
                .listRowInsets(EdgeInsets())
            
        }
        .listStyle(PlainListStyle())
        .withPreviewEnvironment()
    }
}
