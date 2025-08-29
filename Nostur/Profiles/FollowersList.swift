//
//  FollowersList.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/02/2023.
//

import SwiftUI

// TODO: Remove @FetchRequest
struct FollowersList: View {
    @Environment(\.theme) private var theme
    public let pubkey: String // Pubkey of whose followers to view

    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(value: false), animation: .none)
    private var clEvents:FetchedResults<Event>
    
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
    
    private var clEventsPerPubkey: [Event] {
        clEvents.uniqued(on: { $0.pubkey })
    }
    
    private var clEventsFollowingPubkeyWithContact: [Event] {
        get { clEventsPerPubkey
            .filter { $0.contact != nil } }
    }
    
    private var clEventsFollowingPubkeyMissingContact: [Event] {
        get { clEventsPerPubkey
            .filter { $0.contact == nil } }
    }
    
    @State private var rechecking = false
    
    var body: some View {
        HStack {
            Spacer()
            Text("Total: \(clEventsPerPubkey.count)")
            if !rechecking {
                Image(systemName:"arrow.clockwise.circle.fill")
                    .onTapGesture {
                        req(RM.getFollowers(pubkey: pubkey))
                        rechecking = true
                    }
                    .help("Recheck")
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .onAppear {
            let missing = clEventsFollowingPubkeyMissingContact.map { $0.pubkey }
            guard !missing.isEmpty else { return }
            L.og.debug("Fetching \(missing.count) missing contacts")
            QueuedFetcher.shared.enqueue(pTags: missing)
            
            if pubkey == AccountsState.shared.activeAccountPublicKey {
                FollowerNotifier.shared.checkForUpdatedContactList(pubkey: pubkey)
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
        
        ForEach(clEventsFollowingPubkeyWithContact) { event in
            ProfileRow(contact: event.contact!)
                .frame(height: 120)
                .background(theme.listBackground)
                .overlay(alignment: .bottom) {
                    theme.background.frame(height: GUTTER)
                }
        }
        ForEach(clEventsFollowingPubkeyMissingContact, id:\.self) { event in
            ProfileRowMissing(pubkey: event.pubkey)
                .frame(height: 120)
                .background(theme.listBackground)
                .overlay(alignment: .bottom) {
                    theme.background.frame(height: GUTTER)
                }
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
