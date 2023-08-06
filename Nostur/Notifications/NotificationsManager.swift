//
//  NotificationsManager.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/03/2023.
//

import Foundation
import CoreData
import Combine

class NotificationsManager: ObservableObject {
    
    let FETCH_LIMIT = 999
    
    static let shared = NotificationsManager()
    
    @Published var unreadMentions:Int = 0 {
        didSet {
            if unreadMentions > oldValue {
                sendNotification(.newMentions)
            }
            sendNotification(.updateNotificationsCount, unread)
        }
    }
    @Published var unreadReactions:Int = 0 {
        didSet {
            if unreadReactions > oldValue {
                sendNotification(.newReactions)
            }
            sendNotification(.updateNotificationsCount, unread)
        }
    }
    @Published var unreadZaps:Int = 0 {
        didSet {
            if unreadZaps > oldValue {
                sendNotification(.newZaps)
            }
            sendNotification(.updateNotificationsCount, unread)
        }
    }
    @Published var unreadDMsAccepted:Int = 0 {
        didSet {
            sendNotification(.updateDMsCount, unreadDMs)
        }
    }
    @Published var unreadDMRequests:Int = 0 {
        didSet {
            sendNotification(.updateDMsCount, unreadDMs)
        }
    }
    
    // Notifications tab
    var unread: Int {
        let sum = unreadMentions &+ unreadReactions
        return sum &+ unreadZaps
    }
    
    // DMs tab
    var unreadDMs:Int {
        unreadDMsAccepted &+ unreadDMRequests
    }
    
//    let viewContext = DataProvider.shared().viewContext
    let context = DataProvider.shared().bg
    let ns:NosturState = .shared
    
    var subscriptions = Set<AnyCancellable>()
    
    var timer: Timer?
    
    
    init() {
        startTimer()
                
        receiveNotification(.activeAccountChanged)
            .sink { [unowned self] _ in
                self.unreadMentions = 0
                self.unreadReactions = 0
                self.unreadZaps = 0
                self.unreadDMsAccepted = 0
                self.unreadDMRequests = 0
            }
            .store(in: &subscriptions)
        
        // Check relays for newest messages NOW
//        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
//            self.relayCheckNewestNotifications()
//        }
        
        // Check relays for since... later
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { // TODO: Change to event based instead of timer. (after instant feed finished)
            self.relayCheckSinceNotifications()
        }
    }
    
    private func relayCheckNewestNotifications() {
        let calendar = Calendar.current
        let ago = calendar.date(byAdding: .minute, value: -1, to: Date())!
        let sinceNTimestamp = NTimestamp(date: ago)
        req(RM.getMentions(pubkeys: [ns.activeAccountPublicKey],
                           subscriptionId: "Notifications", since: sinceNTimestamp),
            activeSubscriptionId: "Notifications")
    }
    
    func relayCheckSinceNotifications() {
        // THIS ONE IS TO CATCH UP, WILL CLOSE AFTER EOSE:
        guard ns.account != nil else { return }
        guard ns.activeAccountPublicKey != "" else { return }
        guard let since = NosturState.shared.lastNotificationReceivedAt else { return }
    
        let sinceNTimestamp = NTimestamp(date: since)
        L.og.info("checking notifications since: \(since.description(with: .current))")
        
        let ago = since.agoString
        
        req(RM.getMentions(pubkeys: [ns.activeAccountPublicKey], subscriptionId: "Notifications-CATCHUP-\(ago)", since: sinceNTimestamp))
    }
    
