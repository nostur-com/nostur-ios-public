////
////  TheTimeline.swift
////  Nostur
////
////  Created by Fabian Lachman on 17/02/2023.
////
//import SwiftUI
//
//struct Timeline: View {
//    var body: some View {
//        let _ = Self._printChanges()
//        
//        ZStack {
//            
//            TimelineView()
//            
//            TimelineController()
//        }
//    }
//}
//
//struct TimelineController: View {
//    
//    @EnvironmentObject var ns:NosturState
//    
//    func updateTimeline() {
//        if (ns.account != nil) {
//            sendNotification(.activeAccountChanged, ns.account!)
//        }
//    }
//    
//    var body: some View {
//        let _ = Self._printChanges()
//        
//        VStack {
//            
//        }
//        .onChange(of: ns.account) { newAccount in
//            if (newAccount != nil) {
//                updateTimeline()
//            }
//        }
//        .onChange(of: ns.isOnboarding) { newValey in
//            if (ns.account != nil) {
//                updateTimeline()
//            }
//        }
//        .onAppear {
//            updateTimeline()
//        }
//    }
//}
//
//struct TimelineView: View {
//    
//    @Environment(\.managedObjectContext) var viewContext
//    
//    private let sp: SocketPool = .shared
//    private let ep: EventsProvider = .shared
//    private let mp: MessageParser = .shared
//    
//    @FetchRequest
//    var events: FetchedResults<Event>
//    
//    init() {
//        let fr = Event.fetchRequest()
//        fr.predicate = NSPredicate(value: false)
////        fr.fetchLimit = 125
//        fr.fetchBatchSize = 25
//        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
//        fr.includesPendingChanges = false
//        _events = FetchRequest(fetchRequest: fr)
//    }
//    
//    var eventsSorted:[Event] {
//        get { events.sorted(by: { $0.created_at < $1.created_at }) } // OLD = 0
//    } // 2. Make sure the sorting is always correct
//    
//    @State var lastNewNoteTimestamp:Int64 = 0
//    
////    @State var notesWithoutOlderNotes: [Event] = [] // 3. eventsSorted can have notes that are too old, they are filtered here
//    
////    @State var notes: [Event] = [] // 4. These are the notes on screen
////    @State var lastAddedNotes: [Event] = [] // 5. To fetch their replies/mentions/likes etc
//    @State private var unreadCount = 0
//    
//    @State var account:Account? = nil
//    
//    @State var didSetup = false
//    @State var isViewDisplayed = false
//    
//    @State var showingNewNote = false
//    @State var noteCancellationId:UUID?
//    
//    let timelineRunLoop = Timer.publish(every: 15, tolerance: 1, on: .main, in: .common).autoconnect()
//    @State var timesFetchedWhileUnread = 0 // Increases if there are unread messages (prevent unnecessary refresh)
//    @State var shouldSkipTimes = 0
//    @AppStorage("devToggle") var devToggle = false
//    
//    var body: some View {
//        let _ = Self._printChanges()
//
//        ZStack {
//            NotesList()
//            UnreadCounter()
////            UnreadCounter(count:unreadCount, notes: notes)
//            NewNoteButton(showingNewNote: $showingNewNote)
//        }
//        .sheet(isPresented: $showingNewNote) {
//            NewNote(noteCancellationId: $noteCancellationId)
//        }
////        .onReceive(receiveNotification(.willDeleteAllEvents)) { _ in
////            notes = []
////            notesWithoutOlderNotes = []
////        }
//        .onReceive(receiveNotification(.activeAccountChanged)) { notification in
//            guard notification.object as? Account != self.account else { return }
//            account = notification.object as? Account
//            let pubkeys = (notification.object as! Account).follows?.map { $0.pubkey } ?? []
//            events.nsPredicate = NSPredicate(format: "kind IN {1,6} AND pubkey IN %@", pubkeys)
//            //TODO: SHould re-add blocklist in predicate
//        }
//        .onAppear { isViewDisplayed = true }
//        .onDisappear { isViewDisplayed = false }
////        .onReceive(timelineRunLoop) { time in
////
////            if (!isViewDisplayed) {
////                return
////            }
////
////            print("unread is: \(unreadCount) timesFetchedWhileUnread: \(timesFetchedWhileUnread) shouldSkipTimes: \(shouldSkipTimes)")
////
////
////            if (unreadCount > 0 && shouldSkipTimes > 0) {
////                shouldSkipTimes = shouldSkipTimes - 1
////                return
////            }
////
////
////            if (!Importer.shared.isImporting) {
////                fetchEventsFromFollowing(amount: 500)
////            } else {
////                print("⏳ Still importing, new fetch skipped.")
////            }
////
////            if (unreadCount > 0) {
////                shouldSkipTimes = timesFetchedWhileUnread + shouldSkipTimes + 1
////                timesFetchedWhileUnread = timesFetchedWhileUnread + 1
////
////                if (shouldSkipTimes > 8) {
////                    shouldSkipTimes = 8
////                    timesFetchedWhileUnread = 0
////                    print("never skip more than 8 times")
////                }
////                else {
////                    print("increase delay!")
////                }
////
////            }
////            else {
//////                print("delay reset")
////                shouldSkipTimes = 0
////                timesFetchedWhileUnread = 0
////            }
//////            if (MessageParser.shared.lastTimelineEventTimestamp != nil) {
//////                print("last timeline event timestamp: \(d(MessageParser.shared.lastTimelineEventTimestamp!.timestamp).description)")
//////            }
//////            if (Importer.shared.lastTimelineEventTimestamp != nil) {
//////                print("last timeline event timestamp: \(d(Importer.shared.lastTimelineEventTimestamp!.timestamp).description)")
//////            }
////        }
////        .onAppear {
////            guard let lastEvent = eventsSorted.last else { return }
////
////            lastNewNoteTimestamp = lastEvent.created_at
////
////            sendNotification(.newNotesAvailable, eventsSorted)
////        }
//        .onChange(of: eventsSorted) { [eventsSorted] newEventsSorted in
//            guard let lastEvent = eventsSorted.last else {
//                print(".onChange(of: eventsSorted) - GUARD HIT")
//            // NO LAST EVENT (BEFORE), SO MUST BE THE FIRST SETTING OF eventsSorted
//                lastNewNoteTimestamp = newEventsSorted.last?.created_at ?? 0
//                sendNotification(.newNotesAvailable, Array(newEventsSorted.suffix(25))) //Only take the last 125!
//                return
//            }
//            print("eventsSorted.last.id == \(lastEvent.id)")
//            
//            let newIndexOfLastEvent = newEventsSorted.firstIndex(of: lastEvent)
//            guard newIndexOfLastEvent != nil else { return } // TODO: uuhh, apparently we totally wrong if this returns }
//            
//            let newNotes = newEventsSorted.drop(while: { $0 != lastEvent }).dropLast(1)
//                
////            let newNotes = newEventsSorted.dropFirst(eventsSorted.firstIndex(of: lastEvent)!+1)
//            
//            lastNewNoteTimestamp = newNotes.last?.created_at ?? 0
//            
//            sendNotification(.newNotesAvailable, Array(newNotes))
//            
////            notesWithoutOlderNotes = eventsSorted.filter {
////                // Only take notes newer than the last newest note on screen (+10 min wiggle room)
////                // Or also take notes that are already on screen
////                ($0.created_at > (lastNewNoteTimestamp - 600)) || eventsSorted.firstIndex(of: $0) != nil
////                // So don't take older notes, like 10-40 days older loaded from profile
////                // because FetchedResult does received those new notes but does not update correct sorting.
////            }
////            loadNewNotes()
////            fetchMissingReplyToContacts()
////            fetchStuffForLastAddedNotes()
//        }
////        .onAppear { if (!didSetup) { setupNotes() } }
//    }
//    
//    private func fetchEventsFromFollowing(amount:Int? = 500) {
//        if (account?.follows != nil) {
//            let pubkeys = account!.follows?.map { $0.pubkey } ?? []
//            if (eventsSorted.count < 20) {
//                print("💿💿 getFollowingEvents for \(pubkeys.count) pubkeys 💿💿")
//                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getFollowingEvents(pubkeys: Array(pubkeys), limit: amount!)))
//            }
//            else {
//                print("💿💿 getFollowingEvents for \(pubkeys.count) pubkeys, with since timestamp: \(d(mp.lastTimelineEventTimestamp).description) 💿💿")
//                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getFollowingEvents(pubkeys: Array(pubkeys), limit: amount!, since: mp.lastTimelineEventTimestamp)))
//            }
//            
//        }
//    }
//    
////    func eventAppeared(_ event:Event) {
////        guard let index = notes.firstIndex(of: event) else { return }
////        if (index < unreadCount) {
////            unreadCount = index
////        }
////    }
////
//    
////    func setupNotes() {
////        didSetup = true
////        notesWithoutOlderNotes = eventsSorted
////        for index in 0..<notesWithoutOlderNotes.count {
////            notes.append(notesWithoutOlderNotes[index])
////        }
////        sendNotification(.newNotesAvailable, notes)
////
////    }
////
////    func loadNewNotes() {
////        lastAddedNotes = []
////        unreadCount = unreadCount + (notesWithoutOlderNotes.count-notes.count)
////        if notesWithoutOlderNotes.count > notes.count && notes.count != 0 {
////            sendNotification(.timelineWillReceiveNewNotes, nil)
////        }
////
////        guard (notesWithoutOlderNotes.count > notes.count) else { return }
////        for index in 0..<(notesWithoutOlderNotes.count-notes.count) { // 0..<11
////            notes.append(notesWithoutOlderNotes[index])
////            lastAddedNotes.insert(notesWithoutOlderNotes[index], at: 0)
////        }
////        print("🟡🟡 loadNewNotes(), notes inserted in Timeline.notes")
////        sendNotification(.newNotesAvailable, lastAddedNotes)
////    }
//    
////    func fetchMissingReplyToContacts() {
////        // TODO: FIXEN
////        // TODO, bij importer, replyTo p in event.replyToPTag for speed up
////        let pubkeys = Array(Set(notes.compactMap { TagsHelpers($0.tags()).reactingToPubkey() }))
////        let contacts = Contact.fetchByPubkeys(pubkeys, context: viewContext)
////        let missingPubkeys = pubkeys.filter {
////            contacts.map { $0.pubkey }.firstIndex(of: $0) == nil
////        }
////        let emptyContactPubkeys = pubkeys
////            .compactMap { pubkey in
////                contacts.first(where: { $0.pubkey == pubkey })
////            }
////            .filter { $0.updated_at == 0 }
////            .map { $0.pubkey }
////
////        sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: missingPubkeys + emptyContactPubkeys )))
////    }
//    
////    func fetchStuffForLastAddedNotes() {
////        //TODO: Fixen
////        // Prepare #e filter
////        // Get all events that reference our event.id's on screen
////        // To update likes etc.
////
////        let eventIds = lastAddedNotes.map { $0.id }
////
////        sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEventReferences(ids: eventIds)))
////    }
//}
//
//struct ReRenderCheck: View {
//    @ObservedObject var event:Event
//    @EnvironmentObject var nav:NavigationModel
////    private let nav:NavigationModel = .shared
//    var body: some View {
//        VStack(alignment: .leading) {
//            NoteHeader(event: event, singleLine: true)
//            NoteTextRenderView(event: event)
//        }
//        .onTapGesture {
//            nav.navigateTo(NotePath(id: event.id))
//        }
////        Text("id: \(String(event.id.prefix(4))) \(event.username) \(event.noteText.prefix(20).description) \(d(event.created_at).description)")
//    }
//}
//
//extension TimelineView {
//
//    struct NotesList: View {
//        @EnvironmentObject var tm:TimelineModel
////        @State var notesOnScreen:[Event] = []
//        @State var appearedNoteIds:Set<String> = []
//        @Namespace var theBottom
////        @EnvironmentObject var ucm:UnreadCounterModel
//        private let ucm:UnreadCounterModel = .shared
//        
//        
//        var body: some View {
//            let _ = Self._printChanges()
//            ScrollViewReader { proxy in
//                List(tm.notesOnScreen) { note in
////                        NoteRowView(event: note)
//                    ReRenderCheck(event: note)
//                        .onAppear {
//                            guard let indexOfNote = tm.notesOnScreen.firstIndex(of: note) else { return }
//                            guard note.created_at > ucm.mostRecentCreatedAt else { return }
//                            ucm.mostRecentCreatedAt = note.created_at
//                            let newUnreadCount = tm.notesOnScreen.count - indexOfNote - 1
//                            if (newUnreadCount != ucm.unreadCount) {
//                                print("Setting ucm.unreadCount to: \(newUnreadCount)")
//                                ucm.unreadCount = tm.notesOnScreen.count - indexOfNote - 1
//                            }
//                        }
//                        .listRowInsets(EdgeInsets())
//                        .id(note.id)
//                }
//                .listStyle(.plain)
//                .onReceive(receiveNotification(.activeAccountChanged)) { notification in
//                    tm.notesOnScreen = []; appearedNoteIds.removeAll()
//                }
//                .onReceive(receiveNotification(.newNotesAvailable)) { notification in
//                    let newNotes = notification.object as! [Event]
//                    let beforeCount = tm.notesOnScreen.count
//                    tm.notesOnScreen.append(contentsOf: Set(newNotes).subtracting(Set(tm.notesOnScreen)))
//                    tm.notesOnScreen.sort(by: { $0.created_at < $1.created_at })
//                    let afterCount = tm.notesOnScreen.count
//                    if (beforeCount != afterCount) {
//                        ucm.unreadCount = ucm.unreadCount + (afterCount-beforeCount)
//                        print("Added \(afterCount-beforeCount) new notes.")
//                    }
//                }
//                .onReceive(receiveNotification(.blockListUpdated)) { notification in
//                    tm.notesOnScreen = tm.notesOnScreen.filter {
//                        !(notification.object as! Set<Contact>).map { $0.pubkey } .contains($0.pubkey)
//                    }
//                }
////                .onChange(of: notesOnScreen) { [notesOnScreen = notesOnScreen] newNotesOnScreen in
////                    if (notesOnScreen.count == 0 && newNotesOnScreen.count > 0) {
////                        // FIRST TIME PUTTING NOTES ON SCREEN. SCROLL TO END OR TO LAST SAVED STATE
////                        proxy.scrollTo(newNotesOnScreen.last!.id)
////                    }
////                }
////                .onReceive(receiveNotification(.shouldScrollToNote)) { notification in
////                    let noteId = notification.object as! String
////                    proxy.scrollTo(noteId, anchor: .bottom)
////                }
////                .onReceive(receiveNotification(.shouldScrollToNote)) { notification in
////                    let noteId = notification.object as! String
////                    proxy.scrollTo(noteId, anchor: .bottom)
////                }
//            }
//        }
//    }
//    
//    struct UnreadCounter: View {
//        @EnvironmentObject var ucm:UnreadCounterModel
//        
////        var notes:[Event]
//        var body: some View {
//            VStack {
//                Spacer()
//                HStack {
//                    Spacer()
//                    if (ucm.unreadCount > 0) {
//                        HStack {
//                            Image(systemName: "arrow.down")
//                            Text("\(ucm.unreadCount) unread")
//                            Image(systemName: "arrow.down")
//                        }
//                        .frame(minWidth: 30)
//                        .padding(10)
//                        .fontWeight(.bold)
//                        .foregroundColor(.white)
//                        .background(.blue)
//                        .opacity(0.95)
//                        .cornerRadius(20)
//                        .onTapGesture {
////                            if let noteId = notes.dropLast(count).last?.id {
////                                sendNotification(.shouldScrollToNote, noteId)
////                            }
//                        }
//                    }
//                    Spacer()
//                }
//            }
//        }
//    }
//}
//
//
//
//struct TheTimeline_Previews: PreviewProvider {
//    static var previews: some View {
//        VStack {
//            Timeline()
//        }
//        .withPreviewEnvironment()
//    }
//}
