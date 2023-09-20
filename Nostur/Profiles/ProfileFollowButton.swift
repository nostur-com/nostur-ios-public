//
//  ProfileFollowButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/04/2023.
//

import SwiftUI

struct ProfileFollowButton: View {
    @EnvironmentObject private var theme:Theme
    @ObservedObject public var contact:Contact
    @EnvironmentObject private var la:LoggedInAccount
    @ObservedObject private var fg:FollowingGuardian = .shared
    @State private var isFollowing = false
    @State private var editingAccount:Account?
    
    var body: some View {
        if (contact.pubkey != la.pubkey) {
            Button {
                if (isFollowing && !contact.privateFollow) {
                    contact.privateFollow = true
                    la.follow(contact, pubkey: contact.pubkey)
                }
                else if (isFollowing && contact.privateFollow) {
                    isFollowing = false
                    contact.privateFollow = false
                    la.unfollow(contact, pubkey: contact.pubkey)
                }
                else {
                    isFollowing = true
                    la.follow(contact, pubkey: contact.pubkey)
                }
            } label: {
                FollowButton(isFollowing:isFollowing, isPrivateFollowing:contact.privateFollow)
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
                NavigationStack {
                    AccountEditView(account: account)
                }
                .presentationBackground(theme.background)
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
