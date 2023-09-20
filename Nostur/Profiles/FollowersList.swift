//
//  FollowersList.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/02/2023.
//

import SwiftUI

struct FollowersList: View {
    
    var pubkey:String // Pubkey of whose followers to view
    let sp:SocketPool = .shared
    
    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(value: false), animation: .none)
    var clEvents:FetchedResults<Event>
    
    init(pubkey: String) {
        self.pubkey = pubkey
        
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = []
        // Not parsing and filtering tags, but searching for string. Ugly hack but works fast
        fr.predicate = NSPredicate(format: "kind == 3 AND tagsSerialized CONTAINS %@", serializedP(pubkey))
        
        
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
    
    var clEventsPerPubkey:[Event] {
        clEvents.uniqued(on: { $0.pubkey })
    }
    
    var clEventsFollowingPubkeyWithContact:[Event] {
        get { clEventsPerPubkey
            .filter { $0.contact != nil } }
    }
    
    var clEventsFollowingPubkeyMissingContact:[Event] {
        get { clEventsPerPubkey
            .filter { $0.contact == nil } }
    }
    
    @State var rechecking = false
    
    var body: some View {
        VStack {
            HStack {
                Text("Total: \(clEventsPerPubkey.count)")
                if !rechecking {
                    Image(systemName:"arrow.clockwise.circle.fill")
                        .onTapGesture {
                            req(RM.getFollowers(pubkey: pubkey))
                            rechecking = true
                        }
                        .help("Recheck")
                }
            }
            LazyVStack {
                ForEach(clEventsFollowingPubkeyWithContact) { event in
                    ProfileRow(contact: event.contact!)
                        .frame(height: 120)
                    Divider()
                }
                ForEach(clEventsFollowingPubkeyMissingContact, id:\.self) { event in
                    ProfileRowMissing(pubkey: event.pubkey)
                        .frame(height: 120)
                    Divider()
                }
            }
        }
        .onAppear {
            let missing = clEventsFollowingPubkeyMissingContact.map { $0.pubkey }
            guard !missing.isEmpty else { return }
            L.og.info("Fetching \(missing.count) missing contacts")
            QueuedFetcher.shared.enqueue(pTags: missing)
            
            if pubkey == NRState.shared.activeAccountPublicKey {
                FollowerNotifier.shared.checkForUpdatedContactList()
            }
            else {
                req(RM.getFollowers(pubkey: pubkey))
            }
        }
        .onDisappear {
            let missing = clEventsFollowingPubkeyMissingContact.map { $0.pubkey }
            guard !missing.isEmpty else { return }
            QueuedFetcher.shared.dequeue(pTags: missing)
        }
    }
    
}

struct FollowersList_Previews: PreviewProvider {
  
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadContactLists()
        }) {
            VStack {
                
                let pubkey = "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240"
                
                FollowersList(pubkey: pubkey)
            }
        }
    }
}
