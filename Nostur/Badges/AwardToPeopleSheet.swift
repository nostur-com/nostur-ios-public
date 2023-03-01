//
//  AwardToPeopleSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/03/2023.
//

import SwiftUI

struct AwardToPeopleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var selectedContacts:[Contact] = []
    var onFinish:([Contact]) -> Void
    
    var body: some View {
        NavigationStack {
            VStack {
                ScrollView {
                    ContactsSearch(onSelected: { selectedContact in
                        if selectedContacts.firstIndex(of: selectedContact) == nil {
                            selectedContacts.insert(selectedContact, at:0)
                        }
                    }, prompt: "Search contact")
                }
                ScrollView {
                    Text("Selected to receive badge: \(selectedContacts.count)")
                    ForEach(selectedContacts) { contact in
                        ContactSearchResultRow(contact: contact) {
                            selectedContacts.removeAll(where: { $0.pubkey == contact.pubkey })
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: {
                        dismiss()
                    }, label: {
                        Text("Cancel")
                    })
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        onFinish(selectedContacts)
                        dismiss()
                    }, label: {
                        Text("Done")
                    })
                }
            }
            .navigationTitle("Award badges to")
        }
    }
}

struct AwardToPeopleSheet_Previews: PreviewProvider {
    static var previews: some View {
        AwardToPeopleSheet(onFinish: { contacts in
            
        })
            .withPreviewEnvironment()
    }
}
