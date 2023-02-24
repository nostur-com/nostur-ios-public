//
//  TL3.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/02/2023.
//
import SwiftUI
import CoreData
import Combine

struct TimelineContainer: View {
    @EnvironmentObject var ns:NosturState
    @Environment(\.managedObjectContext) var viewContext
    @State var showingNewNote = false
    @State var noteCancellationId:UUID?

    
    var body: some View {
        let _ = print("👍👍 \(ns.followingPublicKeys)")
        let _ = Self._printChanges()
        ZStack {
            if UIDevice.current.userInterfaceIdiom == .pad {
                Timeline(pubkeys: ns.followingPublicKeys, context: viewContext)
            }
            else {
                Timeline(pubkeys: ns.followingPublicKeys, context: viewContext)
            }
            NewNoteButton(showingNewNote: $showingNewNote)
        }
        .sheet(isPresented: $showingNewNote) {
            NewNote(noteCancellationId: $noteCancellationId)
        }
//        .onReceive(ns.$followingPublicKeys) { (p) in
//            print("👍👍👍👍")
//            print(p)
//            print("👍👍👍👍")
//        }
    }
}

struct Timeline: View { /// 5.907 events in one view!, butter smooth scrolling is possible!
    let ds:DataStore = .shared
    @Environment(\.managedObjectContext) var viewContext
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
    
    let FETCH_LIMIT = 120
    
    init(pubkeys:Set<String>, context:NSManagedObjectContext) {
        print("🧨🧨🧨🧨🧨 I INIT AGAIN 🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨")
        self.pubkeys = pubkeys
        let r1 = Event.fetchRequest()
        r1.predicate = NSPredicate(format: "kind IN {1,6} AND pubkey IN %@", pubkeys)
        r1.fetchLimit = FETCH_LIMIT
        r1.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        let oldestCreatedAt = (try? context.fetch(r1).last?.created_at) ?? 0
        
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
                                .id(event.id!)
                                .listRowInsets(EdgeInsets())
                                .onTapGesture {
                                    selectedEvent = event
                                }
                                .onAppear {
                                    //                                    print("onAppear: \(d(event.created_at).description)")
                                    Task.detached(priority: .userInitiated) {
                                        await ds.markAsRead.send(event)
                                    }
                                }
                        }
                    }
                    .onAppear {
                        if (!ds.didRestore && ds.selectedItemId != nil) {
                            withAnimation(.none) {
                                print("AppStorage SCROLLING: \(ds.selectedItemId ?? "")")
                                proxy.scrollTo(ds.selectedItemId!, anchor: .bottom)
                            }
                        }
                        ds.didRestore = true
                    }
                    .onReceive(receiveNotification(.shouldScrollToUnreadNote)) { _ in
                        if (ds.mostRecentReadEvent != nil) && (eventsSorted.firstIndex(of: ds.mostRecentReadEvent!) != nil) {
                            withAnimation {
                                proxy.scrollTo(ds.mostRecentReadEvent!.id!, anchor: .bottom)
                            }
                        }
                        else {
                            if (events.last != nil) {
                                withAnimation {
                                    proxy.scrollTo(events.last!.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
//                .toolbar(content: toolbarContent)
                .safeAreaInset(edge: .top) {
                    AppTopBar()
                        .padding(5)
                        .background(Color("BackgroundColor").opacity(0.9))
                }
                UnreadCounter()
            }
            EmptyView()
        }
        .onAppear {
            //            print("🟣🟣🟣 APPEAR: oldEvents: \(oldEvents.count) events: \(events.count)")
            isViewDisplayed = true
            ds.notesChanged.send(eventsSorted)
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
            let events = notification.object as! [Event]
            fetchStuffForLastAddedNotes(ids: ids(events))
            fetchMissingReplyToContacts(events: events)
            NIP05.verifyBatch(contacts: events.compactMap { $0.contact }, context: viewContext)
        }
        .onReceive(timelineRunLoop) { time in
            guard isViewDisplayed else { return }
            guard !Importer.shared.isImporting else { print("⏳ Still importing, new fetch skipped."); return }
            fetchEvents(pubkeys: pubkeys, amount: events.count == 0 ? 50 : 500)
        }
        .onReceive(receiveNotification(.blockListUpdated)) { notification in
//            tm.notesOnScreen = tm.notesOnScreen.filter {
//                !(notification.object as! Set<Contact>).map { $0.pubkey! } .contains($0.pubkey!)
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
        
        for event in events {
            let pubkeys = Array(Set(event.pTags()))
            if pubkeys.count > 0 {
                let contacts = Contact.fetchByPubkeys(pubkeys, context:viewContext)
//                event.objectWillChange.send()
                event.addToContacts(NSSet(array: contacts))
            }
        }
        // TODO: FIXEN
        // TODO, bij importer, replyTo p in event.replyToPTag for speed up
        let pubkeys = Array(Set(events.flatMap { TagsHelpers($0.tags()).pTags().map{ $0.pubkey } }))
        let contacts = Contact.fetchByPubkeys(pubkeys, context: viewContext)
        let missingPubkeys = pubkeys.filter {
            contacts.map { $0.pubkey! }.firstIndex(of: $0) == nil
        }
        let emptyContactPubkeys = pubkeys
            .compactMap { pubkey in
                contacts.first(where: { $0.pubkey! == pubkey })
            }
            .filter { $0.updated_at == 0 }
            .map { $0.pubkey! }
        
        guard (missingPubkeys + emptyContactPubkeys).count > 0 else { return }
        SocketPool.shared.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: missingPubkeys + emptyContactPubkeys )))
    }
}

struct Timeline_Previews: PreviewProvider {
    static var previews: some View {
        TimelineContainer()
            .withPreviewEnvironment()
    }
}




