//
//  FollowersList.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/02/2023.
//

import SwiftUI

struct FollowersList: View {
    
    var pubkey:String // Pubkey of whose followers to view
    @EnvironmentObject var sp:SocketPool
    
    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(value: false), animation: .none)
    var clEvents:FetchedResults<Event>
    
    init(pubkey: String) {
        self.pubkey = pubkey
        
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = []
        // Not parsing and filtering tags, but searching for string. Ugly hack but works fast
        fr.predicate = NSPredicate(format: "kind == 3 AND tagsSerialized CONTAINS %@", pubkey)
        
        
        _clEvents = FetchRequest(fetchRequest: fr)
    }
    
    // CLEAN PARSING AND FILTERING OF TAGS, BUT IS SLOW:
//    var clEventsFollowingPubkey:[Event] {
//        get {
//            clEvents.filter { // check for a "p" tag with your public key
//                ($0.tags() ?? []).filter { $0.type == "p" && $0.otherInformation[0] == pubkey }.count > 0
//            }
//        }
//    }
    
    var clEventsFollowingPubkeyWithContact:[Event] {
        get { clEvents.filter { $0.contact != nil } }
    }
    
    var clEventsFollowingPubkeyMissingContact:[Event] {
        get { clEvents.filter { $0.contact == nil } }
    }
    
    var body: some View {
        VStack {
            Text("Total: \(clEvents.count)")
            if (clEvents.count > 75) {
                LazyVStack {
                    ForEach(clEventsFollowingPubkeyWithContact) { event in
                        ProfileRow(contact: event.contact!)
                            .frame(height: 120)
                        Divider()
                    }
                }
            }
            else {
                ForEach(clEventsFollowingPubkeyWithContact) { event in
                    ProfileRow(contact: event.contact!)
                    Divider()
                }
            }
            
            // TODO: ForEach for Fake ProfileRow view for pubkeys not in Contact
            
            VStack {
                Text("Missing: \(clEventsFollowingPubkeyMissingContact.count)")
                ForEach(clEventsFollowingPubkeyMissingContact) { event in
                    Text("Missing: \(event.pubkey!)")
                }
            }
            
        }.onAppear {
            // fetch missing
            // fetch pubkeys not in [contacts.pubkey]
            
            let missing = clEventsFollowingPubkeyMissingContact.map { $0.pubkey! }
            
            sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: missing)))
        }
    }
    
}

struct FollowersList_Previews: PreviewProvider {
  
    static var previews: some View {
        VStack {
            
            let pubkey = "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240"
            
            FollowersList(pubkey: pubkey)
                .withPreviewEnvironment()
            
        }
    }
}
