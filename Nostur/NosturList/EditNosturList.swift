//
//  EditList.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/04/2023.
//

import SwiftUI

struct EditNosturList: View {
    
    @ObservedObject var list:NosturList
    @Environment(\.managedObjectContext) var viewContext
    
    @State var confirmDeleteShown = false
    @State var contactToRemove:Contact? = nil
    @State var addContactsSheetShown = false
    
    var body: some View {
        List(list.contacts_) { contact in
            ContactSearchResultRow(contact: contact)
                .padding()
                .onTapGesture { navigateTo(contact) }
                .listRowInsets(EdgeInsets())
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        viewContext.delete(contact)
                        DataProvider.shared().save()
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    
                }
        }
        .listStyle(.plain)
        .navigationTitle("Edit \(list.name ?? "list")")
        .navigationBarTitleDisplayMode(.inline)
//        .confirmationDialog("Delete list \(contactToRemove?.name ?? "")", isPresented: $confirmDeleteShown, titleVisibility: .visible) {
//            Button("Delete", role: .destructive) {
//                guard let contactToRemove = contactToRemove else { return }
//
//                self.contactToRemove = nil
//            }
//        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    addContactsSheetShown = true
                } label: {
                    Label("", systemImage: "plus")
                }

            }
        }
        .sheet(isPresented: $addContactsSheetShown) {
            AddContactsToListSheet { contacts in
                list.contacts_.append(contentsOf: contacts)
                DataProvider.shared().save()
            }
        }
    }
}

struct EditList_Previews: PreviewProvider {
    static var previews: some View {
        if let list = PreviewFetcher.fetchList() {
            NavigationStack {
                EditNosturList(list: list)
                    .withNavigationDestinations()
            }
            .withPreviewEnvironment()
        }
    }
}
