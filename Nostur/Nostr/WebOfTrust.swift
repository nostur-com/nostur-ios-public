//
//  WebOfTrust.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/06/2023.
//

// Where should we handle spam?
// Nostur does not have global, so that is not a problem
// Posts are loaded from people you follow, unfollow if they spam
// Replies are shown from all, here we need to stop spam
// Notifications (#p) can be spam
// DM's can have spam (new requests)
// So basically just 3 places to filter

// We can search hashtag, but follow hashtag is not a thing yet so low prio

// PLAN: What do we white list:
// Followers + Followers of followers
// We can create a Web of Trust setting, strict, normal or off.

// In the future we could have more data points (badges, nip05, post counts, interactions with followers, etc
// Could also add quality check, don't use follows from people who follow too many people, what is the nostr-dunbar number?

import SwiftUI
import FileProvider
import Foundation
import Combine

class WebOfTrust: ObservableObject {
 
    let ENABLE_THRESHOLD = 1000 // To not degrade onboarding/new user experience, we should have more contacts in WoT than this threshold before the filter is active
    
    // For views
    @Published var lastUpdated:Date? = nil {
        didSet {
            SettingsStore.shared.objectWillChange.send() // update Settings screen
        }
    }
    @Published var allowedKeysCount:Int = 0 {
        didSet {
            SettingsStore.shared.objectWillChange.send() // update Settings screen
        }
    }
    
    // Only accessed from bg thread
    // Keep seperate lists for faster filtering
    
    // follows of follows (NORMAL)
    private var followingFollowingPubkeys = Set<String>() {
        didSet {
            self.updateViewData()
        }
    }
    
    // Only follows (STRICT)
    private var followingPubkeys:Set<String> {
        didSet {
            self.updateViewData()
        }
    }

    private func updateViewData() {
        DispatchQueue.main.async {
            if SettingsStore.shared.webOfTrustLevel == SettingsStore.WebOfTrustLevel.strict.rawValue {
                self.allowedKeysCount = self.followingPubkeys.count
            }
            else {
                self.allowedKeysCount = self.followingPubkeys.count + self.followingFollowingPubkeys.count
            }
        }
    }
    
    var backlog:Backlog {
        get { NosturState.shared.backlog }
        set { NosturState.shared.backlog = newValue }
    }
    var subscriptions = Set<AnyCancellable>()
    
    init(pubkey:String, followingPubkeys:Set<String>) {
        self.pubkey = pubkey
        self.followingPubkeys = followingPubkeys
        updateWoTonNewFollowing()
    }
    
    private func updateWoTonNewFollowing() {
        receiveNotification(.followingAdded)
            .sink { [weak self] notification in
                guard let self = self else { return }
                guard SettingsStore.shared.webOfTrustLevel != SettingsStore.WebOfTrustLevel.off.rawValue else { return }
                guard NosturState.shared.account != nil else { return }
                let pubkey = notification.object as! String
                self.followingPubkeys.insert(pubkey)
                guard SettingsStore.shared.webOfTrustLevel == SettingsStore.WebOfTrustLevel.normal.rawValue else { return }
                self.updateWoTwithFollowsOf(pubkey)
            }
            .store(in: &subscriptions)
    }
    
    private func updateWoTwithFollowsOf(_ pubkey:String) {
        // Fetch kind 3 for pubkey
        let task = ReqTask(
            prefix: "S-WoTFol-",
            reqCommand: { taskId in
                L.sockets.debug("🕸️🕸️ WebOfTrust/WoTFol: updateWoTwithFollowsOf - Fetching contact list for \(pubkey)")
                req(RM.getAuthorContactsList(pubkey: pubkey, subscriptionId: taskId))
            },
            processResponseCommand: { [weak self] taskId, _ in
                L.sockets.debug("🕸️🕸️ WebOfTrust/WoTFol: updateWoTwithFollowsOf - Received contact list")
                self?.regenerateWoTWithFollowsOf(pubkey)
            },
            timeoutCommand: {  [weak self] _ in
                L.sockets.debug("🕸️🕸️ WebOfTrust/WoTFol: updateWoTwithFollowsOf - Time-out")
                self?.regenerateWoTWithFollowsOf(pubkey)
            })

        backlog.add(task)
        task.fetch()
    }
    
