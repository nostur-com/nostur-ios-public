//
//  NewListSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/04/2023.
//

import SwiftUI

struct NewListSheet: View {
    
    @Environment(\.dismiss) var dismiss
    @State var newList:NosturList?
    @State var title = ""
    @State var addContactsSheetShown = false
    @State var selectedContacts:Set<Contact> = []
    @State var contactSelectionVisible = false
    var followingPubkeys = NosturState.shared.followingPublicKeys
        
    
    var body: some View {
        Form {
            Section(header: Text("Title")) {
                TextField("Title of your list", text: $title)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }
        }
        .navigationTitle("New list")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.navigationStack)
        .navigationDestination(isPresented: $contactSelectionVisible) {
            ContactsSearch(followingPubkeys:followingPubkeys,
                           prompt: "Search contacts", onSelectContacts: { selectedContacts in
                guard let newList = newList else { return }
                newList.contacts_.append(contentsOf: selectedContacts)
                contactSelectionVisible = false
                DataProvider.shared().save()
                dismiss()
            })
            .equatable()
            .navigationTitle("Add contacts to list")
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
                    contactSelectionVisible = true
                }
                .disabled(title.isEmpty)
            }
        }
    }
}

struct NewListSheet_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            NewListSheet()
        }
        .withPreviewEnvironment({ pe in
            pe.loadContacts()
            pe.loadNosturLists()
        })
    }
}
