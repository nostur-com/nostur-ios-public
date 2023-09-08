//
//  EditList.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/04/2023.
//

import SwiftUI

struct EditNosturList: View {
    @EnvironmentObject var theme:Theme
    @ObservedObject var list:NosturList
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.dismiss) var dismiss
    
    @State var confirmDeleteShown = false
    @State var contactToRemove:Contact? = nil
    @State var addContactsSheetShown = false
    @State var editList:NosturList? = nil
    @State var selectedContacts:Set<Contact> = []
    
    var body: some View {
        List(list.contacts_) { contact in
            ContactSearchResultRow(contact: contact)
                .padding()
                .onTapGesture { navigateTo(contact) }
                .listRowInsets(EdgeInsets())
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        list.removeFromContacts(contact)
                        DataProvider.shared().save()
                        sendNotification(.listPubkeysChanged, NewPubkeysForList(subscriptionId: list.subscriptionId, pubkeys: Set(list.contacts_.map { $0.pubkey })))
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    
                }
                .listRowBackground(theme.background)
        }
        .scrollContentBackground(.hidden)
        .background(theme.listBackground)
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
            NavigationStack {
                EditListTitleSheet(list: list)
            }
            .presentationBackground(theme.background)
        })
        .sheet(isPresented: $addContactsSheetShown) {
            NavigationStack {
                ContactsSearch(followingPubkeys:NosturState.shared.followingPublicKeys,
                               prompt: "Search", onSelectContacts: { selectedContacts in
                    list.contacts_.append(contentsOf: selectedContacts)
                    addContactsSheetShown = false
                    DataProvider.shared().save()
                    sendNotification(.listPubkeysChanged, NewPubkeysForList(subscriptionId: list.subscriptionId, pubkeys: Set(list.contacts_.map { $0.pubkey })))
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
            .presentationBackground(theme.background)
        }
    }
}

struct EditList_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadNosturLists()
        }) {
            NavigationStack {
                if let list = PreviewFetcher.fetchList() {
                    EditNosturList(list: list)
                    .withNavigationDestinations()
                }
            }
        }
    }
}
