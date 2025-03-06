//
//  NewDM.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/03/2023.
//

import SwiftUI

struct NewDM: View {
    
    @Binding var showingNewDM: Bool
    @State private  var toPubkey: String?
    @State private  var toContact: NRContact?
    @State private  var message: String = ""
    @Binding var tab: String
    @State private var preloaded = false
    
    var body: some View {
        VStack {
            if toPubkey != nil {
                NewDMComposer(toPubkey: $toPubkey, toContact: $toContact, message: $message, showingNewDM: $showingNewDM, tab: $tab, preloaded: preloaded)
            }
            else {
                ContactsSearch(followingPubkeys:follows(),
                               prompt: "Search contact", onSelectContact: { selectedContact in
                    
                    let selectedContactPubkey = selectedContact.pubkey
                    bg().perform {
                        guard let bgContact = Contact.fetchByPubkey(selectedContactPubkey, context: bg()) else { return }
                        let nrSelectedContact = NRContact(pubkey: bgContact.pubkey, contact: bgContact)
                        Task { @MainActor in
                            toContact = nrSelectedContact
                            toPubkey = nrSelectedContact.pubkey
                        }
                    }
                })
                .navigationTitle(String(localized:"Send DM to", comment:"Navigation title for screen to select a contact to send a Direct Message to"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingNewDM = false
                        }
                    }
                }
            }
        }
        .onReceive(receiveNotification(.preloadNewDMInfo)) { notification in
            let preloadNewDMInfo = notification.object as! (String, NRContact)
            toContact = preloadNewDMInfo.1
            toPubkey = preloadNewDMInfo.0
            preloaded = true
        }
    }
}

import NavigationBackport

struct NewDM_Previews: PreviewProvider {
    @State static var showingNewDM = true
    @State static var tab = "Accepted"
    static var previews: some View {
        PreviewContainer({ pe in pe.loadDMs() }) {
            NBNavigationStack {
                NewDM(showingNewDM: $showingNewDM, tab: $tab)
            }
        }
    }
}
