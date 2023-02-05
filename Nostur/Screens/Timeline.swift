//
//  ReversedTimeline.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/02/2023.
//

import SwiftUI
import CoreData
import Combine

struct Timeline: View {

    @Environment(\.managedObjectContext) var viewContext
    @Namespace var SCROLL_TO_TOP_ANCHOR
    
    @State var pages: [PageModel] = []
    let pageSize:Int = 1
    
    @State var didSetup = false
//    @State var isRefreshing = true
    @State var isLoading = true
    
    let timelineRunLoop = Timer.publish(every: 15, tolerance: 1, on: .main, in: .common).autoconnect()
    @State var timesFetchedWhileUnread = 0 // Increases if there are unread messages (prevent unnecessary refresh)
    @State var shouldSkipTimes = 0
    @State var isViewDisplayed = false
    
    var ep: EventsProvider = .shared
    var sp: SocketPool = .shared
    var mp: MessageParser = .shared
    
//    var events:FetchedResults<Event>
//    var reversed:[Event]
    var account:Account
    
    @AppStorage("lastReadDate") var lastReadDate = 0
    @State var didAutoScroll = false // Only scroll to last unread after launch, not after .onAppear after coming back from detail
    @State var unreadCount = 0
    @Binding var showMenu:Bool // _showMenu changed ... why??? lots of reloads??
    
    @EnvironmentObject var ns:NosturState
    
    @FetchRequest(
        entity: Event.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
        predicate: NSPredicate(format: "FALSEPREDICATE")
    )
    var events: FetchedResults<Event>
    
    init(showReplies:Bool, showMenu:Binding<Bool>, followingPubkeys: Set<String>, account:Account) {
        self.account = account
        _showMenu = showMenu
    
        let fr = NSFetchRequest<Event>(entityName: "Event")
        if (1 == 1 || account.blockedContacts == nil) {
            fr.predicate = showReplies
            ? NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId != nil", followingPubkeys)
            : NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId == nil", followingPubkeys)
//            fr.predicate = NSPredicate(format: "kind == 1 and replyToId == nil")
        } else {
            fr.predicate = showReplies
            ? NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId != nil AND NOT contact IN %@", followingPubkeys, account.blockedContacts!)
            : NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId == nil AND NOT contact IN %@", followingPubkeys, account.blockedContacts!)
        }
        
        fr.fetchLimit = 50 // 5 = FAST TIMELINE TO DETAIL. 75 = SLOW (MET VSTACK).
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        
//        let fr = Event.fetchRequest()
//        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
//        fr.predicate = NSPredicate(format: "kind == 1 and replyToId == nil")
//        fr.fetchLimit = 50
        
        _events = FetchRequest(fetchRequest: fr)
    }
    
    func getUnreadCount(events:[Event]? = nil) -> Int {
        if (events != nil) {
            return events!.filter { $0.created_at > lastReadDate }.count
        }
        return 0
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
    
    func scrollToTop(_ proxy:ScrollViewProxy) {
        proxy.scrollTo(SCROLL_TO_TOP_ANCHOR)
//        withAnimation {
//            proxy.scrollTo(SCROLL_TO_TOP_ANCHOR)
//        }
    }
    
    var body: some View {
        let _ = Self._printChanges()
        VStack {
            HStack {
                Color.clear.frame(width: 200, height: 30)
            }
            ZStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack { // PAGES ARE LAZY
                            ForEach(pages, id:\.id) { page in
                                Page(events: page.events)
                                    .scaleEffect(x:1, y:-1)
                                //                                .onAppear {
                                //                                    print("🥶🥶 onAppear: PAGE \(page.id)")
                                //                                }
                            }
                        }
                        //                    .background(Color.random)
                        Color.clear.frame(width: 300, height: 0)
                            .id(SCROLL_TO_TOP_ANCHOR)
                    }
                    .scaleEffect(x:1, y:-1)
                    .onAppear {
                        if (!didSetup) {
                            setupPages()
                        }
                    }
                    .onDisappear {
                        print("ScrollView.onDisappear!")
                    }
                    .safeAreaInset(edge: .bottom) {
                        VStack(alignment: .center) {
                            HStack {
                                Button { fetchEventsFromFollowing(amount:500) } label: { Text("Fetch") }
                                Button {
                                    print("🚘 ADDING EVENTS")
                                    for _ in 0...3 {
                                        let newEvent = Event(context: viewContext)
                                        newEvent.id = UUID().description
                                        newEvent.pubkey = "1833ee04459feb2ca4ae690d5f31269ad488c69e5fe903a42b532c677c4a8170"
                                        
                                        //                                    newEvent.pubkey = "50d94fc2d8580c682b071a542f8b1e31a200b0508bab95a33bef0855df281d63"
                                        newEvent.kind = 1
                                        newEvent.created_at = Int64(Date.now.timeIntervalSince1970)
                                    }
                                    //                                updatePages()
                                } label: { Text("Add events (\(events.count))") }
                                Button { updatePages() } label: { Text("Pages (\(pages.count))") }
                                Button { scrollToTop(proxy) } label: { Text("To Top") }
                                //                            Text("LRD \(d(lastReadDate).description)")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            //                        HStack {
                            //                            Button { fetchEventsFromFollowing(amount:500) } label: { Text("1. Fetch") }
                            //                            Button { importNotes() } label: { Text("2. Import") }
                            //                            Button { updatePages() } label: { Text("3. Pages") }
                            //                            Button { scrollToTop() } label: { Text("To Top") }
                            //                            Text("\(unreadCount)")
                            //                        }
                            
                        }.background(.regularMaterial)
                    }
                    .onAppear {
                        unreadCount = getUnreadCount()
                        if (events.first != nil) {
                            //                    print("🤩🤩 onAppear, last read = \(d(lastReadDate).description)")
                            //                    print("🤩🤩 onAppear, last first = \(d(events.first!.created_at).description)")
                            //                    print("🤩🤩 onAppear, last event = \(d(events.last!.created_at).description)")
                        }
                        else {
                            isLoading = false
                            didAutoScroll = true
                        }
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
                        
                        
                        if (!Importer.shared.isImporting) {
                            print("💿💿 GONNA FETCH BABY 💿💿")
                            fetchEventsFromFollowing(amount: 500)
                        } else {
                            print("💿💿 STILL IMPORTING. NOT FETCHING YET 💿💿")
                        }
                        
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
                        if (MessageParser.shared.lastTimelineEventTimestamp != nil) {
                            print("last timeline event timestamp: \(d(MessageParser.shared.lastTimelineEventTimestamp!.timestamp).description)")
                        }
                        if (Importer.shared.lastTimelineEventTimestamp != nil) {
                            print("last timeline event timestamp: \(d(Importer.shared.lastTimelineEventTimestamp!.timestamp).description)")
                        }
                    }
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
            }
        }
    }
}

