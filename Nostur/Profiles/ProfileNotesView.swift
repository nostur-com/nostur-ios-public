//
//  TestTimeline.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/01/2023.
//

import SwiftUI
import CoreData

// NOTES ON USER PROFILE SCREEN
struct ProfileNotesView: View {
    
    let sp:SocketPool = .shared
    let pubkey:String
    @State var limit = 10
    
    var body: some View {
        DynamicFetchView(
            predicate: NSPredicate(format: "pubkey == %@ AND kind IN {1,6}", pubkey),
            fetchLimit: limit,
            sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]) { (events: FetchedResults<Event>)  in
                LazyVStack {
                    if (events.count > 0) {
                        ForEach(events.compactMap { VPostTransformer.shared.toVPost($0, skipParents: true) }) { vPost in
                            NoteRow(vPost: vPost)
                                .id(vPost.id)
                            Divider()
                        }
                        VStack {
                            if (events.count == limit) {
                                HStack {
                                    Spacer()
                                    Button("Load more") {
                                        limit = limit + 25
                                    }
                                    .padding(30)
                                    Spacer()
                                }
                            }
                        }
                    }
                    else {
                        CenteredProgressView()
                            .onAppear {
                                print("🟢 ProfileNotesView.onAppear always REQ.1: \(pubkey)")
                                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getAuthorNotes(pubkey: pubkey)))
                            }
                    }
                }
            }
    }
}

struct ProfileNotesView_Previews: PreviewProvider {
    static var previews: some View {
        
        // snowden: 84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240
        
        let pubkey = "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240"
        
//        VStack {
            ProfileNotesView(pubkey: pubkey)
                .withPreviewEnvironment()
//        }
    }
}
