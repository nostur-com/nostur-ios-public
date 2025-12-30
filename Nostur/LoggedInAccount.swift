//
//  LoggedInAccount.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/09/2023.
//

import SwiftUI
import CoreData
import NostrEssentials

// Helpers, cache etc for CloudAccount
// Must be initialized with account
class LoggedInAccount: ObservableObject, Equatable, Hashable {

    func hash(into hasher: inout Hasher) {
        hasher.combine(account.publicKey)
    }
    
    static func == (lhs: LoggedInAccount, rhs: LoggedInAccount) -> Bool {
        lhs.account.publicKey == rhs.account.publicKey
    }
    
    @MainActor
    public init(_ account: CloudAccount) {
        self.bg = Nostur.bg()
        self.account = account
        self.pubkey = account.publicKey
        self.setupAccount(account)
    }
    
    @Published
    public var pubkey: String
    
    @Published
    public var viewFollowingPublicKeys: Set<String> = []
    
    
    
    public var outboxLoader: OutboxLoader? = nil
    
    // BG high speed
    public var accountCache: AccountCache?
    public var followingPublicKeys: Set<String> = []
    public var followingCache: [String: FollowCache] = [:]
    
    // View context
    @Published
    var account: CloudAccount {
        didSet { // REMINDER, didSet does not run on init!
            Task { @MainActor [weak self] in
                guard let self else { return }
                if oldValue.publicKey != account.publicKey {
                    self.setupAccount(account)
                }
            }
        }
    }
    
    // BG context
    public var bgAccount: CloudAccount? = nil
    public var mutedWords: [String] = []
    
   
    
    
    
    
    // Other
    private var bg: NSManagedObjectContext
}

extension LoggedInAccount {
    
    // USER ACTIONS/METHODS - TRIGGERED FROM VIEWS
    @MainActor
    public func isFollowing(pubkey: String) -> Bool {
        viewFollowingPublicKeys.contains(pubkey)
    }
    
    @MainActor
    public func isPrivateFollowing(pubkey: String) -> Bool {
        account.privateFollowingPubkeys.contains(pubkey)
    }
    
