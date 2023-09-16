//
//  MultiFollowSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/09/2023.
//

import SwiftUI

struct MultiFollowSheet: View {
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var theme:Theme
    
    let pubkey:String
    let name:String
    var onDismiss:(() -> Void)?
    
    var accounts:[Account] { // Only accounts with private key
        NosturState.shared.accounts.filter { $0.privateKey != nil }
    }
    
    @State var followingOn = Set<String>()
    
    func toggleAccount(_ account:Account) {
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
    
    func isFollowingOn(_ account:Account) -> Bool {
        followingOn.contains(account.publicKey)
    }
    
    var body: some View {
        VStack(alignment: .center) {
            Text("Follow \(name) on")
            HStack {
                ForEach(accounts) { account in
                    PFP(pubkey: account.publicKey, account: account, size: 50)
                        .overlay(alignment: .bottom) {
                            if isFollowingOn(account) {
                                Text("Following", comment: "Shown when you follow someone in the multi follow sheet")
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                                    .fixedSize()
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(theme.accent)
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
        .onAppear {
            followingOn = Set(
                accounts
                    .filter({ $0.followingPublicKeys.contains(pubkey) })
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
    
    private func follow(_ pubkey:String, account:Account) {
        if let contact = Contact.contactBy(pubkey: pubkey, context: viewContext) {
            contact.couldBeImposter = 0
            account.addToFollows(contact)
        }
        else {
            // if nil, create new contact
            let contact = Contact(context: viewContext)
            contact.pubkey = pubkey
            contact.couldBeImposter = 0
            account.addToFollows(contact)
        }
        if account == NosturState.shared.account {
            NosturState.shared.followingPublicKeys = NosturState.shared._followingPublicKeys
            NosturState.shared.loadFollowingPFPs()
            sendNotification(.followersChanged, account.followingPublicKeys)
            sendNotification(.followingAdded, pubkey)
            NosturState.shared.publishNewContactList()
        }
        else {
            self.publishNewContactList(account)
        }
        DataProvider.shared().save()
    }
    

    private func unfollow(_ pubkey: String, account:Account) {
        guard let contact = Contact.contactBy(pubkey: pubkey, context: viewContext) else {
            return
        }
        account.removeFromFollows(contact)
        if account == NosturState.shared.account {
            NosturState.shared.followingPublicKeys = NosturState.shared._followingPublicKeys
            NosturState.shared.loadFollowingPFPs()
            sendNotification(.followersChanged, account.followingPublicKeys)
            NosturState.shared.publishNewContactList()
        }
        else {
            self.publishNewContactList(account)
        }
        DataProvider.shared().save()
    }
    
    func publishNewContactList(_ account:Account) {
        guard let clEvent = try? AccountManager.createContactListEvent(account: account) else {
            L.og.error("🔴🔴 Could not create new clEvent")
            return
        }
        if account.isNC {
            NosturState.shared.nsecBunker = NSecBunkerManager(account)
            NosturState.shared.nsecBunker?.requestSignature(forEvent: clEvent, usingAccount: account, whenSigned: { signedEvent in
                _ = Unpublisher.shared.publishLast(signedEvent, ofType: .contactList)
            })
        }
        else {
            _ = Unpublisher.shared.publishLast(clEvent, ofType: .contactList)
        }
    }
}
