//
//  ReversedTimeline.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/02/2023.
//

import SwiftUI
import CoreData
import Combine

extension Timeline {
    
    @MainActor class TimelineViewModel: ObservableObject {
        
//        static var shared = TimelineViewModel()
        var cancellables = Set<AnyCancellable>()
        
        @Published private(set) var scrollOffset = CGFloat.zero
        @Published private(set) var contentHeight = CGFloat.zero
        @Published private(set) var anchorOffset = CGFloat.zero
        
        @Published private(set) var oldScrollOffset = CGFloat.zero
        @Published private(set) var oldContentHeight = CGFloat.zero
        @Published private(set) var savedHeight = CGFloat.zero
        @Published private(set) var scrollCounter = 0
        
        @Published private(set) var scrollOffsetEmitter = PassthroughSubject<CGFloat, Never>()
        @Published private(set) var contentHeightEmitter = PassthroughSubject<CGFloat, Never>()
        
        var theDiff = 0.0
        var pendingRescroll = false
        
        init() {
            addSubscribers()
        }
        
        deinit { for c in cancellables { c.cancel() } }
        
        func updateAnchorOffset() {
            if (pendingRescroll) {
                print("🎃 ANCHOR DIFF:\(self.theDiff)")
                self.anchorOffset = self.scrollOffset + self.theDiff
                self.theDiff = 0
                self.pendingRescroll = false
            }
//            self.anchorOffset = self.contentHeight - self.oldContentHeight + self.scrollOffset
//            print("💿💿 NEW ANCHOR DIFF: \(self.contentHeight - self.oldContentHeight)")
        }
        
        func saveHeight() {
            self.savedHeight = self.contentHeight
            self.theDiff = 0.0
            self.pendingRescroll = true
        }
        
        func saveOldHeightAndOffset() {
            self.oldContentHeight = self.contentHeight
            self.oldScrollOffset = self.scrollOffset
            print("💿💿 SAVE HEIGHT + OFFSET = \(self.contentHeight) ::: \(self.scrollOffset)")
        }
        
        func addSubscribers() {
            scrollOffsetEmitter
//                .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
                .sink { value in
                    self.scrollOffset = value
                    self.anchorOffset = value // Keep anchor + scroll in sync
                }
                .store(in: &cancellables)
            
            contentHeightEmitter
//                .debounce(for: .seconds(0.15), scheduler: RunLoop.main)
                .sink { value in
                    self.contentHeight = value
                    
                    if (self.pendingRescroll) {
                        self.theDiff = self.contentHeight - self.savedHeight
                        self.scrollCounter = self.scrollCounter + 1
                        print("🎃 NEW HEIGHT:\(self.contentHeight)")
                    }
                    
//                    print("💿💿🟢 S:\(self.scrollOffset) A:\(self.anchorOffset) H:\(self.contentHeight) - HERES THE NEW HEIGHT")
                }
                .store(in: &cancellables)
        }
    }
}

struct Timeline: View {
    
    @StateObject private var vm = TimelineViewModel()
    
    @Namespace var scrollSpace
    // MARK: PAGINATION
//    @State var firstPageEvents: Slice<FetchedResults<Event>>? = nil
//    @State var pages: [Slice<FetchedResults<Event>>] = []
//    @State var pages: [ArraySlice<FetchedResults<Event>>] = []
//    @State var pages: [ArraySlice<[Event]>] = []
//    @State var pages: [ReversedCollection<ArraySlice<Event>>] = []
    @State var pages: [Slice<FetchedResults<Event>>] = []
//    @State var pages: [[Event]] = []
    let pageSize:Int = 7
    
    
    
    // MARK: FIRST PAGE: KEEP SCROLL POSITION AFTER NEW EVENTS LOADED
    @Namespace var SCROLL_ANCHOR

//    @State var scrollCounter = 0
    
    @State var isRefreshing = true
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
    @Binding var showMenu:Bool
    
    @EnvironmentObject var ns:NosturState
//    @Binding var showMenu:Bool
    
    @FetchRequest(
        entity: Event.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
        predicate: NSPredicate(format: "FALSEPREDICATE")
    )
    var events: FetchedResults<Event>
    
