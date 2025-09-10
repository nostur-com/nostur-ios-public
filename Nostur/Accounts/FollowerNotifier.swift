//
//  FollowerNotifier.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/06/2023.
//

import Foundation
import Combine
import NostrEssentials

// The follower notififier tracks if you have new followers
// To get your followers the filter "#p": [your pubkey], "kinds": [3]  is used
// We get the full list and store the most recent .created_at
// If we find a newer .created_at from someone with our pubkey in p's we generate a notification in the app

class FollowerNotifier {
    
    static let LIMIT = 500 // After 500 followers will only check for Follow-backs because of data usage
    
    static let shared = FollowerNotifier()
    private var currentFollowerPubkeys = Set<String>()
    private var newFollowerPubkeys = Set<String>()
    private var subscriptions = Set<AnyCancellable>()
    private let generateNewFollowersNotification = PassthroughSubject<String, Never>()
    private var checkForNewTimer:Timer?
    
    private init() {
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
                // Should still be same account (account switch could have happened in 5 sec)
                guard AccountsState.shared.activeAccountPublicKey == accountPubkey else { return }
                self?._generateNewFollowersNotification(accountPubkey)
            }
            .store(in: &subscriptions)
        
        guard checkForNewTimer == nil else { return }
        checkForNewTimer = Timer.scheduledTimer(withTimeInterval: 14400, repeats: true, block: { [weak self] _ in
            guard !AccountsState.shared.activeAccountPublicKey.isEmpty else { return }
            let pubkey = AccountsState.shared.activeAccountPublicKey
            self?.checkForUpdatedContactList(pubkey: pubkey)
        })
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard !AccountsState.shared.activeAccountPublicKey.isEmpty else { return }
            let pubkey = AccountsState.shared.activeAccountPublicKey
            self?.checkForUpdatedContactList(pubkey: pubkey)
        }
    }
    
    public func checkForUpdatedContactList(pubkey: String) {
        guard !SettingsStore.shared.lowDataMode else { return }
#if DEBUG
        L.og.debug("Checking for new followers")
#endif
        
        bg().perform { [weak self] in
            guard let self = self else { return }
            self.loadCurrentFollowers(pubkey: pubkey)
            self.newFollowerPubkeys.removeAll()
            
            let since = if let mostRecent = PersistentNotification.fetchPersistentNotification(byPubkey: pubkey, type: .newFollowers, context: bg()) {
                NTimestamp(date: mostRecent.createdAt)
            }
            else {
                NTimestamp(timestamp: Int(Date.now.timeIntervalSince1970 - (259200)))
            }
            
            if self.currentFollowerPubkeys.count <= Self.LIMIT { // Check all new followers
                let rf = Filters(
                    kinds: [3],
                    tagFilter: TagFilter(tag: "p", values: [AccountsState.shared.activeAccountPublicKey]),
                    since: since.timestamp
                )
                
                if let cm = NostrEssentials.ClientMessage(type: .REQ,
                                                          subscriptionId: "FOLL-" + UUID().uuidString,
                                                          filters: [rf]).json() {
                    req(cm)
                }
            }
            else if let follows = AccountsState.shared.loggedInAccount?.followingPublicKeys { // Check only new following back (because data usage)

                // We need to REQ all that we follow (for follow-back check), but we don't need to check those already following us
                let followsWithoutFollowers = follows.subtracting(self.currentFollowerPubkeys)
                
                // if too many, pick random 1900
                let followsNotTooMany = followsWithoutFollowers.count <= 2000 ? followsWithoutFollowers : Set(followsWithoutFollowers.shuffled().prefix(2000))
                
                let rf = Filters(
                    authors: followsNotTooMany,
                    kinds: [3],
                    tagFilter: TagFilter(tag: "p", values: [AccountsState.shared.activeAccountPublicKey]),
                    since: since.timestamp
                )
                
                if let cm = NostrEssentials.ClientMessage(type: .REQ,
                                                          subscriptionId: "FOLL-" + UUID().uuidString,
                                                          filters: [rf]).json() {
                    req(cm)
                }
            }
        }
    }
    
    private func loadCurrentFollowers(pubkey:String) {
        shouldBeBg()
        let fr = Event.fetchRequest()
        fr.sortDescriptors = []
        // Not parsing and filtering tags, but searching for string. Ugly hack but works fast
        fr.predicate = NSPredicate(format: "kind == 3 AND tagsSerialized CONTAINS %@", serializedP(pubkey))
        if let currentFollowerPubkeys = try? bg().fetch(fr) {
            self.currentFollowerPubkeys = Set(currentFollowerPubkeys.map { $0.pubkey })
        }
    }
    
    func listenForAccountChanged() {
        
        receiveNotification(.activeAccountChanged)
            .sink { [weak self] notification in
                let account = notification.object as! CloudAccount
                let pubkey = account.publicKey
                
                bg().perform { [weak self] in
                    self?.loadCurrentFollowers(pubkey: pubkey)
                }
            }
            .store(in: &subscriptions)
        
        
        receiveNotification(.activeAccountChanged)
            .debounce(for: .seconds(20), scheduler: RunLoop.main)
            .sink { [weak self] notification in
                guard !SettingsStore.shared.lowDataMode else { return }
                let account = notification.object as! CloudAccount
                L.og.info("Checking for new followers after account switch")
                let pubkey = account.publicKey
                
                self?.checkForUpdatedContactList(pubkey: pubkey)
            }
            .store(in: &subscriptions)
    }
    
    func listenForNewContactListEvents() {
        receiveNotification(.newFollowingListFromRelay)
            .sink { [weak self] notification in
                guard let self = self else { return }
                let nEvent = notification.object as! NEvent
                guard nEvent.kind == .contactList else { return }
                guard nEvent.pTags().contains(AccountsState.shared.activeAccountPublicKey) else { return }
                bg().perform { [weak self] in
                    guard let self = self else { return }
                    guard !self.currentFollowerPubkeys.isEmpty else { return }

                    if !self.currentFollowerPubkeys.contains(nEvent.publicKey) {
                        self.newFollowerPubkeys.insert(nEvent.publicKey)
                        self.generateNewFollowersNotification.send(AccountsState.shared.activeAccountPublicKey)
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    private func _generateNewFollowersNotification(_ pubkey:String) {
        bg().perform { [weak self] in
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
            
            let notification = PersistentNotification.create(
                pubkey: pubkey,
                followers: Array(self.newFollowerPubkeys),
                context: bg()
            )
            NotificationsViewModel.shared.checkNeedsUpdate(notification)
            
//            if let account = account() {
//                account.lastFollowerCreatedAt = Int64(Date.now.timeIntervalSince1970) // HM not needed since we use mostRecent (PNotification)
//            }
            
#if DEBUG
            L.og.info("New followers (\(self.newFollowerPubkeys.count)) notification, for \(pubkey)")
            L.og.debug("Prefetching kind 0 for first 10 new followers")
#endif
            QueuedFetcher.shared.enqueue(pTags: Array(self.newFollowerPubkeys.prefix(10)))
            self.newFollowerPubkeys.removeAll()
            DataProvider.shared().saveToDisk(.bgContext)
        }
    }
}
