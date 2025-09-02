//
//  NewListSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/04/2023.
//

import SwiftUI
import NavigationBackport

struct NewListSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var newList: CloudFeed?
    @State private var title = ""
    @State private var wotEnabled = true
    @State private var addContactsSheetShown = false
    @State private var selectedContacts: Set<Contact> = []
    @State private var contactSelectionVisible = false
    @State private var feedType: ListType = .pubkeys
    @State private var selectedRelays: Set<CloudRelay> = []
    
    private var selectedRelaysData: Set<RelayData> {
        Set(selectedRelays.map { $0.toStruct() })
    }
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\CloudRelay.createdAt_, order: .forward)],
        animation: .default)
    private var relays: FetchedResults<CloudRelay>
    
    private var formIsValid: Bool {
        guard !title.isEmpty else { return false }
        if feedType == .relays && selectedRelays.isEmpty { return false }
        return true
    }
    
    var body: some View {
        List {
            Group {
                Section(header: Text("Title", comment: "Header for entering title of a feed")) {
                    TextField(String(localized:"Title of your feed", comment:"Placeholder for input field to enter title of a feed"), text: $title)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                
                Section(header: Text("Feed settings", comment: "Header for a feed setting")) {
                    Picker("Feed content", selection: $feedType) {
                        Text("Posts from contacts")
                            .tag(ListType.pubkeys)
                        Text("Posts from relays")
                            .tag(ListType.relays)
                    }
                }

                if feedType == .relays {
                    Section(header: Text("Relay selection", comment: "Header for a feed setting")) {
                        ForEach(relays, id:\.objectID) { relay in
                                HStack {
                                    Image(systemName: selectedRelays.contains(relay) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedRelays.contains(relay) ? Color.primary : Color.secondary)
                                    Text(relay.url_ ?? "(Missing relay address)")
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
            .listRowBackground(theme.background)
        }
        .scrollContentBackgroundCompat(.hidden)
        .navigationTitle(String(localized:"New feed", comment:"Navigation title for screen to create a new feed"))
        .navigationBarTitleDisplayMode(.inline)
        .nbNavigationDestination(isPresented: $contactSelectionVisible) {
            ContactsSearch(followingPubkeys: follows(),
                           prompt: String(localized:"Search contacts", comment:"Placeholder in search contacts input field"), onSelectContacts: { selectedContacts in
                guard let newList = newList else { return }
                newList.contactPubkeys.formUnion(Set(selectedContacts.map { $0.pubkey }))
                contactSelectionVisible = false
                DataProvider.shared().save()
                sendNotification(.listPubkeysChanged, NewPubkeysForList(subscriptionId: newList.subscriptionId, pubkeys: newList.contactPubkeys))
                dismiss()
            })
            .equatable()
            .environment(\.theme, theme)
            .navigationTitle(String(localized:"Add contacts to feed", comment:"Navigation title for screen where you can add contacts to a feed"))
            .background(theme.listBackground)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Next") {
                    newList = CloudFeed(context: DataProvider.shared().viewContext)
                    newList?.id = UUID()
                    newList?.name = title
                    newList?.showAsTab = true
                    newList?.createdAt = .now
                    newList?.order = 0
                    
                    if feedType == .relays, let newList = newList {
                        newList.relays_ = selectedRelays
                        newList.type = feedType.rawValue
                        newList.wotEnabled = wotEnabled
                        DataProvider.shared().save()
                        sendNotification(.listRelaysChanged, NewRelaysForList(subscriptionId: newList.subscriptionId, relays: selectedRelaysData, wotEnabled: wotEnabled))
                        dismiss()
                    }
                    else {
                        contactSelectionVisible = true
                        newList?.type = feedType.rawValue
                    }
                }
                .disabled(!formIsValid)
            }
        }
    }
}

import NavigationBackport

struct NewListSheet_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadCloudFeeds()
            pe.loadRelays()
        }) {
            NBNavigationStack {
                NewListSheet()
            }
        }
    }
}
