//
//  NaturalTimelineView.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/01/2023.
//

import SwiftUI
import CoreData

struct NaturalTimelineView: View {
    
//    @Environment(\.managedObjectContext) var viewContext
    
    // Timer to check for stuff to parse every 3 sec..
//    let parseRunLoop = Timer.publish(every: 3, tolerance: 1, on: .main, in: .common).autoconnect()
    
    var ep: EventsProvider = .shared
    @EnvironmentObject var cm:ConnectionManager
    @EnvironmentObject var accountState:AccountState

    @AppStorage("lastUpdated")
    private var lastUpdated = Date.distantFuture.timeIntervalSince1970

//    @FetchRequest(
//        sortDescriptors: [SortDescriptor(\.created_at, order: .reverse)],
//        predicate: NSPredicate(format: "FALSEPREDICATE"),
//        animation: .none)
    @FetchRequest
    private var events: FetchedResults<Event>
//    @State var predicateConfigured = false
    
    @AppStorage("showReplies") var showReplies = false
    var showRepliesToggle: Binding<Bool> {
        Binding {
            showReplies
        } set: { newValue in
            showReplies = newValue
//            configurePredicate(showReplies: newValue)
        }
    }
    
    @State private var isLoading = false
    @State private var error: EventError?
    @State private var hasError = false
    
    
//    init(followingPubkeys:[String], showReplies:Bool) {
    init(showReplies:Bool) {
        
        let request: NSFetchRequest<Event> = Event.fetchRequest()
//        request.predicate = NSPredicate(format: "active = true")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Event.created_at, ascending: false)
        ]
        
        if (showReplies) {
            request.predicate = NSPredicate(format: "kind == 1 AND replyToId != nil")
        }
        else {
            request.predicate = NSPredicate(format: "kind == 1 AND replyToId == nil")
        }
        _events = FetchRequest(fetchRequest: request)
        
    }
    
//    func configurePredicate(showReplies:Bool) {
//        let followingPubkeys = [String](accountState.followingPublicKeys)
//        if (showReplies) {
//            events.nsPredicate = NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId != nil", followingPubkeys)
//        }
//        else {
//            events.nsPredicate = NSPredicate(format: "pubkey IN %@ AND kind == 1 AND replyToId == nil", followingPubkeys)
//        }
//        predicateConfigured = true
//    }
    
//    @FetchRequest
//    var events:FetchedResults<Event>
    
//    init(withReplies:Bool = false) {
//    init() {
//        let request: NSFetchRequest<Event> = Event.fetchRequest()
////        if (withReplies) {
////            request.predicate = NSPredicate(format: "kind == 1")
////        }
////        else {
////            request.predicate = NSPredicate(format: "kind == 1 && replyToId == nil")
////        }
////
////        //        request.fetchBatchSize = 1
//        request.fetchLimit = 200
//        request.predicate = NSPredicate(format: "kind == 1 && replyToId == nil")
//        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
//        _events = FetchRequest(fetchRequest: request)
//    }
    
    var body: some View {
        VStack {
            Toggle(isOn: showRepliesToggle) {
                HStack {
                    Spacer()
                    Label("Show replies", systemImage: "bubble.left.and.bubble.right")
                }
            }.toggleStyle(.switch)
                .padding(.horizontal)
            ScrollView {
                LazyVStack {
                    ForEach(events, id:\.self) { event in
                        NoteRow(event: event)
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = event.noteId
                                } label: {
                                    Label("Copy note id \(event.noteId)", systemImage: "doc.on.clipboard")
                                }
                                Button {
                                    UIPasteboard.general.string = event.id!
                                } label: {
                                    Label("Copy note id hex \(event.id!))", systemImage: "doc.on.clipboard")
                                }
                                Button {
                                    print("Unfollow @\(event.username)")
                                } label: {
                                    Label("Unfollow @\(event.username)", systemImage: "person.fill.xmark")
                                }
                                Button {
                                    print("Block @\(event.username)")
                                } label: {
                                    Label("Block @\(event.username)", systemImage: "slash.circle")
                                }
                            }
                    }
                }
            }
        }
        .onAppear {
            
        }
//        .onReceive(parseRunLoop) { time in
////            if (!predicateConfigured) {
////                configurePredicate(showReplies: showReplies)
////            }
//            Task {
//                await importEvents()
//            }
//        }
        .refreshable {
            fetchEventsFromFollowing(amount: 500)//TODO: 500 when fixed
        }
    }
}

// MARK: Core Data

extension NaturalTimelineView {

    
    // maybe use delete for bookmarsk
//    private func deleteQuakes(at offsets: IndexSet) {
//        let objectIDs = offsets.map { quakes[$0].objectID }
//        quakesProvider.deleteQuakes(identifiedBy: objectIDs)
//        selection.removeAll()
//    }
//
//    private func deleteQuakes(for codes: Set<String>) async {
//        do {
//            let quakesToDelete = quakes.filter { codes.contains($0.code) }
//            try await quakesProvider.deleteQuakes(quakesToDelete)
//        } catch {
//            self.error = error as? QuakeError ?? .unexpectedError(error: error)
//            self.hasError = true
//        }
//        selection.removeAll()
//        #if os(iOS)
//        editMode = .inactive
//        #endif
//    }
    
    private func fetchEventsFromFollowing(amount:Int? = 500) {
        for socket in cm.relaySockets {
            if (socket.relay.read || socket.relay.write) && !socket.isConnected {
                socket.socket.connect()
            }
        }

        let followingPubkeys = [String](accountState.followingPublicKeys)
        cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getFollowingEvents(pubkeys: followingPubkeys, limit: amount!, since: ep.lastTimelineEventTimestamp)))
    }

    private func importEvents() async {
        isLoading = true
        do {
            Task {
                let before = await ep.queue.count
                try await ep.importEvents()
                if (before != 0) {
                    print("didParse? queue count, before: \(before) after: \(await ep.queue.count)")
                }
            }
            lastUpdated = Date().timeIntervalSince1970
        } catch {
            self.error = error as? EventError ?? .unexpectedError(error: error)
            self.hasError = true
        }
        isLoading = false
    }
}

struct NaturalTimelineView_Previews: PreviewProvider {
    static let eventsProvider = EventsProvider.preview
    static var previews: some View {
//        NaturalTimelineView()
//            .withPreviewEnvironment()
        
//        NaturalTimelineView(ep: eventsProvider)
        NaturalTimelineView(showReplies: true)
            .withPreviewEnvironment()
    }
}
