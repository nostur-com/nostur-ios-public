//
//  NewListSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/04/2023.
//

import SwiftUI

struct NewListSheet: View {
    
    @State var title: String = ""
//    @FocusState var titleFieldIsFocused = false
    @State var selectedContacts:[Contact] = []

    
    var body: some View {
        VStack {
            Form {
                Section(header: Text("Notifications")) {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
            }
            List(selectedContacts) { contact in
                ProfileRow(contact: contact)
            }
        }
        .navigationTitle("New list")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NewListSheet_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            NewListSheet()
        }
        .withPreviewEnvironment()
    }
}
