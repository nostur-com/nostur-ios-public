//
//  EventsWindow.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/01/2023.
//

import SwiftUI
import CoreData

class TimelineModel {
    // Yo use this??
}

struct TimelineView: View {
    
    let timelineRunLoop = Timer.publish(every: 8, tolerance: 1, on: .main, in: .common).autoconnect()
    @State var timesFetchedWhileUnread = 0 // Increases if there are unread messages (prevent unnecessary refresh)
    @State var shouldSkipTimes = 0
    @State var isViewDisplayed = false
    
    var ep: EventsProvider = .shared
    var sp: SocketPool = .shared
    var mp: MessageParser = .shared
    
    //    @EnvironmentObject var ns:NosturState
    
    //    @EnvironmentObject var cm:ConnectionManager
    
    
    @State var isRefreshing = true
    @State var isLoading = true
    var events:FetchedResults<Event>
    var reversed:[Event]
    var account:Account
    
    init(events: FetchedResults<Event>, account:Account) {
        self.events = events
        self.reversed = events.reversed() // Starts with (30?) events
        self.account = account
    }
    
    
    @AppStorage("lastReadDate") var lastReadDate = 0
    @State var didAutoScroll = false // Only scroll to last unread after launch, not after .onAppear after coming back from detail
    @State var unreadCount = 0
    
    func getUnreadCount(events:[Event]? = nil) -> Int {
        if (events != nil) {
            return events!.filter { $0.created_at > lastReadDate }.count
        }
        return reversed.filter { $0.created_at > lastReadDate }.count
    }
    
    func lastReadEvent() -> Event? {
        return events.filter { $0.created_at == lastReadDate }.first
    }
    
    func firstUnreadEvent() -> Event? {
        return events.filter { $0.created_at > lastReadDate }
            .sorted { e1, e2 in
                e1.created_at > e2.created_at
            }
            .last
    }
    
