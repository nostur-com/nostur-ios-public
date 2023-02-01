//
//  ReversedTimeline.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/02/2023.
//

import SwiftUI
import CoreData
import Combine

struct ReversedTimeline: View {
    
    @Namespace var SCROLL_ANCHOR
     
    @State var items = Array(0..<15)
    
    @State var scrollOffset = CGFloat.zero
    @State var anchorOffset = CGFloat.zero
    @State var contentHeight = CGFloat.zero
    
    @State var oldScrollOffset = CGFloat.zero
    @State var oldContentHeight = CGFloat.zero
    
    
    @State var isRefreshing = true
    @State var isLoading = true
    
    let timelineRunLoop = Timer.publish(every: 8, tolerance: 1, on: .main, in: .common).autoconnect()
    @State var timesFetchedWhileUnread = 0 // Increases if there are unread messages (prevent unnecessary refresh)
    @State var shouldSkipTimes = 0
    @State var isViewDisplayed = false
    
    var ep: EventsProvider = .shared
    var sp: SocketPool = .shared
    var mp: MessageParser = .shared
    
    var events:FetchedResults<Event>
    var reversed:[Event]
    var account:Account
    
    @AppStorage("lastReadDate") var lastReadDate = 0
    @State var didAutoScroll = false // Only scroll to last unread after launch, not after .onAppear after coming back from detail
    @State var unreadCount = 0
    @Binding var showMenu:Bool
    
    init(events: FetchedResults<Event>, account:Account, showMenu:Binding<Bool>) {
        self._showMenu = showMenu
        self.events = events
        self.reversed = events.reversed() // Starts with (30?) events
        self.account = account
        
        self.debouncedPublisher = relay
            .debounce(for: 0.15, scheduler: RunLoop.main)
                    .eraseToAnyPublisher()
    }
    
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
    @State var subscriptions = Set<AnyCancellable>()
    
    let subject = PassthroughSubject<CGFloat, Never>()
    let subject2 = PassthroughSubject<CGFloat, Never>()
    
    private var relay = PassthroughSubject<CGFloat,Never>()
    private var debouncedPublisher: AnyPublisher<CGFloat, Never>
    
    var body: some View {
        
        ZStack {
//            ObservableScrollView(scrollOffset: $scrollOffset, contentHeight: $contentHeight) { proxy in
            ScrollView {
                ZStack {
                    VStack { // LazyVStack here = STUTTER, SO VSTACK FOR NOW
                        ForEach(reversed, id:\.self) { event in
                            NoteRowView(event: event)
//                            VStack {
//                                NoteRowView(event: event)
//                            }.id(event.id)
                        }
                    }
                    VStack(spacing: 0) {
                        Rectangle().foregroundColor(.red).frame(width:370, height: anchorOffset < 0 ? 0 : anchorOffset).foregroundColor(.red)
                        Rectangle().foregroundColor(.red).frame(width: 370, height: 0)
//                        Color.clear.frame(width:370, height: anchorOffset < 0 ? 0 : anchorOffset).foregroundColor(.red)
//                        Color.clear.frame(width: 370, height: 0)
                            .id(SCROLL_ANCHOR)
                        Spacer()
                    }
                }
                .background(GeometryReader { geo in
                    
//                    Color.clear.onAppear {
//                        scrollOffset = -geo.frame(in: .named("scroll")).origin.y
//                        contentHeight = geo.size.height
//                    }
                    
                    Color.clear.preference(
                        key: ViewOffsetKey.self,
                        value: -geo.frame(in: .named("scroll")).origin.y
                    )
                    .preference(
                        key: ContentHeightKey.self,
                        value: geo.size.height
                    )
                    
                })
                .onPreferenceChange(ViewOffsetKey.self) { offset in
//                    subject.send(offset)
//                    scrollOffset = offset
                    relay.send(offset)
                }
                .onPreferenceChange(ContentHeightKey.self) { height in
//                    subject2.send(height)
//                    relay.send(height)
                    contentHeight = height
                }
                // This will work with items last I think????
//                .onChange(of: items) { newItems in
//                    anchorOffset = contentHeight - oldContentHeight + oldScrollOffset
//                    proxy.scrollTo(SCROLL_ANCHOR, anchor: .top)
//                }
                .onChange(of: scrollOffset) { newScrollOfset in
                    anchorOffset = newScrollOfset // KEEP SCROLL ANCHOR IN SYNC WITH SCROLL OFFSET
                }
                .onReceive(debouncedPublisher, perform: { offset in
//                    contentHeight = height
                    scrollOffset = offset
                })
            }
            .onAppear {
                
//                let cancellable = subject
//                    .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
//                    .sink { offset in
//                        print ("Received offset \(offset)")
//                        scrollOffset = offset
//                    }
//                    .store(in: &subscriptions)
//
//                let cancellable2 = subject2
//                    .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
//                    .sink { height in
//                        contentHeight = height
//                        print("height >> \(height)")
//                    }
//                    .store(in: &subscriptions)
            }
            .safeAreaInset(edge: .top) {
                VStack(alignment: .center) {
                    Text("Items: \(items.count)\nScroll offset: \(scrollOffset)\nAnchor offset: \(anchorOffset)\nContent height: \(contentHeight)\nScroll-Anchor diff:\(anchorOffset - scrollOffset)")
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
                    ControlGroup {
                        Text("\(unreadCount)")
                        
                        Button { importNotes() } label: { Text("Import") }
                        Button { fetchEventsFromFollowing(amount:500) } label: { Text("Fetch & parse") }
                        
                    }
                    
                }.background(.regularMaterial)
            }
            .onAppear {
                unreadCount = getUnreadCount()
                if (events.first != nil) {
                    print("🤩🤩 onAppear, last read = \(d(lastReadDate).description)")
                    print("🤩🤩 onAppear, last first = \(d(events.first!.created_at).description)")
                    print("🤩🤩 onAppear, last event = \(d(events.last!.created_at).description)")
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

struct ReversedTimelineFRControllerView: View {
    
    @EnvironmentObject var ns:NosturState
    
    @FetchRequest
    var events:FetchedResults<Event>
    
    @Binding var showMenu:Bool
    
    init(followingPubkeys:[String], showReplies:Bool, showMenu:Binding<Bool>) {
        self._showMenu = showMenu
        let fr = NSFetchRequest<Event>(entityName: "Event")
        
        if (showReplies) {
            fr.predicate = NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId != nil", followingPubkeys)
        }
        else {
            fr.predicate = NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId == nil", followingPubkeys)
        }
        
        fr.fetchLimit = 30 // 5 = FAST TIMELINE TO DETAIL. 75 = SLOW
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        
        _events = FetchRequest(fetchRequest: fr)
    }
    
    var body: some View {
        if (ns.account != nil) {
            ReversedTimeline(events:events, account: ns.account!, showMenu: $showMenu)
        }
        else {
            Text("Please set up account first")
        }
        //        Spacer()
    }
    
}

extension ReversedTimeline {
    
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

struct ReversedTimeline_Previews: PreviewProvider {
    
    @State static var showMenu = true
    
    static var previews: some View {
        
        let pubkeys = ["1833ee04459feb2ca4ae690d5f31269ad488c69e5fe903a42b532c677c4a8170","84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240","3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24"]
        
        ReversedTimelineFRControllerView(followingPubkeys: pubkeys, showReplies:false, showMenu: $showMenu)
            .withPreviewEnvironment()
        
    }
}
