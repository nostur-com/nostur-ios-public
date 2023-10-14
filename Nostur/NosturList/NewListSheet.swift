//
//  NewListSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/04/2023.
//

import SwiftUI

struct NewListSheet: View {
    
    @Environment(\.dismiss) private var dismiss
    @State private var newList:NosturList?
    @State private var title = ""
    @State private var wotEnabled = true
    @State private var addContactsSheetShown = false
    @State private var selectedContacts:Set<Contact> = []
    @State private var contactSelectionVisible = false
    @State private var feedType:LVM.ListType = .pubkeys
    @State private var selectedRelays:Set<Relay> = []
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Relay.createdAt, order: .forward)],
        animation: .default)
    private var relays: FetchedResults<Relay>
    
    private var formIsValid:Bool {
        guard !title.isEmpty else { return false }
        if feedType == .relays && selectedRelays.isEmpty { return false }
        return true
    }
    
    var body: some View {
        List {
            Section(header: Text("Title", comment: "Header for entering title of a feed")) {
                TextField(String(localized:"Title of your feed", comment:"Placeholder for input field to enter title of a feed"), text: $title)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }
            
            Section(header: Text("Feed settings", comment: "Header for a feed setting")) {
                Picker("Feed content", selection: $feedType) {
                    Text("Posts from contacts")
                        .tag(LVM.ListType.pubkeys)
                    Text("Posts from relays")
                        .tag(LVM.ListType.relays)
                }
            }
            
            if feedType == .relays {
                Section(header: Text("Relay selection", comment: "Header for a feed setting")) {
                    ForEach(relays, id:\.objectID) { relay in
                            HStack {
                                Image(systemName: selectedRelays.contains(relay) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedRelays.contains(relay) ? Color.primary : Color.secondary)
                                Text(relay.url ?? "(Missing relay address)")
                            }
                            .id(relay.objectID)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedRelays.contains(relay) {
                                    selectedRelays.remove(relay)
                                }
                                else {
                                    selectedRelays.insert(relay)
                                }
                            }
                        }
                }
                
                Section(header: Text("Spam filter", comment: "Header for a feed setting")) {
                    Toggle(isOn: $wotEnabled) {
                        Text("Enable Web of Trust filter")
                        Text("Only show content from your follows or follows-follows")
                    }
                }
            }
            
        }
        .navigationTitle(String(localized:"New feed", comment:"Navigation title for screen to create a new feed"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.navigationStack)
        .navigationDestination(isPresented: $contactSelectionVisible) {
            ContactsSearch(followingPubkeys: follows(),
                           prompt: String(localized:"Search contacts", comment:"Placeholder in search contacts input field"), onSelectContacts: { selectedContacts in
                guard let newList = newList else { return }
                newList.contacts_.append(contentsOf: selectedContacts)
                contactSelectionVisible = false
                DataProvider.shared().save()
                sendNotification(.listPubkeysChanged, NewPubkeysForList(subscriptionId: newList.subscriptionId, pubkeys: Set(newList.contacts_.map { $0.pubkey })))
                dismiss()
            })
            .equatable()
            .navigationTitle(String(localized:"Add contacts to feed", comment:"Navigation title for screen where you can add contacts to a feed"))
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Next") {
                    newList = NosturList(context: DataProvider.shared().viewContext)
                    newList?.id = UUID()
                    newList?.name = title
                    newList?.showAsTab = true
                    
                    if feedType == .relays, let newList = newList {
                        newList.relays = selectedRelays
                        newList.type = feedType.rawValue
                        newList.wotEnabled = wotEnabled
                        DataProvider.shared().save()
                        sendNotification(.listRelaysChanged, NewRelaysForList(subscriptionId: newList.subscriptionId, relays: selectedRelays, wotEnabled: wotEnabled))
                        dismiss()
                    }
                    else {
                        contactSelectionVisible = true
                    }
                }
                .disabled(!formIsValid)
            }
        }
    }
}

struct NewListSheet_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadNosturLists()
            pe.loadRelays()
        }) {
            NavigationStack {
                NewListSheet()
            }
        }
    }
}
