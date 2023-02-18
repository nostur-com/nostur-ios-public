//
//  ProfileLikesView.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/01/2023.
//

import SwiftUI
import CoreData


struct ProfileLikesView: View {
    
//    @EnvironmentObject var cm:ConnectionManager
    var cm:SocketPool = .shared
    var pubkey:String
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Event.created_at, order: .reverse)],
        predicate: NSPredicate(format: "kind == 7"),
        animation: .none)
    var reactions: FetchedResults<Event>
    
    
    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "FALSEPREDICATE"),
        animation: .none)
    var reactionsTo: FetchedResults<Event>
    
    init(pubkey: String) {
        self.pubkey = pubkey
        _reactions = FetchRequest(
            sortDescriptors: [SortDescriptor(\Event.created_at, order: .reverse)],
            predicate: NSPredicate(format: "pubkey == %@ AND kind == 7", pubkey)
        )
    }
    
    
    var body: some View {
        
        VStack {
            LazyVStack {
                ForEach(reactionsTo, id:\Event.id) { event in
                    NoteRowView(event:event)
                }
            }
        }
        .onAppear {
            print("🟢 ProfileLikesView.onAppear always REQ.7: \(pubkey)")
            cm.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getAuthorReactions(pubkey: pubkey)))
            
            if (reactions.count > 0) {
                let eventIds = reactions.map { event in
                    return TagsHelpers(event.oldTags() ?? [])
                        .reactingToEventId() ?? nil
                }.filter { id in
                    return id != nil
                }
                reactionsTo.nsPredicate = NSPredicate(format: "id IN %@ AND kind == 1", eventIds)
            }
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
