//
//  ProfileLikesView.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/01/2023.
//

import SwiftUI
import CoreData


struct ProfileLikesView: View {

    var sp:SocketPool = .shared
    var pubkey:String
    @State var limit = 20
    
    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "FALSEPREDICATE"),
        animation: .none)
    var reactionsTo: FetchedResults<Event>

    
    var body: some View {
        DynamicFetchView(
            predicate: NSPredicate(format: "pubkey == %@ AND kind == 7", pubkey),
            fetchLimit: limit,
            sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]) { (events: FetchedResults<Event>)  in
                LazyVStack {
                    if (reactionsTo.count > 0) {
                        ForEach(reactionsTo.map(VPostTransformer.shared.toVPost)) { vPost in
                            NoteRow(vPost: vPost)
                                .id(vPost.id)
                            Divider()
                        }
                        VStack {
                            if (reactionsTo.count == limit) {
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
                .onAppear {
                    if (events.count > 0) {
                        let eventIds = events.map { event in
                            return TagsHelpers(event.tags())
                                .reactingToEventId() ?? nil
                        }.filter { id in
                            return id != nil
                        }
                        reactionsTo.nsPredicate = NSPredicate(format: "id IN %@ AND kind == 1", eventIds)
                    }
                }
            }
            .onAppear {
                print("🟢 ProfileLikesView.onAppear always REQ.7: \(pubkey)")
                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getAuthorReactions(pubkey: pubkey)))
            }
    }
}

struct ProfileLikesView_Previews: PreviewProvider {
    static var previews: some View {
        
        // snowden: 84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240
        
        let pubkey = "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240"
        
        ScrollView {
            ProfileLikesView(pubkey: pubkey)
                .withPreviewEnvironment()
        }
    }
}
