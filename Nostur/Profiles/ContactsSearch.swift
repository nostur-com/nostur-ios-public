//
//  ContactsSearch.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/03/2023.
//
import SwiftUI
import Combine

struct ContactsSearch: View {
    
    @StateObject var debounceObject = DebounceObject()

    var onSelected:((Contact) -> Void)?
    var sp:SocketPool = .shared
    var prompt:LocalizedStringKey
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)],
        predicate: NSPredicate(value: false),
        animation: .none)
    var contacts:FetchedResults<Contact>
    
    @State var searching = false
    
    var body: some View {
        let _ = Self._printChanges()
        ScrollView {
            if (contacts.count == 0 && searching) {
                ProgressView()
            }
            ForEach(contacts) { contact in
                ContactSearchResultRow(contact: contact) {
                    if onSelected != nil {
                        self.onSelected!(contact)
                    }
                    searching = false
                    debounceObject.text = ""
                    contacts.nsPredicate = NSPredicate(value: false)

                }
                Divider()
            }
        }
        .padding(10)
        .searchable(text: $debounceObject.text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
        .onChange(of: debounceObject.debouncedText) { searchString in
            
            let searchTrimmed = searchString.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // try npub
            if (searchTrimmed.prefix(5) == "npub1") {
                do {
                    searching = true
                    let key = try NIP19(displayString: searchTrimmed)
                    contacts.nsPredicate = NSPredicate(format: "pubkey = %@", key.hexString)
                    sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: key.hexString)))
                }
                catch {
                    print("npub1 search fail \(error)")
                    searching = false
                }
            }
            // search in names/usernames
            else {
                searching = false
                contacts.nsPredicate = NSPredicate(format: "name CONTAINS[cd] %@ OR display_name CONTAINS[cd] %@", searchTrimmed, searchTrimmed)
            }
        }
    }
}

struct ContactsSearch_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ContactsSearch(prompt: "Search")
                .withPreviewEnvironment()
        }
    }
}
