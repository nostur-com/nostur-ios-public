//
//  RestoreContactsSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/04/2023.
//

import SwiftUI

struct RestoreContactsSheet: View {
    
    let removed:RemovedPubkeys
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack {
            Text("It looks like \(removed.pubkeys.count) contacts were removed from your following list, perhaps from another nostr app")
            HStack {
                Button("Restore") { }
                Button("OK") { }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    // TODO: Remove contacts
                    dismiss()
                }
            }
        }
    }
}

struct RestoreContactsSheet_Previews: PreviewProvider {
    static var previews: some View {
        RestoreContactsSheet(removed: RemovedPubkeys(pubkeys: Set(arrayLiteral: "dsfddsfddf", "dsfsdfdsfddf", "dsfddffdfsd")))
    }
}
