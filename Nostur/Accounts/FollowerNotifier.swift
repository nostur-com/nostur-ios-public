//
//  FollowerNotifier.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/06/2023.
//

import Foundation
import Combine

// The follower notififier tracks if you have new followers
// To get your followers the filter "#p": [your pubkey], "kinds": [3]  is used
// We get the full list and store the most recent .created_at
// If we find a newer .created_at from a new .pubkey we generate a notification in the app

class FollowerNotifier {
    
    static let shared = FollowerNotifier()
    
    var ctx = DataProvider.shared().bg
    var currentFollowerPubkeys = Set<String>()
    var newFollowerPubkeys = Set<String>()
    var subscriptions = Set<AnyCancellable>()
    let generateNewFollowersNotification = PassthroughSubject<String, Never>()
    var checkForNewTimer:Timer?
    
    init() {
#if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return
        }
#endif
        listenForNewContactListEvents()
        listenForAccountChanged()
        generateNewFollowersNotification
            .debounce(for: .seconds(5), scheduler: RunLoop.main) // Debounce 5 seconds to allow collection of more contact lists during import
            .sink { [weak self] accountPubkey in
                guard let self = self else { return }
                self._generateNewFollowersNotification(accountPubkey)
            }
            .store(in: &subscriptions)
        
        checkForNewTimer = Timer.scheduledTimer(withTimeInterval: 3600*4, repeats: true, block: { _ in
            self.checkForUpdatedContactList()
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            self.checkForUpdatedContactList()
        }
    }
    
    func checkForUpdatedContactList() {
        guard !NosturState.shared.activeAccountPublicKey.isEmpty else { return }
        L.og.info("Checking for new followers")
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = []
        // Not parsing and filtering tags, but searching for string. Ugly hack but works fast
        fr.predicate = NSPredicate(format: "kind == 3 AND tagsSerialized CONTAINS %@", serializedP(NosturState.shared.activeAccountPublicKey))
        
        ctx.perform { [weak self] in
            guard let self = self else { return }
            if let currentFollowerPubkeys = try? self.ctx.fetch(fr) {
                self.currentFollowerPubkeys = Set(currentFollowerPubkeys.map { $0.pubkey })
                self.newFollowerPubkeys.removeAll()
                if let mostRecent = PersistentNotification.fetchPersistentNotification(context: self.ctx) {
                    let since = NTimestamp(date: mostRecent.createdAt)
                    req(RM.getFollowers(pubkey: NosturState.shared.activeAccountPublicKey, since: since))
                }
                else {
                    let since = Int(Date.now.timeIntervalSince1970 - (3600 * 3*24)) // how long ago  ago
                    req(RM.getFollowers(pubkey: NosturState.shared.activeAccountPublicKey, since: NTimestamp(timestamp: since)))
                }
            }
        }
    }
    
    func listenForAccountChanged() {
        receiveNotification(.activeAccountChanged)
            .debounce(for: .seconds(20), scheduler: RunLoop.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                let account = notification.object as! Account
                guard account.privateKey != nil else { return }
                L.og.info("Checking for new after account switch")
                
                self.ctx.perform {
                    if let mostRecent = PersistentNotification.fetchPersistentNotification(context: self.ctx) {
                        let since = NTimestamp(date: mostRecent.createdAt)
                        req(RM.getFollowers(pubkey: account.publicKey, since: since))
                    }
                    else {
                        let since = Int(Date.now.timeIntervalSince1970 - (3600 * 3*24)) // how long ago  ago
                        req(RM.getFollowers(pubkey: account.publicKey, since: NTimestamp(timestamp: since)))
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    func listenForNewContactListEvents() {
        receiveNotification(.newFollowingListFromRelay)
//            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                let nEvent = notification.object as! NEvent
                guard nEvent.kind == .contactList else { return }
                guard nEvent.pTags().contains(NosturState.shared.activeAccountPublicKey) else { return }
                guard let account = NosturState.shared.account else { return }
                guard account.privateKey != nil else { return }
                
                if !self.currentFollowerPubkeys.contains(nEvent.publicKey) {
                    self.newFollowerPubkeys.insert(nEvent.publicKey)
                    self.generateNewFollowersNotification.send(NosturState.shared.activeAccountPublicKey)
                }
            }
            .store(in: &subscriptions)
    }
    
    private func _generateNewFollowersNotification(_ pubkey:String) {
        guard newFollowerPubkeys.count > 0 else { return }
        ctx.perform { [weak self] in
            guard let self = self else { return }
            let newFollowersNotification = PersistentNotification(context: self.ctx)
            newFollowersNotification.id = UUID()
            newFollowersNotification.createdAt = .now
            newFollowersNotification.pubkey = pubkey
            newFollowersNotification.type = .newFollowers
            newFollowersNotification.content = self.newFollowerPubkeys.joined(separator: ",")
            
            if let account = NosturState.shared.account?.toBG() {
                account.lastFollowerCreatedAt = Int64(Date.now.timeIntervalSince1970) // HM not needed since we use mostRecent (PNotification)
            }
            
            L.og.info("New followers (\(self.newFollowerPubkeys.count)) notification, for \(pubkey)")
            L.og.debug("Prefetching kind 0 for first 10 new followers")
            req(RM.getUserMetadata(pubkeys: Array(self.newFollowerPubkeys.prefix(10))))
            DataProvider.shared().bgSave()
        }
    }
}