    private func checkForNewPosts() {
        guard let account = ns.bgAccount else { return }
        let mutedRootIds = account.mutedRootIds_
        let pubkey = account.publicKey
        let blockedPubkeys = account.blockedPubkeys_
        let lastSeenPostCreatedAt = account.lastSeenPostCreatedAt

        let r2 = Event.fetchRequest()
        r2.predicate = NSPredicate(format:
                                    "created_at > %i " +
                                    "AND NOT pubkey IN %@ " +
                                    "AND kind IN {1,9802,30023} " +
                                    "AND tagsSerialized CONTAINS %@ " +
                                    "AND NOT id IN %@ " +
                                    "AND (replyToRootId == nil OR NOT replyToRootId IN %@) " + // mutedRootIds
                                    "AND (replyToId == nil OR NOT replyToId IN %@) " + // mutedRootIds
                                    "AND flags != \"is_update\" ", // mutedRootIds
                                    lastSeenPostCreatedAt,
                                    blockedPubkeys + [pubkey],
                                    serializedP(pubkey),
                                    mutedRootIds,
                                    mutedRootIds,
                                    mutedRootIds)
        
        r2.fetchLimit = self.FETCH_LIMIT
        r2.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        
        let r3 = PersistentNotification.fetchRequest()
        r3.predicate = NSPredicate(format: "readAt == nil AND type_ == %@", PNType.newFollowers.rawValue)
        r3.fetchLimit = self.FETCH_LIMIT
        r3.sortDescriptors = [NSSortDescriptor(keyPath:\PersistentNotification.createdAt, ascending: false)]
        r3.resultType = .countResultType
         
        var unreadMentions = ((try? context.fetch(r2)) ?? [])
            .filter { !$0.isSpam }
            .count
        
        let unreadNewFollowers = (try? context.count(for: r3)) ?? 0
        unreadMentions = unreadMentions + unreadNewFollowers
        DispatchQueue.main.async {
            if unreadMentions != self.unreadMentions {
                self.unreadMentions = min(unreadMentions,9999)
            }
        }
    }
    
    private func checkForNewReactions() {
        guard let account = ns.bgAccount else { return }
        let pubkey = account.publicKey
        let blockedPubkeys = account.blockedPubkeys_
        
        
        // Same query as in NotificationsPosts.init. should be kept in sync, refactor to 1 function source someday
        // except oldestCreatedAt = lastSeenPostInstertedAt
        let r2 = Event.fetchRequest()
        r2.predicate = NSPredicate(format:
                                    "created_at > %i " +
                                    "AND NOT pubkey IN %@ " +
                                    "AND kind == 7 " +
                                    "AND reactionTo.pubkey == %@",
                                    account.lastSeenReactionCreatedAt,
                                    blockedPubkeys + [pubkey],
                                    pubkey)
        r2.fetchLimit = FETCH_LIMIT
        r2.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        
        
        let unreadReactions = ((try? context.fetch(r2)) ?? [])
            .filter { !$0.isSpam }
            .count
        
        DispatchQueue.main.async {
            if unreadReactions != self.unreadReactions {
                self.unreadReactions = min(unreadReactions,9999)
            }
        }
    }
    
    private func checkForNewZaps() {
        guard let account = ns.bgAccount else { return }
        let pubkey = account.publicKey
        let blockedPubkeys = account.blockedPubkeys_

        let r2 = Event.fetchRequest()
        r2.predicate = NSPredicate(format:
                                    "created_at > %i " + // AFTER LAST SEEN
                                    "AND zappedContactPubkey == %@" + // ONLY TO ME
                                    "AND kind == 9735 " + // ONLY ZAPS
                                    "AND NOT zapFromRequest.pubkey IN %@", // NOT FROM BLOCKED PUBKEYS
                                    account.lastSeenZapCreatedAt,
                                    pubkey,
                                    blockedPubkeys)
        r2.fetchLimit = FETCH_LIMIT
        r2.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        
        let r3 = PersistentNotification.fetchRequest()
        r3.predicate = NSPredicate(format: "readAt == nil AND type_ IN %@", [PNType.failedLightningInvoice.rawValue,PNType.failedZap.rawValue,PNType.failedZaps.rawValue,PNType.failedZapsTimeout.rawValue])
        r3.fetchLimit = self.FETCH_LIMIT
        r3.sortDescriptors = [NSSortDescriptor(keyPath:\PersistentNotification.createdAt, ascending: false)]
        r3.resultType = .countResultType
        
        
        var unreadZaps = ((try? context.fetch(r2)) ?? [])
            .filter { !$0.isSpam }
            .count
        
        let unreadZapNotifications = (try? context.count(for: r3)) ?? 0
        unreadZaps = unreadZaps + unreadZapNotifications
        DispatchQueue.main.async {
            if unreadZaps != self.unreadZaps {
                self.unreadZaps = min(unreadZaps,9999)
            }
        }
    }
    
