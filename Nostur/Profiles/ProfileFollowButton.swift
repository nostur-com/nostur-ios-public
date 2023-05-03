//
//  ProfileFollowButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/04/2023.
//

import SwiftUI

struct ProfileFollowButton: View {
    @ObservedObject var contact:Contact
    @EnvironmentObject var ns:NosturState
    @State var isFollowing = false
    @State var editingAccount:Account?
    
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
            .onAppear {
                if (ns.isFollowing(contact)) {
                    isFollowing = true
                }
            }
        }
        else {
            Button {
                if let account = ns.account {
                    editingAccount = account
                }
            } label: {
                Text("Edit profile")
                    .sheet(item: $editingAccount) { account in
                        NavigationStack {
                            AccountEditView(account: account)
                        }
                    }
            }
            .buttonStyle(NosturButton())
        }
    }
}

struct ProfileFollowButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            if let contact = PreviewFetcher.fetchContact() {
                ProfileFollowButton(contact: contact)
            }
        }
        .withPreviewEnvironment()
    }
}
