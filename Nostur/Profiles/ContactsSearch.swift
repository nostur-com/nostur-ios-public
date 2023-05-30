//
//  ContactsSearch.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/03/2023.
//
import SwiftUI
import Combine

struct ContactsSearch: View, Equatable {
    static func == (lhs: ContactsSearch, rhs: ContactsSearch) -> Bool {
        lhs.followingPubkeys == rhs.followingPubkeys
    }
    
    @Environment(\.dismiss) var dismiss

    @State var searchText = ""

    let followingPubkeys:Set<String>
    let sp:SocketPool = .shared
    var prompt:String
    var onSelectContacts:((Set<Contact>) -> Void)?
    var onSelectContact:((Contact) -> Void)?
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)],
        predicate: NSPredicate(value: false),
        animation: .none)
    var contacts:FetchedResults<Contact>

    var filteredContacts:[Contact] {
        contacts
            .filter {
                contactFilter == "All" || followingPubkeys.contains($0.pubkey)
            }
    }
    
    @State var searching = false
    @State var selectedContacts:Set<Contact> = []
    @State var contactFilter = "All"
    
    var body: some View {
        let _ = Self._printChanges()
        VStack {
            Group {
                SearchBox(prompt: prompt, text: $searchText)

                if (followingPubkeys.count > 1 || 1 == 1) {
                    Picker("Filter contacts", selection: $contactFilter) {
                        Text("Following").tag("Following")
                        Text("All").tag("All")
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding(.horizontal)
            ScrollView {
                if (filteredContacts.count == 0 && searching) {
                    ProgressView()
                }
                LazyVStack {
                    ForEach(filteredContacts) { contact in
                        HStack(alignment:.top) {
                            if onSelectContacts != nil {
                                Button {
                                    if selectedContacts.contains(contact) {
                                        selectedContacts.remove(contact)
                                    }
                                    else {
                                        selectedContacts.insert(contact)
                                    }
                                } label: {
                                    if selectedContacts.contains(contact) {
                                        Image(systemName:  "checkmark.circle.fill")
                                            .padding(.top, 18)
                                    }
                                    else {
                                        Image(systemName:  "circle")
                                            .foregroundColor(Color.secondary)
                                            .padding(.top, 18)
                                    }
                                }
                            }
                            ContactSearchResultRow(contact: contact) {
                                if let onSelectContact {
                                    onSelectContact(contact)
                                }
                                else {
                                    if selectedContacts.contains(contact) {
                                        selectedContacts.remove(contact)
                                    }
                                    else {
                                        selectedContacts.insert(contact)
                                    }
                                }
                            }
                        }
                        Divider()
                    }
                }
            }
            .padding(10)
        }
        .onChange(of: searchText) { searchString in

            let searchTrimmed = searchString.trimmingCharacters(in: .whitespacesAndNewlines)

            guard searchTrimmed.count > 1 else { return }

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if onSelectContacts != nil {
                    Button(selectedContacts.count > 0 ? "Add (\(selectedContacts.count))" : "Done") {
                        guard let onSelectContacts = onSelectContacts else { return }
                        onSelectContacts(selectedContacts)
                    }
                }
                else {
                    EmptyView()
                }
            }
        }
    }
}

struct ContactsSearch_Previews: PreviewProvider {
    
    @State static var selectedContacts:Set<Contact> = []
    static var previews: some View {
        NavigationStack {
            ContactsSearch(followingPubkeys: NosturState.shared.followingPublicKeys,
                           prompt: "Search")
        }
        .withPreviewEnvironment({ pe in
            pe.loadContacts()
        })
    }
}
