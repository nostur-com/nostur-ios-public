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
            Section(header: Text("Title", comment: "Header for entering title of a List")) {
                TextField(String(localized:"Title of your list", comment:"Placeholder for input field to enter title of a List"), text: $title)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }
        }
        .navigationTitle(String(localized:"New list", comment:"Navigation title for screen to create a new List"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.navigationStack)
        .navigationDestination(isPresented: $contactSelectionVisible) {
            ContactsSearch(followingPubkeys:followingPubkeys,
                           prompt: String(localized:"Search contacts", comment:"Placeholder in search contacts input field"), onSelectContacts: { selectedContacts in
                guard let newList = newList else { return }
                newList.contacts_.append(contentsOf: selectedContacts)
                contactSelectionVisible = false
                DataProvider.shared().save()
                dismiss()
            })
            .equatable()
            .navigationTitle(String(localized:"Add contacts to list", comment:"Navigation title for screen where you can add contacts to a List"))
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
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadNosturLists()
        }) {
            NavigationStack {
                NewListSheet()
            }
        }
    }
}
