//
//  NewListSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/04/2023.
//

import SwiftUI

struct NewListSheet: View {
    
    @Environment(\.dismiss) var dismiss
    @ObservedObject var list:NosturList
    @State var addContactsSheetShown = false
    @State var selectedContacts:Set<Contact> = []
    @State var contactSelectionVisible = false
    var followingPubkeys = NosturState.shared.followingPublicKeys
        
    
    var body: some View {
        Form {
            Section(header: Text("Title")) {
                TextField("Title of your list", text: $list.name_)
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
                list.contacts_.append(contentsOf: selectedContacts)
                contactSelectionVisible = false
                DataProvider.shared().save()
                dismiss()
            })
            .equatable()
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Next") {
                    contactSelectionVisible = true
                }
                .disabled(list.name_.isEmpty)
            }
        }
    }
}

struct NewListSheet_Previews: PreviewProvider {
    static var previews: some View {
        let newList = NosturList(context: PreviewFetcher.viewContext)
        NavigationStack {
            NewListSheet(list: newList)
        }
        .withPreviewEnvironment()
    }
}
