//
//  TestTimeline.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/01/2023.
//

import SwiftUI


// NOTES ON USER PROFILE SCREEN
struct ProfileNotesView: View {
    
    @EnvironmentObject var cm:ConnectionManager
    var pubkey:String
    
    @FetchRequest(
        sortDescriptors: [],
        animation: .none)
    var contacts:FetchedResults<Contact>
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Event.created_at, order: .reverse)],
        predicate: NSPredicate(format: "kind == 1"),
        animation: .none)
    var events: FetchedResults<Event>
    
    init(pubkey: String) {
        self.pubkey = pubkey
        _events = FetchRequest(
            sortDescriptors: [SortDescriptor(\Event.created_at, order: .reverse)],
            predicate: NSPredicate(format: "pubkey == %@ AND kind == 1", pubkey)
        )
        
        _contacts = FetchRequest(
            sortDescriptors: [],
            predicate: NSPredicate(format: "pubkey == %@", pubkey)
        )
    }
    
    
    var body: some View {
        VStack {
            if (contacts.first != nil) {
                ProfileNotesViewInner(contact: contacts.first!, events: events)
            }
            else {
                Text("Profile not found").onAppear {
                    // fetch
                    
                }
            }
        }.onAppear {
            cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: pubkey)))
        }
    }
}

struct ProfileNotesViewInner: View {
    
    @EnvironmentObject var cm:ConnectionManager
    var contact:Contact
    var events:FetchedResults<Event>
    
    var body: some View {
        HStack {
            if (events.count > 0) {
                LazyVStack {
                    ForEach(events, id:\Event.id) { event in
                        NoteRow(event:event)
                    }
                }
            }
            else {
                Text("Fetching posts from user...")
                    .onAppear {
                        // .REQ by author
                        // TODO:
                        
                    }
            }
        }.onAppear {
            cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getAuthorNotes(pubkey: contact.pubkey!)))
        }
    }
}



struct ProfileNotesView_Previews: PreviewProvider {
    static var previews: some View {
        
        // snowden: 84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240
        
        let pubkey = "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240"
        
        ScrollView {
            ProfileNotesView(pubkey: pubkey)
                .withPreviewEnvironment()
        }
    }
}
