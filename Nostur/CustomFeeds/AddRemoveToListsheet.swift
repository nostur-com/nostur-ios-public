//
//  AddRemoveToListsheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/04/2023.
//

import SwiftUI
import Combine
import NavigationBackport

struct AddRemoveToListsheet: View {
    
    @Environment(\.dismiss) var dismiss
    @ObservedObject var contact: Contact
    
    // only contact lists, not relay lists
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CloudFeed.createdAt, ascending: false)],
        predicate: NSPredicate(format: "type != %@ OR type == nil", LVM.ListType.relays.rawValue),
        animation: .none)
    var lists:FetchedResults<CloudFeed>
    
    var body: some View {
        NBNavigationStack {
            ScrollView {
                if !lists.isEmpty {
                    LazyVStack {
                        ForEach(lists) { list in
                            HStack(spacing: 10) {
                                if list.contactPubkeys.contains(contact.pubkey) {
                                    Button {
                                        list.contactPubkeys.remove(contact.pubkey)
                                    } label: {
                                        Image(systemName:  "checkmark.circle.fill")
                                            .padding(.vertical, 10)
                                    }
                                }
                                else {
                                    Button {
                                        list.contactPubkeys.insert(contact.pubkey)
                                    } label: {
                                        Image(systemName:  "circle")
                                            .foregroundColor(Color.secondary)
                                            .padding(.vertical, 10)
                                    }
                                }
                                ListRow(list: list, showPin: false)
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if list.contactPubkeys.contains(contact.pubkey) {
                                            list.contactPubkeys.remove(contact.pubkey)
                                        }
                                        else {
                                            list.contactPubkeys.insert(contact.pubkey)
                                        }
                                    }
                            }
                        }
                        Divider()
                    }
                }
            }
            .padding(10)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                        DataProvider.shared().save()
                        for list in lists {
                            sendNotification(.listPubkeysChanged, NewPubkeysForList(subscriptionId: list.subscriptionId, pubkeys: list.contactPubkeys))
                        }
                    }
                }
            }
            .navigationTitle(String(localized:"Add/Remove from feed", comment: "Navigation title for screen to add or remove contacts to a feed"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .nbUseNavigationStack(.never)
    }
}
struct AddRemoveToListsheet_Previews: PreviewProvider {
    static var previews: some View {
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadNosturLists()
        }) {
            NBNavigationStack {
                if let contact = PreviewFetcher.fetchContact() {
                    AddRemoveToListsheet(contact: contact)
                }
            }
        }
    }
}
