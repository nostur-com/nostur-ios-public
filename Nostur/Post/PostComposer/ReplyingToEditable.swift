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
    public var requiredP: String? = nil
    public var available: Set<NRContact>
    @Binding var selected: Set<NRContact>
    @Binding var unselected: Set<NRContact>
    
    private var selectedSorted: [NRContact] {
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
            .font(.body)
            .fontWeightLight()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard available.count > 1 else { return } // always require at least one .p or we dont show the toggle sheet
            showContactsToggleSheet = true
        }
        .sheet(isPresented: $showContactsToggleSheet) {
            NBNavigationStack {
                ContactsToggleSheet(requiredP: requiredP, available: available, selected: $selected, unselected: $unselected)
                    .presentationDetentsMedium()
                    .environmentObject(themes)
            }
            .nbUseNavigationStack(.never)
        }
    }
}

struct ReplyingToEditableTester: View {
    @State private var requiredP: String? = nil
    @State private var available: Set<NRContact> = []
    @State private var selected: Set<NRContact> = []
    @State private var unselected: Set<NRContact> = []
    
    var body: some View {
        ReplyingToEditable(requiredP: requiredP, available: available, selected: $selected, unselected: $unselected)
            .onAppear {
                let nrContacts = PreviewFetcher.allContacts().map { NRContact.instance(of: $0.pubkey, contact: $0) }
                available = Set(nrContacts.prefix(6))
                selected = Set(nrContacts.prefix(6))
            }
    }
}

import NavigationBackport

#Preview("Replying to selector") {
    PreviewContainer({ pe in
        pe.loadContacts()
    }) {
        NBNavigationStack {
            ReplyingToEditableTester()
        }
    }
}
