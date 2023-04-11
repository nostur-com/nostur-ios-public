//
//  EditList.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/04/2023.
//

import SwiftUI

struct EditList: View {
    
    @ObservedObject var list:NosturList
    @Environment(\.managedObjectContext) var viewContext
    
    @State var confirmDeleteShown = false
    @State var contactToRemove:Contact? = nil
    @State var newListSheetShown = false
    
    var body: some View {
        List(list.contacts_) { contact in
            ContactSearchResultRow(contact: contact)
                .padding()
                .onTapGesture { navigateTo(contact) }
                .listRowInsets(EdgeInsets())
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        contactToRemove = contact
                        confirmDeleteShown = true
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    
                }
        }
        .listStyle(.plain)
        .navigationTitle("Edit \(list.name ?? "list")")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete list \(contactToRemove?.name ?? "")", isPresented: $confirmDeleteShown, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let contactToRemove = contactToRemove else { return }
                viewContext.delete(contactToRemove)
                DataProvider.shared().save()
                self.contactToRemove = nil
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    
                } label: {
                    Label("", systemImage: "plus")
                }

            }
        }
        .sheet(isPresented: $newListSheetShown) {
            NewListSheet()
        }
    }
}

struct EditList_Previews: PreviewProvider {
    static var previews: some View {
        if let list = PreviewFetcher.fetchList() {
            NavigationStack {
                EditList(list: list)
                    .withNavigationDestinations()
            }
            .withPreviewEnvironment()
        }
    }
}
