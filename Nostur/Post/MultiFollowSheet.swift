//
//  MultiFollowSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/09/2023.
//

import SwiftUI

struct MultiFollowSheet: View {
    public let pubkey: String
    public let name: String
    public var onDismiss: (() -> Void)?
    
    @EnvironmentObject private var themes: Themes
    
    private var accounts: [CloudAccount] { // Only accounts with private key
        AccountsState.shared.accounts.filter { $0.isFullAccount }
    }
    
    private var firstRow: ArraySlice<CloudAccount> {
        accounts.prefix(6)
    }
    
    private var secondRow: ArraySlice<CloudAccount> {
        accounts.dropFirst(6).prefix(6)
    }
    
    private var thirdRow: ArraySlice<CloudAccount> {
        accounts.dropFirst(12).prefix(6)
    }
    
    @State private var followingOn = Set<String>()
    
    private func toggleAccount(_ account: CloudAccount) {
        if followingOn.contains(account.publicKey) {
            followingOn.remove(account.publicKey)
            Task {
                self.unfollow(pubkey, account: account)
            }
        }
        else {
            followingOn.insert(account.publicKey)
            Task {
                self.follow(pubkey, account: account)
            }
        }
    }
    
    private func isFollowingOn(_ account: CloudAccount) -> Bool {
        followingOn.contains(account.publicKey)
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 30) {
            Text("Follow \(name) on")
            VStack(spacing: 30) {
                HStack {
                    ForEach(firstRow) { account in
                        VStack {
                            PFP(pubkey: account.publicKey, account: account, size: 50)
                                .overlay(alignment: .top) {
                                    Text(account.anyName)
                                        .font(.system(size: 10))
                                        .lineLimit(1)
                                        .frame(width: 50)
                                        .fixedSize()
                                        .offset(y: -15)
                                }
                                .overlay(alignment: .bottom) {
                                    if isFollowingOn(account) {
                                        Text("Following", comment: "Shown when you follow someone in the multi follow sheet")
                                            .font(.system(size: 10))
                                            .lineLimit(1)
                                            .fixedSize()
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2)
                                            .background(themes.theme.accent)
                                            .cornerRadius(13)
                                            .offset(y: 10)
                                    }
                                }
                                .onTapGesture {
                                    toggleAccount(account)
                                }
                                .opacity(isFollowingOn(account) ? 1.0 : 0.25)
                        }
                    }
                }
                HStack {
                    ForEach(secondRow) { account in
                        VStack {
                            PFP(pubkey: account.publicKey, account: account, size: 50)
                                .overlay(alignment: .top) {
                                    Text(account.anyName)
                                        .font(.system(size: 10))
                                        .lineLimit(1)
                                        .frame(width: 50)
                                        .fixedSize()
                                        .offset(y: -15)
                                }
                                .overlay(alignment: .bottom) {
                                    if isFollowingOn(account) {
                                        Text("Following", comment: "Shown when you follow someone in the multi follow sheet")
                                            .font(.system(size: 10))
                                            .lineLimit(1)
                                            .fixedSize()
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2)
                                            .background(themes.theme.accent)
                                            .cornerRadius(13)
                                            .offset(y: 10)
                                    }
                                }
                                .onTapGesture {
                                    toggleAccount(account)
                                }
                                .opacity(isFollowingOn(account) ? 1.0 : 0.25)
                        }
                    }
                }
                HStack {
                    ForEach(thirdRow) { account in
                        VStack {
                            PFP(pubkey: account.publicKey, account: account, size: 50)
                                .overlay(alignment: .top) {
                                    Text(account.anyName)
                                        .font(.system(size: 10))
                                        .lineLimit(1)
                                        .frame(width: 50)
                                        .fixedSize()
                                        .offset(y: -15)
                                }
                                .overlay(alignment: .bottom) {
                                    if isFollowingOn(account) {
                                        Text("Following", comment: "Shown when you follow someone in the multi follow sheet")
                                            .font(.system(size: 10))
                                            .lineLimit(1)
                                            .fixedSize()
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2)
                                            .background(themes.theme.accent)
                                            .cornerRadius(13)
                                            .offset(y: 10)
                                    }
                                }
                                .onTapGesture {
                                    toggleAccount(account)
                                }
                                .opacity(isFollowingOn(account) ? 1.0 : 0.25)
                        }
                    }
                }
            }
        }
        .onAppear {
            followingOn = Set(
                accounts
                    .filter({ $0.getFollowingPublicKeys(includeBlocked: true).contains(pubkey) })
                    .map({ $0.publicKey })
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    onDismiss?()
                }
            }
        }
    }
    
    private func follow(_ pubkey: String, account: CloudAccount) {
        account.followingPubkeys.insert(pubkey)
        
        bg().perform {
            if let contact = Contact.fetchByPubkey(pubkey, context: bg()) {
                contact.couldBeImposter = 0
            }
            else {
                // if nil, create new contact
                let contact = Contact(context: bg())
                contact.pubkey = pubkey
                contact.couldBeImposter = 0
            }
            
            Task { @MainActor in
                account.publishNewContactList()
                
                if account == Nostur.account() {
                    AccountsState.shared.loggedInAccount?.reloadFollows()
                    sendNotification(.followingAdded, pubkey) // For WoT
                }
                DataProvider.shared().save()
            }
        }
    }
    

    private func unfollow(_ pubkey: String, account: CloudAccount) {
        account.followingPubkeys.remove(pubkey)
        if account == Nostur.account() {
            AccountsState.shared.loggedInAccount?.reloadFollows()
        }
        account.publishNewContactList()
        DataProvider.shared().save()
    }
}
