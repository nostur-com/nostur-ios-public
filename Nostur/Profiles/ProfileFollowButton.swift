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
    @EnvironmentObject private var ns:NosturState
    @ObservedObject private var fg:FollowingGuardian = .shared
    @State private var isFollowing = false
    @State private var editingAccount:Account?
    
    var body: some View {
        if (contact.pubkey != ns.account?.publicKey) {
            Button {
                if (isFollowing && !contact.privateFollow) {
                    contact.privateFollow = true
                    ns.follow(contact)
                }
                else if (isFollowing && contact.privateFollow) {
                    isFollowing = false
                    contact.privateFollow = false
                    ns.unfollow(contact)
                }
                else {
                    isFollowing = true
                    ns.follow(contact)
                }
            } label: {
                FollowButton(isFollowing:isFollowing, isPrivateFollowing:contact.privateFollow)
            }
            .disabled(!fg.didReceiveContactListThisSession)
            .onAppear {
                if (ns.isFollowing(contact)) {
                    isFollowing = true
                }
            }
        }
        else {
            Button {
                guard ns.account?.privateKey != nil else { ns.readOnlyAccountSheetShown = true; return }
                if let account = ns.account {
                    editingAccount = account
                }
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
