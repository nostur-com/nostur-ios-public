//
//  TestTimeline.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/01/2023.
//

import SwiftUI
import CoreData

//class XEvents : ObservableObject {
//    @Published var events:[Event] = []
//    @Published var metaDataEvent:Event?
//    @Published var contacts:[Contact] = [Contact]()
//    @Published var contactsFR:FetchedResults<Contact>?
//
//    func contact(byPubkey:String?) -> Contact? {
//        guard byPubkey != nil else {
//            return nil
//        }
//        return contacts.first(where: { ($0.pubkey != nil) && $0.pubkey == byPubkey})
//    }
//}

struct Wrapper: View {
    
    @Environment(\.managedObjectContext) var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)],
        animation: .none)
    var contacts:FetchedResults<Contact>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
        predicate: NSPredicate(format: "kind == 1"),
        animation: .none)
    var events: FetchedResults<Event>
    
    var body: some View {
        VStack {
            TestTimeline(contacts: contacts, events: events)
        }
    }
}

struct TestTimeline: View {
    
    @EnvironmentObject var accountState:AccountState
    @EnvironmentObject var cm:ConnectionManager
    
//    @FetchRequest(
//        sortDescriptors: [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)],
//        animation: .none)
    var contacts:FetchedResults<Contact>
    
//    @FetchRequest(
//        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
//        predicate: NSPredicate(format: "kind == 1"),
//        animation: .none)
    var events: FetchedResults<Event>
    
    func contact(byPubkey:String?) -> Contact? {
        guard byPubkey != nil else {
            return nil
        }
        return contacts.first(where: { ($0.pubkey != nil) && $0.pubkey == byPubkey})
    }
    
    func fetchLatest100EventsFromFollowing() {
//        let allContacts = contacts.map { $0.pubkey }
        
        for socket in cm.relaySockets {
            if (socket.relay.read || socket.relay.write) && !socket.isConnected {
                socket.socket.connect()
            }
        }
        
        let followingPubkeys = [String](accountState.followingPublicKeys)
        cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getAuthorsEvents(pubkeys: followingPubkeys, limit: 100)))
    }
    
    
    var body: some View {
        
        VStack {
//            Text("contacts: \(contacts.count) events: \(events.count)")
            Button {
                fetchLatest100EventsFromFollowing()
            } label: {
                Text("Fetch latest 100 events from who you follow \(accountState.followingPublicKeys.count)")
            }
            
            ScrollView { // TODO
                LazyVStack {
                    ForEach(events) { event in
                        let note = Note(event: event, contact: contact(byPubkey: event.pubkey))
                        NoteView(note:note)
                    }
                }
            }
        }
    }
}

struct TestTimeline_Previews: PreviewProvider {
    
    static var previewUserDefaults: UserDefaults = {
                let d = UserDefaults(suiteName: "preview_user_defaults")!
                
        d.set("5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0", forKey: "activeAccountPublicKey")
                
        return d
            }()
    
    static var previews: some View {
        
        let accountState = AccountState(viewContext: PersistenceController.preview.container.viewContext)
        
        Wrapper()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
            .environmentObject(accountState)
    }
}
