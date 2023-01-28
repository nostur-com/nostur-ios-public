//
//  EventsWindow.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/01/2023.
//

import SwiftUI
import CoreData

struct TimelineView: View {
    
    var ep: EventsProvider = .shared
    @EnvironmentObject var accountState:AccountState
    @EnvironmentObject var cm:ConnectionManager
    
    
    var events:FetchedResults<Event>
    var reversed:[Event]
    //    @State var loadedEvents:[Event] = []
    
    init(events: FetchedResults<Event>) {
        self.events = events
        self.reversed = events.reversed()
    }
    
    
    //    @State var allItems = Array(1...500) // 0 = old, 500 = new
    //    @State var loadedItems:[Int] = []
    
    //    var initialItemsCount:Int = 30
    //    @State var lastOffset = 0
    
    //    func fetchMore() {
    //        if (loadedEvents.last != nil) {
    //            let indexOf = events.firstIndex(of: loadedEvents.last!)
    //
    //            for index in 1...5 {
    //                loadedItems.append(events.)
    //            }
    //        }
    //
    //        loadedEvents = events.first != nil ? [events.first!] : []
    ////        for index in 1...5 {
    ////            loadedItems.append(lastOffset+index)
    ////        }
    ////        lastOffset = lastOffset + 5
    //        unreadCount = updateUnreadCount()
    //    }
    
    //    func removeFirst() {
    //        loadedItems.remove(at: 0)
    //    }
    
    @AppStorage("lastReadDate") var lastReadDate = 0
    @State var unreadCount = 0
    
    func updateUnreadCount() -> Int {
        return events.filter { $0.created_at > lastReadDate }.count
    }
    
    
    func firstUnreadEvent() -> Event? {
        return events.filter { $0.created_at > lastReadDate }
            .sorted { e1, e2 in
                e1.created_at < e2.created_at
            }
            .last
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                VStack {
                    ScrollView {
                        LazyVStack {
                            ForEach(reversed, id:\.self) { event in
                                NoteRow(event: event)
                                    .scaleEffect(x: 1, y: -1)
                                    .onAppear {
                                        lastReadDate = Int(event.created_at) >= lastReadDate ? Int(event.created_at) : lastReadDate
                                        unreadCount = updateUnreadCount()
                                    }
                                    .contextMenu {
                                        Button {
                                            UIPasteboard.general.string = event.noteId
                                        } label: {
                                            Label("Copy note id \(event.noteId)", systemImage: "doc.on.clipboard")
                                        }
                                        Button {
                                            UIPasteboard.general.string = event.id!
                                        } label: {
                                            Label("Copy note id hex \(event.id!))", systemImage: "doc.on.clipboard")
                                        }
                                        Button {
                                            print("Unfollow @\(event.username)")
                                        } label: {
                                            Label("Unfollow @\(event.username)", systemImage: "person.fill.xmark")
                                        }
                                        Button {
                                            print("Block @\(event.username)")
                                        } label: {
                                            Label("Block @\(event.username)", systemImage: "slash.circle")
                                        }
                                    }
                                    .id(event.id)
                            }
                            Color.clear
                                .frame(width: 100, height: 1, alignment: .bottom)
                                .id("TOP")
                                .onAppear {
                                    if (events.count > 10) {
                                        //                                            removeFirst()
                                        //                                            removeFirst()
                                        //                                            removeFirst()
                                        //                                                proxy.scrollTo("TOP", anchor: .bottom)
                                    }
                                }
                        }
                    } .transaction { t in
                        t.animation = .none
                    }
                    .scaleEffect(x: 1, y: -1)
                    .safeAreaInset(edge: .top) {
                        HStack {
                            VStack {
                                Text("Last READ \(Date(timeIntervalSince1970: TimeInterval(lastReadDate)).formatted(.iso8601))")
                                Text("1st UNREAD: \(firstUnreadEvent() != nil ? Date(timeIntervalSince1970: TimeInterval(firstUnreadEvent()!.created_at)).description : "?")")
                                ControlGroup {
                                    Button {
                                        proxy.scrollTo("TOP", anchor: .bottom) } label: { Text("TO TOP") }
                                    Button {
                                        if let unreadEvent = firstUnreadEvent() {
                                            proxy.scrollTo(unreadEvent.id!, anchor: .bottom)
                                        }
                                        else {
                                            proxy.scrollTo("TOP", anchor: .bottom)
                                            
                                        }
                                    } label: { Text("TO UNREAD") }
                                    
                                    Text("\(unreadCount)")
                                    
                                    Button { fetchEventsFromFollowing(amount:500) } label: { Text("Fetch") }
                                }
                            }
                        }
                        .background(.regularMaterial)
                    }
                    
                }.onAppear {
                    //                    proxy.scrollTo("TOP")
                    unreadCount = updateUnreadCount()
                }
                VStack {
                    HStack {
                        Spacer()
                        if (unreadCount > 0) {
                            Text("\(unreadCount)")
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
                .onChange(of: reversed) { newReversed in
                    print("onChange")
                    print("first: \(reversed.first!.created_at)")
                    print("last: \(reversed.first!.created_at)")
                    unreadCount = updateUnreadCount()
                }
            }
        }
        
    }
}

extension TimelineView {
    private func fetchEventsFromFollowing(amount:Int? = 500) {
        for socket in cm.relaySockets {
            if (socket.relay.read || socket.relay.write) && !socket.isConnected {
                socket.socket.connect()
            }
        }
        
        let followingPubkeys = [String](accountState.followingPublicKeys)
        cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getFollowingEvents(pubkeys: followingPubkeys, limit: amount!, since: ep.lastTimelineEventTimestamp)))
    }
    
    private func importEvents() async {
        Task {
            let before = await ep.queue.count
            try await ep.importEvents()
            if (before != 0) {
                print("didParse? queue count, before: \(before) after: \(await ep.queue.count)")
            }
        }
    }
}

struct TimelineFRControllerView: View {
    
    @FetchRequest
    var events:FetchedResults<Event>
    
    //    init(followingPubkeys:[String]) {
    //        _events = FetchRequest(
    //            sortDescriptors: [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)],
    //            predicate: NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId == nil", followingPubkeys)
    //        )
    //    }
    
    init(followingPubkeys:[String], showReplies:Bool) {
        let fr = NSFetchRequest<Event>(entityName: "Event")
        
        if (showReplies) {
            fr.predicate = NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId != nil", followingPubkeys)
        }
        else {
            fr.predicate = NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId == nil", followingPubkeys)
        }
        
        fr.fetchLimit = 30
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        
        _events = FetchRequest(fetchRequest: fr)
    }
    
    var body: some View {
        TimelineView(events:events)
    }
    
}

struct TimelineView_Previews: PreviewProvider {
    static var previews: some View {
        
        let pubkeys = ["1833ee04459feb2ca4ae690d5f31269ad488c69e5fe903a42b532c677c4a8170","84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240","3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24"]
        
        TimelineFRControllerView(followingPubkeys: pubkeys, showReplies:false)
            .withPreviewEnvironment()
    }
}
