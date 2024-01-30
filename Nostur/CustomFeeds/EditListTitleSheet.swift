//
//  EditListTitleSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/04/2023.
//

import SwiftUI
import NavigationBackport

struct EditListTitleSheet: View {
    
    @Environment(\.dismiss) var dismiss
    var list: CloudFeed
    @State var newTitle = ""
    @State var showAsTab = false
    
    var body: some View {
        VStack {
            Form {
                Section(header: Text("Title", comment: "Header for entering title of a feed")) {
                    TextField(String(localized:"Title of your feed", comment:"Placeholder for input field to enter title of a feed"), text: $newTitle)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    
                    Toggle(isOn: $showAsTab, label: { Text("Pin on tab bar", comment: "Toggle to pin/unpin a feed on tab bar")})
                }
            }
            Spacer()
        }
        .onAppear {
            newTitle = list.name_
            showAsTab = list.showAsTab
        }
        .navigationTitle("Edit title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Save") {
                    dismiss()
                    list.name_ = newTitle
                    list.showAsTab = showAsTab
                    DataProvider.shared().save()
                }
                .disabled(newTitle.isEmpty)
            }
        }
    }
}


struct EditListTitleSheet_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadNosturLists()
        }) {
            NBNavigationStack {
                if let list = PreviewFetcher.fetchList() {
                    EditListTitleSheet(list: list)
                        .withNavigationDestinations()
                }
            }
        }
    }
}
