//
//  ContactsToggleSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/09/2023.
//

import SwiftUI
import NavigationBackport

struct ContactsToggleSheet: View {
    @EnvironmentObject private var themes: Themes
    @Environment(\.dismiss) private var dismiss
    public var requiredP: String? = nil
    public var available: Set<Contact>
    @Binding public var selected: Set<Contact>
    @Binding public var unselected: Set<Contact>
    
    private var contactList: [Contact] {
        Array(available)
            .sorted(by: { $0.pubkey == requiredP && $1.pubkey != requiredP })
    }
    
    var body: some View {
        NBNavigationStack {
            ScrollView {
                Divider()
                LazyVStack(alignment: .leading, spacing: 10) {
                    // if we don't have requiredP in contactList, render placeholder here:
                    if let requiredP = requiredP, contactList.first(where: { $0.pubkey == requiredP }) == nil {
                        HStack(spacing: 10) {
                            Button { } label: {
                                Image(systemName:  "checkmark.circle.fill")
                                    .padding(.vertical, 10)
                            }
                            Text(requiredP.prefix(11))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Spacer()
                            Text("required")
                                .font(.system(size: 12.0))
                                .italic()
                        }
                        .disabled(true)
                        .opacity(0.5)
                        Divider()
                    }
                    
                    // contacts to toggle (but disable toggle for requiredP)
                    ForEach(contactList) { contact in
                        HStack(spacing: 10) {
                            Button {
                                guard contact.pubkey != requiredP else { return }
                                if selected.contains(contact) {
                                    selected.remove(contact)
                                    unselected.insert(contact)
                                }
                                else {
                                    selected.insert(contact)
                                    unselected.remove(contact)
                                }
                            } label: {
                                if selected.contains(contact) {
                                    Image(systemName:  "checkmark.circle.fill")
                                        .padding(.vertical, 10)
                                }
                                else {
                                    Image(systemName:  "circle")
                                        .foregroundColor(Color.secondary)
                                        .padding(.vertical, 10)
                                }
                            }
                            PFP(pubkey: contact.pubkey, contact: contact)
                            Text(contact.anyName)
                            //                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if contact.pubkey == requiredP {
                                Spacer()
                                Text("required")
                                    .font(.system(size: 12.0))
                                    .italic()
                            }
                        }
                        .contentShape(Rectangle())
                        .disabled(contact.pubkey == requiredP)
                        .opacity(contact.pubkey == requiredP ? 0.5 : 1.0)
                        .onTapGesture {
                            guard contact.pubkey != requiredP else { return }
                            if selected.contains(contact) {
                                selected.remove(contact)
                                unselected.insert(contact)
                            }
                            else {
                                selected.insert(contact)
                                unselected.remove(contact)
                            }
                        }
                        Divider()
                    }
                    
                }
            }
            .environmentObject(themes)
            .navigationTitle("Notify selection (\(selected.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if available.count > 4 {
                        if selected.count == available.count {
                            Image(systemName: "checklist.checked")
                                .onTapGesture {
                                    selected = available.filter { $0.pubkey == requiredP }
                                }
                        }
                        else {
                            Image(systemName: "checklist.unchecked")
                                .onTapGesture {
                                    selected = available
                                }
                        }
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Back") {
                        dismiss()
                    }
                }
            }
            .padding(10)
        }
        .nbUseNavigationStack(.never)
    }
}

#Preview("Replying to selector") {
    PreviewContainer({ pe in
        pe.loadContacts()
    }) {
        NBNavigationStack {
            ReplyingToEditableTester()
        }
    }
}
