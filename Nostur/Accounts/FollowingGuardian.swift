//
//  FollowingGuardian.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/04/2023.
//

import Foundation
import Combine

// The following guardian, watches for any changes in your contact list
// If contacts are reduced (by another (broken) client) it can ask you to restore
// It also adds new followers you added through other clients

class FollowingGuardian {
    
    static let shared = FollowingGuardian()
    
    var subscriptions = Set<AnyCancellable>()
//    var lastRemovedPubkeys:Set<String>? // These we can restore after asking user
    
    init() {
        listenForNewContactListEvents()
        listenForAccountChanged()
    }
    
    func listenForAccountChanged() {
        receiveNotification(.activeAccountChanged)
            .debounce(for: .seconds(15), scheduler: RunLoop.main)
            .sink { notification in
                let account = notification.object as! Account
                guard account.privateKey != nil else { return }
                SocketPool.shared.sendMessage(ClientMessage(
                        type: .REQ,
                        message: RequestMessage.getAuthorContactsList(pubkey: account.publicKey)))
            }
            .store(in: &subscriptions)
    }
    
    func listenForNewContactListEvents() {
        receiveNotification(.newFollowingListFromRelay)
            .receive(on: RunLoop.main)
            .sink { notification in
                let nEvent = notification.object as! NEvent
                guard nEvent.kind == .contactList else { return }
                guard nEvent.publicKey == NosturState.shared.activeAccountPublicKey else { return }
                guard let account = NosturState.shared.account else { return }
                guard account.privateKey != nil else { return }
                
                // TODO: Make this work for all accounts, not just active
                let pubkeysOwn = Set(account.follows?.map({ c in c.pubkey }) ?? [])
                let pubkeysRelay = Set(nEvent.pTags())
                
                print("🫂🫂 \(pubkeysOwn.joined(separator: ","))")
                print("🫂🫂 \(pubkeysRelay.joined(separator: ","))")
                
                let removed = pubkeysOwn.subtracting(pubkeysRelay)
                let added = pubkeysRelay.subtracting(pubkeysOwn)
                
                self.followNewContacts(added: added, account: account)
                
                if removed.count > 0 {
                    sendNotification(.requestConfirmationChangedFollows, removed)
                }
            }
            .store(in: &subscriptions)
    }
    
    func followNewContacts(added:Set<String>, account:Account) {
        guard added.count > 0 else { return }
        account.objectWillChange.send()
        
        let context = DataProvider.shared().viewContext
        for pubkey in added { // sanity... limit 25
            let contact = Contact.fetchByPubkey(pubkey, context: context)
            if let contact {
                account.addToFollows(contact)
            }
            else {
                let newContact = Contact(context: context)
                newContact.pubkey = pubkey
                newContact.metadata_created_at = 0
                newContact.updated_at = 0
                account.addToFollows(newContact)
            }
        }
        sendNotification(.followersChanged, account.followingPublicKeys)
        DataProvider.shared().save()
    }
    
    func restoreFollowing() {
        guard let account = NosturState.shared.account else { return }
        guard let clEvent = try? AccountManager.createContactListEvent(account: account) else {
            print("🔴🔴 Could not create new clEvent")
            return
        }
        _ = Unpublisher.shared.publishLast(clEvent, ofType: .contactList)
    }
    
    func removeFollowing(_ pubkeys:Set<String>) {
        guard let account = NosturState.shared.account else { return }
        for contact in account.follows_ {
            if pubkeys.contains(contact.pubkey) {
                account.removeFromFollows(contact)
            }
        }
        sendNotification(.followersChanged, account.followingPublicKeys)
        DataProvider.shared().save()
    }
}
