//
//  NoteReposts.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/08/2023.
//

import SwiftUI
import NostrEssentials

// Copy pasta from NoteReactions and adjusted a bit. ReactionRow replaced with ProfileRows
struct NoteReposts: View {
    @Environment(\.theme) private var theme
    
    let id: String
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)], predicate: NSPredicate(value: false))
    var reposts: FetchedResults<Event>
    var repostsPubkeys: [String] { reposts.filter({ $0.firstE() == id }) .map ({ $0.pubkey }) }
    
    init(id: String) {
        self.id = id
        _reposts = FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: true)], predicate: NSPredicate(format: "kind == 6 AND tagsSerialized CONTAINS %@", serializedE(id)))
    }
    
    var body: some View {
//        let _ = Self._printChanges()
        ScrollView {
            ProfileRows(repostsPubkeys)
            Spacer()
        }
        .background(theme.listBackground)
        .onAppear {
            req(CM(type: .REQ, filters: [Filters(kinds: [6], tagFilter: TagFilter(tag: "e", values: [id]))]).json()!)
        }
         .nosturNavBgCompat(theme: theme)
    }
}

struct NoteReposts_Previews: PreviewProvider {
    static var previews: some View {

        PreviewContainer({ pe in
            pe.loadReposts()
        }) {
            VStack {
                if let noteWithReposts = PreviewFetcher.fetchEvent("6f74b952991bb12b61de7c5891706711e51c9e34e9f120498d32226f3c1f4c81") {
                    NoteReposts(id: noteWithReposts.id)
                }
            }
        }
    }
}



struct ProfileRows: View {
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Contact.metadata_created_at, ascending: false)], predicate: NSPredicate(value: false))
    var contacts: FetchedResults<Contact>
    
    var pubkeys: [String]
    
    init(_ pubkeys: [String]? = nil) {
        self.pubkeys = pubkeys ?? []
    }
    
    var body: some View {
        LazyVStack {
            ForEach(contacts) {
                ProfileRow(contact: $0)
                    .frame(maxHeight: 200)
                Divider()
            }
        }
        .onChange(of: contacts.last) { contact in
            var missing:[Contact] = []
            for contact in contacts {
                if contact.metadata_created_at == 0 {
                    missing.append(contact)
                    EventRelationsQueue.shared.addAwaitingContact(contact, debugInfo: "ProfileRows.001")
                }
            }
            QueuedFetcher.shared.enqueue(pTags: missing.map { $0.pubkey })
        }
        .onAppear {
            contacts.nsPredicate = NSPredicate(format: "pubkey IN %@", pubkeys)
        }
    }
}
