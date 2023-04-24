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
    
    @StateObject var debounceObject = DebounceObject()

    let followingPubkeys:Set<String>
    let sp:SocketPool = .shared
    var prompt:LocalizedStringKey
    var onSelectContacts:((Set<Contact>) -> Void)?
    
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
                TextField(text: $debounceObject.text, prompt: Text("Search").foregroundColor(Color.secondary), label: {
                    Text("Search")
                })
                .padding(5)
                .padding(.leading, 25)
                .background {
                    Color("ListBackground").opacity(0.5)
                        .overlay(alignment:.leading) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(Color.secondary)
                                .padding(.leading, 5)
                        }
                }
                .overlay(alignment:.trailing) {
                    if debounceObject.text != "" {
                        Image(systemName: "multiply.circle.fill")
                            .foregroundColor(Color.secondary)
                            .padding(.trailing, 5)
                            .onTapGesture {
                                debounceObject.text = ""
                            }
                    }
                }
                .cornerRadius(8.0)

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
                            ContactSearchResultRow(contact: contact) {
                                if selectedContacts.contains(contact) {
                                    selectedContacts.remove(contact)
                                }
                                else {
                                    selectedContacts.insert(contact)
                                }
                            }
                        }
                        Divider()
                    }
                }
            }
            .padding(10)
        }
        .onChange(of: debounceObject.debouncedText) { searchString in

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
                Button(selectedContacts.count > 0 ? "Add (\(selectedContacts.count))" : "Done") {
                    guard let onSelectContacts = onSelectContacts else { return }
                    onSelectContacts(selectedContacts)
                }
            }
        }
    }
}

//struct ContactsSearch: View {
//
//    @Environment(\.dismiss) var dismiss
//    @StateObject var debounceObject = DebounceObject()
//
//    let followingPubkeys:Set<String>
//    let sp:SocketPool = .shared
//    var prompt:LocalizedStringKey
//
//    @FetchRequest(
//        sortDescriptors: [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)],
//        predicate: NSPredicate(value: false),
//        animation: .none)
//    var contacts:FetchedResults<Contact>
//
//    var filteredContacts:[Contact] {
//        contacts
//            .filter {
//                contactFilter == "All" || followingPubkeys.contains($0.pubkey)
//            }
//    }
//
//    @State var searching = false
//    @Binding var selectedContacts:Set<Contact>
//    @State var contactFilter = "All"
//
//    var body: some View {
//        let _ = Self._printChanges()
//        Text("wuuu")
////        VStack {
////            Group {
////                TextField(text: $debounceObject.text, prompt: Text("Search").foregroundColor(Color.secondary), label: {
////                    Text("Search")
////                })
////                .padding(5)
////                .padding(.leading, 25)
////                .background {
////                    Color("ListBackground").opacity(0.5)
////                        .overlay(alignment:.leading) {
////                            Image(systemName: "magnifyingglass")
////                                .foregroundColor(Color.secondary)
////                                .padding(.leading, 5)
////                        }
////                }
////                .overlay(alignment:.trailing) {
////                    if debounceObject.text != "" {
////                        Image(systemName: "multiply.circle.fill")
////                            .foregroundColor(Color.secondary)
////                            .padding(.trailing, 5)
////                            .onTapGesture {
////                                debounceObject.text = ""
////                            }
////                    }
////                }
////                .cornerRadius(8.0)
////
////                if (followingPubkeys.count > 1 || 1 == 1) {
////                    Picker("Filter contacts", selection: $contactFilter) {
////                        Text("Following").tag("Following")
////                        Text("All").tag("All")
////                    }
////                    .pickerStyle(.segmented)
////                }
////            }
////            .padding(.horizontal)
////            ScrollView {
////                if (filteredContacts.count == 0 && searching) {
////                    ProgressView()
////                }
////                ForEach(filteredContacts) { contact in
////                    HStack(alignment:.top) {
////                        Button {
////                            if selectedContacts.contains(contact) {
////                                selectedContacts.remove(contact)
////                            }
////                            else {
////                                selectedContacts.insert(contact)
////                            }
////                        } label: {
////                            if selectedContacts.contains(contact) {
////                                Image(systemName:  "checkmark.circle.fill")
////                                    .padding(.top, 18)
////                            }
////                            else {
////                                Image(systemName:  "circle")
////                                    .foregroundColor(Color.secondary)
////                                    .padding(.top, 18)
////                            }
////                        }
////                        ContactSearchResultRow(contact: contact)
////                    }
////                    Divider()
////                }
////            }
////            .padding(10)
////        }
////        .onChange(of: debounceObject.debouncedText) { searchString in
////
////            let searchTrimmed = searchString.trimmingCharacters(in: .whitespacesAndNewlines)
////
////            guard searchTrimmed.count > 1 else { return }
////
////            // try npub
////            if (searchTrimmed.prefix(5) == "npub1") {
////                do {
////                    searching = true
////                    let key = try NIP19(displayString: searchTrimmed)
////                    contacts.nsPredicate = NSPredicate(format: "pubkey = %@", key.hexString)
////                    sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: key.hexString)))
////                }
////                catch {
////                    print("npub1 search fail \(error)")
////                    searching = false
////                }
////            }
////            // search in names/usernames
////            else {
////                searching = false
////                contacts.nsPredicate = NSPredicate(format: "name CONTAINS[cd] %@ OR display_name CONTAINS[cd] %@", searchTrimmed, searchTrimmed)
////            }
////        }
////        .toolbar {
////            ToolbarItem(placement: .primaryAction) {
////                Button("Add") { dismiss() }
////            }
////        }
//    }
//
//    private static func _printChanges() {
//            dump("ContactsSearch: \(#function) - before")
//            defer {
//                dump("ContactsSearch: \(#function) - after")
//            }
//        }
//}

struct ContactsSearch_Previews: PreviewProvider {
    
    @State static var selectedContacts:Set<Contact> = []
    static var previews: some View {
        NavigationStack {
            ContactsSearch(followingPubkeys: NosturState.shared.followingPublicKeys,
                           prompt: "Search")
                .withPreviewEnvironment()
        }
    }
}
