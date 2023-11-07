//
//  AddRemoveToListsheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/04/2023.
//

import SwiftUI
import Combine

struct AddRemoveToListsheet: View {
    
    @Environment(\.dismiss) var dismiss
    @ObservedObject var contact:Contact
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CloudFeed.createdAt, ascending: false)],
        predicate: NSPredicate(value: true),
        animation: .none)
    var lists:FetchedResults<CloudFeed>
    
    @State var selectedLists:Set<CloudFeed> = []
    @State var noSelectedLists = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if !lists.isEmpty && (!selectedLists.isEmpty || noSelectedLists) {
                    LazyVStack {
                        ForEach(lists.filter { $0.type != LVM.ListType.relays.rawValue }) { list in
                            HStack(spacing: 10) {
                                Button {
                                    if selectedLists.contains(list) {
                                        selectedLists.remove(list)
                                    }
                                    else {
                                        selectedLists.insert(list)
                                    }
                                } label: {
                                    if selectedLists.contains(list) {
                                        Image(systemName:  "checkmark.circle.fill")
                                            .padding(.vertical, 10)
                                    }
                                    else {
                                        Image(systemName:  "circle")
                                            .foregroundColor(Color.secondary)
                                            .padding(.vertical, 10)
                                    }
                                }
                                ListRow(list: list, showPin: false)
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if selectedLists.contains(list) {
                                            selectedLists.remove(list)
                                        }
                                        else {
                                            selectedLists.insert(list)
                                        }
                                    }
                            }
                        }
                        Divider()
                    }
                }
            }
            .padding(10)
            .onAppear {
                selectedLists = Set(contact.lists_)
                if selectedLists.count == 0 {
                    noSelectedLists = true
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                        contact.lists_ = Array(self.selectedLists)
                        DataProvider.shared().save()
                        for list in lists {
                            sendNotification(.listPubkeysChanged, NewPubkeysForList(subscriptionId: list.subscriptionId, pubkeys: Set(list.contacts_.map { $0.pubkey })))
                        }
                    }
                }
            }
            .navigationTitle(String(localized:"Add/Remove from feed", comment: "Navigation title for screen to add or remove contacts to a feed"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
struct AddRemoveToListsheet_Previews: PreviewProvider {
    static var previews: some View {
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadNosturLists()
        }) {
            NavigationStack {
                if let contact = PreviewFetcher.fetchContact() {
                    AddRemoveToListsheet(contact: contact)
                }
            }
        }
    }
}
