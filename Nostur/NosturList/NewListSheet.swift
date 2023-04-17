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
//    @State var title: String = ""
//    @FocusState var titleFieldIsFocused = false
    @State var selectedContacts:[Contact] = []
    @State var addContactsSheetShown = false

    
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink("Next") {
                    AddContactsToListSheet { contacts in
                        list.contacts_.append(contentsOf: contacts)
                        DataProvider.shared().save()
                        dismiss()
                    }
                }
                    .disabled(list.name_ == "")
            }
        }
        .sheet(isPresented: $addContactsSheetShown) {
            
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
