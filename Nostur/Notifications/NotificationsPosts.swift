//
//  NotificationsNotes.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/03/2023.
//

import SwiftUI
import CoreData

struct NotificationsPosts: View, Equatable {
    
    static func == (lhs: NotificationsPosts, rhs: NotificationsPosts) -> Bool {
        lhs.pubkey == rhs.pubkey
        && lhs.mutedRootIds == rhs.mutedRootIds
        && lhs.blockedPubkeys == rhs.blockedPubkeys
    }
    
    let pubkey:String
    let mutedRootIds:[String]
    let blockedPubkeys:[String]
    let FETCH_LIMIT = 200
    let sp:SocketPool = .shared
    let nav:NavigationModel = .shared
    @EnvironmentObject var ns:NosturState
    @Environment(\.managedObjectContext) var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
        predicate: NSPredicate(value: false))
    var notes:FetchedResults<Event>
    var vPosts:[VPost] {
        notes.compactMap { VPostTransformer.shared.toVPost($0, skipParents: true) }
    }
    
    init(pubkey:String, mutedRootIds:[String], blockedPubkeys:[String], context:NSManagedObjectContext) {
        self.pubkey = pubkey
        self.mutedRootIds = mutedRootIds
        self.blockedPubkeys = blockedPubkeys
        
        let r2 = Event.fetchRequest()
        r2.predicate = NSPredicate(
            format:
                "NOT pubkey IN %@ " +
                "AND kind == 1 " +
                "AND tagsSerialized CONTAINS %@ " +
                "AND NOT id IN %@ " +
                "AND NOT replyToRootId IN %@ " +
                "AND NOT replyToId IN %@ ",
                blockedPubkeys + [pubkey],
                serializedP(pubkey),
                mutedRootIds,
                mutedRootIds,
                mutedRootIds
          )
        r2.fetchLimit = FETCH_LIMIT
        r2.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _notes = FetchRequest(fetchRequest: r2)
    }
    
    var body: some View {
        let _ = Self._printChanges()
        ScrollView {
            LazyVStack {
                ForEach(vPosts) { vPost in
                    NoteRow(vPost: vPost)
                        .boxShadow()
                        .onTapGesture {
                            nav.navigateTo(vPost)
                        }
                        .id(vPost.id)
                }
                HStack {
                    Spacer()
                    Button("Fetch older") {
                        fetchOlderMentions()
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    Spacer()
                }
            }
        }
        .onAppear {
            fetchNewerMentions()
            if let first = notes.first {
                ns.account?.lastSeenPostCreatedAt = first.created_at
            }
            DataProvider.shared().save()
        }
    }
    func fetchNewerMentions() {
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
    
    func fetchOlderMentions() {
        guard ns.account != nil else { return }
        sp.sendMessage(
            ClientMessage(type: .REQ,
                          message:
                            RequestMessage.getMentions(
                                pubkeys: [ns.account!.publicKey],
                                kinds: [1],
                                limit: 500,
                                until: NTimestamp(timestamp: Int(notes.last?.created_at ?? 0))
                            )
                         )
        )
    }
    
    
}

struct NotificationsNotes_Previews: PreviewProvider {
    static var previews: some View {
        let pubkey = "04c915daefee38317fa734444acee390a8269fe5810b2241e5e6dd343dfbecc9"
        NotificationsPosts(pubkey: pubkey, mutedRootIds: [], blockedPubkeys: [], context: EventsProvider.preview.container.viewContext)
                .withPreviewEnvironment()
    }
}
