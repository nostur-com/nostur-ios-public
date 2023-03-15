//
//  TestTimeline.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/01/2023.
//

import SwiftUI


// NOTES ON USER PROFILE SCREEN
struct ProfileNotesView: View {
    
    let vTransformer:VTransformer
    let sp:SocketPool = .shared
    let pubkey:String
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Event.created_at, order: .reverse)],
        predicate: NSPredicate(format: "kind IN {1,6}"),
        animation: .none)
    var events: FetchedResults<Event>
    
    var vPosts:[VPost] {
        events.map(vTransformer.eventToVPost)
    }
    
    init(pubkey: String) {
        self.pubkey = pubkey
        self.vTransformer = VTransformer(pubkey: pubkey)
        _events = FetchRequest(
            sortDescriptors: [SortDescriptor(\Event.created_at, order: .reverse)],
            predicate: NSPredicate(format: "pubkey == %@ AND kind IN {1,6}", pubkey)
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
                    ForEach(vPosts) { vPost in
                        NoteRow(vPost: vPost)
                        Divider()
                    }
                }
            }
        }.onAppear {
            print("🟢 ProfileNotesView.onAppear always REQ.1: \(pubkey)")
            sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getAuthorNotes(pubkey: pubkey)))
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
