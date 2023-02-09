//
//  ReversedTimeline.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/02/2023.
//

import SwiftUI
import CoreData
import Combine
import Introspect

struct Timeline: View {
///////;o/[-'9
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
    @State var notes: [Event] = []
    @State private var scroller: UIScrollView?
    @State var contentHeight = 0.0
    @State var oldContentHeight = 0.0
    @State var pendingHeightChange = false
    @State var offset = 0.0
    @State var oldOffset = 0.0
    
    init(showReplies:Bool, showMenu:Binding<Bool>, followingPubkeys: Set<String>, account:Account) {
        UIScrollView.appearance().bounces = false
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
        
        fr.fetchLimit = 25 // 5 = FAST TIMELINE TO DETAIL. 75 = SLOW (MET VSTACK).
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        
        _events = FetchRequest(fetchRequest: fr)
    }
    
    func eventAppeared(_ index:Int) {
        if index < unreadCount {
            unreadCount = index
        }
//        print("eventAppeared:\(index), lastReadIndex: \(lastReadIndex) notes.count: \(notes.count)")
//        unreadCount = notes.count - (lastReadIndex+1)
    }
    
    var body: some View {
        VStack {
            HStack {
                Color.clear.frame(width: 200, height: 30)
            }
            ZStack {
                List(notes.indices, id:\.self) { index in
//                    Text("index:\(notes[index].noteId)\n\(d(notes[index].created_at).description)").background(randomColor(seed: notes[index].noteId).frame(width:300,height:100)).frame(width: 300, height: 100)
                    NoteRowView(event: notes[index])
                        .id(notes[index].noteId)
                        .onAppear {
                            eventAppeared(index)
                        }
                        .listRowInsets(EdgeInsets())
                }
                .didChangeHeight { contentHeight in
                    if (scroller != nil) {
                        print(contentHeight)
                        offset = scroller!.contentOffset.y
                        self.contentHeight = contentHeight
                        if (pendingHeightChange) {
                            if (scroller != nil) {
                                //                        scroller!.layoutIfNeeded()
                                UIView.setAnimationsEnabled(true)
                                scroller!.contentOffset.y = oldOffset + (contentHeight - oldContentHeight)
                                pendingHeightChange = false
                                oldContentHeight = contentHeight
                            }
                        }
                    }
                }
                .listStyle(.plain)
                
                /* in iOS 16 List is backed by UICollectionView, no out of the box .introspectMethod ... nbd. */
                .introspect(selector: TargetViewSelector.ancestorOrSiblingContaining, customize: { (collectionView: UICollectionView) in
                    guard #available(iOS 16, *) else { return }
                    self.scroller = collectionView
                    var config = UICollectionLayoutListConfiguration(appearance: .plain)
                    config.showsSeparators = false
                    
                    let layout = UICollectionViewCompositionalLayout.list(using: config)
                    
                    collectionView.collectionViewLayout = layout
                })
                
                /* in iOS 15 List is backed by UITableView ... */
                .introspectTableView(customize: { tableView in
                    guard #available(iOS 15, *) else { return }
                    self.scroller = tableView
                })
                
                .onAppear { if (!didSetup) { setupNotes() } }
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Text("E:\(events.count) N:\(notes.count)")
                        Spacer()
                        Button { fetchEventsFromFollowing(amount:500) } label: { Text("Fetch") }
                        Button {
//                            var transaction = Transaction(animation: .none)
//                            transaction.disablesAnimations = true
//                            withTransaction(transaction) {
//                                loadNewNotes()
//                            }
                            
//                            CATransaction.begin()
                            UIView.setAnimationsEnabled(false)
                            loadNewNotes()
//                            CATransaction.commit()
                        } label: { Text("Load (\(events.count - notes.count))") }
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
            notes.insert(oldestAtIndexZero[index], at:0)
        }
        
        oldestAtIndexZero.forEach { event in
            print("\(event.id!) \(d(event.created_at))")
        }
    }
    
    func loadNewNotes() {
        oldOffset = scroller!.contentOffset.y
        offset = scroller!.contentOffset.y
        oldContentHeight = contentHeight
        pendingHeightChange = true
        
        unreadCount = unreadCount + (events.count-notes.count)
        let oldestAtIndexZero = events.sorted(by: { $0.created_at < $1.created_at })
            .sorted { a, b in
                return notes.firstIndex(of: a) == nil // Move new notes not already on screen, but older created_at, to front
            }
        for index in 0..<(events.count-notes.count) { // 0..<11
//            if (index < beforeEventsCount) { continue }
            //            notes.insert(oldestAtIndexZero[index],at:0)
            notes.insert(oldestAtIndexZero[index], at:0)
            
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
