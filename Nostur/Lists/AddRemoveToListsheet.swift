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
    public var onDismiss: (() -> Void)?
    
    // only contact lists, not relay lists
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CloudFeed.createdAt, ascending: false)],
        predicate: NSPredicate(format: "type == %@ OR type == nil", ListType.pubkeys.rawValue),
        animation: .none)
    var lists: FetchedResults<CloudFeed>
    
    var body: some View {
        NXForm {
            ForEach(lists) { list in
                HStack {
                    if list.contactPubkeys.contains(nrContact.pubkey) {
                        Image(systemName:  "checkmark.circle.fill")
                        
                    }
                    else {
                        Image(systemName:  "circle")
                            .foregroundColor(Color.secondary)
                    }
                    ListRow(list: list, showPin: false)
  
                }
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
            
            // Add to new list
            NavigationLink {
                EnterNewListNameSheet(onAdd: { newListName in
                    addToNewList(newListName, pubkey: nrContact.pubkey)
                })
                                       
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                        .foregroundColor(Color.secondary)
                    Text("New list...")
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Done") {
                    onDismiss?()
                    DataProvider.shared().save()
                    for list in lists {
                        sendNotification(.listPubkeysChanged, NewPubkeysForList(subscriptionId: list.subscriptionId, pubkeys: list.contactPubkeys))
                    }
                    broadcastUpdatedSharedLists()
                }
            }
        }
        .navigationTitle(String(localized:"Add/remove from Lists", comment: "Navigation title for screen to add or remove contacts to a feed"))
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
    
    private func addToNewList(_ listName: String, pubkey: String) {
        let newList = CloudFeed(context: DataProvider.shared().viewContext)
        newList.id = UUID()
        newList.name = listName
        newList.showAsTab = true
        newList.createdAt = .now
        newList.order = 0
        newList.type = ListType.pubkeys.rawValue
        newList.contactPubkeys.insert(pubkey)
    }
}


struct EnterNewListNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var listName: String = ""

    var onAdd: (String) -> Void
    
    var body: some View {
        NXForm {
            Section("Enter list name") {
                TextField(text: $listName, prompt: Text("List name")) {
                    Text("Enter list name")
                }
            }
        }
        
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add") {
                    guard isValid else { return }
                    // TODO: add validation
                    onAdd(listName.trimmingCharacters(in: .whitespaces))
                    dismiss()
                }
                .disabled(!isValid)
            }
        }
    }
    
    var isValid: Bool {
        listName.trimmingCharacters(in: .whitespaces).count > 0
    }
}

#Preview {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadCloudFeeds()
    }) {
        NBNavigationStack {
            if let nrContact = PreviewFetcher.fetchNRContact() {
                AddRemoveToListsheet(nrContact: nrContact)
                    .environment(\.theme, Themes.GREEN)
            }
        }
    }
}
