//
//  ReplyingToEditable.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/09/2023.
//

import SwiftUI

struct ReplyingToEditable: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themes: Themes
    public var requiredP:String? = nil
    public var available:Set<Contact>
    @Binding var selected:Set<Contact>
    @Binding var unselected:Set<Contact>
    
    private var selectedSorted:[Contact] {
        Array(selected)
            .sorted(by: { $0.pubkey == requiredP && $1.pubkey != requiredP })
    }
    
    @State private var showContactsToggleSheet = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Group {
                Text("Replying to ")
                    .foregroundColor(themes.theme.secondary)
                    .lineLimit(1)
                Text(selectedSorted.map { "@\($0.anyName)" }.formatted(.list(type: .and)))
                    .foregroundColor(themes.theme.accent)
                    .lineLimit(3)
            }
            .font(.system(size: 13))
            .fontWeight(.light)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard available.count > 1 else { return } // always require at least one .p or we dont show the toggle sheet
            showContactsToggleSheet = true
        }
        .sheet(isPresented: $showContactsToggleSheet) {
            ContactsToggleSheet(requiredP: requiredP, available: available, selected: $selected, unselected: $unselected)
            .presentationDetents([.medium])
        }
    }
}

struct ReplyingToEditableTester: View {
    @State private var requiredP:String? = nil
    @State private var available:Set<Contact> = []
    @State private var selected:Set<Contact> = []
    @State private var unselected:Set<Contact> = []
    
    var body: some View {
        ReplyingToEditable(requiredP: requiredP, available: available, selected: $selected, unselected: $unselected)
            .onAppear {
                let contacts = PreviewFetcher.allContacts()
                available = Set(contacts.prefix(6))
                selected = Set(contacts.prefix(6))
            }
    }
}


#Preview("Replying to selector") {
    PreviewContainer({ pe in
        pe.loadContacts()
    }) {
        NavigationStack {
            ReplyingToEditableTester()
        }
    }
}