// MARK: PAGINATION
extension Timeline {

    func setupPages() {
        print("setupPages")
        didSetup = true
        let pageCount = Int(ceil(Double(events.count) / Double(pageSize))) // 33 / 3 = 11
        pages = []
        
        // All pages
        for loopCount in 0..<pageCount { // 0..<11
            let events = events.dropLast(loopCount * pageSize).suffix(pageSize)
            let page = PageModel(id: "\(loopCount)-\(events.count)", events: events)
            pages.append(page)
        }
    }
    
    func updatePages() {
        let pageCount = Int(ceil(Double(events.count) / Double(pageSize))) // 33 / 3 = 11
//        let oldEventsCount = pages.reduce(0) { partialResult, events in
//            return events.count + partialResult
//        }
        pages = []
        // All pages // TODO: HOw only update/add pages, leave existing in tact..
        for loopCount in 0..<pageCount { // 0..<11
            let events = events.dropLast(loopCount * pageSize).suffix(pageSize)
            let page = PageModel(id: "\(loopCount)-\(events.count)", events: events)
            pages.append(page)
        }
    }

}

struct Page: View {
    var events:Slice<FetchedResults<Event>>
    var body: some View {
        VStack {
            ForEach(events) { event in
                NoteRowView(event: event)
                    .id(event.id)
            }
        }
    }
}

//struct TimelineWrapper: View {
//
//    // Maybe put this code no longer needs to be in parent, because of the dynamic predicate problem has been solved.
//
//    @EnvironmentObject var ns:NosturState
//    @Binding var showMenu:Bool
//
//    @FetchRequest(
//        entity: Event.entity(),
//        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
//        predicate: NSPredicate(format: "FALSEPREDICATE")
//    )
//    var events: FetchedResults<Event>
//
//    init(showReplies:Bool, followingPubkeys: Set<String>, showMenu: Binding<Bool>) {
//        _showMenu = showMenu
//
//        let fr = NSFetchRequest<Event>(entityName: "Event")
//        fr.predicate = showReplies
//            ? NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId != nil", followingPubkeys)
//            : NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId == nil", followingPubkeys)
//
//        fr.fetchLimit = 100 // 5 = FAST TIMELINE TO DETAIL. 75 = SLOW
//        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
//
//        _events = FetchRequest(fetchRequest: fr)
//    }
//
//    var body: some View {
//        if (ns.account != nil) {
//            Timeline(events:events, account: ns.account!, showMenu: $showMenu)
//                .onAppear {
//                    print("💿💿 RELOADDED??? ")
//                }
//        }
//        else {
//            Text("Please set up account first")
//        }
//        //        Spacer()
//    }
//
//}

extension Timeline {
    
    private func importNotes() {
//        print("💿💿 2. S:\(vm.scrollOffset) A:\(vm.anchorOffset) H:\(vm.contentHeight) - BEFORE IMPORT events.count: \(events.count)")
        Task { await Importer.shared.importEvents() }
    }
    
    private func fetchNotes() async {
//        isRefreshing = true
        fetchEventsFromFollowing(amount:500)
        //TODO: hmmm need to return earlier if onChange events.last
        try! await Task.sleep(nanoseconds: 1_000_000_000)
//        isRefreshing = false
    }
    
    private func fetchEventsFromFollowing(amount:Int? = 500) {
//        print("💿💿 1. S:\(vm.scrollOffset) A:\(vm.anchorOffset) H:\(vm.contentHeight) - BEFORE FETCH events.count: \(events.count)")
        
        if (account.follows != nil) {
            let followingPubkeys = [String](account.follows!.map { $0.pubkey! } )
            sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getFollowingEvents(pubkeys: followingPubkeys, limit: amount!, since: mp.lastTimelineEventTimestamp)))
        }
    }
}

struct Timeline_Previews: PreviewProvider {
    @State static var showMenu = true
    static var previews: some View {
        
        let account = PreviewFetcher.fetchAccount("5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0")
        
        let pubkeys = Set(["5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0",
            "1833ee04459feb2ca4ae690d5f31269ad488c69e5fe903a42b532c677c4a8170","84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240","3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24"])
        
        Timeline(showReplies: true, showMenu: $showMenu, followingPubkeys: pubkeys, account: account!)
            .withPreviewEnvironment()
        
    }
}
