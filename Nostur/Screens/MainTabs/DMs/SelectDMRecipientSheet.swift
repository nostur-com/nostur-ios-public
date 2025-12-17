//
//  NewDM.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/03/2023.
//

import SwiftUI

struct SelectDMRecipientSheet: View {
    @Environment(\.dismiss) private var dismiss
    // from account
    let accountPubkey: String
    var onSelect: (String) -> Void // String: pubkey
    
    var body: some View {
        ContactsSearch(followingPubkeys: account(by: accountPubkey)?.followingPubkeys ?? [],
                       prompt: "Search contact", onSelectContact: { selectedContact in
            Task { @MainActor in
                onSelect(selectedContact.pubkey)
                dismiss()
            }
        })
        .padding(.top, 10)
        .navigationTitle(String(localized:"Send DM to", comment:"Navigation title for screen to select a contact to send a Direct Message to"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", systemImage: "xmark") {
                    dismiss()
                }
            }
        }
    }
}
