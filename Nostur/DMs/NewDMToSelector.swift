//
//  NewDMToSelector.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/03/2023.
//

import SwiftUI

struct NewDMToSelector: View {
    @Environment(\.dismiss) var dismiss
    @StateObject var debounceObject = DebounceObject()
    @Binding var toPubkey:String?
    @Binding var toContact:Contact?
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)],
        predicate: NSPredicate(value: false),
        animation: .none)
    var contacts:FetchedResults<Contact>
    
    var body: some View {
        ScrollView {
            if isValidNPub(debounceObject.debouncedText) && contacts.isEmpty {
                Button("Send to: \(debounceObject.debouncedText)") {
                    toPubkey = try! NIP19(displayString: debounceObject.debouncedText).hexString
                }
                .buttonStyle(.bordered)
            }
            LazyVStack {
                ForEach(contacts.prefix(150)) { contact in
                    ContactSearchResultRow(contact: contact) {
                        toContact = contact
                        toPubkey = contact.pubkey
                        contacts.nsPredicate = NSPredicate(value: false)
                    }
                    Divider()
                }
            }
            .padding()
        }
        .searchable(text: $debounceObject.text, placement: .navigationBarDrawer(displayMode: .always), prompt: String(localized: "Search contact", comment: "Placeholder in contact search field"))
        .navigationTitle(String(localized: "New direct message", comment: "Navigation title for a new Direct Message"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) {
                    dismiss()
                } label: {
                    Text("Cancel")
                }
                
            }
        }
        .onChange(of: debounceObject.debouncedText) { searchString in
            let searchTrimmed = searchString.trimmingCharacters(in: .whitespacesAndNewlines)
            contacts.nsPredicate = NSPredicate(format: "name CONTAINS[cd] %@ OR display_name CONTAINS[cd] %@", searchTrimmed, searchTrimmed)
        }
    }
    
    func isValidNPub(_ text:String) -> Bool {
        let nostr = text.matchingStrings(regex: "^(npub1)([023456789acdefghjklmnpqrstuvwxyz]{58})$")
        return (nostr.count == 1 && nostr[0].count == 3)
    }
}

import NavigationBackport

struct NewDMToSelector_Previews: PreviewProvider {
    @State static var toPubkey:String? = ""
    @State static var toContact:Contact?
    
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadDMs()
        }) {
            NBNavigationStack {
                NewDMToSelector(toPubkey: $toPubkey, toContact: $toContact)
            }
        }
    }
}
