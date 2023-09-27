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
// If we find a newer .created_at from someone with our pubkey in p's we generate a notification in the app

class FollowerNotifier {
    
    static let shared = FollowerNotifier()
    
    private var ctx = DataProvider.shared().bg
    private var currentFollowerPubkeys = Set<String>()
    private var newFollowerPubkeys = Set<String>()
    private var subscriptions = Set<AnyCancellable>()
    private let generateNewFollowersNotification = PassthroughSubject<String, Never>()
    private var checkForNewTimer:Timer?
    
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
                // Should still be same account (account switch could have happened in 5 sec)
                guard NRState.shared.activeAccountPublicKey == accountPubkey else { return }
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
        guard !SettingsStore.shared.lowDataMode else { return }
        guard !NRState.shared.activeAccountPublicKey.isEmpty else { return }
        L.og.info("Checking for new followers")
        
        let fr = Event.fetchRequest()
        fr.sortDescriptors = []
        // Not parsing and filtering tags, but searching for string. Ugly hack but works fast
        fr.predicate = NSPredicate(format: "kind == 3 AND tagsSerialized CONTAINS %@", serializedP(NRState.shared.activeAccountPublicKey))
        
        ctx.perform { [weak self] in
            guard let self = self else { return }
            if let currentFollowerPubkeys = try? self.ctx.fetch(fr) {
                self.currentFollowerPubkeys = Set(currentFollowerPubkeys.map { $0.pubkey })
                self.newFollowerPubkeys.removeAll()
                if let mostRecent = PersistentNotification.fetchPersistentNotification(context: self.ctx) {
                    let since = NTimestamp(date: mostRecent.createdAt)
                    req(RM.getFollowers(pubkey: NRState.shared.activeAccountPublicKey, since: since))
                }
                else {
                    let since = Int(Date.now.timeIntervalSince1970 - (3600 * 3*24)) // how long ago  ago
                    req(RM.getFollowers(pubkey: NRState.shared.activeAccountPublicKey, since: NTimestamp(timestamp: since)))
                }
            }
        }
    }
    
    func listenForAccountChanged() {
        receiveNotification(.activeAccountChanged)
            .debounce(for: .seconds(20), scheduler: RunLoop.main)
            .sink { [weak self] notification in
                guard !SettingsStore.shared.lowDataMode else { return }
                guard let self = self else { return }
                let account = notification.object as! Account
                guard account.privateKey != nil else { return }
                L.og.info("Checking for new followers after account switch")
                let pubkey = account.publicKey
                
                self.ctx.perform { [weak self] in
                    guard let self = self else { return }
                    if let mostRecent = PersistentNotification.fetchPersistentNotification(type: .newFollowers, context: self.ctx) {
                        let since = NTimestamp(date: mostRecent.createdAt)
                        req(RM.getFollowers(pubkey: pubkey, since: since))
                    }
                    else {
                        let since = Int(Date.now.timeIntervalSince1970 - (3600 * 3*24)) // how long ago  ago
                        req(RM.getFollowers(pubkey: pubkey, since: NTimestamp(timestamp: since)))
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    func listenForNewContactListEvents() {
        receiveNotification(.newFollowingListFromRelay)
            .sink { [weak self] notification in
                guard let self = self else { return }
                let nEvent = notification.object as! NEvent
                guard nEvent.kind == .contactList else { return }
                guard nEvent.pTags().contains(NRState.shared.activeAccountPublicKey) else { return }
//                guard let account = NosturState.shared.account else { return }
                guard !self.currentFollowerPubkeys.isEmpty else { return }
//                guard account.privateKey != nil else { return }
                
                if !self.currentFollowerPubkeys.contains(nEvent.publicKey) {
                    self.newFollowerPubkeys.insert(nEvent.publicKey)
                    self.generateNewFollowersNotification.send(NRState.shared.activeAccountPublicKey)
                }
            }
            .store(in: &subscriptions)
    }
    
    private func _generateNewFollowersNotification(_ pubkey:String) {
        ctx.perform { [weak self] in
            guard let self = self else { return }
            guard !self.newFollowerPubkeys.isEmpty else { return }
                        
            // Check WoT if enabled
            if WOT_FILTER_ENABLED() {
                self.newFollowerPubkeys = self.newFollowerPubkeys.filter {
                    return WebOfTrust.shared.isAllowed($0)
                }
            }
            
            // Don't continue if newFollowerPubkeys is empty after WoT check
            guard !self.newFollowerPubkeys.isEmpty else { return }
            
            _ = PersistentNotification.create(
                pubkey: pubkey,
                followers: Array(self.newFollowerPubkeys),
                context: self.ctx
            )
            
            if let account = account() {
                account.lastFollowerCreatedAt = Int64(Date.now.timeIntervalSince1970) // HM not needed since we use mostRecent (PNotification)
            }
            
            L.og.info("New followers (\(self.newFollowerPubkeys.count)) notification, for \(pubkey)")
            L.og.debug("Prefetching kind 0 for first 10 new followers")
            req(RM.getUserMetadata(pubkeys: Array(self.newFollowerPubkeys.prefix(10))))
            self.newFollowerPubkeys.removeAll()
            DataProvider.shared().bgSave()
        }
    }
}
