//
//  TestTimeline.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/01/2023.
//

import SwiftUI
import CoreData

struct MainTimeline: View {
    
    // every 8 seconds, should toggle between fetch and parse
    // 0..fetch....8..parse...16...fetch....24....parse...etc..
    
    // fetch every 8 sec
    // parse every 5 is now done on NosturApp
    let timelineRunLoop = Timer.publish(every: 8, tolerance: 1, on: .main, in: .common).autoconnect()
    
    @State var fetching = true // fetching: true or, false if parsing
    @State var isViewDisplayed = false
    
    @EnvironmentObject var ep:EventsProvider
    @EnvironmentObject var accountState:AccountState
    @EnvironmentObject var cm:ConnectionManager
    
    @State var unread = 0
    @AppStorage("lastUnreadIndex") var lastUnreadIndex = 0
    
    @State var restored = false
    @AppStorage("lastAppearedIndex") var lastAppearedIndex = 0

    var contacts:FetchedResults<Contact>
    
    var events: FetchedResults<Event>
    
    func contact(byPubkey:String?) -> Contact? {
        guard byPubkey != nil else {
            return nil
        }
        return contacts.first(where: { ($0.pubkey != nil) && $0.pubkey == byPubkey})
    }
    
    func fetchEventsFromFollowing(amount:Int? = 200) {
//        let allContacts = contacts.map { $0.pubkey }
        
        for socket in cm.relaySockets {
            if (socket.relay.read || socket.relay.write) && !socket.isConnected {
                socket.socket.connect()
            }
        }
        
        
        
        let followingPubkeys = [String](accountState.followingPublicKeys)
        cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getAuthorsEvents(pubkeys: followingPubkeys, limit: amount!, since: ep.lastTimelineEventTimestamp)))
    }
    
    
    var body: some View {
          
        HStack {
            Button {
                    print("queue count: \(ep.messageQueue.count)")
            } label: {Text("COUNT")}
            
            Button {
                    _ = Task {
                        try! await ep.parseMessagesFromQueue()
                        print("queue count: \(ep.messageQueue.count)")
                    }
            } label: {Text("PARSE")}
        }
        ZStack {
            VStack {
                Button {
                    fetchEventsFromFollowing(amount:100)
                } label: {
                    Text("Fetch latest 50 events from who you follow \(accountState.followingPublicKeys.count)")
                }
                Group {
                    ScrollViewReader { proxy in
                        ScrollView { // TODO
                            LazyVStack {
                                ForEach(events.indices, id:\.self) { index in
                                    let note = Note(event: events[index], responses:[], contact: contact(byPubkey: events[index].pubkey))
                                    NoteView(note:note)
                                        .onAppear {
                                            print("🍿🍿 appear index: \(index) lastUnreadIndex: \(lastUnreadIndex) events.count: \(events.count)")
                                            if (index > lastUnreadIndex) {
                                                lastUnreadIndex = index
                                                let unreadOld = unread
                                                unread = events.count-1 - index
                                                print("🍿🍿 unread: \(unread) (was: \(unreadOld))")
                                            }
                                            lastAppearedIndex = index
                                        }
                                        .scaleEffect(x: 1, y: -1)
                                }
                            }
                        }
                        .padding(.top, 1)
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
                            print("🍿🍿 onAppear: lastAppearedIndex \(lastAppearedIndex) events.count:\(events.count) unread: \(unread) (not changed)")
                            if (!restored) {
                                proxy.scrollTo(lastAppearedIndex)
                                restored = true
                                unread = events.count-1 - lastUnreadIndex
                                print("🍿🍿 RESTORING SCROLL INDEX 🍿🍿🍿🍿")
                            }
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
                            .frame(minWidth: 30)
                            .padding(5)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .background(.tint)
                            .cornerRadius(20)
                            .offset(x:-30,y:35)
                    }
                        
                }
                Spacer()
            }
        }
        .onAppear {
                self.isViewDisplayed = true
        }
        .onDisappear {
            self.isViewDisplayed = false
        }
        .onReceive(timelineRunLoop) { time in
            
            if (!isViewDisplayed) {
                return
            }

            print("🍭🍭🍭 GONNA FETCH BABY 🍭🍭🍭🍭")
            fetchEventsFromFollowing(amount: 200)
            
//            if (fetching) { // fetching
//                print("🍭🍭🍭 GONNA FETCH BABY 🍭🍭🍭🍭")
//                fetchEventsFromFollowing(amount: 200)
//            }
//            else { // parsing
//                _ = Task {
//                    try! await ep.parseMessagesFromQueue()
//                    print("queue count: \(ep.messageQueue.count)")
//                }
//                print("🧚🧚🧚 GONNA PARSE YEA 🧚🧚🧚")
//            }
//
//            fetching = !fetching
            
            print("last timeline event timestamp: \(String(describing: ep.lastTimelineEventTimestamp?.timestamp))")
        }
    }
}

// FOR PREVIEW??
struct MainTimelineWrapper: View {
    
    @Environment(\.managedObjectContext) var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)],
        animation: .none)
    var contacts:FetchedResults<Contact>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: true)],
        predicate: NSPredicate(format: "kind == 1 and replyToId == nil"),
        animation: .none)
    var events: FetchedResults<Event>
    
    var body: some View {
        VStack {
            MainTimeline(contacts: contacts, events: events)
        }
    }
}

struct MainTimeline_Previews: PreviewProvider {
    
    static var previewUserDefaults: UserDefaults = {
                let d = UserDefaults(suiteName: "preview_user_defaults")!
                
        d.set("5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0", forKey: "activeAccountPublicKey")
                
        return d
            }()
    
    static var previews: some View {
        
        let accountState = AccountState(viewContext: EventsProvider.preview.container.viewContext)
        
        let eventsProvider = EventsProvider.shared
        
        let cm = ConnectionManager()
        
        MainTimelineWrapper()
            .environment(\.managedObjectContext, EventsProvider.preview.container.viewContext)
            .environmentObject(accountState)
            .environmentObject(eventsProvider)
            .environmentObject(cm)
    }
}
