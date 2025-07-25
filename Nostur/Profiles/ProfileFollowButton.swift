//
//  ProfileFollowButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/04/2023.
//

import SwiftUI
import NavigationBackport

struct ProfileFollowButton: View {
    @Environment(\.theme) private var theme
    @ObservedObject public var contact: Contact
    @EnvironmentObject private var la: LoggedInAccount
    @State private var editingAccount: CloudAccount?
    
    var body: some View {
        if (contact.pubkey != la.pubkey) {
            FollowButton(pubkey: contact.pubkey)
        }
        else {
            Button {
                guard let account = account() else { return }
                guard isFullAccount(account) else { showReadOnlyMessage(); return }
                editingAccount = account
            } label: {
                Text("Edit profile", comment: "Button to edit own profile")
            }
            .buttonStyle(NosturButton())
            .sheet(item: $editingAccount) { account in
                NBNavigationStack {
                    AccountEditView(account: account)
                        .environment(\.theme, theme)
                }
                .nbUseNavigationStack(.never)
                .presentationBackgroundCompat(theme.listBackground)
            }
        }
    }
}

#Preview("ProfileFollowButton") {
    PreviewContainer({ pe in
        pe.loadContacts()
    }) {
        VStack {
            if let contact = PreviewFetcher.fetchContact() {
                ProfileFollowButton(contact: contact)
            }
        }
    }
}
