//
//  TheTimeline.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/02/2023.
//

import SwiftUI
import Introspect

struct TheTimeline: View {
    
    var body: some View {
        let _ = Self._printChanges()
        
        TimelineController()
        
        TimelineView()
        
    }
}

struct TimelineController: View {
    
    @EnvironmentObject var ns:NosturState
    
    func updateTimeline() {
        if (ns.account != nil) {
            sendNotification(.activeAccountChanged, ns.account!)
        }
    }
    
    var body: some View {
        let _ = Self._printChanges()
        
        VStack {
//            Text("Followers: \(ns.account?.follows?.count ?? 0)")
        }
        .onChange(of: ns.account) { newAccount in
            if (newAccount != nil) {
                updateTimeline()
            }
        }
        .onChange(of: ns.isOnboarding) { newValey in
            if (ns.account != nil) {
                updateTimeline()
            }
        }
        .onAppear {
            updateTimeline()
        }
    }
}

struct TimelineView: View {
    
    var sp: SocketPool = .shared
    var ep: EventsProvider = .shared
    var mp: MessageParser = .shared
    
    @FetchRequest
    var events: FetchedResults<Event>
    
    init() {
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(value: false)
        fr.fetchLimit = 125
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _events = FetchRequest(fetchRequest: fr)
    }
    
    var eventsSorted:[Event] {
        get { events.sorted(by: { $0.created_at < $1.created_at }) }
    } // 2. Make sure the sorting is always correct
    
    var lastNewNoteTimestamp:Int64 {
        get { notes.first?.created_at ?? Int64(Date().timeIntervalSince1970) }
    }
    
    @State var notesWithoutOlderNotes: [Event] = [] // 3. eventsSorted can have notes that are too old, they are filtered here
    
    @State var notes: [Event] = [] // 4. These are the notes on screen
    
    @State var unreadCount = 0
    
    @State var account:Account? = nil
    
    @State var didSetup = false
    @State var isViewDisplayed = false
    
    @State var showingNewNote = false
    @State var noteCancellationId:UUID?
    
    let timelineRunLoop = Timer.publish(every: 15, tolerance: 1, on: .main, in: .common).autoconnect()
    @State var timesFetchedWhileUnread = 0 // Increases if there are unread messages (prevent unnecessary refresh)
    @State var shouldSkipTimes = 0
    
    var body: some View {
        let _ = Self._printChanges()

        ZStack {
            NotesList(notes: $notes, eventAppeared: self.eventAppeared)
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Text("$E:\(events.count) E:\(notesWithoutOlderNotes.count) N:\(notes.count)")
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
            UnreadCounter(count:unreadCount)
            NewNoteButton(showingNewNote: $showingNewNote)
        }
        .sheet(isPresented: $showingNewNote) {
            NewNote(noteCancellationId: $noteCancellationId)
        }
        .onReceive(receiveNotification(.willDeleteAllEvents)) { _ in
            notes = []
            notesWithoutOlderNotes = []
        }
        .onReceive(receiveNotification(.activeAccountChanged)) { notification in
            guard notification.object as? Account != self.account else { return }
            
            notes = []
            notesWithoutOlderNotes = []
            
            account = notification.object as? Account
            let pubkeys = (notification.object as! Account).follows?.map { $0.pubkey! } ?? []
            events.nsPredicate = NSPredicate(format: "kind IN {1,6} AND pubkey IN %@", pubkeys)
        }
        .onAppear { isViewDisplayed = true }
        .onDisappear { isViewDisplayed = false }
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
        .onChange(of: eventsSorted) { newValue in
            print(".onChange(of: events.first) { _ in")
            
            if (notes.count == 0) {
                notes = newValue.reversed()
                notesWithoutOlderNotes = notes
                return
            }
            
            notesWithoutOlderNotes = eventsSorted.filter {
                // Only take notes newer than the last newest note on screen (+10 min wiggle room)
                // Or also take notes that are already on screen
                ($0.created_at > (lastNewNoteTimestamp - 600)) || notes.firstIndex(of: $0) != nil
                // So don't take older notes, like 10-40 days older loaded from profile
                // because FetchedResult does received those new notes but does not update correct sorting.
            }
            loadNewNotes()
        }
        .onReceive(receiveNotification(.blockListUpdated)) { notification in
            notes = notes.filter {
                !(notification.object as! Set<Contact>).map { $0.pubkey! } .contains($0.pubkey!)
            }
        }
        .onAppear { if (!didSetup) { setupNotes() } }
    }
    
    private func fetchEventsFromFollowing(amount:Int? = 500) {
        //        print("💿💿 1. S:\(vm.scrollOffset) A:\(vm.anchorOffset) H:\(vm.contentHeight) - BEFORE FETCH events.count: \(events.count)")
        
        if (account?.follows != nil) {
            let pubkeys = account!.follows?.map { $0.pubkey! } ?? []
            if (notes.count < 20) {
                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getFollowingEvents(pubkeys: Array(pubkeys), limit: amount!)))
            }
            else {
                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getFollowingEvents(pubkeys: Array(pubkeys), limit: amount!, since: mp.lastTimelineEventTimestamp)))
            }
            
        }
    }
    
    func eventAppeared(_ index:Int) {
        if (index < unreadCount) {
            unreadCount = index
        }
    }
    
    func setupNotes() {
        didSetup = true
        notesWithoutOlderNotes = eventsSorted
        for index in 0..<notesWithoutOlderNotes.count {
            notes.insert(notesWithoutOlderNotes[index], at:0)
        }
    }
    
    func loadNewNotes() {
        
        unreadCount = unreadCount + (notesWithoutOlderNotes.count-notes.count)
        if notesWithoutOlderNotes.count > notes.count && notes.count != 0 {
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

extension TimelineView {
    struct NotesList: View, Equatable {
        static func == (lhs: TimelineView.NotesList, rhs: TimelineView.NotesList) -> Bool {
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
                config.showsSeparators = true
                
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
                                .foregroundColor(Color(.white))
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

struct TheTimeline_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            TheTimeline()
        }
        .withPreviewEnvironment()
    }
}
