//
//  LoggedInAccount.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/09/2023.
//

import SwiftUI
import CoreData
import NostrEssentials

// Must be initialized with account
class LoggedInAccount: ObservableObject {

    // VIEW
    @Published public var pubkey: String
    
    @Published public var viewFollowingPublicKeys: Set<String> = []
    
    @MainActor public func isFollowing(pubkey: String) -> Bool {
        viewFollowingPublicKeys.contains(pubkey)
    }
    
    @MainActor public func isPrivateFollowing(pubkey: String) -> Bool {
        account.privateFollowingPubkeys.contains(pubkey)
    }
    
    // USER ACTIONS - TRIGGERED FROM VIEWS
    
    @MainActor public func follow(_ pubkey: String, privateFollow: Bool = false) {
        viewFollowingPublicKeys.insert(pubkey)
        if privateFollow {
            account.followingPubkeys.remove(pubkey)
            account.privateFollowingPubkeys.insert(pubkey)
        }
        else {
            account.followingPubkeys.insert(pubkey)
        }
        account.publishNewContactList() // Should always publish  so if unfollow (1) -> follow (2) -> private follow (3),  .publishLast() will publish (3) and not (2) if we don't publish on private follow action.
                
        viewContextSave()
        
        let viewFollowingPublicKeys = viewFollowingPublicKeys
        
        bg.perform { [weak self] in
            guard let self else { return }
            
            let contact: Contact = Contact.contactBy(pubkey: pubkey, context: self.bg) ?? Contact(context: self.bg)
            contact.pubkey = pubkey
            contact.couldBeImposter = 0
            
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
    
    @MainActor public func unfollow(_ pubkey: String) {
        viewFollowingPublicKeys.remove(pubkey)
        account.followingPubkeys.remove(pubkey)
        account.privateFollowingPubkeys.remove(pubkey)
        account.publishNewContactList()
        viewContextSave()
        
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
    
    @MainActor public func report(_ event:Event, reportType:ReportType, note:String = "", includeProfile:Bool = false) -> NEvent? {
        guard account.isFullAccount else { NRState.shared.readOnlyAccountSheetShown = true; return nil }
        
        let report = EventMessageBuilder.makeReportEvent(pubkey: event.pubkey, eventId: event.id, type: reportType, note: note, includeProfile: includeProfile)

        guard let signedEvent = try? account.signEvent(report) else {
            L.og.error("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
            return nil
        }
        return signedEvent
    }
    
    @MainActor public func reportContact(pubkey:String, reportType:ReportType, note:String = "") -> NEvent? {
        guard account.isFullAccount else { NRState.shared.readOnlyAccountSheetShown = true; return nil }
        
        let report = EventMessageBuilder.makeReportContact(pubkey: pubkey, type: reportType, note: note)

        guard let signedEvent = try? account.signEvent(report) else {
            L.og.error("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
            return nil
        }
        return signedEvent
    }
    
    @MainActor public func deletePost(_ eventId:String) -> NEvent? {
        guard account.isFullAccount else { NRState.shared.readOnlyAccountSheetShown = true; return nil }
        
        let deletion = EventMessageBuilder.makeDeleteEvent(eventId: eventId)

        guard let signedEvent = try? account.signEvent(deletion) else {
            L.og.error("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
            return nil
        }
        return signedEvent
    }
    
    private var outboxLoader: OutboxLoader? = nil
    
    // BG high speed
    public var accountCache: AccountCache?
    public var followingPublicKeys: Set<String> = []
    public var followingCache: [String: FollowCache] = [:]
    
    // View context
    @Published var account: CloudAccount {
        didSet { // REMINDER, didSet does not run on init!
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.setupAccount(account)
            }
        }
    }
    
    // BG context
    public var bgAccount: CloudAccount? = nil
    
    public var mutedWords: [String] = []
    
    @MainActor public init(_ account: CloudAccount) {
        self.bg = Nostur.bg()
        self.pubkey = account.publicKey
        self.account = account
        self.setupAccount(account)
    }
    
    @MainActor private func setupAccount(_ account: CloudAccount) {
        NRContactCache.shared.clear()
        self.pubkey = pubkey
        
        // Set to true only if it is a brand new account, otherwise set to false and wait for kind 3 from relay
        if account.flagsSet.contains("nostur_created") {
            FollowingGuardian.shared.didReceiveContactListThisSession = true
        }
        else {
            FollowingGuardian.shared.didReceiveContactListThisSession = false
        }
        
        let follows = account.getFollowingPublicKeys(includeBlocked: true) // if we do this in bg.perform it loads too late for other views
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
                sendNotification(.activeAccountChanged, account)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if SettingsStore.shared.webOfTrustLevel == SettingsStore.WebOfTrustLevel.off.rawValue {
                    WebOfTrust.shared.loadWoT()
                    DirectMessageViewModel.default.load()
                }
                else {
                    DirectMessageViewModel.default.loadAfterWoT()
                    WebOfTrust.shared.loadWoT()
                }
                
                self.outboxLoader = OutboxLoader(pubkey: self.pubkey, follows: follows, cp: ConnectionPool.shared)
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
    
    public func changeAccount(account: CloudAccount) {
        self.account = account
    }
    
    public func reloadFollows() {
        self.bg.perform { [weak self] in
            guard let self, let bgAccount = self.bgAccount else { return }
            self.followingPublicKeys = bgAccount.getFollowingPublicKeys(includeBlocked: true)
            self.followingCache = bgAccount.loadFollowingCache()
        
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.viewFollowingPublicKeys = self.followingPublicKeys
                sendNotification(.followsChanged, self.followingPublicKeys)
            }
        }
    }
    
    
    
    
    // Other
    private var bg: NSManagedObjectContext
}


public struct FollowCache {
    public let anyName: String
    public var pfpURL: URL?
    public var bgContact: Contact?
}
