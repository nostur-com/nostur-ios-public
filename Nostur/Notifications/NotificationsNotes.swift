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
    let FETCH_LIMIT = 2000
    let sp:SocketPool = .shared
    let nav:NavigationModel = .shared
    @EnvironmentObject var ns:NosturState
    @Environment(\.managedObjectContext) var viewContext
    var onAppear:(Int64) -> ()
    let vTransformer:VTransformer
    
    @FetchRequest
    var notes:FetchedResults<Event>
    
    var vPosts:[VPost] {
        notes.map(vTransformer.eventToVPost)
    }
        
    init(pubkey:String, mutedRootIds:[String], blockedPubkeys:[String], context:NSManagedObjectContext, onAppear: @escaping (Int64) -> ()) {
        print("🧨🧨🧨🧨🧨 I INIT NotificationsNotes 🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨")
        self.pubkey = pubkey
        self.onAppear = onAppear
        self.vTransformer = VTransformer(pubkey:pubkey, context: DataProvider.shared().viewContext)
//        let r1 = Event.fetchRequest()
//        r1.predicate = NSPredicate(format: "NOT pubkey IN %@ AND kind == 1 AND tagsSerialized CONTAINS %@ AND NOT id IN %@ AND (NOT replyToRootId IN %@ OR replyToRootId == nil) AND (NOT replyToId IN %@ OR replyToId == nil)", blockedPubkeys + [pubkey], serializedP(pubkey), mutedRootIds, mutedRootIds, mutedRootIds)
////        r1.fetchLimit = FETCH_LIMIT
//        r1.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
//        let oldestCreatedAt = (try? context.fetch(r1).last?.created_at) ?? 0
        
        let oldestCreatedAt = 0
        
        let r2 = Event.fetchRequest()
        r2.predicate = NSPredicate(format: "created_at >= %i AND NOT pubkey IN %@ AND kind == 1 AND tagsSerialized CONTAINS %@ AND NOT id IN %@ AND (NOT replyToRootId IN %@ OR replyToRootId == nil) AND (NOT replyToId IN %@ OR replyToId == nil)", oldestCreatedAt, blockedPubkeys + [pubkey], serializedP(pubkey), mutedRootIds, mutedRootIds, mutedRootIds)
        r2.fetchLimit = FETCH_LIMIT
        r2.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _notes = FetchRequest(fetchRequest: r2)
    }
    
    var body: some View {
        List {
            Section {
                ForEach(vPosts) { vPost in
                    NoteRow(vPost: vPost)
                        .id(vPost.id)
                        .listRowInsets(EdgeInsets())
                }
            }
            Section {
                HStack {
                    Spacer()
                    Button("Fetch older") {
                        fetchOlderNotes()
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    Spacer()
                }
                .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.plain)
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
    
    func fetchOlderNotes() {
        guard ns.account != nil else { return }
        sp.sendMessage(
            ClientMessage(type: .REQ,
                          message:
                            RequestMessage.getMentions(
                                pubkeys: [ns.account!.publicKey],
                                kinds: [1],
                                limit: 500,
                                until: NTimestamp(timestamp: Int(notes.last?.created_at ?? 0)))
                         )
        )
    }
    
    
}

struct NotificationsNotes_Previews: PreviewProvider {
    static var previews: some View {
        let pubkey = "04c915daefee38317fa734444acee390a8269fe5810b2241e5e6dd343dfbecc9"
        NotificationsNotes(pubkey: pubkey, mutedRootIds: [], blockedPubkeys: [], context: EventsProvider.preview.container.viewContext) { _ in
            
        }
            .withPreviewEnvironment()
    }
}
