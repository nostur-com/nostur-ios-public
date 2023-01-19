//
//  TestTimeline.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/01/2023.
//

import SwiftUI
import CoreData

struct Wrapper: View {
    
    @Environment(\.managedObjectContext) var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)],
        animation: .none)
    var contacts:FetchedResults<Contact>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: true)],
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
    
    @State var unread = 0
    @AppStorage("lastAppearedIndex") var lastAppearedIndex = 0

    var contacts:FetchedResults<Contact>
    
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
          
        ZStack {
            VStack {
                Button {
                    fetchLatest100EventsFromFollowing()
                } label: {
                    Text("Fetch latest 100 events from who you follow \(accountState.followingPublicKeys.count)")
                }
                Group {
                    ScrollViewReader { proxy in
                        ScrollView { // TODO
                            LazyVStack {
                                ForEach(events.indices, id:\.self) { index in
                                    let note = Note(event: events[index], contact: contact(byPubkey: events[index].pubkey))
                                    NoteView(note:note)
                                        .onAppear {
                                            print("🍿🍿 appear index: \(index) lastAppearedIndex: \(lastAppearedIndex) events.count: \(events.count)")
                                            if (index > lastAppearedIndex) {
                                                lastAppearedIndex = index
                                                let unreadOld = unread
                                                unread = events.count-1 - index
                                                print("🍿🍿 unread: \(unread) (was: \(unreadOld))")
                                            }
                                        }
                                        .scaleEffect(x: 1, y: -1)
                                }
                            }
                        }
                        Button {
                            proxy.scrollTo(events.count-1, anchor: .bottom)
                        } label: {
                            Text("Scroll to index: \(events.count-1)")
                        }
                        .scaleEffect(x: 1, y: -1)
                        .onChange(of: events.count) { newCount in
                            let unreadOld = unread
                            unread = unread + (newCount - events.count)
                            print("🍿🍿 events.count: \(events.count) newCount: \(newCount) unread: \(unread) (was: \(unreadOld))")
                        }
                        .onAppear {
                            print("🍿🍿 onAppear .scrollTo:\(lastAppearedIndex) events.count:\(events.count) unread: \(unread) (not changed)")
                            proxy.scrollTo(lastAppearedIndex)
//                            proxy.scrollTo(events.last?.id, anchor: .bottom)
                        }
                    }
                    .scaleEffect(x: 1, y: -1)
                }
            }
            VStack {
                HStack {
                    Spacer()
                    if (unread > 0) {
                        Text("\(unread)")
                            .padding(5)
                            .fontWeight(.heavy)
                            .foregroundColor(.white)
                            .background(.gray)
                            .cornerRadius(10)
                            .offset(x:-30,y:35)
                    }
                        
                }
                Spacer()
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
