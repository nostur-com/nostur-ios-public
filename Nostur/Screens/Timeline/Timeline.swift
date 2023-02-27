//
//  Timeline.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/02/2023.
//

import SwiftUI
import CoreData

struct Timeline: View { /// 5.907 events in one view!, butter smooth scrolling is possible!
    ///
    @AppStorage("firstTimeCompleted") var firstTimeCompleted = false
    @EnvironmentObject var ds:TimelineModel
    let ot:OnboardingTracker = .shared
    @Environment(\.managedObjectContext) var viewContext
    let pubkey:String
    let pubkeys:Set<String>
    @FetchRequest
    var events: FetchedResults<Event>
    
    var eventsSorted:[Event] {
        events.sorted(by: { $0.created_at < $1.created_at }) // OLDEST INDEX = 0
    }
    
    let timelineRunLoop = Timer.publish(every: 15, tolerance: 1, on: .main, in: .common).autoconnect()
    
    @State var selectedEvent:Event?
    @State private var oldEvents: [Event] = []
    @State var isViewDisplayed = false
    @State var didRestore = false
//    @State var isScrolling = false
    
    let FETCH_LIMIT = 120
    
    init(pubkey:String, pubkeys:Set<String>, context:NSManagedObjectContext) {
        print("🧨🧨🧨🧨🧨 I INIT AGAIN 🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨")
        self.pubkey = pubkey
        self.pubkeys = pubkeys
        
        let r1 = Event.fetchRequest()
        r1.predicate = NSPredicate(format: "kind IN {1,6} AND pubkey IN %@", pubkeys)
        r1.fetchLimit = FETCH_LIMIT
        r1.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        
        // OLDEST IS EITHER 8 HOURS AGO MAX. OR HITTING THE 125 FETCH LIMIT.
        let oldestCreatedAt = (try? context.fetch(r1).last?.created_at) ?? Int64(Date.now.addingTimeInterval(-(28800)).timeIntervalSince1970)
        
        
        let r2 = Event.fetchRequest()
        r2.predicate = NSPredicate(format: "created_at >= %i AND kind IN {1,6} AND pubkey IN %@", oldestCreatedAt, pubkeys)
        r2.fetchLimit = FETCH_LIMIT
        r2.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _events = FetchRequest(fetchRequest: r2)
    }
    
    var body: some View {
        let _ = Self._printChanges()
        VStack {
            ZStack {
                ScrollViewReader { proxy in
                    List {
                        ForEach(eventsSorted) { event in
                            NoteRowView(event:event)
                                .id(event.id)
                                .listRowInsets(EdgeInsets())
                                .onTapGesture {
                                    selectedEvent = event
                                }
                                .onAppear {
                                    ds.eventAppeared.send(event)
                                }
                        }
                    }
                    .onAppear {
                        guard ds.didRestoreScrollPosition == false else { return }
                        if let id = UserDefaults.standard.string(forKey: "restoreScrollToId") {
                            ds.didRestoreScrollPosition = true
                            withAnimation(.none) {
                                print("AppStorage SCROLLING: \(id)")
                                proxy.scrollTo(id, anchor: .bottom)
                            }
                        }
//                        if (!ds.didRestore && ds.selectedItemId != nil) {
//                            withAnimation(.none) {
//                                print("AppStorage SCROLLING: \(ds.selectedItemId ?? "")")
//                                proxy.scrollTo(ds.selectedItemId!, anchor: .bottom)
//                            }
//                        }
//                        ds.didRestore = true
                    }
                    .onReceive(receiveNotification(.shouldScrollToUnreadNote)) { _ in
//                        if (ds.mostRecentEvent != nil) && (eventsSorted.firstIndex(of: ds.mostRecentEvent!) != nil) {
//                            withAnimation {
//                                proxy.scrollTo(ds.mostRecentEvent!.id, anchor: .bottom)
//                            }
//                        }
//                        else {
//                            if (events.last != nil) {
//                                withAnimation {
//                                    proxy.scrollTo(events.last!.id, anchor: .bottom)
//                                }
//                            }
//                        }
                    }
                }
                .listStyle(.plain)
//                .toolbar(content: toolbarContent)
            }
            EmptyView()
        }
        .onAppear {
            //            print("🟣🟣🟣 APPEAR: oldEvents: \(oldEvents.count) events: \(events.count)")
            isViewDisplayed = true
            ds.notesChanged.send(eventsSorted)
        
            if (ot.isOnboarding && pubkey == ot.pubkey && ot.didFetchKind3 && !ot.didFillTimeline) {
                fetchEvents(pubkeys: Set(ot.followingKeys), amount: 50)
                ot.didFillTimeline = true
                firstTimeCompleted = true
            }
        }
        .onDisappear {
            isViewDisplayed = false
        }
        .onChange(of: eventsSorted) { [eventsSorted] newEventsSorted in
            guard eventsSorted.last != nil else { return }
            
            let newIndexOfLastEvent = newEventsSorted.firstIndex(of: eventsSorted.last!)
            guard newIndexOfLastEvent != nil else { return } // TODO: uuhh, apparently we totally wrong if this returns }
            
            let newNotes = newEventsSorted.suffix(from: newIndexOfLastEvent! + 1)
            
            print("🟣🟣🟣 CHANGE: events: \(events.count) newNotes: \(newNotes.count)")
            ds.notesChanged.send(newEventsSorted)
            fetchStuffForLastAddedNotes(ids: ids(newNotes))
        }
        .onReceive(receiveNotification(.requestForJustAppeared)) { notification in
//            guard 1 == 2 else { return } // Performance test
//            guard !isScrolling else { return }
            let events = notification.object as! [Event]
            
            let ids = ids(events)
            let contacts = events.compactMap { $0.contact }
            let shouldVerifyContacts = contacts.filter { NIP05.shouldVerify($0) }
//            Task.detached(priority: .userInitiated) {
            Task {
                ThreadWarning.which(".onReceive(receiveNotification(.requestForJustAppeared)")
                fetchStuffForLastAddedNotes(ids: ids)
                fetchMissingReplyToContacts(events: events)
                NIP05.verifyBatch(contacts: shouldVerifyContacts, context: viewContext)
            }
        }
        .onReceive(timelineRunLoop) { time in
//            guard 1 == 2 else { return } // Performance test
//            guard !isScrolling else { return }
            guard isViewDisplayed else { return }
            guard !Importer.shared.isImporting else { print("⏳ Still importing, new fetch skipped."); return }
            
            if (ot.isOnboarding && pubkey == ot.pubkey && ot.didFetchKind3 && !ot.didFillTimeline) {
                fetchEvents(pubkeys: Set(ot.followingKeys), amount: 50)
                ot.didFillTimeline = true
                firstTimeCompleted = true
            }
            else if (!ot.isOnboarding) {
                let hoursAgo = Int64(Date.now.addingTimeInterval(-(28800)).timeIntervalSince1970)  // 8 hours day ago
                if (eventsSorted.count == 0) {
                    fetchEvents(pubkeys: pubkeys, since: hoursAgo)
                }
                else {
                    
                    // Start from first event, but not more than 8 hours ago...
                    // Else it will load 1000 posts on timeline and Core data has some bug with fetchlimit
                    let firstEventCreatedAt = eventsSorted.first!.created_at
                    fetchEvents(pubkeys: pubkeys, since: firstEventCreatedAt < hoursAgo ? hoursAgo : firstEventCreatedAt)
                }
            }
            
        }
        .onReceive(receiveNotification(.blockListUpdated)) { notification in
//            tm.notesOnScreen = tm.notesOnScreen.filter {
//                !(notification.object as! Set<Contact>).map { $0.pubkey } .contains($0.pubkey)
//            }
        }
    }
}

