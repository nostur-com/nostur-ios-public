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
                account.addToFollows(contact)
            }
            else {
                // if nil, create new contact
                let contact = Contact(context: self.bg)
                contact.pubkey = pubkey
                contact.couldBeImposter = 0
                account.addToFollows(contact)
            }
            self.followingPublicKeys = self.viewFollowingPublicKeys
            self.followingPFPs = self.account.getFollowingPFPs()
            
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
            account.addToFollows(contact)
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
            guard let contact = Contact.contactBy(pubkey: pubkey, context: self.bg) else {
                return
            }
            account.removeFromFollows(contact)
            bgSave()
            self.followingPublicKeys = self.viewFollowingPublicKeys
            self.followingPFPs = account.getFollowingPFPs()
            
            account.publishNewContactList()
            DispatchQueue.main.async {
                sendNotification(.followersChanged, self.viewFollowingPublicKeys)
            }
        }
    }
    
    @MainActor public func unfollow(_ contact:Contact, pubkey:String) {
        viewFollowingPublicKeys.remove(pubkey)
        bg.perform {
            guard let account = self.bgAccount else { return }
            account.removeFromFollows(contact)
            bgSave()
            self.followingPublicKeys = self.viewFollowingPublicKeys
            self.followingPFPs = account.getFollowingPFPs()
            
            account.publishNewContactList()
            DispatchQueue.main.async {
                sendNotification(.followersChanged, self.viewFollowingPublicKeys)
            }
        }
    }
    
    @MainActor public func addBookmark(_ nrPost:NRPost) {
        sendNotification(.postAction, PostActionNotification(type:.bookmark, eventId: nrPost.id, bookmarked: true))
        
        bg.perform {
            guard let account = self.bgAccount else { return }
            account.addToBookmarks(nrPost.event)
            DataProvider.shared().bgSave()
        }
    }
    
    @MainActor public func removeBookmark(_ nrPost:NRPost) {
        sendNotification(.postAction, PostActionNotification(type:.bookmark, eventId: nrPost.id, bookmarked: false))
        bg.perform {
            guard let account = self.bgAccount else { return }
            account.removeFromBookmarks(nrPost.event)
            DataProvider.shared().bgSave()
        }
    }
    
    @MainActor public func muteConversation(_ nrPost:NRPost) {
        bg.perform {
            guard let account = self.bgAccount else { return }
            if let replyToRootId = nrPost.replyToRootId {
                account.mutedRootIds_.insert(replyToRootId)
                account.mutedRootIds_.insert(nrPost.id)
                L.og.info("Muting \(replyToRootId)")
            }
            else if let replyToId = nrPost.replyToId {
                account.mutedRootIds_.insert(replyToId)
                account.mutedRootIds_.insert(nrPost.id)
                L.og.info("Muting \(replyToId)")
            }
            else {
                account.mutedRootIds_.insert(nrPost.id)
                L.og.info("Muting \(nrPost.id)")
            }
            DataProvider.shared().bgSave()
            DispatchQueue.main.async {
                sendNotification(.muteListUpdated)
            }
        }
    }
    
    @MainActor public func report(_ event:Event, reportType:ReportType, note:String = "", includeProfile:Bool = false) -> NEvent? {
        guard account.privateKey != nil else { NRState.shared.readOnlyAccountSheetShown = true; return nil }
        
        let report = EventMessageBuilder.makeReportEvent(pubkey: event.pubkey, eventId: event.id, type: reportType, note: note, includeProfile: includeProfile)

        guard let signedEvent = try? account.signEvent(report) else {
            L.og.error("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
            return nil
        }
        return signedEvent
    }
    
    @MainActor public func reportContact(pubkey:String, reportType:ReportType, note:String = "") -> NEvent? {
        guard account.privateKey != nil else { NRState.shared.readOnlyAccountSheetShown = true; return nil }
        
        let report = EventMessageBuilder.makeReportContact(pubkey: pubkey, type: reportType, note: note)

        guard let signedEvent = try? account.signEvent(report) else {
            L.og.error("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
            return nil
        }
        return signedEvent
    }
    
    @MainActor public func deletePost(_ eventId:String) -> NEvent? {
        guard account.privateKey != nil else { NRState.shared.readOnlyAccountSheetShown = true; return nil }
        
        let deletion = EventMessageBuilder.makeDeleteEvent(eventId: eventId)

        guard let signedEvent = try? account.signEvent(deletion) else {
            L.og.error("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
            return nil
        }
        return signedEvent
    }
    
    
    // BG high speed
    public var followingPublicKeys:Set<String> = []
    public var followingPFPs:[String: URL] = [:]
    
    public var lastNotificationReceivedAt:Date? // stored here so we dont have to worry about different object contexts / threads
    
    // View context
    @Published var account:Account {
        didSet { // REMINDER, didSet does not run on init!
            Task { @MainActor in
                self.setupAccount(account)
            }
        }
    }
    
    // BG context
    public var bgAccount:Account? = nil
    
    public var mutedWords:[String] = []
    
    @MainActor public init(_ account:Account) {
        self.bg = Nostur.bg()
        self.pubkey = account.publicKey
        self.account = account
        self.setupAccount(account)
    }
    
    @MainActor private func setupAccount(_ account:Account) {
        self.pubkey = pubkey
        FollowingGuardian.shared.didReceiveContactListThisSession = false
        
        let follows = account.getFollowingPublicKeys(includeBlocked: true) // if we do this in bg.perform it loads too late for other views
        self.viewFollowingPublicKeys = follows
        
        // Remove currectly active "Following" subscriptions from connected sockets
        self.bg.perform {
            guard let bgAccount = try? self.bg.existingObject(with: self.account.objectID) as? Account else {
                L.og.notice("🔴🔴 Problem loading bgAccount")
                return
            }
            self.bgAccount = bgAccount
            SocketPool.shared.removeActiveAccountSubscriptions()
            
            self.followingPublicKeys = follows
            self.followingPFPs = bgAccount.getFollowingPFPs()
            self.lastNotificationReceivedAt = bgAccount.lastNotificationReceivedAt
            
            DispatchQueue.main.async {
                sendNotification(.activeAccountChanged, account)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                WebOfTrust.shared.loadWoT(self.account)
                if SettingsStore.shared.webOfTrustLevel == SettingsStore.WebOfTrustLevel.off.rawValue {
                    DirectMessageViewModel.default.load(pubkey: self.account.publicKey)
                }
                else {
                    DirectMessageViewModel.default.loadAfterWoT()
                }
            }
        }
    }
    
    public func changeAccount(account: Account) {
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