    private func checkForOfflinePosts(_ maxAgo:TimeInterval = 3600 * 24 * 3) { // 3 days
        guard SocketPool.shared.anyConnected else { return }
        guard let account = ns.bgAccount else { return }
        let pubkey = account.publicKey
        let xDaysAgo = Date.now.addingTimeInterval(-(maxAgo))
        
        let r1 = Event.fetchRequest()
        // X days ago, from our pubkey, only kinds that we can create+send
        r1.predicate = NSPredicate(format:
                                    "created_at > %i " +
                                    "AND pubkey = %@ " +
                                    "AND kind IN {0,1,3,4,5,6,7,9802} " +
                                    "AND relays = \"\"" +
                                    "AND NOT flags IN {\"nsecbunker_unsigned\",\"awaiting_send\"}" +
                                    "AND sig != nil"
                                    ,
                                    Int64(xDaysAgo.timeIntervalSince1970),
                                    pubkey)
        r1.fetchLimit = 100 // sanity
        r1.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        
        if let offlinePosts = try? context.fetch(r1) {
            guard !offlinePosts.isEmpty else { return }
            for offlinePost in offlinePosts {
                L.og.debug("Publishing offline post: \(offlinePost.id)")
                let nEvent = offlinePost.toNEvent()
                DispatchQueue.main.async {
                    Unpublisher.shared.publishNow(nEvent)
                }
            }
        }
    }
    
    func checkForEverything() {
        guard ns.account != nil else { return }
        guard ns.activeAccountPublicKey != "" else { return }
        
        DataProvider.shared().bg.perform { [weak self] in
            guard let self = self else { return }
            guard !Importer.shared.isImporting else {
                L.og.info("⏳ Still importing, new fetch skipped."); return
            }

            self.relayCheckNewestNotifications() // or wait 3 seconds?
            
            self.checkForOfflinePosts() // Not really part of notifications but easy to add here and reuse the same timer
            self.checkForNewPosts()
            self.checkForNewReactions()
            self.checkForNewZaps()
            self.checkForDMs()
        }
    }
    
