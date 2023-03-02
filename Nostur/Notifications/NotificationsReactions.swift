//
//  Notifications.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/02/2023.
//

import SwiftUI
import CoreData

// NIP-25: The last p tag MUST be the pubkey of the event being reacted to.
// TODO: Maybe when performance problems: store lastE + lasteE in Events table
struct NotificationsReactions: View {
    
    let pubkey:String
//    let FETCH_LIMIT = 1000
    let sp:SocketPool = .shared
    let nav:NavigationModel = .shared
    @EnvironmentObject var ns:NosturState
    @Environment(\.managedObjectContext) var viewContext
    var onAppear:(Int64) -> ()
    
    @FetchRequest
    var reactions:FetchedResults<Event>
    
    var myNotesReactedTo:[Event] {
        reactions.compactMap { $0.reactionTo }
    }
    
    func reactionsForNote(_ note:Event) -> [Event] {
        reactions.compactMap {  $0.reactionTo == note ? $0 : nil }
    }
    
    init(pubkey:String, context:NSManagedObjectContext, onAppear: @escaping (Int64) -> ()) {
        print("🧨🧨🧨🧨🧨 I INIT NotificationsV 🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨")
        self.pubkey = pubkey
        self.onAppear = onAppear
        let r1 = Event.fetchRequest()
        r1.predicate = NSPredicate(format: "kind == 7 AND reactionTo.contact.pubkey == %@", pubkey)
//        r1.fetchLimit = FETCH_LIMIT
        r1.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        let oldestCreatedAt = (try? context.fetch(r1).last?.created_at) ?? 0
        
        let r2 = Event.fetchRequest()
        r2.predicate = NSPredicate(format: "created_at >= %i AND kind == 7 AND reactionTo.contact.pubkey == %@", oldestCreatedAt, pubkey)
//        r2.fetchLimit = FETCH_LIMIT
        r2.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _reactions = FetchRequest(fetchRequest: r2)
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment:.leading) {
                ForEach(myNotesReactedTo) { note in
                    VStack(alignment:.leading, spacing: 3) {
                        Group {
                            ReactionsForThisNote(reactions:reactionsForNote(note), onAppear: self.onAppear)
                            NoteMinimalContentView(event: note)
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
                                kinds: [7],
                                limit: 500,
                                since: NTimestamp(timestamp: Int(reactions.first?.created_at ?? 0)))
                         )
        )
    }
}

struct ReactionsForThisNote: View {
    var reactions:[Event]
    @Environment(\.managedObjectContext) var viewContext
    var onAppear:(Int64) -> ()
    
    var withoutDuplicates:[Event] { // Author may accidentally like multiple times 
        reactions
            .reduce(into: [String: Event]()) { result, event in
                result[event.pubkey] = event
            }.values.sorted(by: { $0.created_at > $1.created_at })
    }
    
    var body: some View {
        VStack(alignment:.leading) {
            ZStack {
                ForEach(withoutDuplicates.prefix(10).indices, id:\.self) { index in
                    ZStack {
                        ProfilePic(event: reactions[index])
                            .id(reactions[index].id)
                            .onAppear {
                                onAppear(reactions[index].created_at)
                            }
                            .zIndex(-Double(index))
                        Text(reactions[index].content == "+" ? "❤️" : reactions[index].content ?? "❤️")
                            .offset(x:-10, y:+15)
                            .zIndex(20)
                        
                    }
                    .offset(x:Double(0 + (25*index)))
                }
            }
            if (withoutDuplicates.count > 1) {
                Text("**\(withoutDuplicates.first(where: { $0.contact?.authorName != nil })?.contact?.authorName ?? "???")** and \(withoutDuplicates.count - 1) others reacted to your post")
            }
            else {
                Text("**\(withoutDuplicates.first(where: { $0.contact?.authorName != nil })?.contact?.authorName ?? "???")** reacted on your post")
            }
        }
        .onAppear {
            self.fetchMissingEventContacts(events:Array(withoutDuplicates.prefix(10)))
        }
    }
    
    func fetchMissingEventContacts(events:[Event]) {
        let pubkeys = pubkeys(events)
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
        print("Fetching  \((missingPubkeys + emptyContactPubkeys).count) missing or empty contacts")
        SocketPool.shared.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: missingPubkeys + emptyContactPubkeys )))
    }
}

struct NotificationsV_Previews: PreviewProvider {
    static var previews: some View {
        let pubkey = "04c915daefee38317fa734444acee390a8269fe5810b2241e5e6dd343dfbecc9"
        NotificationsReactions(pubkey: pubkey, context: EventsProvider.preview.container.viewContext) { _ in
            
        }
            .withPreviewEnvironment()
    }
}