    init(showReplies:Bool, followingPubkeys: Set<String>, showMenu: Binding<Bool>, account:Account) {
        self.account = account
        _showMenu = showMenu
        
        let fr = NSFetchRequest<Event>(entityName: "Event")
        if (account.blockedContacts == nil) {
            fr.predicate = showReplies
            ? NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId != nil", followingPubkeys)
            : NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId == nil", followingPubkeys)
            
            fr.fetchLimit = 150 // 5 = FAST TIMELINE TO DETAIL. 75 = SLOW (MET VSTACK).
            fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        } else {
            fr.predicate = showReplies
            ? NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId != nil AND NOT contact IN %@", followingPubkeys, account.blockedContacts!)
            : NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId == nil AND NOT contact IN %@", followingPubkeys, account.blockedContacts!)
            
            fr.fetchLimit = 150 // 5 = FAST TIMELINE TO DETAIL. 75 = SLOW (MET VSTACK).
            fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        }
        
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
    
    var body: some View {
        
        ZStack {
            ScrollView {
                ScrollViewReader { proxy in
                    ZStack { // ZSTACK WITH 2 LAYERS: PAGES, ANCHOR.
                        LazyVStack { // PAGES ARE LAZY
                            ForEach(pages.reversed(), id:\.first) { events in
                                Page(events: events)
                                    .onAppear {
//                                        print("🥶🥶 LAZY PAGE \(pages.firstIndex { $0.first! == events.first! } )")
                                    }
                            }
                        }
                        VStack(spacing: 0) { // THE SCROLL ANCHOR
                            Rectangle().foregroundColor(.yellow).opacity(0.3).frame(width:370, height: vm.anchorOffset < 0 ? 0 : vm.anchorOffset).foregroundColor(.yellow)
                            Color.clear.frame(width: 370, height: 0)
                                .id(SCROLL_ANCHOR)
                            Spacer()
                        }
                    }
                    // SEND TO PARENT: SCROLL OFFSET + CONTENT HEIGHT
                    .background(GeometryReader { geo in
                        Color.clear.preference(
                            key: ViewOffsetKey.self,
                            value: -geo.frame(in: .named(scrollSpace)).minY
                        ).preference(
                            key: ContentHeightKey.self,
                            value: geo.size.height
                        )
                    })
                    // RECEIVE FROM CHILD: SCROLL OFFSET
                    .onPreferenceChange(ViewOffsetKey.self) { offset in
//                        emitter.send(offset) // SEND DEBOUNCED
//                        print("💿💿💿💿💿💿 .onPreferenceChange(ViewOffsetKey.self)")
                        vm.scrollOffsetEmitter.send(offset)
                    }
                    // RECEIVE FROM CHILD: CONTENT HEIGHT
                    .onPreferenceChange(ContentHeightKey.self) { height in
//                        print("💿💿💿💿💿💿 .onPreferenceChange(ContentHeightKe")
                        if (1 == 1) { // TODO: IF did receive or change events. Else height cannot be changed.
//                            emitter2.send(height) // SEND DEBOUNCED
                            vm.contentHeightEmitter.send(height)
                        }
                    }
                    // MAKE PROXY.SCROLLTO ACCESSIBLE FROM OUTSIDE
                    // BY WATCHING FOR SCROLLCOUNTER CHANGES
                    .onChange(of: vm.scrollCounter) { newScrollCounter in
//                        print("💿💿 4. S:\(vm.scrollOffset) A:\(vm.anchorOffset) H:\(vm.contentHeight) - BEFORE SCROLL TO. 💿 OH: \(vm.oldContentHeight).   DIFF: \(vm.contentHeight - vm.oldContentHeight)")
                        
//                        let scrollDiff = vm.contentHeight - vm.oldContentHeight
                        
//                        if (scrollDiff > 0) { // TODO: Can scrollDiff be negative??? dunno
                            vm.updateAnchorOffset()
                            proxy.scrollTo(SCROLL_ANCHOR, anchor: .top)
//                            vm.saveOldHeightAndOffset()
//                        }
                        
                    }
                }
            }
            .coordinateSpace(name: scrollSpace)
            .onAppear {
                setupPages()
            }
            .onChange(of: events.first) { newestEvent in
//                updatePages() // Even nog niet auto updaten tijdens debuggen
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .center) {
                    HStack {
                        Text("EVENTS: \(events.count)\nSCROLL: \(Int(vm.scrollOffset)) ANCHOR: \(Int(vm.anchorOffset))\nCONTENT: \(Int(vm.contentHeight)) DIFF:\(Int(vm.anchorOffset - vm.scrollOffset))")
                    }
                    HStack {
                        ProfilePicView(pubkey: account.publicKey!, account: account, size:30)
                            .offset(x: 30)
                            .onTapGesture {
                                showMenu = true
                            }
                        Spacer()
                        Spacer()
                        Image("NosturLogo")
                                                        .resizable()
                                                        .scaledToFit()
                            .frame(height:30)
                            .offset(x: -15)
                        Spacer()
                        Text("LRD \(d(lastReadDate).description)")
                        Spacer()
                    }
                    HStack {
                        Button { fetchEventsFromFollowing(amount:500) } label: { Text("1. Fetch") }
                        Button { importNotes() } label: { Text("2. Import") }
                        Button { updatePages() } label: { Text("3. Pages \(pages.count)") }
//                        Button { vm.scrollCounter += 1 } label: { Text("4. Scroll") }
                        Button {
                            print("💿💿 I. S:\(vm.scrollOffset) A:\(vm.anchorOffset) H:\(vm.contentHeight) - INFO events.count: \(events.count)")
                        } label: { Text("I") }
                        Text("\(unreadCount)")
                    }.buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle)
                        .tint(.cyan)
                    
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
//                print("🤩🤩 (Fetched)events changed, first was: \(String(events.first!.noteText.prefix(100)))")
//                print("🤩🤩 (Fetched)events changed, first is: \(String(newFirstEvent!.noteText.prefix(100)))")
            }
            .onChange(of: events.last) { newLastEvent in
//                print("🤩🤩 (Fetched)events changed, last was: \(String(events.last!.noteText.prefix(100)))")
//                print("🤩🤩 (Fetched)events changed, last is: \(String(newLastEvent!.noteText.prefix(100)))")
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
    }
}

// MARK: PAGINATION
extension Timeline {

    func setupPages() {
//        print("💿💿 2. S:\(vm.scrollOffset) A:\(vm.anchorOffset) H:\(vm.contentHeight) - BEFORE PAGES events.count: \(events.count)")
        let pageCount = Int(ceil(Double(events.count) / Double(pageSize))) // 33 / 3 = 11
        pages = []
        
        // All pages
        for loopCount in 0..<pageCount { // 0..<11
            pages.append(events.dropLast(loopCount * pageSize).suffix(pageSize))
        }
//        print("💿💿 3. S:\(vm.scrollOffset) A:\(vm.anchorOffset) H:\(vm.contentHeight) - AFTER PAGES events.count: \(events.count)")
//        scrollCounter = scrollCounter + 1
    }
    
    func updatePages() {
        print("🎃 HEIGHT:\(vm.contentHeight)")
        
        vm.saveHeight()
        
        let pageCount = Int(ceil(Double(events.count) / Double(pageSize))) // 33 / 3 = 11
        let oldEventsCount = pages.reduce(0) { partialResult, events in
            return events.count + partialResult
        }
//        print("💿💿🟡 BEFORE updatePages S:\(vm.scrollOffset) A:\(vm.anchorOffset) H:\(vm.contentHeight) pageCount: \(pageCount) oldEvents: \(oldEventsCount)")
        
        pages = []
        // All pages // TODO: HOw only update/add pages, leave existing in tact..
        for loopCount in 0..<pageCount { // 0..<11
            pages.append(events.dropLast(loopCount * pageSize).suffix(pageSize))
        }

        let newEventsCount = pages.reduce(0) { partialResult, events in
            return events.count + partialResult
        }
        
        //TODO: For new events in the timeline, fetch mention, contacts. "mention", "p", req.0
        
        
//        print("💿💿🟢 AFTER updatePages S:\(vm.scrollOffset) A:\(vm.anchorOffset) H:\(vm.contentHeight) pageCount: \(pageCount) newEventsCount: \(newEventsCount) -- prolly new height not rendered yet")
//        scrollCounter = scrollCounter + 1
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

struct ViewOffsetKey: PreferenceKey {
    typealias Value = CGFloat
    static var defaultValue = CGFloat.zero
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value += nextValue()
    }
}

struct ContentHeightKey: PreferenceKey {
  static var defaultValue = CGFloat.zero

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value += nextValue()
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
        isRefreshing = true
        fetchEventsFromFollowing(amount:500)
        //TODO: hmmm need to return earlier if onChange events.last
        try! await Task.sleep(nanoseconds: 1_000_000_000)
        isRefreshing = false
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
        
        let pubkeys = Set(["1833ee04459feb2ca4ae690d5f31269ad488c69e5fe903a42b532c677c4a8170","84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240","3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24"])
        
        Timeline(showReplies: true, followingPubkeys: pubkeys, showMenu: $showMenu, account: account!)
            .withPreviewEnvironment()
        
    }
}
