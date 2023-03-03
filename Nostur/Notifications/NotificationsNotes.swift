//
//  NotificationsNotes.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/03/2023.
//

import SwiftUI
import CoreData

struct NotificationsNotes: View {
    
    let pubkey:String
//    let FETCH_LIMIT = 200
    let sp:SocketPool = .shared
    let nav:NavigationModel = .shared
    @EnvironmentObject var ns:NosturState
    @Environment(\.managedObjectContext) var viewContext
    var onAppear:(Int64) -> ()
    
    @FetchRequest
    var notes:FetchedResults<Event>
        
    init(pubkey:String, mutedRootIds:[String], context:NSManagedObjectContext, onAppear: @escaping (Int64) -> ()) {
        print("🧨🧨🧨🧨🧨 I INIT NotificationsNotes 🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨")
        self.pubkey = pubkey
        self.onAppear = onAppear
        let r1 = Event.fetchRequest()
        r1.predicate = NSPredicate(format: "pubkey != %@ AND kind == 1 AND tagsSerialized CONTAINS %@ AND NOT id IN %@ AND NOT replyToRootId IN %@ AND NOT replyToId IN %@", pubkey, serializedP(pubkey), mutedRootIds, mutedRootIds, mutedRootIds)
//        r1.fetchLimit = FETCH_LIMIT
        r1.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        let oldestCreatedAt = (try? context.fetch(r1).last?.created_at) ?? 0
        
        let r2 = Event.fetchRequest()
        r2.predicate = NSPredicate(format: "created_at >= %i AND pubkey != %@ AND kind == 1 AND tagsSerialized CONTAINS %@ AND NOT id IN %@ AND NOT replyToRootId IN %@ AND NOT replyToId IN %@", oldestCreatedAt, pubkey, serializedP(pubkey), mutedRootIds, mutedRootIds, mutedRootIds)
//        r2.fetchLimit = FETCH_LIMIT
        r2.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _notes = FetchRequest(fetchRequest: r2)
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment:.leading) {
                ForEach(notes) { note in
                    VStack(alignment:.leading, spacing: 3) {
                        Group {
                            NoteRowView(event: note)
                        }.onTapGesture {
                            nav.navigateTo(NotePath(id: note.id))
                        }
                        Divider()
                    }
                }
            }
            .padding()
        }
        .onAppear {
            fetchReactions()
        }
    }
    func fetchReactions() {
        guard ns.account != nil else { return }
        sp.sendMessage(
            ClientMessage(type: .REQ,
                          message:
                            RequestMessage.getMentions(
                                pubkeys: [ns.account!.publicKey],
                                kinds: [1],
                                limit: 500,
                                since: NTimestamp(timestamp: Int(notes.first?.created_at ?? 0)))
                         )
        )
    }
}

struct NotificationsNotes_Previews: PreviewProvider {
    static var previews: some View {
        let pubkey = "04c915daefee38317fa734444acee390a8269fe5810b2241e5e6dd343dfbecc9"
        NotificationsNotes(pubkey: pubkey, mutedRootIds: [], context: EventsProvider.preview.container.viewContext) { _ in
            
        }
            .withPreviewEnvironment()
    }
}
