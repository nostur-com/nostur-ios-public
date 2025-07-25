//
//  ContactsToggleSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/09/2023.
//

import SwiftUI
import NavigationBackport

struct ContactsToggleSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    public var requiredP: String? = nil
    public var available: Set<NRContact>
    @Binding public var selected: Set<NRContact>
    @Binding public var unselected: Set<NRContact>
    
    private var nrContactList: [NRContact] {
        Array(available)
            .sorted(by: { $0.pubkey == requiredP && $1.pubkey != requiredP })
    }
    
    var body: some View {
        ScrollView {
            Divider()
            LazyVStack(alignment: .leading, spacing: 10) {
                // if we don't have requiredP in contactList, render placeholder here:
                if let requiredP = requiredP, nrContactList.first(where: { $0.pubkey == requiredP }) == nil {
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
                ForEach(nrContactList) { nrContact in
                    HStack(spacing: 10) {
                        Button {
                            guard nrContact.pubkey != requiredP else { return }
                            if selected.contains(nrContact) {
                                selected.remove(nrContact)
                                unselected.insert(nrContact)
                            }
                            else {
                                selected.insert(nrContact)
                                unselected.remove(nrContact)
                            }
                        } label: {
                            if selected.contains(nrContact) {
                                Image(systemName:  "checkmark.circle.fill")
                                    .padding(.vertical, 10)
                            }
                            else {
                                Image(systemName:  "circle")
                                    .foregroundColor(Color.secondary)
                                    .padding(.vertical, 10)
                            }
                        }
                        PFP(pubkey: nrContact.pubkey, nrContact: nrContact)
                        Text(nrContact.anyName)
                        //                                .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if nrContact.pubkey == requiredP {
                            Spacer()
                            Text("required")
                                .font(.system(size: 12.0))
                                .italic()
                        }
                    }
                    .contentShape(Rectangle())
                    .disabled(nrContact.pubkey == requiredP)
                    .opacity(nrContact.pubkey == requiredP ? 0.5 : 1.0)
                    .onTapGesture {
                        guard nrContact.pubkey != requiredP else { return }
                        if selected.contains(nrContact) {
                            selected.remove(nrContact)
                            unselected.insert(nrContact)
                        }
                        else {
                            selected.insert(nrContact)
                            unselected.remove(nrContact)
                        }
                    }
                    Divider()
                }
                
            }
        }
        .environment(\.theme, theme)
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
