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
    
    @State var notes: [Event] = []
//    @State var notes:[Slice<FetchedResults<Event>>] = []
    
    @State var didSetup = false
    @State var isLoading = true
    
    let timelineRunLoop = Timer.publish(every: 15, tolerance: 1, on: .main, in: .common).autoconnect()
    @State var timesFetchedWhileUnread = 0 // Increases if there are unread messages (prevent unnecessary refresh)
    @State var shouldSkipTimes = 0
    @State var isViewDisplayed = false
    
    var ep: EventsProvider = .shared
    var sp: SocketPool = .shared
    var mp: MessageParser = .shared
    
    var account:Account
    
    @AppStorage("lastReadDate") var lastReadDate = 0
    @State var didAutoScroll = false // Only scroll to last unread after launch, not after .onAppear after coming back from detail
    @State var unreadCount = 0
    @State var lastReadIndex = 0
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
        if (account.blockedContacts == nil) {
            fr.predicate = showReplies
            ? NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId != nil", followingPubkeys)
            : NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId == nil", followingPubkeys)
        } else {
            fr.predicate = showReplies
            ? NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId != nil AND NOT contact IN %@", followingPubkeys, account.blockedContacts!)
            : NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId == nil AND NOT contact IN %@", followingPubkeys, account.blockedContacts!)
        }
        
        fr.fetchLimit = 10 // 5 = FAST TIMELINE TO DETAIL. 75 = SLOW (MET VSTACK).
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.insertedAt, ascending: false),
                              NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        
        _events = FetchRequest(fetchRequest: fr)
    }
    
    func scrollToTop(_ proxy:ScrollViewProxy) {
        proxy.scrollTo(SCROLL_TO_TOP_ANCHOR)
//        withAnimation {
//            proxy.scrollTo(SCROLL_TO_TOP_ANCHOR)
//        }
    }
    
    func eventAppeared(_ index:Int) {
        if index >= lastReadIndex {
            lastReadIndex = index
        }
//        print("eventAppeared:\(index), lastReadIndex: \(lastReadIndex) notes.count: \(notes.count)")
        unreadCount = notes.count - (lastReadIndex+1)
    }
    
    var body: some View {
        VStack {
            HStack {
                Color.clear.frame(width: 200, height: 30)
            }
            ZStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) { // Lazy = Jittery, Vstack
                            ForEach(notes.indices, id:\.self) { index in
                                VStack(spacing: 0) {
                                    NoteRowView(event: notes[index])
                                        .scaleEffect(x:1, y:-1)
                                    Color.clear.frame(width: 200, height: 0).onAppear { eventAppeared(index) }
                                }.id(notes[index].id)
                                Divider()
                            }
                        }
                        //                    .background(Color.random)
                        Color.clear.frame(width: 300, height: 0)
                            .id(SCROLL_TO_TOP_ANCHOR)
                    }
                    .scaleEffect(x:1, y:-1)
                    .onAppear { if (!didSetup) { setupNotes() } }
                    .safeAreaInset(edge: .bottom) {
                        HStack {
                            Text("E:\(events.count) N:\(notes.count)")
                            Spacer()
                            Button { fetchEventsFromFollowing(amount:500) } label: { Text("Fetch") }
                            Button { loadNewNotes() } label: { Text("Load (\(events.count - notes.count))") }
                            Button { scrollToTop(proxy) } label: { Text("To Top") }
                            Spacer()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .background(.regularMaterial)
                    }
                    .onAppear {
                        if (events.first == nil) {
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
                UnreadCounter(count:unreadCount)
            }
        }
    }
}

struct UnreadCounter: View {
    var count:Int
    var body: some View {
        VStack {
            HStack {
                Spacer()
                if (count > 0) {
                    Text("\(count)")
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

// MARK: PAGINATION
extension Timeline {

    func setupNotes() {
        print("setupPages")
        didSetup = true
        
        let oldestAtIndexZero = events.sorted(by: { $0.created_at < $1.created_at })
        for index in 0..<events.count {
            notes.append(oldestAtIndexZero[index])
        }
        
        oldestAtIndexZero.forEach { event in
            print("\(event.id!) \(d(event.created_at))")
        }
    }
    
    func loadNewNotes() {
        
        let oldestAtIndexZero = events.sorted(by: { $0.created_at < $1.created_at })
        let beforeEventsCount = notes.count
        for index in 0..<events.count { // 0..<11
            if (index < beforeEventsCount) { continue }
            notes.append(oldestAtIndexZero[index])
            
            // 0, 1, 2, 3, 4, 5, 6, 7
            // N, N, 0, 1, 2, 3, 4, 5
        }
        oldestAtIndexZero.forEach { event in
            print("\(event.id!) \(d(event.created_at))")
        }
    }
}

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
        
        let account = PreviewFetcher.fetchAccount("5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0", context: EventsProvider.preview.container.viewContext)
        
        let pubkeys = Set(["1833ee04459feb2ca4ae690d5f31269ad488c69e5fe903a42b532c677c4a8170","84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240","3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24"])
        
        Timeline(showReplies: true, showMenu: $showMenu, followingPubkeys: pubkeys, account: account!)
            .withPreviewEnvironment()
        
    }
}