    private func checkForDMs() {
        guard let account = ns.bgAccount else { return }
        let pubkey = account.publicKey
        let blockedPubkeys = account.blockedPubkeys_
        
        let receivedFR = Event.fetchRequest()
        receivedFR.predicate = NSPredicate(
            format:
                "kind == 4 " +
                "AND tagsSerialized CONTAINS %@ " +
                "AND NOT pubkey IN %@",
            serializedP(pubkey),
            blockedPubkeys)
        receivedFR.fetchLimit = 999
        receivedFR.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        
        
        let lastSeenDMRequestCreatedAt = account.lastSeenDMRequestCreatedAt
        
        do {
            let received = try context.fetch(receivedFR)
            
            let sentFR = Event.fetchRequest()
            sentFR.predicate = NSPredicate(
                format: "kind == 4 AND pubkey == %@", pubkey)
            sentFR.fetchLimit = 999
            sentFR.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            let sent = try context.fetch(sentFR)
            
            let onlyMostRecentAll = computeOnlyMostRecentAll(sent: sent, received: received, pubkey: pubkey)
            let onlyMostRecentAccepted = computeOnlyMostRecentAccepted(onlyMostRecentAll)
            let onlyMostRecentRequests = computeOnlyMostRecentRequests(onlyMostRecentAll)
            let newUnreadDMsAccepted = computeOnlyMostRecentAcceptedTotalUnread(onlyMostRecentAccepted)
            let newUnreadDMRequests = computeRequestTotalUnread(onlyMostRecentRequests, lastSeenDMRequestCreatedAt:lastSeenDMRequestCreatedAt)
            
            
            DispatchQueue.main.async {
                // Only set if changed. (else rerender because _nm changed.)
                if newUnreadDMsAccepted != self.unreadDMsAccepted {
                    self.unreadDMsAccepted = min(newUnreadDMsAccepted,9999)
                }
                
                if newUnreadDMRequests != self.unreadDMRequests {
                    self.unreadDMRequests = min(newUnreadDMRequests,9999)
                }
            }
        }
        catch {
            L.og.error("🔴🔴 problem checking DM notifications")
        }
    }
    
    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] timer in
            self?.checkForEverything()
        }
        timer?.tolerance = 5.0
    }
    
    func stopTimer() {
        timer?.invalidate()
    }
    
    func markMentionsAsRead() {
        guard let account = ns.account else { return }
        let mutedRootIds = account.mutedRootIds_
        let pubkey = account.publicKey
        let blockedPubkeys = account.blockedPubkeys_
        
        let r2 = Event.fetchRequest()
        r2.predicate = NSPredicate(format:
                                    "NOT pubkey IN %@ " +
                                    "AND kind IN {1,9802,30023} " +
                                    "AND tagsSerialized CONTAINS %@ " +
                                    "AND NOT id IN %@ " +
                                    "AND (replyToRootId == nil OR NOT replyToRootId IN %@) " + // mutedRootIds
                                    "AND (replyToId == nil OR NOT replyToId IN %@) " + // mutedRootIds
                                    "AND flags != \"is_update\" ", // mutedRootIds
                                   blockedPubkeys + [pubkey],
                                   serializedP(pubkey),
                                   mutedRootIds,
                                   mutedRootIds,
                                   mutedRootIds)
        r2.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        r2.fetchLimit = 1
        
        // Also do new follower notifications
        let r3 = NSBatchUpdateRequest(entityName: "PersistentNotification")
        r3.propertiesToUpdate = ["readAt": NSDate()]
        r3.predicate = NSPredicate(format: "readAt == nil && type_ == %@", PNType.newFollowers.rawValue)
        r3.resultType = .updatedObjectIDsResultType

        
        
        context.perform { [weak self] in
            guard let self = self else { return }
            guard let account = ns.bgAccount else { return }
            if let mostRecent = try? self.context.fetch(r2).first {
                account.lastSeenPostCreatedAt = mostRecent.created_at
            }
            else {
                account.lastSeenPostCreatedAt = Int64(Date.now.timeIntervalSince1970)
            }
            let _ = try? self.context.execute(r3) as? NSBatchUpdateResult
            DataProvider.shared().bgSave()
        }
    }
    
    func markReactionsAsRead() {
        guard let account = ns.account else { return }
        let pubkey = account.publicKey
        let blockedPubkeys = account.blockedPubkeys_
        
        let r2 = Event.fetchRequest()
        r2.predicate = NSPredicate(format:
                                    "NOT pubkey IN %@ " +
                                    "AND kind == 7 " +
                                    "AND reactionTo.pubkey == %@",
                                    blockedPubkeys + [pubkey],
                                    pubkey)
        r2.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        r2.fetchLimit = 1
        
        context.perform { [weak self] in
            guard let self = self else { return }
            guard let account = ns.bgAccount else { return }
            
            if let mostRecent = try? context.fetch(r2).first {
                account.lastSeenReactionCreatedAt = mostRecent.created_at
            }
            else {
                account.lastSeenReactionCreatedAt = Int64(Date.now.timeIntervalSince1970)
            }
            DataProvider.shared().bgSave()
        }
    }
    
    func markZapsAsRead() {
        guard let account = ns.account else { return }
        let pubkey = account.publicKey
        let blockedPubkeys = account.blockedPubkeys_
        
        let r2 = Event.fetchRequest()
        r2.predicate = NSPredicate(format:
                                    "zappedContactPubkey == %@" + // ONLY TO ME
                                    "AND kind == 9735 " + // ONLY ZAPS
                                    "AND NOT zapFromRequest.pubkey IN %@", // NOT FROM BLOCKED PUBKEYS
                                    pubkey,
                                    blockedPubkeys)
        r2.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        r2.fetchLimit = 1
        
        // Also do zap notifications
        let r3 = NSBatchUpdateRequest(entityName: "PersistentNotification")
        r3.propertiesToUpdate = ["readAt": NSDate()]
        r3.predicate = NSPredicate(format: "readAt == nil && type_ IN %@", [PNType.failedLightningInvoice.rawValue,PNType.failedZap.rawValue,PNType.failedZaps.rawValue,PNType.failedZapsTimeout.rawValue])
        r3.resultType = .updatedObjectIDsResultType
        
        context.perform { [weak self] in
            guard let self = self else { return }
            guard let account = ns.bgAccount else { return }
            if let mostRecent = try? context.fetch(r2).first {
                account.lastSeenZapCreatedAt = mostRecent.created_at
            }
            else {
                account.lastSeenZapCreatedAt = Int64(Date.now.timeIntervalSince1970)
            }
            let _ = try? context.execute(r3) as? NSBatchUpdateResult
            DataProvider.shared().bgSave()
        }
    }
}
