////
////  AwardToPeopleSheet.swift
////  Nostur
////
////  Created by Fabian Lachman on 01/03/2023.
////
//
//import SwiftUI
//
//struct AddContactsToListSheet: View {
//    @Environment(\.dismiss) private var dismiss
//    @State var selectedContacts:[Contact] = []
//    var onFinish:([Contact]) -> Void
//    
//    var body: some View {
//        NavigationStack {
//            VStack {
//                ScrollView {
//                    ContactsSearch(onSelected: { selectedContacts in
//                        if selectedContacts.firstIndex(of: selectedContact) == nil {
//                            selectedContacts.insert(selectedContact, at:0)
//                        }
//                    }, prompt: "Search contact")
//                }
//                ScrollView {
//                    Button("Add \(selectedContacts.count) contacts") {
//                        onFinish(selectedContacts)
//                        dismiss()
//                    }.opacity(selectedContacts.count > 0 ? 1 : 0)
//                        .buttonStyle(.borderedProminent)
//                    
//                    Text("Selected contacts:").font(.title2)
//                    ForEach(selectedContacts) { contact in
//                        ContactSearchResultRow(contact: contact) {
//                            selectedContacts.removeAll(where: { $0.pubkey == contact.pubkey })
//                        }
//                    }
//                    
//                }
//            }
//            .toolbar {
////                ToolbarItem(placement: .cancellationAction) {
////                    Button(action: {
////                        dismiss()
////                    }, label: {
////                        Text("Cancel")
////                    })
////                }
//                ToolbarItem(placement: .primaryAction) {
//                    Button(action: {
//                        onFinish(selectedContacts)
//                        dismiss()
//                    }, label: {
//                        Text("Done")
//                    })
//                }
//            }
//            .navigationTitle("Add contacts to list")
//            .navigationBarTitleDisplayMode(.inline)
//        }
//    }
//}
//
//struct AddContactsToListSheet_Previews: PreviewProvider {
//    static var previews: some View {
//        AddContactsToListSheet(onFinish: { contacts in
//            
//        })
//            .withPreviewEnvironment()
//    }
//}
