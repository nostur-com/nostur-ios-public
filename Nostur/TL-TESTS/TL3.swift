//
//  TL3.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/02/2023.
//
 
/// 5.907 events, butter smooth scrolling is possible!

import SwiftUI
import CoreData


struct TL4: View {
    
    let pubkeys:Set<String>
    let newAtTop:Bool
    
    @FetchRequest
    var events: FetchedResults<Event>
    
    var eventsSorted:[Event] {
        get {
            if (newAtTop) { return events.sorted(by: { $0.created_at < $1.created_at }) }// NEW INDEX = 0
            return events.sorted(by: { $0.created_at < $1.created_at }) // OLD INDEX = 0
        }
    }
    
    @State var selectedEvent:Event?
    @State private var oldEvents: [Event] = []

    
    init(pubkeys:Set<String>, context:NSManagedObjectContext, newAtTop:Bool = false) {
        self.pubkeys = pubkeys
        self.newAtTop = newAtTop
        let r1 = Event.fetchRequest()
        r1.predicate = NSPredicate(format: "kind IN {1,6} AND pubkey IN %@", pubkeys)
        r1.fetchLimit = 75
        r1.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        let oldestCreatedAt = (try? context.fetch(r1).last?.created_at) ?? 0
        
        let r2 = Event.fetchRequest()
        r2.predicate = NSPredicate(format: "created_at >= %i AND kind IN {1,6} AND pubkey IN %@", oldestCreatedAt, pubkeys)
        r2.fetchLimit = 75
        r2.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _events = FetchRequest(fetchRequest: r2)
    }
    
    var body: some View {
        VStack {
            Button { fetchEvents(pubkeys: pubkeys) } label: {
                Text("FETCH")
            }
            Button {
                fetchStuffForLastAddedNotes(ids: ids(eventsSorted))
            } label: {
                Text("FETCH REFS (ALL)")
            }
            NavigationSplitView {
                List(selection: $selectedEvent) {
                    ForEach(eventsSorted) { event in
                        NoteRowView(event:event).listRowInsets(EdgeInsets())
                    }
                }
                .listStyle(.plain)
                .toolbar(content: toolbarContent)
                EmptyView()
            } detail: {
                if let selectedEvent {
                    NoteDetail(event: selectedEvent)
                }
            }
        }
        .onAppear {
            print("🟣🟣🟣 APPEAR: oldEvents: \(oldEvents.count) events: \(events.count) 🟣🟣🟣🟣")
        }
        .onChange(of: eventsSorted) { [eventsSorted] newEventsSorted in
            guard eventsSorted.last != nil else { return }

            let newIndexOfLastEvent = newEventsSorted.firstIndex(of: eventsSorted.last!)
            guard newIndexOfLastEvent != nil else { return } // TODO: uuhh, apparently we totally wrong if this returns }

            let newNotes = newEventsSorted.suffix(from: newIndexOfLastEvent! + 1)

            print("🟣🟣🟣 CHANGE: events: \(events.count) newNotes: \(newNotes.count) 🟣🟣🟣🟣")
            fetchStuffForLastAddedNotes(ids: ids(newNotes))
        }
    }
    
    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            HStack {
                Text("\(events.count) posts")
                    .foregroundStyle(Color.secondary)
                    .font(.caption)
                Button { sendNotification(.wantsNewEvents) } label: {
                    Text("FETCH")
                }
                Spacer()
            }
        }
    }
}

struct TLController: View {
    @EnvironmentObject var ns:NosturState
    @Environment(\.managedObjectContext) var viewContext
    var sp: SocketPool = .shared
    var mp: MessageParser = .shared
    
    @State private var oldestCreatedAt:Int64 = 0
    @State private var newestCreatedAt:Int64?
    
    @State private var oldEvents: [Event] = []
    @State private var lastEventId: [NSManagedObjectID] = []
    