    //    func firstUnreadEvent2() -> Event? {
    //        return events.filter { $0.created_at >= lastReadDate }
    //            .sorted { e1, e2 in
    //                e1.created_at < e2.created_at
    //            }
    //            .last
    //    }
    //
    //    func firstUnreadEvent3() -> Event? {
    //        return events.filter { $0.created_at >= lastReadDate }
    //            .sorted { e1, e2 in
    //                e1.created_at > e2.created_at
    //            }
    //            .first
    //    }
    //
    //    func firstUnreadEvent4() -> Event? {
    //        return events.filter { $0.created_at >= lastReadDate }
    //            .sorted { e1, e2 in
    //                e1.created_at < e2.created_at
    //            }
    //            .first
    //    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                //                VStack {
                ScrollView {
                    // INVERTED SCROLLVIEW: THIS IS THE BOTTOM
                    VStack { // LazyVStack here = STUTTER, SO VSTACK FOR NOW
                        ForEach(reversed, id:\.self) { event in
                            VStack {
                                
                                NoteRowView(event: event)
                                    .scaleEffect(x: 1, y: -1)
                                
                                //                                    .contextMenu {
                                //                                        Button {
                                //                                            UIPasteboard.general.string = event.noteId
                                //                                        } label: {
                                //                                            Label("Copy note id \(event.noteId)", systemImage: "doc.on.clipboard")
                                //                                        }
                                //                                        Button {
                                //                                            UIPasteboard.general.string = event.id!
                                //                                        } label: {
                                //                                            Label("Copy note id hex \(event.id!))", systemImage: "doc.on.clipboard")
                                //                                        }
                                //                                        Button {
                                //                                            print("Unfollow @\(event.username)")
                                //                                        } label: {
                                //                                            Label("Unfollow @\(event.username)", systemImage: "person.fill.xmark")
                                //                                        }
                                //                                        Button {
                                //                                            print("Block @\(event.username)")
                                //                                        } label: {
                                //                                            Label("Block @\(event.username)", systemImage: "slash.circle")
                                //                                        }
                                //                                    }
                                
                                // BECAUSE INVERTED, THIS ONE IS ABOVE EVERY NOTE:
                                LazyHStack {
                                    Color.clear.frame(width: 100, height: 1)
                                        .onAppear {
                                            isViewDisplayed = true
                                            if (didAutoScroll) {
                                                print("💖 lastReadDate was: \(d(event.created_at).description)")
                                                lastReadDate = Int(event.created_at) >= lastReadDate ? Int(event.created_at) : lastReadDate
                                                unreadCount = getUnreadCount()
                                                print("💖 lastReadDate is now: \(d(lastReadDate).description)")
                                            }
                                        }
                                }
                                
                            }
                            .id(event.id)
                        }
                        // THIS FRAME (ID:TOP) IS ALWAYS AT THE TOP BECAUSE INVERTED SCROLLVIEW
                        Color.clear
                            .frame(width: 100, height: 1, alignment: .bottom)
                            .id("TOP")
                        //                                .onAppear {
                        //                                    unreadCount = getUnreadCount()
                        //                                    if (events.count > 10) {
                        //                                        //                                            removeFirst()
                        //                                        //                                            removeFirst()
                        //                                        //                                            removeFirst()
                        //                                        //                                                proxy.scrollTo("TOP", anchor: .bottom)
                        //                                    }
                        //                                }
                    }
                    // INVERTED SCROLLVIEW: THIS THE TOP
                }
                .scaleEffect(x: 1, y: -1)
                //                    .refreshable {
                //                        await fetchNotes()
                //                    }
                //                    .transaction { t in
                //                        t.animation = .none
                //                    }
                .safeAreaInset(edge: .top) {
                    HStack {
                        VStack {
                            Text("Last lastReadDate \(d(lastReadDate).description)")
                            //                            Text("Last READ \(d(lastReadDate))")
                            //                                Text("1st UNREAD: \(firstUnreadEvent() != nil ? d(firstUnreadEvent()!.created_at) : "?")")
                            ControlGroup {
                                Button {
                                    proxy.scrollTo("TOP", anchor: .bottom) } label: { Text("TO TOP") }
                                //                                    Button {
                                //                                        if let unreadEvent = firstUnreadEvent() {
                                //                                            proxy.scrollTo(unreadEvent.id!, anchor: .bottom)
                                //                                        }
                                //                                        else {
                                //                                            proxy.scrollTo("TOP", anchor: .bottom)
                                //
                                //                                        }
                                //                                    } label: { Text("TO UNREAD") }
                                
                                Text("\(unreadCount)")
                                
                                Button { importNotes() } label: { Text("Import") }
                                Button { fetchEventsFromFollowing(amount:500) } label: { Text("Fetch & parse") }
                            }
                        }
                    }
                    .background(.regularMaterial)
                }
                //                }
                .onAppear {
                    //                    proxy.scrollTo("TOP")
                    unreadCount = getUnreadCount()
                    if (events.first != nil) {
                        print("🤩🤩 onAppear, last read = \(d(lastReadDate).description)")
                        print("🤩🤩 onAppear, last first = \(d(events.first!.created_at).description)")
                        print("🤩🤩 onAppear, last event = \(d(events.last!.created_at).description)")
                    }
                    
                    let x = lastReadEvent()
                    if (x != nil) {
                        Task {
                            if (!didAutoScroll) {
                                try await Task.sleep(nanoseconds: 2_000_000_000)
                                print("🤩🤩 XXXX, last event = \(d(x!.created_at).description)")
                                proxy.scrollTo(x!.id, anchor: .bottom)
                                isLoading = false
                                didAutoScroll = true
                            }
                        }
                    }
                    else {
                        isLoading = false
                        didAutoScroll = true
                    }
                    
                    //                    let x = firstUnreadEvent()
                    //                    if (x != nil) {
                    //                        Task {
                    //                            try await Task.sleep(nanoseconds: 3_000_000_000)
                    //                            print("🤩🤩 XXXX, last event = \(d(x!.created_at))")
                    //                            proxy.scrollTo(x!.id)
                    //                        }
                    //                    }
                    
                    
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
                .onChange(of: events.first) { newFirstEvent in
                    print("🤩🤩 (Fetched)events changed, first was: \(String(events.first!.noteText.prefix(100)))")
                    print("🤩🤩 (Fetched)events changed, first is: \(String(newFirstEvent!.noteText.prefix(100)))")
                }
                .onChange(of: events.last) { newLastEvent in
                    print("🤩🤩 (Fetched)events changed, last was: \(String(events.last!.noteText.prefix(100)))")
                    print("🤩🤩 (Fetched)events changed, last is: \(String(newLastEvent!.noteText.prefix(100)))")
                }
                .onChange(of: reversed) { newReversed in
                    // NEW EVENTS LOADED
                    print("🤩🤩 reversed onChange")
                    print("🤩🤩 first: \(d(reversed.first!.created_at))")
                    print("🤩🤩 last: \(d(reversed.last!.created_at))")
                    let nextUnreadCount = getUnreadCount(events:newReversed)
                    if (nextUnreadCount != unreadCount) {
                        unreadCount = nextUnreadCount
                    }
                    //                    unreadCount = getUnreadCount(events:newReversed)
                    print("🤩🤩 unreadCount: \(unreadCount)")
                    //                    isRefreshing = false
                }
                .onReceive(timelineRunLoop) { time in
                    
                    if (!isViewDisplayed) {
                        return
                    }
                    
                    print("unread is: \(unreadCount) timesFetchedWhileUnread: \(timesFetchedWhileUnread) shouldSkipTimes: \(shouldSkipTimes)")
                    
                    
                    if (unreadCount > 0 && shouldSkipTimes > 0) {
                        shouldSkipTimes = shouldSkipTimes - 1
                        return
                    }
                    
                    
                    print("🍭🍭🍭 GONNA FETCH BABY 🍭🍭🍭🍭")
                    fetchEventsFromFollowing(amount: 500)
                    
                    if (unreadCount > 0) {
                        shouldSkipTimes = timesFetchedWhileUnread + shouldSkipTimes + 1
                        timesFetchedWhileUnread = timesFetchedWhileUnread + 1
                        
                        if (shouldSkipTimes > 8) {
                            shouldSkipTimes = 8
                            timesFetchedWhileUnread = 0
                            print("never skip more than 8 times")
                        }
                        else {
                            print("increase delay!")
                        }
                        
                    }
                    else {
                        print("delay reset")
                        shouldSkipTimes = 0
                        timesFetchedWhileUnread = 0
                    }
                    
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
                    
                    if (MessageParser.shared.lastTimelineEventTimestamp != nil) {
                        print("last timeline event timestamp: \(d(MessageParser.shared.lastTimelineEventTimestamp!.timestamp).description)")
                    }
                    if (Importer.shared.lastTimelineEventTimestamp != nil) {
                        print("last timeline event timestamp: \(d(Importer.shared.lastTimelineEventTimestamp!.timestamp).description)")
                    }
                }
                VStack {
                    if (isLoading) {
                        Rectangle()
                            .background(.regularMaterial)
                    }
                }
            }
        }
        
    }
}

