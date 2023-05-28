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
        sortDescriptors: [NSSortDescriptor(keyPath: \NosturList.createdAt, ascending: false)],
        predicate: NSPredicate(value: true),
        animation: .none)
    var lists:FetchedResults<NosturList>
    
    @State var selectedLists:Set<NosturList> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack {
                    ForEach(lists) { list in
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
            .padding(10)
            .onAppear {
                selectedLists = Set(contact.lists_)
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
                    }
                }
            }
            .navigationTitle("Add/Remove from list")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
struct AddRemoveToListsheet_Previews: PreviewProvider {
    static var previews: some View {
        
        NavigationStack {
            if let contact = PreviewFetcher.fetchContact() {
                AddRemoveToListsheet(contact: contact)
                }
            }
        .withPreviewEnvironment()
    }
}