    var body: some View {
        
        
        VStack {
            Button { fetchEvents() } label: {
                Text("FETCH")
            }
            Button {
                fetchStuffForLastAddedNotes(events: oldEvents)
            } label: {
                Text("FETCH REFS")
            }
            DynamicFetchView(predicate: NSPredicate(format: "created_at >= %i AND kind IN {1,6} AND pubkey IN %@", oldestCreatedAt, ns.followingPublicKeys), fetchLimit: 5, sortDescriptors: [NSSortDescriptor(keyPath:\Event.created_at, ascending: true)]) { (events: FetchedResults<Event>) in
//                    let newEvents = events.filter { event in
//                        newestCreatedAt == nil || event.created_at > newestCreatedAt!
//                    }
//                    let _ = fetchStuffForLastAddedNotes(events: newEvents)
                    TLView(events: events)
                    .onAppear {
                        oldEvents = Array(events)
                        print("🟣🟣🟣 APPEAR: oldEvents: \(oldEvents.count) events: \(events.count) 🟣🟣🟣🟣")
                    }
                    .onChange(of: events.last) { last in
                        guard last != nil else { return }
        
                        let newIndexOfLastEvent = events.firstIndex(of: last!)
                        guard newIndexOfLastEvent != nil else { return } // TODO: uuhh, apparently we totally wrong if this returns }
        
                        let newNotes = events.drop(while: { $0 != last! }).dropLast(1)
        
                        print("🟣🟣🟣 CHANGE: events: \(events.count) newNotes: \(newNotes.count) 🟣🟣🟣🟣")
//                        let newEvents = Set(newNotes).subtracting(Set(events))
//                        let latestQuakes = quakes.filter { latestQuakeIDs.contains($0.objectID) }
//                        newQuakes = Array(latestQuakes.reversed())
//                        callAnotherFunction(with: newQuakes)
//                        latestQuakeIDs = Array(quakes.prefix(3).map { $0.objectID })
                    }
                
            }.opacity(oldestCreatedAt != 0 ? 1 : 0)
        }
        .onAppear {
            setOldestCreatedAt()
        }
        .onReceive(receiveNotification(.wantsNewEvents)) { notification in
            fetchEvents()
            // @TODO: fetch missing firstQuoteId + firstQuote == nil
        }
        .onReceive(receiveNotification(.requestEventReferences)) { notification in
            let eventsNeedingDetails = notification.object as! [Event]
            fetchStuffForLastAddedNotes(events: eventsNeedingDetails)
        }
    }
    
    private func fetchEvents(amount:Int? = 500) {
        guard let pubkeys = ns.account?.follows?.map({ contact in
            return contact.pubkey!
        }) else { return }
        
        print("💿💿 getFollowingEvents for \(pubkeys.count) pubkeys 💿💿")
        sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getFollowingEvents(pubkeys: Array(pubkeys), limit: amount!)))
    }
}

extension TLController {
    func setOldestCreatedAt() {
        // NEEDED BECAUSE: INITIAL FETCHREQUEST RESPECTS FETCHLIMIT
        // BUT AFTER IMPORTER, OLDER AND MANY MORE EVENTS START SHOWING UP IN FETCHEDRESULTS
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind IN {1,6} AND pubkey IN %@", ns.followingPublicKeys)
        fr.fetchLimit = 5
        fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        oldestCreatedAt = (try? viewContext.fetch(fr).last?.created_at) ?? 0
    }
    
    func fetchMissingReplyToContacts(events:[Event]) {
        // TODO: FIXEN
        // TODO, bij importer, replyTo p in event.replyToPTag for speed up
        let pubkeys = Array(Set(events.compactMap { TagsHelpers($0.tags()).reactingToPubkey() }))
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

        sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: missingPubkeys + emptyContactPubkeys )))
    }
        
    func fetchStuffForLastAddedNotes(events:[Event]) {
        //TODO: Fixen
        // Prepare #e filter
        // Get all events that reference our event.id's on screen
        // To update likes etc.

        let eventIds = events.map { $0.id! }
        sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEventReferences(ids: eventIds)))
    }
}


struct TLView: View {
    var events:FetchedResults<Event>
    @State var selectedEvent:Event?
    var last:Event? { events.last }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedEvent) {
                ForEach(events) { event in
                    NoteRowView(event:event).listRowInsets(EdgeInsets())
                }
            }
            .listStyle(.plain)
            .toolbar(content: toolbarContent)
//            .onChange(of: last) { [last] newLast in
//                guard last != nil else { return }
//
//                let newIndexOfLastEvent = events.firstIndex(of: last!)
//                guard newIndexOfLastEvent != nil else { return } // TODO: uuhh, apparently we totally wrong if this returns }
//
//                let newNotes = events.drop(while: { $0 != last }).dropLast(1)
//
//                let newEvents = Set(newNotes).subtracting(Set(events))
//                if (newEvents.count != 0) {
//                    print("Added \(newEvents.count) new notes.")
//                    sendNotification(.requestEventReferences, Array(newEvents))
//                }
//            }
            EmptyView()
        } detail: {
            if let selectedEvent {
                NoteDetail(event: selectedEvent)
            }
        }
    }
}

// MARK: Toolbar Content
extension TLView {
    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            HStack {
                Text("\(events.count) posts")
                    .foregroundStyle(Color.secondary)
                    .font(.caption)
                Button { sendNotification(.wantsNewEvents) } label: {
                    Text("FETCH")
                }
                Spacer()
            }
        }
    }
}

struct TLController_Previews: PreviewProvider {
    static var previews: some View {
        TLController()
            .withPreviewEnvironment()
    }
}
