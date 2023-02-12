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
    @State var watchForHeightChange = false
    @State var showingNewNote = false
    @State var noteCancellationId:UUID?
    
    @EnvironmentObject var ns:NosturState
    
    @FetchRequest(
        entity: Event.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
        predicate: NSPredicate(format: "FALSEPREDICATE")
    )
    var events: FetchedResults<Event> // 1. When new events enter DB, this one gets out of sync, wrong sorting.
    
    var eventsSorted:[Event] {
        get {
            events.sorted(by: { $0.created_at < $1.created_at })
        }
    } // 2. Make sure the sorting is always correct
    var lastNewNoteTimestamp:Int64 {
        get {
            notes.first?.created_at ?? Int64(Date().timeIntervalSince1970)
        }
    }
    
    @State var notesWithoutOlderNotes: [Event] = [] // 3. eventsSorted can have notes that are too old, they are filtered here
    
    @State var notes: [Event] = [] // 4. These are the notes on screen
    @Binding var followingPubkeys:Set<String>
    var showReplies:Bool
    
    init(showReplies:Bool, followingPubkeys: Binding<Set<String>>, account:Account) {
//        UIScrollView.appearance().bounces = false
        self.showReplies = showReplies
        self.account = account
        self._followingPubkeys = followingPubkeys
        
        let fr = NSFetchRequest<Event>(entityName: "Event")
        if (account.blockedContacts == nil) {
            fr.predicate = showReplies
            ? NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId != nil", followingPubkeys.wrappedValue)
            : NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId == nil", followingPubkeys.wrappedValue)
        } else {
            fr.predicate = showReplies
            ? NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId != nil AND NOT contact IN %@", followingPubkeys.wrappedValue, account.blockedContacts!)
            : NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId == nil AND NOT contact IN %@", followingPubkeys.wrappedValue, account.blockedContacts!)
        }
        
        fr.fetchLimit = 125 // 5 = FAST TIMELINE TO DETAIL. 75 = SLOW (MET VSTACK).
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        
        _events = FetchRequest(fetchRequest: fr)
    }
    
    func eventAppeared(_ index:Int) {
        if (index < unreadCount) {
            unreadCount = index
        }
    }
    
    var body: some View {
        let _ = Self._printChanges()
        ZStack {
            NotesList(notes: $notes, eventAppeared: self.eventAppeared)
                .onAppear { if (!didSetup) { setupNotes() } }
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Text("E:\(notesWithoutOlderNotes.count) N:\(notes.count)")
                        Spacer()
                        Button { fetchEventsFromFollowing(amount:500) } label: { Text("Fetch") }
                        Button {
                            //                            var transaction = Transaction(animation: .none)
                            //                            transaction.disablesAnimations = true
                            //                            withTransaction(transaction) {
                            //                                loadNewNotes()
                            //                            }
                            
                            //                            CATransaction.begin()
                            //                            UIView.setAnimationsEnabled(false)
                            loadNewNotes()
                            //                            CATransaction.commit()
                        } label: { Text("Load (\(notesWithoutOlderNotes.count - notes.count))") }
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
                .onChange(of: eventsSorted) { _ in
                    notesWithoutOlderNotes = eventsSorted.filter {
                        // Only take notes newer than the last newest note on screen (+10 min wiggle room)
                        // Or also take notes that are already on screen
                        ($0.created_at > (lastNewNoteTimestamp - 600)) || notes.firstIndex(of: $0) != nil
                        // So don't take older notes, like 10-40 days older loaded from profile
                        // because FetchedResult does received those new notes but does not update correct sorting.
                    }
                }
            
            UnreadCounter(count:unreadCount)
            
            NewNoteButton(showingNewNote: $showingNewNote)
        }
        .sheet(isPresented: $showingNewNote) {
            NewNote(noteCancellationId: $noteCancellationId)
        }
        .onChange(of: followingPubkeys) { newPubkeys in
            notes = []
            if (account.blockedContacts == nil) {
                events.nsPredicate = showReplies
                ? NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId != nil", newPubkeys)
                : NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId == nil", newPubkeys)
            } else {
                events.nsPredicate = showReplies
                ? NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId != nil AND NOT contact IN %@", newPubkeys, account.blockedContacts!)
                : NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId == nil AND NOT contact IN %@", newPubkeys, account.blockedContacts!)
            }
        }
    }
}

