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

class WebOfTrust: ObservableObject {
 
    let ENABLE_THRESHOLD = 200 // To not degrade onboarding/new user experience, we should have more contacts in WoT than this threshold before the filter is active
    
    // For views
    @Published var lastUpdated:Date? = nil
    @Published var allowedKeysCount:Int = 0
    
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
    
    init(pubkey:String, followingPubkeys:Set<String>) {
        self.pubkey = pubkey
        self.followingPubkeys = followingPubkeys
    }
    
    // TODO: Listen for follow changes
    
    public func isAllowed(_ pubkey:String) -> Bool {
        if allowedKeysCount < ENABLE_THRESHOLD { return true }
        
        // Maybe check small set first, faster?
        if followingPubkeys.contains(pubkey) { return true }
        
        // if strict, we don't have to check the follows-follows list
        if SettingsStore.shared.webOfTrustLevel == SettingsStore.WebOfTrustLevel.strict.rawValue {
            return false
        }
        return followingFollowingPubkeys.contains(pubkey)
    }
    
    private var pubkey:String
    
    public func loadNormal() { // This is for "normal" mode (follows + follows of follows)
        if let lastUpdated = lastUpdatedDate(pubkey) {
            L.og.info("🕸️🕸️ WebOfTrust: lastUpdatedDate: web-of-trust-\(self.pubkey).txt --> \(lastUpdated.description)")
            DispatchQueue.main.async {
                self.lastUpdated = lastUpdated
            }
        }
        self.loadFollowingFollowing()
    }
    
    private func loadFollowingFollowing() {
        // Load from disk
        self.followingFollowingPubkeys = self.loadData(pubkey)
        
        var pubkeys = followingPubkeys
        pubkeys.remove(pubkey)
        
        // Fetch kind 3's
        let task = ReqTask(
            prefix: "WoTFol-",
            reqCommand: { (taskId) in
                L.sockets.info("🕸️🕸️ WebOfTrust: Fetching contact lists for \(pubkeys.count) contacts")
                req(RM.getAuthorContactsLists(pubkeys: Array(pubkeys), subscriptionId: taskId))
            },
            processResponseCommand: { [weak self] (taskId, _) in
                guard let self = self else { return }
                L.sockets.debug("🕸️🕸️ WebOfTrust: Received contact list(s)")
                self.generateWoT()
            },
            timeoutCommand: { [weak self] (taskId) in
                guard let self = self else { return }
                L.sockets.info("🕸️🕸️ WebOfTrust: Time-out")
                self.generateWoT()
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
                L.sockets.debug("🕸️🕸️ WebOfTrust: allowList now has \(self.followingPubkeys.count) + \(self.followingFollowingPubkeys.count) pubkeys")
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
                L.og.info("🕸️🕸️ WebOfTrust: lastUpdatedDate: web-of-trust-\(pubkey).txt --> \(lastUpdated.description)")
                DispatchQueue.main.async {
                    self.lastUpdated = lastUpdated
                }
            }
        }
        catch {
            L.og.error("🕸️🕸️ WebOfTrust: Failed to write file: web-of-trust-\(pubkey).txt: \(error)")
        }
    }
    
    // Get data from documents directory
    private func loadData(_ pubkey:String) -> Set<String> {
        do {
            let filename = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                .appendingPathComponent("web-of-trust-\(pubkey).txt")
            
            let input = try String(contentsOf: filename)
            let pubkeys = Set(input.components(separatedBy: "\n"))
            return pubkeys
        }
        catch {
            L.og.error("🕸️🕸️ WebOfTrust: Failed to read file: web-of-trust-\(pubkey).txt: \(error)")
            return Set<String>()
        }
    }
    
    public func loadLastUpdatedDate() {
        if let date = self.lastUpdatedDate(pubkey) {
            self.lastUpdated = date
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
            L.og.info("🕸️🕸️ WebOfTrust: lastUpdatedDate? doesn't exist yet: web-of-trust-\(pubkey).txt")
            return nil
        }
    }
}

func WOT_FILTER_ENABLED() -> Bool {
    SettingsStore.shared.webOfTrustLevel != SettingsStore.WebOfTrustLevel.off.rawValue
}
