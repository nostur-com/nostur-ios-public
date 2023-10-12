//
//  Reactions.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/02/2023.
//

import SwiftUI

struct NoteReactions: View {
    @EnvironmentObject private var themes:Themes
    
    private let id:String
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)], predicate: NSPredicate(value: false))
    private var reactions:FetchedResults<Event>
    private var reactions_:[Event] { reactions.filter { $0.lastE() == id }  }
    
    init(id:String) {
        self.id = id
        _reactions = FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: true)], predicate: NSPredicate(format: "kind == 7 AND tagsSerialized CONTAINS %@", serializedE(id)))
    }
    
    var body: some View {
//        let _ = Self._printChanges()
        ScrollView {
            ForEach(reactions_) { reaction in
                ReactionRow(reaction: reaction)
            }
            Spacer()
        }
        .background(themes.theme.listBackground)
        .onAppear {
            var missing:[Event] = []
            for reaction in reactions_ {
                if let contact = reaction.contact, contact.metadata_created_at == 0 {
                    missing.append(reaction)
                    EventRelationsQueue.shared.addAwaitingContact(contact, debugInfo: "NoteReactions.001")
                }
                else if reaction.contact == nil {
                    missing.append(reaction)
                    EventRelationsQueue.shared.addAwaitingEvent(reaction, debugInfo: "NoteReactions.002") // wrong ctx
                }
            }
            
            QueuedFetcher.shared.enqueue(pTags: missing.map { $0.pubkey })
        }
    }
}

struct ReactionRow: View {
    @ObservedObject public var reaction:Event
    
    var body: some View {
        HStack(alignment: .top) {
            PFP(pubkey: reaction.pubkey, contact: reaction.contact)
                .onTapGesture {
                    navigateTo(ContactPath(key: reaction.pubkey))
                }
            VStack(alignment: .leading) {
                NoteHeaderViewEvent(event: reaction)
                Text(reaction.content == "+" ? "❤️" : reaction.content ?? "")
            }
        }
        .padding()
        .contentShape(Rectangle())
        .onTapGesture {
            navigateTo(ContactPath(key: reaction.pubkey))
        }
        Divider()
    }
}

struct Reactions_Previews: PreviewProvider {
    static var previews: some View {

        PreviewContainer({ pe in
            pe.loadRepliesAndReactions()
        }) {
            VStack {
                if let noteWithReactions = PreviewFetcher.fetchEvent("6f74b952991bb12b61de7c5891706711e51c9e34e9f120498d32226f3c1f4c81") {
                    NoteReactions(id: noteWithReactions.id)
                }
            }
        }
    }
}
