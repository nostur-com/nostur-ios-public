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
// Follows + Follows of follows
// We can create a Web of Trust setting, strict, normal or off.

// In the future we could have more data points (badges, nip05, post counts, interactions with followers, etc
// Could also add quality check, don't use follows from people who follow too many people

import SwiftUI
import FileProvider
import Foundation
import Combine

class WebOfTrust: ObservableObject {
    
    static let shared = WebOfTrust()
 
    private let ENABLE_THRESHOLD = 2000 // To not degrade onboarding/new user experience, we should have more contacts in WoT than this threshold before the filter is active
    
    public var tresholdReached: Bool {
        allowedKeysCount >= ENABLE_THRESHOLD
    }
    
    @AppStorage("wotDunbarNumber") private var wotDunbarNumber: Int = 1000
    
    // UserDefaults can be slow and its called every .isAllowed() so cache the value in .mainAccountWoTpubkey
    @AppStorage("main_wot_account_pubkey") private var _mainAccountWoTpubkey = "" {
        didSet {
            mainAccountWoTpubkey = _mainAccountWoTpubkey
        }
    }
    
    // cached
    private var mainAccountWoTpubkey: String = ""
    
    // For views
    @Published public var lastUpdated: Date? = nil
    
    @Published public var allowedKeysCount: Int = 0
    
    @Published public var updatingWoT = false
    
    // Only accessed from bg thread
    // Keep separate lists for faster filtering
    
    // follows of follows (NORMAL)
    private var followingFollowingPubkeys: Set<String> = [] {
        didSet {
            self.updateViewData()
        }
    }
    
    // Only follows (STRICT)
    private var followingPubkeys: Set<String> = [] {
        didSet {
            self.updateViewData()
        }
    }

    public func updateViewData() {
        let allowedKeysCount = switch SettingsStore.shared.webOfTrustLevel {
            case SettingsStore.WebOfTrustLevel.strict.rawValue:
                self.followingPubkeys.count
            case SettingsStore.WebOfTrustLevel.normal.rawValue:
                self.followingFollowingPubkeys.union(self.followingPubkeys).count
            case SettingsStore.WebOfTrustLevel.off.rawValue:
                0
            default:
                0
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.allowedKeysCount = self.mainAccountWoTpubkey == "" ? 0 : allowedKeysCount
        }
    }
    
    var didWoT = false
    
    private var backlog = Backlog(timeout: 60, auto: true)
    private var subscriptions = Set<AnyCancellable>()
    
    private init() {
        mainAccountWoTpubkey = UserDefaults.standard.string(forKey: SettingsStore.Keys.mainWoTaccountPubkey) ?? ""
        if _mainAccountWoTpubkey == "" {
            DispatchQueue.main.async { [weak self] in
                self?.guessMainAccount()
            }
        }
    }
    
    // For first time guessing the main account, user can change actual main account in Settings
    public func guessMainAccount() {
        guard _mainAccountWoTpubkey == "" else { return }
        // in preferred order:
        // 1. full account with most follows, and >50 follows
        // 2. read-only account currently logged and >50 follows

        // this ignores full accounts that are test accounts
        // and it ignores "login as someone else" accounts
        
        // so the main account is likely the currently logged in read-only account at start OR
        // any full-account with more than 50 follows, so we know its probably not a test throwaway account
        
        // never use the built-in guest account
        
        if let fullAccount = NRState.shared.accounts
            .filter({ $0.isFullAccount && $0.followingPubkeys.count > 50 && $0.publicKey != GUEST_ACCOUNT_PUBKEY }) // only full accounts with 50+ follows (exclude guest account)
            .sorted(by: { $0.followingPubkeys.count > $1.followingPubkeys.count }).first // sorted to get the one with the most follows
        {
            L.og.info("🕸️🕸️ WebOfTrust: Main WoT full account guessed: \(fullAccount.publicKey)")
            _mainAccountWoTpubkey = fullAccount.publicKey
        }
        // the currently logged in read only account, if it has 50+ follows but not if its the guest account
        else if let readOnlyAccount = NRState.shared.accounts
            .first(where: { $0.publicKey == NRState.shared.activeAccountPublicKey && $0.followingPubkeys.count > 50 && $0.publicKey != GUEST_ACCOUNT_PUBKEY })
        {
            L.og.info("🕸️🕸️ WebOfTrust: Main WoT read account guessed: \(readOnlyAccount.publicKey)")
            _mainAccountWoTpubkey = readOnlyAccount.publicKey
        }
    }
    