    @MainActor
    public func follow(_ pubkey: String, privateFollow: Bool = false) {
        viewFollowingPublicKeys.insert(pubkey)
        if privateFollow {
            account.followingPubkeys.remove(pubkey)
            account.privateFollowingPubkeys.insert(pubkey)
        }
        else {
            account.followingPubkeys.insert(pubkey)
        }
        account.publishNewContactList() // Should always publish  so if unfollow (1) -> follow (2) -> private follow (3),  .publishLast() will publish (3) and not (2) if we don't publish on private follow action.
                
        DataProvider.shared().saveToDiskNow(.viewContext)
        
        let viewFollowingPublicKeys = viewFollowingPublicKeys
        
        bg.perform { [weak self] in
            guard let self else { return }
            
            let contact: Contact = Contact.fetchByPubkey(pubkey, context: self.bg) ?? Contact(context: self.bg)
            contact.pubkey = pubkey
            contact.couldBeImposter = 0
            contact.similarToPubkey = nil
            
            self.followingPublicKeys = viewFollowingPublicKeys
            
            let pfpURL: URL? = if let picture = contact.picture, picture.prefix(7) != "http://" {
                URL(string: picture)
            }
            else {
                nil
            }
            
            self.followingCache[contact.pubkey] = FollowCache(
                anyName: contact.anyName,
                pfpURL: pfpURL,
                bgContact: contact
            )
            
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                sendNotification(.followsChanged, self.viewFollowingPublicKeys)
                sendNotification(.followingAdded, pubkey)
            }
        }
    }
    
    public func multiFollow(_ pubkeys: Set<String>) {
        viewFollowingPublicKeys = viewFollowingPublicKeys.union(pubkeys)
        account.followingPubkeys = account.followingPubkeys.union(pubkeys)
        account.publishNewContactList()
        DataProvider.shared().saveToDiskNow(.viewContext)
        
        let viewFollowingPublicKeys = viewFollowingPublicKeys
        
        bg.perform { [weak self] in
            guard let self else { return }
            
            for pubkey in pubkeys {
                let contact: Contact = Contact.fetchByPubkey(pubkey, context: self.bg) ?? Contact(context: self.bg)
                contact.pubkey = pubkey
                contact.couldBeImposter = 0
                contact.similarToPubkey = nil
                
                let pfpURL: URL? = if let picture = contact.picture, picture.prefix(7) != "http://" {
                    URL(string: picture)
                }
                else {
                    nil
                }
                
                self.followingCache[contact.pubkey] = FollowCache(
                    anyName: contact.anyName,
                    pfpURL: pfpURL,
                    bgContact: contact
                )
            }
            
            self.followingPublicKeys = viewFollowingPublicKeys
            
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                sendNotification(.followsChanged, self.viewFollowingPublicKeys)
                sendNotification(.followingAdded)
            }
        }
    }
    
    @MainActor
    public func unfollow(_ pubkey: String) {
        viewFollowingPublicKeys.remove(pubkey)
        account.followingPubkeys.remove(pubkey)
        account.privateFollowingPubkeys.remove(pubkey)
        account.publishNewContactList()
        DataProvider.shared().saveToDiskNow(.viewContext)
        
        let viewFollowingPublicKeys = viewFollowingPublicKeys
        
        bg.perform { [weak self] in
            guard let self else { return }

            self.followingPublicKeys = viewFollowingPublicKeys
            self.followingCache[pubkey] = nil
            
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                sendNotification(.followsChanged, self.viewFollowingPublicKeys)
            }
        }
    }
    
    @MainActor
    public func report(pubkey: String, eventId: String, reportType: ReportType, note:String = "", includeProfile:Bool = false) -> NEvent? {
        guard account.isFullAccount else { AppSheetsModel.shared.readOnlySheetVisible = true; return nil }
        
        let report = EventMessageBuilder.makeReportEvent(pubkey: pubkey, eventId: eventId, type: reportType, note: note, includeProfile: includeProfile)

        guard let signedEvent = try? account.signEvent(report) else {
            L.og.error("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
            return nil
        }
        return signedEvent
    }
    
    @MainActor
    public func reportContact(pubkey:String, reportType:ReportType, note:String = "") -> NEvent? {
        guard account.isFullAccount else { AppSheetsModel.shared.readOnlySheetVisible = true; return nil }
        
        let report = EventMessageBuilder.makeReportContact(pubkey: pubkey, type: reportType, note: note)

        guard let signedEvent = try? account.signEvent(report) else {
            L.og.error("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
            return nil
        }
        return signedEvent
    }
    
    @MainActor
    public func deletePost(_ eventId:String) -> NEvent? {
        guard account.isFullAccount else { AppSheetsModel.shared.readOnlySheetVisible = true; return nil }
        
        let deletion = EventMessageBuilder.makeDeleteEvent(eventId: eventId)

        guard let signedEvent = try? account.signEvent(deletion) else {
            L.og.error("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
            return nil
        }
        return signedEvent
    }
    
    
    
    @MainActor
    private func setupAccount(_ account: CloudAccount) {
        self.pubkey = account.publicKey
        // Set to true only if it is a brand new account, otherwise set to false and wait for kind 3 from relay
        if account.flagsSet.contains("nostur_created") {
            FollowingGuardian.shared.didReceiveContactListThisSession = true
        }
        else {
            FollowingGuardian.shared.didReceiveContactListThisSession = false
        }
        
        let follows = account.getFollowingPublicKeys(includeBlocked: true)
            .union(account.privateFollowingPubkeys) // if we do this in bg.perform it loads too late for other views
        self.viewFollowingPublicKeys = follows
        
        // Remove currently active "Following" subscriptions from connected sockets
        ConnectionPool.shared.removeActiveAccountSubscriptions()
        
        self.bg.perform { [weak self] in
            guard let self = self else { return }
            guard let bgAccount = try? self.bg.existingObject(with: self.account.objectID) as? CloudAccount else {
                L.og.notice("🔴🔴 Problem loading bgAccount")
                return
            }
            self.bgAccount = bgAccount
            self.accountCache = AccountCache(self.pubkey)
            
            self.followingPublicKeys = follows
            self.followingCache = bgAccount.loadFollowingCache()
            self.reprocessContactListIfNeeded(bgAccount)
            
            DispatchQueue.main.async {
                // Probably should not use this. Observe LoggedInAccount instead
                sendNotification(.activeAccountChanged, account)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if SettingsStore.shared.webOfTrustLevel == SettingsStore.WebOfTrustLevel.off.rawValue {
                    Task { @MainActor in
                        await DMsVM.shared.reload(accountPubkey: self.pubkey)
                    }
                }
                else {
                    WebOfTrust.shared.loadWoT()
                }
                
                if SettingsStore.shared.enableOutboxRelays {   
                    self.outboxLoader = OutboxLoader(pubkey: self.pubkey, follows: follows, cp: ConnectionPool.shared)
                }
            }
        }
    }
    
    // If CloudAccount is following has 12 pubkeys, but kind 3 in db has 21 pubkeys and is newest, it will not update at login
    // So we need to handle the existing kind 3 as if .newFollowingListFromRelay
    // Above situation can happen if we login on other account, then somehow fetch our kind 3, because we are
    // not logged in we're not updating properly as its not our logged in account. So as work around on account change
    // is to check the kind 3 and handle again if needed
    public func reprocessContactListIfNeeded(_ account: CloudAccount) {
        guard let kind3 = Event.fetchMostRecentEventBy(pubkey: account.publicKey, andKind: 3, context: context()) else {
            return
        }
        if account.followingPubkeys.count < kind3.fastPs.count {
            let kind3nEvent = kind3.toNEvent()
            DispatchQueue.main.async {
                sendNotification(.newFollowingListFromRelay, kind3nEvent)
            }
        }
    }
    
    public func reloadFollows() {
        self.bg.perform { [weak self] in
            guard let self, let bgAccount = self.bgAccount else { return }
            self.followingPublicKeys = bgAccount.getFollowingPublicKeys(includeBlocked: true)
                .union(bgAccount.privateFollowingPubkeys)
            self.followingCache = bgAccount.loadFollowingCache()
        
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.viewFollowingPublicKeys = self.followingPublicKeys
                sendNotification(.followsChanged, self.followingPublicKeys)
            }
        }
    }
}


public struct FollowCache {
    public let anyName: String
    public var pfpURL: URL?
    public var bgContact: Contact?
}
