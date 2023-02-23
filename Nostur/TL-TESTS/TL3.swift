//
//  TL3.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/02/2023.
//
import SwiftUI
import CoreData
import Combine

struct TL4W: View {
    @EnvironmentObject var ns:NosturState
    @Environment(\.managedObjectContext) var viewContext
    
    var body: some View {
        let _ = Self._printChanges()
        TL4(pubkeys: ns.followingPublicKeys, context: viewContext)
    }
}

struct TL4: View { /// 5.907 events in one view!, butter smooth scrolling is possible!
    let ds:DataStore = .shared
    @Environment(\.managedObjectContext) var viewContext
    let pubkeys:Set<String>
    @FetchRequest
    var events: FetchedResults<Event>
    
    var eventsSorted:[Event] {
        events.sorted(by: { $0.created_at < $1.created_at }) // OLDEST INDEX = 0
    }
    
    @State var selectedEvent:Event?
    @State private var oldEvents: [Event] = []
    
    @SceneStorage("selectedItemId") var selectedItemId: String?
    @State var didRestore = false
    
    let FETCH_LIMIT = 120
    
    init(pubkeys:Set<String>, context:NSManagedObjectContext) {
        print("🧨🧨🧨🧨🧨 I INIT AGAIN BITCH 🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨")
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
            NavigationSplitView {
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
                                            ds.markAsRead.send(event)
                                        }
                                        if (didRestore) {
                                            selectedItemId = event.id!
                                            print("SceneStorage STORED: \(selectedItemId ?? "")")
                                        }
                                    }
                            }
                        }
                        .onAppear {
                            if (!didRestore && selectedItemId != nil) {
                                withAnimation(.none) {
                                    print("SceneStorage SCROLLING: \(selectedItemId ?? "")")
                                    proxy.scrollTo(selectedItemId!, anchor: .bottom)
                                    didRestore = true
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .toolbar(content: toolbarContent)
                    .safeAreaInset(edge: .top) {
                        AppTopBar()
                            .padding(5)
                            .background(Color("BackgroundColor").opacity(0.9))
                    }
                    UnreadCounter()
                }
//                EmptyView()
            } detail: {
                if let selectedEvent {
                    NoteDetail(event: selectedEvent)
                }
            }
        }
        .onAppear {
//            print("🟣🟣🟣 APPEAR: oldEvents: \(oldEvents.count) events: \(events.count)")
            ds.notesChanged.send(eventsSorted)
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
        }
    }
}

extension TL4 {
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

struct TL4Wrapper: View {
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    var body: some View {
        let _ = Self._printChanges()
        TL4(pubkeys: ns.followingPublicKeys, context: viewContext)
    }
}

struct TL4_Previews: PreviewProvider {
    static var previews: some View {
        TL4Wrapper()
            .withPreviewEnvironment()
    }
}





struct UnreadCounter: View {
    @EnvironmentObject var ds:DataStore
    
    var body: some View {
        let _ = Self._printChanges()
        VStack {
            Spacer()
            HStack {
                Spacer()
                if (ds.unreadCount > 0) {
                    HStack {
                        Image(systemName: "arrow.down")
                        Text("\(ds.unreadCount) unread")
                        Image(systemName: "arrow.down")
                    }
                    .frame(minWidth: 30)
                    .padding(10)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .background(.blue)
                    .opacity(0.95)
                    .cornerRadius(20)
                    .onTapGesture {
//                            if let noteId = notes.dropLast(count).last?.id {
//                                sendNotification(.shouldScrollToNote, noteId)
//                            }
                    }
                }
                Spacer()
            }
        }
    }
}