extension Timeline {
    struct NotesList: View, Equatable {
        static func == (lhs: Timeline.NotesList, rhs: Timeline.NotesList) -> Bool {
            return lhs.notes == rhs.notes && lhs.watchForHeightChange == rhs.watchForHeightChange
        }
        
        @Binding var notes:[Event]
        @State var watchForHeightChange = false
        
        @State private var scroller: UIScrollView?
        @State var oldContentHeight = 0.0
        @State var oldOffset = 0.0
        
        var eventAppeared:(Int) -> Void
        
        var body: some View {
            let _ = Self._printChanges()
            List(notes.indices, id:\.self) { index in
                //                    Text("index:\(notes[index].noteId)\n\(d(notes[index].created_at).description)").background(randomColor(seed: notes[index].noteId).frame(width:300,height:100)).frame(width: 300, height: 100)
                NoteRowView(event: notes[index])
                    .id(notes[index].noteId)
                    .onAppear {
                        guard !watchForHeightChange else { return }
                        self.eventAppeared(index)
                    }
                    .listRowInsets(EdgeInsets())
            }
            .didChangeHeight { contentHeight in
                guard (contentHeight != oldContentHeight) else { return }
                guard (watchForHeightChange) else { return }
                guard (scroller != nil) else { return }
                scroller!.contentOffset.y = oldOffset + (contentHeight - oldContentHeight)
                watchForHeightChange = false
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
            .onReceive(receiveNotification(.timelineWillReceiveNewNotes)) { _ in
                guard scroller != nil else { return }
                watchForHeightChange = true
                oldOffset = scroller!.contentOffset.y
                oldContentHeight = scroller!.contentSize.height
            }
        }
        
        
    }
    
    struct NewNoteButton: View {
        @EnvironmentObject var nav:NavigationModel
        @Binding var showingNewNote:Bool
        
        var body: some View {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        showingNewNote = true
                    } label: {
                        ZStack {
                            Circle() // Transparent plug.circle looks weird - so make white here
                                .foregroundColor(Color(.systemBackground))
                                .frame(width: 45, height: 45)
                                .padding(30)
                            Image(systemName: "plus.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 45, height: 45)
                                .padding(30)
                        }
                    }
                }
//                .offset(x:-30,y:-55)
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
}

// MARK: PAGINATION
extension Timeline {
    
    func setupNotes() {
        didSetup = true
        notesWithoutOlderNotes = eventsSorted
        for index in 0..<notesWithoutOlderNotes.count {
            notes.insert(notesWithoutOlderNotes[index], at:0)
        }
    }
    
    func loadNewNotes() {
        
        unreadCount = unreadCount + (notesWithoutOlderNotes.count-notes.count)
        if notesWithoutOlderNotes.count > notes.count {
            sendNotification(.timelineWillReceiveNewNotes, nil)
        }
        
        let oldestAtIndexZero = notesWithoutOlderNotes
            .sorted { $0.created_at > $1.created_at }
            .sorted { a, b in
                return notes.firstIndex(of: a) == nil // Move new notes not already on screen, but older created_at, to front
            }
        guard (oldestAtIndexZero.count > notes.count) else { return }
        for index in 0..<(oldestAtIndexZero.count-notes.count) { // 0..<11
            notes.insert(oldestAtIndexZero[index], at:0)
        }
        print("🟡🟡 loadNewNotes(), notes inserted in Timeline.notes")
        //        oldestAtIndexZero.forEach { event in
        //            print("\(event.id!) \(d(event.created_at))")
        //        }
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
    
    @State static var pubkeys = Set(["1833ee04459feb2ca4ae690d5f31269ad488c69e5fe903a42b532c677c4a8170","84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240","3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24"])
    
    static var previews: some View {
        
        let account = PreviewFetcher.fetchAccount("5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0", context: EventsProvider.preview.container.viewContext)
        
        
        
            Timeline(showReplies: true, followingPubkeys: $pubkeys, account: account!)
                .withPreviewEnvironment()
        
    }
}