extension Timeline {
    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            HStack {
                Text("\(events.count) posts")
                    .foregroundStyle(Color.secondary)
                    .font(.caption)
                Button { fetchEvents(pubkeys: pubkeys) } label: { Text("FETCH") }
                Button { fetchStuffForLastAddedNotes(ids: ids(eventsSorted)) } label: { Text("REFS") }
                Button { fetchMissingReplyToContacts(events: eventsSorted) } label: { Text("FETCH Ps") }
                Spacer()
            }
        }
    }
    
    func fetchMissingReplyToContacts(events:[Event]) {
        // PLAN
        // FOR EVERY EVENT
        //   TAKE P's. IF P IS NOT IN EVENT.CONTACTS, ADD IT
        // FINALLY, EVERY MISSING OR EMPTY CONTACT
        //  sp.fetch!
        
        for event in events {
            let pubkeys = Array(Set(event.pTags()))
            if pubkeys.count > 0 {
                let contacts = Contact.fetchByPubkeys(pubkeys, context:viewContext)
//                event.objectWillChange.send()
                // dit moet op main queue?
//                ThreadWarning.which("Event.addToContacts( 💖💖💖")
                event.addToContacts(NSSet(array: contacts))
            }
        }
        // TODO: FIXEN
        // TODO, bij importer, replyTo p in event.replyToPTag for speed up
        let pubkeys = Array(Set(events.flatMap { TagsHelpers($0.tags()).pTags().map{ $0.pubkey } }))
        let contacts = Contact.fetchByPubkeys(pubkeys, context: viewContext)
        let missingPubkeys = pubkeys.filter {
            contacts.map { $0.pubkey }.firstIndex(of: $0) == nil
        }
        let emptyContactPubkeys = pubkeys
            .compactMap { pubkey in
                contacts.first(where: { $0.pubkey == pubkey })
            }
            .filter { $0.updated_at == 0 }
            .map { $0.pubkey }
        
        guard (missingPubkeys + emptyContactPubkeys).count > 0 else { return }
//        ThreadWarning.which("SocketPool.shared.sendMessag 💖💖💖")
        SocketPool.shared.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: missingPubkeys + emptyContactPubkeys )))
    
    }
}

struct Timeline_Previews: PreviewProvider {
    static var previews: some View {
        FollowingContainer()
            .withPreviewEnvironment()
    }
}
