//
//  NewListSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/04/2023.
//

import SwiftUI
import CoreData
import NavigationBackport

struct NewContactsFeedSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    
    private var rootDismiss: (() -> Void)? = nil
    
    init(rootDismiss: (() -> Void)? = nil) {
        self.rootDismiss = rootDismiss
        
        let request: NSFetchRequest<Contact> = Contact.fetchRequest()
        request.predicate = NSPredicate(value: false)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)
         ]
        request.fetchLimit = 250

        _contacts = FetchRequest(fetchRequest: request)
    }
    
    @State private var title = ""
    @State private var wotEnabled = true
    @State private var selectedContacts: Set<Contact> = []
    
    @State private var feedType: ListType = .pubkeys

    @FetchRequest
    private var contacts: FetchedResults<Contact>
    
    private var filteredContacts: [Contact] {
        let wot = WebOfTrust.shared
        if WOT_FILTER_ENABLED() {
            return contacts
                .filter {
                    // normal following/all filter
                    contactFilter == "All" || followingPubkeys.contains($0.pubkey)
                }
                // WoT enabled, so put in-WoT before non-WoT
                .sorted(by: { wot.isAllowed($0.pubkey) && !wot.isAllowed($1.pubkey) })
                // Put following before non-following
                .sorted(by: { followingPubkeys.contains($0.pubkey) && !followingPubkeys.contains($1.pubkey) })
        }
        else {
            // WoT disabled, just normal following/all filter
            return contacts
                .filter {
                    contactFilter == "All" || followingPubkeys.contains($0.pubkey)
                }
                // Put following before non-following
                .sorted(by: { followingPubkeys.contains($0.pubkey) && !followingPubkeys.contains($1.pubkey) })
        }
    }
    
    private var formIsValid: Bool {
        guard !title.isEmpty && !selectedContacts.isEmpty else { return false }
        return true
    }
    
    @StateObject var searchContext = SearchContext()
    @State private var searching = false
    @State private var searchText = ""
    @State private var contactFilter = "All"
    @State private var followingPubkeys = Set<String>()
    
    var body: some View {
        NXForm {
            Section(header: Text("Title", comment: "Header for entering title of a feed")) {
                TextField(String(localized:"Title of your feed", comment:"Placeholder for input field to enter title of a feed"), text: $title)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }
            
            Section {
                SearchBox(prompt: "Search contacts to add", text: $searchContext.query)
                if (followingPubkeys.count > 1 || 1 == 1) {
                    Picker(String(localized:"Filter contacts", comment: "Label to filter contacts"), selection: $contactFilter) {
                        Text("Following", comment: "Menu choice to filter by Following").tag("Following")
                        Text("All", comment: "Menu choice to filter by All").tag("All")
                    }
                    .pickerStyle(.segmented)
                }
                
                if (filteredContacts.isEmpty && searching) {
                    ProgressView()
                }
                else {
                    ForEach(filteredContacts) { contact in
                        HStack {
                            Image(systemName: selectedContacts.contains(contact) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedContacts.contains(contact) ? Color.primary  : Color.secondary)
                            
                                                        
                            VStack {
                                ContactSearchResultRow(contact: contact) {
                                
                                }
                                LazyFollowedBy(pubkey: contact.pubkey, alignment: .trailing, minimal: true)
                            }
                            .allowsHitTesting(false)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedContacts.contains(contact) {
                                selectedContacts.remove(contact)
                            }
                            else {
                                selectedContacts.insert(contact)
                            }
                        }
                    }
                }
            } header: {
                Text("Select contacts", comment: "Section header for adding contacts to a feed")
            } footer: {
                if selectedContacts.count > 0 {
                    Text("\(selectedContacts.count) contacts selected")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .font(.footnote)
                        .foregroundColor(Color.gray)
                }
            }
            .listRowSeparator(.hidden, edges: .all)
            .listStyle(.plain)
            

        }

        .onAppear {
            followingPubkeys = follows()
        }
        
        .onChange(of: searchContext.debouncedQuery) { [oldValue = searchContext.debouncedQuery] newValue in
            guard oldValue != newValue else { return }
            search(newValue)
        }
        
        .navigationTitle(String(localized:"New feed from contacts", comment:"Navigation title for screen to create a new feed"))
        .navigationBarTitleDisplayMode(.inline)

        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Done") {
                    let newFeed = CloudFeed(context: DataProvider.shared().viewContext)
                    newFeed.id = UUID()
                    newFeed.name = title
                    newFeed.showAsTab = true
                    newFeed.createdAt = .now
                    newFeed.order = 0
                    newFeed.contactPubkeys = Set(selectedContacts.map { $0.pubkey })
                    newFeed.type = ListType.pubkeys.rawValue
                    viewContextSave()
                    rootDismiss?()
                    
                    // Change active tab to this new feed
                    UserDefaults.standard.setValue("Main", forKey: "selected_tab") // Main feed tab
                    UserDefaults.standard.setValue("List", forKey: "selected_subtab") // Select List
                    UserDefaults.standard.setValue(newFeed.subscriptionId, forKey: "selected_listId") // Which list
                }
                .disabled(!formIsValid)
            }
        }
    }
    
    func search(_ query: String) {
        let searchTrimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard searchTrimmed.count > 0 else {
            searching = false
            contacts.nsPredicate = NSPredicate(value: false)
            return
        }

        // try npub
        if (searchTrimmed.prefix(5) == "npub1") {
            do {
                searching = true
                let key = try NIP19(displayString: searchTrimmed)
                contacts.nsPredicate = NSPredicate(format: "pubkey = %@", key.hexString)
                req(RM.getUserMetadata(pubkey: key.hexString), relayType: .SEARCH)
            }
            catch {
                L.og.debug("npub1 search fail \(error)")
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

import NavigationBackport

#Preview {
    PreviewContainer({ pe in
        pe.loadContacts()
    }) {
        NBNavigationStack {
            NewContactsFeedSheet()
        }
    }
}

class SearchContext: ObservableObject {
    
    init() {
        $query
            .debounce(for: .seconds(0.15), scheduler: RunLoop.main)
            .assign(to: &$debouncedQuery)
    }
    
    @Published var query = ""
    @Published var debouncedQuery = ""
}

