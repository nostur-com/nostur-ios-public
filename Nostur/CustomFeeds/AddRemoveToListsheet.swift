//
//  AddRemoveToListsheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/04/2023.
//

import SwiftUI
import Combine
import NavigationBackport

enum ListType: String, Identifiable, Hashable {
    case pubkeys = "pubkeys"
    case relays = "relays"

    var id: String {
        String(self.rawValue)
    }
}

struct AddRemoveToListsheet: View {
    
    @Environment(\.dismiss) var dismiss
    @ObservedObject var nrContact: NRContact
    
    // only contact lists, not relay lists
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CloudFeed.createdAt, ascending: false)],
        predicate: NSPredicate(format: "type == %@ OR type == nil", ListType.pubkeys.rawValue),
        animation: .none)
    var lists: FetchedResults<CloudFeed>
    
    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(lists) { list in
                    HStack(spacing: 10) {
                        if list.contactPubkeys.contains(nrContact.pubkey) {
                            Button {
                                list.contactPubkeys.remove(nrContact.pubkey)
                                if list.sharedList {
                                    updatedSharedLists.insert(list)
                                }
                            } label: {
                                Image(systemName:  "checkmark.circle.fill")
                                    .padding(.vertical, 10)
                            }
                        }
                        else {
                            Button {
                                list.contactPubkeys.insert(nrContact.pubkey)
                                if list.sharedList {
                                    updatedSharedLists.insert(list)
                                }
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
                                if list.contactPubkeys.contains(nrContact.pubkey) {
                                    list.contactPubkeys.remove(nrContact.pubkey)
                                }
                                else {
                                    list.contactPubkeys.insert(nrContact.pubkey)
                                }
                                if list.sharedList {
                                    updatedSharedLists.insert(list)
                                }
                            }
                    }
                }
                Divider()
                
                // Add to new list
                HStack(spacing: 10) {
                    Text("New list...")
                    Spacer()
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { // Short delay freezes????
                        AppSheetsModel.shared.addContactsToListInfo = AddContactsToListInfo(pubkeys: [nrContact.pubkey])
                    }
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
                    broadcastUpdatedSharedLists()
                }
            }
        }
        .navigationTitle(String(localized:"Add/Remove from feed", comment: "Navigation title for screen to add or remove contacts to a feed"))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    
    @State var updatedSharedLists: Set<CloudFeed> = []
    
    private func broadcastUpdatedSharedLists() {
        for sharedList in updatedSharedLists {
            if let accountPubkey = sharedList.accountPubkey,
               let fullAccount = AccountsState.shared.accounts.first(where: { $0.publicKey ==  accountPubkey }) {
                publishList(sharedList, account: fullAccount)
            }
        }
    }
}
struct AddRemoveToListsheet_Previews: PreviewProvider {
    static var previews: some View {
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadCloudFeeds()
        }) {
            NBNavigationStack {
                if let nrContact = PreviewFetcher.fetchNRContact() {
                    AddRemoveToListsheet(nrContact: nrContact)
                }
            }
        }
    }
}
