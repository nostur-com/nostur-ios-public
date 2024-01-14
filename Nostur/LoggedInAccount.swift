//
//  LoggedInAccount.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/09/2023.
//

import SwiftUI
import CoreData

// Must be initialized with account
class LoggedInAccount: ObservableObject {

    // VIEW
    @Published public var pubkey:String
    
    public var viewFollowingPublicKeys:Set<String> = []
    
    @MainActor public func isFollowing(pubkey: String) -> Bool {
        viewFollowingPublicKeys.contains(pubkey)
    }
    
    // USER ACTIONS - TRIGGERED FROM VIEWS
    
    @MainActor public func follow(_ pubkey:String) {
        viewFollowingPublicKeys.insert(pubkey)
        
        bg.perform {
            guard let account = self.bgAccount else { return }
            if let contact = Contact.contactBy(pubkey: pubkey, context: self.bg) {
                contact.couldBeImposter = 0
                account.followingPubkeys.insert(pubkey)
            }
            else {
                // if nil, create new contact
                let contact = Contact(context: self.bg)
                contact.pubkey = pubkey
                contact.couldBeImposter = 0
                account.followingPubkeys.insert(pubkey)
            }
            self.followingPublicKeys = self.viewFollowingPublicKeys
            self.followingPFPs = account.getFollowingPFPs()
            
            account.publishNewContactList()
            DispatchQueue.main.async {
                sendNotification(.followersChanged, self.viewFollowingPublicKeys)
                sendNotification(.followingAdded, pubkey)
            }
        }
    }
    
    @MainActor public func follow(_ contact:Contact, pubkey: String) {
        viewFollowingPublicKeys.insert(pubkey)
        bg.perform {
            guard let contact = self.bg.object(with: contact.objectID) as? Contact else {
                L.og.error("🔴🔴 Contact in main but not in bg")
                return
            }
            guard let account = self.bgAccount else { return }
            contact.couldBeImposter = 0
            account.followingPubkeys.insert(pubkey)
            bgSave()
            
            self.followingPublicKeys = self.viewFollowingPublicKeys
            self.followingPFPs = account.getFollowingPFPs()

            account.publishNewContactList()
            DispatchQueue.main.async {
                sendNotification(.followersChanged, self.viewFollowingPublicKeys)
                sendNotification(.followingAdded, pubkey)
            }
        }
    }
    
    @MainActor public func unfollow(_ pubkey: String) {
        viewFollowingPublicKeys.remove(pubkey)
        bg.perform {
            guard let account = self.bgAccount else { return }
            account.followingPubkeys.remove(pubkey)
            bgSave()
            self.followingPublicKeys = self.viewFollowingPublicKeys
            self.followingPFPs = account.getFollowingPFPs()
            
            account.publishNewContactList()
            DispatchQueue.main.async {
                sendNotification(.followersChanged, self.viewFollowingPublicKeys)
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
    
    
    // BG high speed
    public var followingPublicKeys: Set<String> = []
    public var followingPFPs: [String: URL] = [:]
    
    // View context
    @Published var account: CloudAccount {
        didSet { // REMINDER, didSet does not run on init!
            Task { @MainActor in
                self.setupAccount(account)
            }
        }
    }
    
    // BG context
    public var bgAccount:CloudAccount? = nil
    
    public var mutedWords:[String] = []
    
    @MainActor public init(_ account:CloudAccount) {
        self.bg = Nostur.bg()
        self.pubkey = account.publicKey
        self.account = account
        self.setupAccount(account)
    }
    
    @MainActor private func setupAccount(_ account: CloudAccount) {
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
        
        // Remove currectly active "Following" subscriptions from connected sockets
        ConnectionPool.shared.removeActiveAccountSubscriptions()
        
        self.bg.perform {
            guard let bgAccount = try? self.bg.existingObject(with: self.account.objectID) as? CloudAccount else {
                L.og.notice("🔴🔴 Problem loading bgAccount")
                return
            }
            self.bgAccount = bgAccount
            
            self.followingPublicKeys = follows
            self.followingPFPs = bgAccount.getFollowingPFPs()
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
            }
        }
    }
    
    // If CloudAccount is following has 12 pubkeys, but kind 3 in db has 21 pubkeys and is newest, it will not update at login
    // So we need to handle the existing kind 3 as if .newFollowingListFromRelay
    // Above situaten can happen if we login on other account, then somehow fetch our kind 3, because we are
    // not logged in we're not updating properly as its not our logged in account. So as work around on account change
    // is to check the kind 3 and handle again if needed
    public func reprocessContactListIfNeeded(_ account: CloudAccount) {
        guard let kind3 = Event.fetchMostRecentEventBy(pubkey: account.publicKey, andKind: 3, context: context()) else {
            return
        }
        if account.followingPubkeys.count < kind3.fastPs.count {
            L.og.debug("refetchContactListIfNeeded: Deleting because we need to refetch and parse")
            DispatchQueue.main.async {
                sendNotification(.newFollowingListFromRelay, kind3.toNEvent())
            }
        }
    }
    
    public func changeAccount(account: CloudAccount) {
        self.account = account
    }
    
    public func reloadFollows() {
        self.bg.perform {
            guard let bgAccount = self.bgAccount else { return } 
            self.followingPublicKeys = bgAccount.getFollowingPublicKeys(includeBlocked: true)
            self.followingPFPs = bgAccount.getFollowingPFPs()
        
            DispatchQueue.main.async {
                self.viewFollowingPublicKeys = self.followingPublicKeys
                sendNotification(.followersChanged, self.followingPublicKeys)
            }
        }
    }
    
    
    
    
    // Other
    private var bg:NSManagedObjectContext
}
