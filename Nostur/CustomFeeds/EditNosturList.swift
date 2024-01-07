//
//  EditList.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/04/2023.
//

import SwiftUI
import NavigationBackport

struct EditNosturList: View {
    @ObservedObject public var list:CloudFeed
    
    @EnvironmentObject private var themes:Themes
    @Environment(\.dismiss) private var dismiss
    
    @State private var confirmDeleteShown = false
    @State private var contactToRemove:Contact? = nil
    @State private var addContactsSheetShown = false
    @State private var editList:CloudFeed? = nil
    @State private var selectedContacts:Set<Contact> = []
    
    var body: some View {
        List(list.contacts_) { contact in
            ContactSearchResultRow(contact: contact)
                .padding()
                .onTapGesture { navigateTo(ContactPath(key: contact.pubkey)) }
                .listRowInsets(EdgeInsets())
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        list.contactPubkeys.remove(contact.pubkey)
                        DataProvider.shared().save()
                        sendNotification(.listPubkeysChanged, NewPubkeysForList(subscriptionId: list.subscriptionId, pubkeys: list.contactPubkeys))
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    
                }
                .listRowBackground(themes.theme.background)
        }
        .scrollContentBackgroundCompat(.hidden)
        .background(themes.theme.listBackground)
        .listStyle(.plain)
        .navigationTitle("\(list.name ?? "feed")")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack {
                    Text(verbatim: "\(list.name ?? "feed")")
                    Button { editList = list } label: { Image(systemName: "square.and.pencil") }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    addContactsSheetShown = true
                } label: {
                    Label("", systemImage: "plus")
                }

            }
        }
        .sheet(item: $editList, content: { list in
            NBNavigationStack {
                EditListTitleSheet(list: list)
            }
            .presentationBackgroundCompat(themes.theme.background)
        })
        .sheet(isPresented: $addContactsSheetShown) {
            NBNavigationStack {
                ContactsSearch(followingPubkeys: follows(),
                               prompt: "Search", onSelectContacts: { selectedContacts in
                    list.contactPubkeys.formUnion(Set(selectedContacts.map { $0.pubkey }))
                    addContactsSheetShown = false
                    DataProvider.shared().save()
                    sendNotification(.listPubkeysChanged, NewPubkeysForList(subscriptionId: list.subscriptionId, pubkeys: list.contactPubkeys))
                })
                .equatable()
                .navigationTitle(String(localized:"Add contacts", comment:"Navigation title of sheet to add contacts to feed"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            addContactsSheetShown = false
                        }
                    }
                }
            }
            .presentationBackgroundCompat(themes.theme.background)
        }
    }
}

struct EditList_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadNosturLists()
        }) {
            NBNavigationStack {
                if let list = PreviewFetcher.fetchList() {
                    EditNosturList(list: list)
                    .withNavigationDestinations()
                }
            }
        }
    }
}
