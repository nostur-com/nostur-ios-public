//
//  NewDM.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/03/2023.
//

import SwiftUI

struct NewDM: View {
    
    @Binding var showingNewDM:Bool
    @State var toPubkey:String?
    @State var toContact:Contact?
    @State var message:String = ""
    @Binding var tab:String
    
    var body: some View {
        VStack {
            if toPubkey != nil {
                NewDMComposer(toPubkey: $toPubkey, toContact: $toContact, message: $message, showingNewDM: $showingNewDM, tab: $tab)
            }
            else {
                ContactsSearch(followingPubkeys:NosturState.shared.followingPublicKeys,
                               prompt: "Search contact", onSelectContact: { selectedContact in
                    
                    toContact = selectedContact
                    toPubkey = selectedContact.pubkey
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
    }
}

struct NewDM_Previews: PreviewProvider {
    @State static var showingNewDM = true
    @State static var tab = "Accepted"
    static var previews: some View {
        PreviewContainer({ pe in pe.loadDMs() }) {
            NavigationStack {
                NewDM(showingNewDM: $showingNewDM, tab: $tab)
            }
        }
    }
}
