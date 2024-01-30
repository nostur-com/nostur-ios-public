//
//  ProfileFollowButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/04/2023.
//

import SwiftUI
import NavigationBackport

struct ProfileFollowButton: View {
    @EnvironmentObject private var themes:Themes
    @ObservedObject public var contact:Contact
    @EnvironmentObject private var la:LoggedInAccount
    @ObservedObject private var fg:FollowingGuardian = .shared
    @State private var isFollowing = false
    @State private var editingAccount:CloudAccount?
    
    var body: some View {
        if (contact.pubkey != la.pubkey) {
            Button {
                if (isFollowing && !contact.isPrivateFollow) {
                    contact.isPrivateFollow = true
                    la.follow(contact, pubkey: contact.pubkey)
                }
                else if (isFollowing && contact.isPrivateFollow) {
                    isFollowing = false
                    contact.isPrivateFollow = false
                    la.unfollow(contact.pubkey)
                }
                else {
                    isFollowing = true
                    la.follow(contact, pubkey: contact.pubkey)
                }
            } label: {
                FollowButton(isFollowing:isFollowing, isPrivateFollowing: contact.isPrivateFollow)
            }
            .disabled(!fg.didReceiveContactListThisSession)
            .onAppear {
                if (la.isFollowing(pubkey: contact.pubkey)) {
                    isFollowing = true
                }
            }
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
                }
                .nbUseNavigationStack(.never)
                .presentationBackgroundCompat(themes.theme.listBackground)
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
