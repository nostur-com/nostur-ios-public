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
    
    let viewContext = DataProvider.shared().viewContext
    let ns:NosturState = .shared
    
    var subscriptions = Set<AnyCancellable>()
    
    var timer: Timer?
    
    
    init() {
        startTimer()
                
        receiveNotification(.activeAccountChanged)
            .sink { _ in
                self.unreadMentions = 0
                self.unreadReactions = 0
                self.unreadZaps = 0
                self.unreadDMsAccepted = 0
                self.unreadDMRequests = 0
            }
            .store(in: &subscriptions)
        
        // Check relays for newest messages NOW
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.relayCheckNewestNotifications()
        }
        
        // Check relays for since... later
        DispatchQueue.main.asyncAfter(deadline: .now() + 11) {
            self.relayCheckSinceNotifications()
        }
    }
    
    func relayCheckNewestNotifications() {
        guard ns.account != nil else { return }
        guard ns.activeAccountPublicKey != "" else { return }
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
        print("checking notifications since: \(since.description(with: .current))")
        
        let ago = since.agoString
        
        req(RM.getMentions(pubkeys: [ns.activeAccountPublicKey], subscriptionId: "Notifications-CATCHUP-\(ago)", since: sinceNTimestamp))
    }
    
    func checkForNewPosts() {
        guard let account = ns.account else { return }
        let mutedRootIds = account.mutedRootIds_
        let pubkey = account.publicKey
        let blockedPubkeys = account.blockedPubkeys_
        
        let context = DataProvider.shared().bg
        context.perform { [weak self] in
            guard let self = self else { return }
            let lastSeenPostCreatedAt = account.toBG()?.lastSeenPostCreatedAt ?? 0
            
            // Same query as in NotificationsPosts.init. should be kept in sync, refactor to 1 function source someday
            // except oldestCreatedAt = lastSeenPostInstertedAt
    //        print("🟣🟣🟣🟣  \(account.lastSeenPostCreatedAt)")
            let r2 = Event.fetchRequest()
            r2.predicate = NSPredicate(format:
                                        "created_at > %i " +
                                        "AND NOT pubkey IN %@ " +
                                        "AND kind == 1 " +
                                        "AND tagsSerialized CONTAINS %@ " +
                                        "AND NOT id IN %@ " +
                                        "AND (replyToRootId == nil OR NOT replyToRootId IN %@) " + // mutedRootIds
                                        "AND (replyToId == nil OR NOT replyToId IN %@) ", // mutedRootIds
                                        lastSeenPostCreatedAt,
                                        blockedPubkeys + [pubkey],
                                        serializedP(pubkey),
                                        mutedRootIds,
                                        mutedRootIds,
                                        mutedRootIds)
            
            r2.fetchLimit = self.FETCH_LIMIT
            r2.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            r2.resultType = .countResultType
             
            let unreadMentions = (try? context.count(for: r2)) ?? 0
            DispatchQueue.main.async {
                if unreadMentions != self.unreadMentions {
                    self.unreadMentions = min(unreadMentions,9999)
                }
            }
        }
    }
    
    func checkForNewReactions() {
        guard let account = ns.account else { return }
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
        r2.resultType = .countResultType
        
        
        let context = DataProvider.shared().bg
        context.perform {
            let unreadReactions = (try? context.count(for: r2)) ?? 0
            DispatchQueue.main.async {
                if unreadReactions != self.unreadReactions {
                    self.unreadReactions = min(unreadReactions,9999)
                }
            }
        }
        
//        let unreadReactions = (try? DataProvider.shared().viewContext.count(for: r2)) ?? 0
//        if unreadReactions != self.unreadReactions {
//            self.unreadReactions = min(unreadReactions,9999)
//        }
    }
    
    func checkForNewZaps() {
        guard let account = ns.account else { return }
        let pubkey = account.publicKey
        let blockedPubkeys = account.blockedPubkeys_
        
//        let regex = ".*(" + blockedPubkeys.map {
//            NSRegularExpression.escapedPattern(for: $0)
//        }.joined(separator: "|") + ").*"
        
        // Same query as in NotificationsPosts.init. should be kept in sync, refactor to 1 function source someday
        // except oldestCreatedAt = lastSeenPostInstertedAt
//        print("🟣🟣🟣  \(account.lastSeenZapCreatedAt)")
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
        r2.resultType = .countResultType
        
        
        let context = DataProvider.shared().bg
        context.perform {
            let unreadZaps = (try? context.count(for: r2)) ?? 0
            DispatchQueue.main.async {
                if unreadZaps != self.unreadZaps {
                    self.unreadZaps = min(unreadZaps,9999)
                }
            }
        }
        
//        let unreadZaps = (try? DataProvider.shared().viewContext.count(for: r2)) ?? 0
//        if unreadZaps != self.unreadZaps {
//            self.unreadZaps = min(unreadZaps,9999)
//        }

    }
    
    func checkForEverything() {
        guard let account = ns.account else { return }
        guard !MessageParser.shared.messageBucket.isImporting else { return }
        
        relayCheckNewestNotifications() // or wait 3 seconds?
        
        checkForNewPosts()
        checkForNewReactions()
        checkForNewZaps()
        checkForDMs()
    }
    
    func checkForDMs() {
        guard let account = ns.account else { return }
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
        
        let ctx = DataProvider.shared().bg
        ctx.perform {
         
            do {
                let received = try ctx.fetch(receivedFR)
                
                let sentFR = Event.fetchRequest()
                sentFR.predicate = NSPredicate(
                    format: "kind == 4 AND pubkey == %@", pubkey)
                sentFR.fetchLimit = 999
                sentFR.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
                let sent = try ctx.fetch(sentFR)
                
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
                print("🔴🔴 problem checking DM notifications")
            }
        }
    }
    
    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] timer in
            self?.checkForEverything()
        }
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
                                    "AND kind == 1 " +
                                    "AND tagsSerialized CONTAINS %@ " +
                                    "AND NOT id IN %@ " +
                                    "AND (replyToRootId == nil OR NOT replyToRootId IN %@) " + // mutedRootIds
                                    "AND (replyToId == nil OR NOT replyToId IN %@) ", // mutedRootIds
                                   blockedPubkeys + [pubkey],
                                   serializedP(pubkey),
                                   mutedRootIds,
                                   mutedRootIds,
                                   mutedRootIds)
        r2.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        r2.fetchLimit = 1
        
        let ctx = DataProvider.shared().bg
        ctx.perform {
            if let mostRecent = try? ctx.fetch(r2).first {
                account.toBG()?.lastSeenPostCreatedAt = mostRecent.created_at
            }
            else {
                account.toBG()?.lastSeenPostCreatedAt = Int64(Date.now.timeIntervalSince1970)
            }
        }
    }
}