    public func loadWoT(force: Bool = false) {
        guard mainAccountWoTpubkey != "" else { return }
        guard SettingsStore.shared.webOfTrustLevel != SettingsStore.WebOfTrustLevel.off.rawValue else { return }
        guard let account = NRState.shared.accounts.first(where: { $0.publicKey == mainAccountWoTpubkey }) ?? (try? CloudAccount.fetchAccount(publicKey: mainAccountWoTpubkey, context: context())) else { return }
        L.og.info("🕸️🕸️ WebOfTrust: Main account: \(account.anyName)")
        
        let wotFollowingPubkeys = account.getFollowingPublicKeys(includeBlocked: true).subtracting(account.privateFollowingPubkeys) // We don't include silent follows in WoT
        let followingPubkeys = account.getFollowingPublicKeys(includeBlocked: true)
        
        bg().perform { [weak self] in
            guard let self else { return }
            self.followingPubkeys = followingPubkeys
            guard wotFollowingPubkeys.count > 10 else {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    sendNotification(.WoTReady)
                    self.updatingWoT = false
                }
                L.og.info("🕸️🕸️ WebOfTrust: Not enough follows to build WoT. Maybe still onboarding and contact list not received yet")
                return
            }
            
            switch SettingsStore.shared.webOfTrustLevel {
                case SettingsStore.WebOfTrustLevel.off.rawValue:
                    L.og.info("🕸️🕸️ WebOfTrust: Disabled")
                    sendNotification(.WoTReady)
                    self.updatingWoT = false
                case SettingsStore.WebOfTrustLevel.normal.rawValue:
                    L.og.info("🕸️🕸️ WebOfTrust: Normal")
                    bg().perform { [weak self] in
                        self?.loadNormal(wotFollowingPubkeys: wotFollowingPubkeys, force: force)
                    }
                case SettingsStore.WebOfTrustLevel.strict.rawValue:
                    L.og.info("🕸️🕸️ WebOfTrust: Strict")
                    self.addOwnFollowsIfNeeded()
                    sendNotification(.WoTReady)
                    self.updatingWoT = false
                default:
                    L.og.info("🕸️🕸️ WebOfTrust: Disabled")
                    sendNotification(.WoTReady)
                    self.updatingWoT = false
            }
        }
    }
    
    // If currently logged in account is not main WoT account
    // Also add our of follows to the main WoT.
    // BUT only after main WoT is loaded! so follows + follows-of-follows, and then add own follows
    // SO NOT: follows + add own follows, and then follows-of-follows
    // Order matters.
    private func addOwnFollowsIfNeeded() {
        guard let account = Nostur.account() else { return }
        guard mainAccountWoTpubkey != account.publicKey else { return }
        let ownFollows = account.followingPubkeys
        self.followingPubkeys = self.followingPubkeys.union(ownFollows)
    }
    
    private func updateWoTonNewFollowing() {
        receiveNotification(.followingAdded)
            .sink { [weak self] notification in
                guard let self = self else { return }
                guard SettingsStore.shared.webOfTrustLevel != SettingsStore.WebOfTrustLevel.off.rawValue else { return }
//                guard NosturState.shared.account != nil else { return } // TODO: NEED THIS?
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
            subscriptionId: "RM.getAuthorContactsList",
            reqCommand: { taskId in
                L.sockets.debug("🕸️🕸️ WebOfTrust/WoTFol: updateWoTwithFollowsOf - Fetching contact list for \(pubkey)")
                req(RM.getAuthorContactsList(pubkey: pubkey, subscriptionId: taskId))
            },
            processResponseCommand: { [weak self] taskId, _, _ in
                L.sockets.debug("🕸️🕸️ WebOfTrust/WoTFol: updateWoTwithFollowsOf - Received contact list")
                self?.regenerateWoTWithFollowsOf(pubkey)
            },
            timeoutCommand: { [weak self] _ in
                L.sockets.debug("🕸️🕸️ WebOfTrust/WoTFol: updateWoTwithFollowsOf - Time-out")
                self?.regenerateWoTWithFollowsOf(pubkey)
            })

        backlog.add(task)
        task.fetch()
    }
    
    private func regenerateWoTWithFollowsOf(_ otherPubkey:String) {
        guard mainAccountWoTpubkey != "" else { return }
        var followsOfPubkey = Set<String>()
        bg().perform { [weak self] in
            guard let self = self else { return }
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "kind == 3 AND pubkey == %@", otherPubkey)
            fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: true)]
            if let list = try? bg().fetch(fr).first {
                followsOfPubkey = followsOfPubkey.union( Set(list.fastPs.map { $0.1 }) )
            }
            if wotDunbarNumber == 0 || followsOfPubkey.count <= wotDunbarNumber {
                self.followingFollowingPubkeys = self.followingFollowingPubkeys.union(followsOfPubkey)
                L.sockets.debug("🕸️🕸️ WebOfTrust/WoTFol: allowList now has \(self.followingPubkeys.count) + \(self.followingFollowingPubkeys.count) pubkeys")
                self.storeData(pubkeys: self.followingFollowingPubkeys, pubkey: mainAccountWoTpubkey)
            }
        }
    }
    
    public var webOfTrustLevel:String = UserDefaults.standard.string(forKey: SettingsStore.Keys.webOfTrustLevel) ?? SettingsStore.WebOfTrustLevel.normal.rawValue // Faster then querying UserDefaults so cache here
    
    public func isAllowed(_ pubkey:String) -> Bool {
        // TODO: Accessing UserDefaults seems slow (mainAccountWoTpubkey)
        guard mainAccountWoTpubkey != "" else { return true }
        if webOfTrustLevel != SettingsStore.WebOfTrustLevel.strict.rawValue && allowedKeysCount < ENABLE_THRESHOLD { return true }
        
        // Maybe check small set first, faster?
        if followingPubkeys.contains(pubkey) { return true }
        
        // if strict, we don't have to check the follows-follows list
        if webOfTrustLevel == SettingsStore.WebOfTrustLevel.strict.rawValue {
            return false
        }
        return followingFollowingPubkeys.contains(pubkey)
    }
    
    // This is for "normal" mode (follows + follows of follows)
    public func loadNormal(wotFollowingPubkeys:Set<String>, force:Bool = false) { // force = true to force fetching (update)
        guard mainAccountWoTpubkey != "" else {
            sendNotification(.WoTReady)
            return
        }
        self.loadFollowingFollowing(wotFollowingPubkeys:wotFollowingPubkeys, force: force)
        if let lastUpdated = lastUpdatedDate(mainAccountWoTpubkey) {
            L.og.debug("🕸️🕸️ WebOfTrust/WoTFol: lastUpdatedDate: web-of-trust-\(self.mainAccountWoTpubkey).txt --> \(lastUpdated.description)")
            DispatchQueue.main.async { [weak self] in
                self?.lastUpdated = lastUpdated
            }
        }
    }
    
    // force = true to force fetching (update) - else will only use what is already on disk
    private func loadFollowingFollowing(wotFollowingPubkeys:Set<String>, force:Bool = false) {
        guard mainAccountWoTpubkey != "" else {
            sendNotification(.WoTReady)
            return
        }
        // Load from disk
        self.followingFollowingPubkeys = self.loadData(mainAccountWoTpubkey)

        var pubkeys = wotFollowingPubkeys
        pubkeys.remove(mainAccountWoTpubkey)
        
        guard self.followingFollowingPubkeys.count < ENABLE_THRESHOLD || force == true else {
            self.addOwnFollowsIfNeeded()
            sendNotification(.WoTReady)
            L.sockets.debug("🕸️🕸️ WebOfTrust/WoTFol: already have loaded enough from file")
            return
        }
        
        guard !didWoT || force == true else {
            self.addOwnFollowsIfNeeded()
            sendNotification(.WoTReady)
            L.sockets.debug("🕸️🕸️ WebOfTrust/WoTFol: already didWot")
            return
        }
        didWoT = true
        
        // Fetch kind 3s
        let task = ReqTask(
            debounceTime: 5.0, // in test, default 0.1 stops at 2000 contacts, with 5.0 its 10000+ contacts
            prefix: "WoTFol-",
            reqCommand: { taskId in
                L.sockets.debug("🕸️🕸️ WebOfTrust/WoTFol: Fetching contact lists for \(pubkeys.count) contacts")
                req(RM.getAuthorContactsLists(pubkeys: Array(pubkeys), subscriptionId: taskId))
            },
            processResponseCommand: { [weak self] taskId, _, _ in
                self?.updatingWoT = true
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
    
    public func localReload(wotFollowingPubkeys: Set<String>) {
        guard mainAccountWoTpubkey != "" else {
            sendNotification(.WoTReady)
            return
        }
        // Load from disk
        self.followingFollowingPubkeys = self.loadData(mainAccountWoTpubkey)

        var pubkeys = wotFollowingPubkeys
        pubkeys.remove(mainAccountWoTpubkey)

        generateWoT()
    }
    
    private func generateWoT() {
        guard mainAccountWoTpubkey != "" else {
            sendNotification(.WoTReady)
            updatingWoT = false
            return
        }
        bg().perform { [weak self] in
            guard let self = self else { return }
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "kind == 3 AND pubkey IN %@", followingPubkeys)
            var followFollows = Set<String>()
            if let contactLists = try? bg().fetch(fr) {
                for list in contactLists {
                    let pubkeys = Set(list.fastPs.map { $0.1 })
                    if wotDunbarNumber == 0 || pubkeys.count <= wotDunbarNumber {
                        followFollows = followFollows.union(pubkeys)
                    }
                }
            }
            self.followingFollowingPubkeys = followFollows
            self.addOwnFollowsIfNeeded()
            L.sockets.debug("🕸️🕸️ WebOfTrust/WoTFol: allowList now has \(self.followingPubkeys.count) + \(self.followingFollowingPubkeys.count) pubkeys")
            self.storeData(pubkeys: self.followingFollowingPubkeys, pubkey: mainAccountWoTpubkey)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                sendNotification(.WoTReady)
                self.updatingWoT = false
            }
        }
    }
    
    private func storeData(pubkeys:Set<String>, pubkey:String) {
        do {
            let filename = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("web-of-trust-\(pubkey).txt")
            
            try pubkeys.joined(separator: "\n").write(to: filename, atomically: true, encoding: String.Encoding.utf8)
            
            if let lastUpdated = lastUpdatedDate(pubkey) {
                L.og.info("🕸️🕸️ WebOfTrust/WoTFol: lastUpdatedDate: web-of-trust-\(pubkey).txt --> \(lastUpdated.description)")
                DispatchQueue.main.async { [weak self] in
                    self?.lastUpdated = lastUpdated
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
            let pubkeys = Set(input.split(separator: "\n").map { String($0) })
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
        guard mainAccountWoTpubkey != "" else { return }
        if let date = self.lastUpdatedDate(mainAccountWoTpubkey) {
            DispatchQueue.main.async { [weak self] in
                self?.lastUpdated = date
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
    WebOfTrust.shared.webOfTrustLevel != SettingsStore.WebOfTrustLevel.off.rawValue
}