extension TimelineView {
    
    private func importNotes() {
        Task { await Importer.shared.importEvents() }
    }
    
    private func fetchNotes() async {
        isRefreshing = true
        fetchEventsFromFollowing(amount:500)
        //TODO: hmmm need to return earlier if onChange events.last
        try! await Task.sleep(nanoseconds: 1_000_000_000)
        isRefreshing = false
    }
    
    private func fetchEventsFromFollowing(amount:Int? = 500) {
        if (account.follows != nil) {
            let followingPubkeys = [String](account.follows!.map { $0.pubkey! } )
            sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getFollowingEvents(pubkeys: followingPubkeys, limit: amount!, since: mp.lastTimelineEventTimestamp)))
        }
    }
}

struct d {
    var t:Int64?
    
    init(_ t:Int64? = nil) {
        self.t = t
    }
    
    init(_ t:NTimestamp? = nil) {
        if (t != nil) {
            self.t = Int64(t!.timestamp)
        }
    }
    
    init(_ t:Int) {
        self.t = Int64(t)
    }
    
    init(_ t:Int? = nil) {
        if (t != nil) {
            self.t = Int64(t!)
        }
    }
    
    var description:String {
        get {
            if (t == nil) { return "?" }
            return Date(timeIntervalSince1970: TimeInterval(t!)).formatted(.dateTime.hour().minute().second())
        }
    }
}
//func d(_ t:Int64?) -> String {
//    if (t == nil) { return "?" }
//
//}

struct TimelineFRControllerView: View {
    
    @EnvironmentObject var ns:NosturState
    
    @FetchRequest
    var events:FetchedResults<Event>
    
    init(followingPubkeys:[String], showReplies:Bool) {
        let fr = NSFetchRequest<Event>(entityName: "Event")
        
        if (showReplies) {
            fr.predicate = NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId != nil", followingPubkeys)
        }
        else {
            fr.predicate = NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId == nil", followingPubkeys)
        }
        
        fr.fetchLimit = 100
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        
        _events = FetchRequest(fetchRequest: fr)
    }
    
    var body: some View {
        if (ns.account != nil) {
            TimelineView(events:events, account: ns.account!)
        }
        else {
            Text("Please set up account first")
        }
        //        Spacer()
    }
    
}

struct TimelineView_Previews: PreviewProvider {
    static var previews: some View {
        
        let pubkeys = ["1833ee04459feb2ca4ae690d5f31269ad488c69e5fe903a42b532c677c4a8170","84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240","3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24"]
        
        TimelineFRControllerView(followingPubkeys: pubkeys, showReplies:false)
            .withPreviewEnvironment()
    }
}