    private func regenerateWoTWithFollowsOf(_ pubkey:String) {
        var followsOfPubkey = Set<String>()
        DataProvider.shared().bg.perform { [weak self] in
            guard let self = self else { return }
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "kind == 3 AND pubkey == %@", pubkey)
            fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: true)]
            if let list = try? DataProvider.shared().bg.fetch(fr).first {
                followsOfPubkey = followsOfPubkey.union( Set(list.fastPs.map { $0.1 }) )
            }
            let newSet = self.followingFollowingPubkeys.union(followsOfPubkey)
            
            DispatchQueue.main.async {
                self.followingFollowingPubkeys = newSet
                L.sockets.debug("🕸️🕸️ WebOfTrust/WoTFol: allowList now has \(self.followingPubkeys.count) + \(self.followingFollowingPubkeys.count) pubkeys")
            }
            self.storeData(pubkeys: newSet, pubkey: pubkey)
        }
    }
    
    // TODO: Listen for follow changes
    
    public func isAllowed(_ pubkey:String) -> Bool {
        if SettingsStore.shared.webOfTrustLevel != SettingsStore.WebOfTrustLevel.strict.rawValue && allowedKeysCount < ENABLE_THRESHOLD { return true }
        
        // Maybe check small set first, faster?
        if followingPubkeys.contains(pubkey) { return true }
        
        // if strict, we don't have to check the follows-follows list
        if SettingsStore.shared.webOfTrustLevel == SettingsStore.WebOfTrustLevel.strict.rawValue {
            return false
        }
        return followingFollowingPubkeys.contains(pubkey)
    }
    
    private var pubkey:String
    
    // This is for "normal" mode (follows + follows of follows)
    public func loadNormal(force:Bool = false) { // force = true to force fetching (update)
        self.loadFollowingFollowing(force: force)
        
        if let lastUpdated = lastUpdatedDate(pubkey) {
            L.og.debug("🕸️🕸️ WebOfTrust/WoTFol: lastUpdatedDate: web-of-trust-\(self.pubkey).txt --> \(lastUpdated.description)")
            DispatchQueue.main.async {
                self.lastUpdated = lastUpdated
            }
        }
    }
    
    // force = true to force fetching (update) - else will only use what is already on disk
    private func loadFollowingFollowing(force:Bool = false) {
        // Load from disk
        self.followingFollowingPubkeys = self.loadData(pubkey)

        var pubkeys = followingPubkeys
        pubkeys.remove(pubkey)
        
        guard self.followingFollowingPubkeys.count < 10 || force == true else { return }
        
        guard !NosturState.shared.didWoT.contains(pubkey) || force == true else { return }
        NosturState.shared.didWoT.insert(pubkey)
        
        // Fetch kind 3s
        let task = ReqTask(
            prefix: "WoTFol-",
            reqCommand: { taskId in
                L.sockets.debug("🕸️🕸️ WebOfTrust/WoTFol: Fetching contact lists for \(pubkeys.count) contacts")
                req(RM.getAuthorContactsLists(pubkeys: Array(pubkeys), subscriptionId: taskId))
            },
            processResponseCommand: { [weak self] taskId, _ in
                L.sockets.debug("🕸️🕸️ WebOfTrust/WoTFol: Received contact list(s)")
                self?.generateWoT()
            },
            timeoutCommand: { [weak self] taskId in
                L.sockets.debug("🕸️🕸️ WebOfTrust/WoTFol: Time-out")
                self?.generateWoT()
            })

        backlog.add(task)
        task.fetch()
    }
    
    private func generateWoT() {
        var followFollows = Set<String>()
        DataProvider.shared().bg.perform { [weak self] in
            guard let self = self else { return }
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "kind == 3 AND pubkey IN %@", followingPubkeys)
            if let contactLists = try? DataProvider.shared().bg.fetch(fr) {
                for list in contactLists {
                    let pubkeys = Set(list.fastPs.map { $0.1 })
                    followFollows = followFollows.union(pubkeys)
                }
            }
            
            DispatchQueue.main.async {
                self.followingFollowingPubkeys = followFollows
                L.sockets.debug("🕸️🕸️ WebOfTrust/WoTFol: allowList now has \(self.followingPubkeys.count) + \(self.followingFollowingPubkeys.count) pubkeys")
            }
            self.storeData(pubkeys: followFollows, pubkey: pubkey)
        }
    }
    
    private func storeData(pubkeys:Set<String>, pubkey:String) {
        do {
            let filename = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("web-of-trust-\(pubkey).txt")
            
            try pubkeys.joined(separator: "\n").write(to: filename, atomically: true, encoding: String.Encoding.utf8)
            
            if let lastUpdated = lastUpdatedDate(pubkey) {
                L.og.info("🕸️🕸️ WebOfTrust/WoTFol: lastUpdatedDate: web-of-trust-\(pubkey).txt --> \(lastUpdated.description)")
                DispatchQueue.main.async {
                    self.lastUpdated = lastUpdated
                }
            }
        }
        catch {
            L.og.error("🕸️🕸️ WebOfTrust/WoTFol: Failed to write file: web-of-trust-\(pubkey).txt: \(error)")
        }
    }
    
    // Get data from documents directory
    private func loadData(_ pubkey:String) -> Set<String> {
        do {
            let filename = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                .appendingPathComponent("web-of-trust-\(pubkey).txt")
            
            let input = try String(contentsOf: filename)
            let pubkeys = Set(input.components(separatedBy: "\n"))
            if pubkeys.count < 2 {
                // Something wrong, delete corrupt file
                do {
                    try FileManager.default.removeItem(at: filename)
                    L.og.error("🕸️🕸️ WebOfTrust/WoTFol: Something wrong, deleting corrupt file: web-of-trust-\(pubkey).txt")
                } catch {
                    L.og.error("🕸️🕸️ WebOfTrust/WoTFol: Something wrong, but could not delete file: web-of-trust-\(pubkey).txt: \(error)")
                }
                return Set<String>()
            }
            return pubkeys
        }
        catch {
            L.og.error("🕸️🕸️ WebOfTrust/WoTFol: Failed to read file: web-of-trust-\(pubkey).txt: \(error)")
            return Set<String>()
        }
    }
    
    public func loadLastUpdatedDate() {
        if let date = self.lastUpdatedDate(pubkey) {
            DispatchQueue.main.async {
                self.lastUpdated = date
            }
        }
    }
    
    private func lastUpdatedDate(_ pubkey:String) -> Date? {
        do {
            let filename = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                .appendingPathComponent("web-of-trust-\(pubkey).txt")

            let attributes = try FileManager.default.attributesOfItem(atPath: filename.path)
            let date = attributes[FileAttributeKey.modificationDate] as! Date
            return date
        }
        catch {
            L.og.debug("🕸️🕸️ WebOfTrust/WoTFol: lastUpdatedDate? doesn't exist yet: web-of-trust-\(pubkey).txt")
            return nil
        }
    }
}

func WOT_FILTER_ENABLED() -> Bool {
    SettingsStore.shared.webOfTrustLevel != SettingsStore.WebOfTrustLevel.off.rawValue
}
