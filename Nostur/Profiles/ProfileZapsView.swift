//
//  ProfileZapsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 18/02/2023.
//

import SwiftUI

// NOTES ON USER PROFILE SCREEN
struct ProfileZapsView: View {
    
//    @EnvironmentObject var cm:ConnectionManager
    var cm:SocketPool = .shared
    var pubkey:String
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Event.created_at, order: .reverse)],
        predicate: NSPredicate(format: "kind IN {9735}"),
        animation: .none)
    var events: FetchedResults<Event>
    
    init(pubkey: String) {
        self.pubkey = pubkey
        _events = FetchRequest(
            sortDescriptors: [SortDescriptor(\Event.created_at, order: .reverse)],
            predicate: NSPredicate(format: "kind = 9735 AND ANY tags.contact.pubkey = %@", pubkey)
        )
    }
    
    
    var body: some View {
        
        VStack {
            if (events.count == 0) {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(50)
                    Spacer()
                }
            }
            else {
                LazyVStack {
                    ForEach(events, id:\Event.id) { event in
                        NoteRowView(event:event)
                        Divider()
                    }
                }
            }
        }.onAppear {
            print("🟢 ProfileZapsView.onAppear always REQ.9735 \(pubkey)")
            cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getAuthorZaps(pubkey: pubkey)))
        }
        
    }
}

struct ProfileZapsView_Previews: PreviewProvider {
    static var previews: some View {
        
        // snowden: 84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240
        
        let pubkey = "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240"
        
        ScrollView {
            ProfileZapsView(pubkey: pubkey)
                .withPreviewEnvironment()
        }
    }
}
