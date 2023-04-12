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
    
    let FETCH_LIMIT = 200
    
    static let shared = NotificationsManager()
    
    @Published var unreadMentions:Int = 0 {
        didSet {
            sendNotification(.updateNotificationsCount, unread)
        }
    }
    @Published var unreadReactions:Int = 0 {
        didSet {
            sendNotification(.updateNotificationsCount, unread)
        }
    }
    @Published var unreadZaps:Int = 0 {
        didSet {
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
        
        checkForNewPosts()
        checkForNewReactions()
        checkForNewZaps()
        checkForDMs()
        
        receiveNotification(.activeAccountChanged)
            .sink { _ in
                self.unreadMentions = 0
                self.unreadReactions = 0
                self.unreadZaps = 0
                self.unreadDMsAccepted = 0
                self.unreadDMRequests = 0
            }
            .store(in: &subscriptions)
    }
    
    func checkForNewPosts() {
        guard let account = ns.account else { return }
        let mutedRootIds = account.mutedRootIds_
        let pubkey = account.publicKey
        let blockedPubkeys = account.blockedPubkeys_
        
        
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
                                    account.lastSeenPostCreatedAt,
                                    blockedPubkeys + [pubkey],
                                    serializedP(pubkey),
                                    mutedRootIds,
                                    mutedRootIds,
                                    mutedRootIds)
        
        r2.fetchLimit = FETCH_LIMIT
        r2.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        r2.resultType = .countResultType
        
        let unreadMentions = (try? DataProvider.shared().viewContext.count(for: r2)) ?? 0
        if unreadMentions != self.unreadMentions {
            self.unreadMentions = min(unreadMentions,9999)
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
        let unreadReactions = (try? DataProvider.shared().viewContext.count(for: r2)) ?? 0
        if unreadReactions != self.unreadReactions {
            self.unreadReactions = min(unreadReactions,9999)
        }
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
        let unreadZaps = (try? DataProvider.shared().viewContext.count(for: r2)) ?? 0
        
        if unreadZaps != self.unreadZaps {
            self.unreadZaps = min(unreadZaps,9999)
        }

    }
    
    func checkForEverything() {
        guard !Importer.shared.isImporting else { return }
        guard let account = ns.account else { return }
        guard ns.activeAccountPublicKey != "" else { return }
        
        let since = NosturState.shared.lastNotificationReceivedAt ?? nil
        let sinceNTimestamp = since != nil ? NTimestamp(date: since!) : nil
        print("checking notifications since: \(since?.description ?? "")")
        
        SocketPool
            .shared
            .sendMessage(
                ClientMessage(
                    type: .REQ,
                    message:
                        RequestMessage
                        .getMentions(
                            pubkeys: [ns.activeAccountPublicKey], subscriptionId: "Notifications", since: sinceNTimestamp)
                )
                , subscriptionId: "Notifications"
            )
        checkForNewPosts()
        checkForNewReactions()
        checkForNewZaps()
        checkForDMs()
    }
    
    func checkForDMs() {
        guard let account = ns.account else { return }
        let pubkey = account.publicKey
        let blockedPubkeys = account.blockedPubkeys_
        let ctx = DataProvider.shared().viewContext
        
        let receivedFR = Event.fetchRequest()
        receivedFR.predicate = NSPredicate(
            format:
                "kind == 4 " +
                "AND tagsSerialized CONTAINS %@ " +
                "AND NOT pubkey IN %@",
            serializedP(pubkey),
            blockedPubkeys)
        receivedFR.fetchLimit = 500
        receivedFR.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        
        do {
            let received = try ctx.fetch(receivedFR)
            
            let sentFR = Event.fetchRequest()
            sentFR.predicate = NSPredicate(
                format: "kind == 4 AND pubkey == %@", pubkey)
            sentFR.fetchLimit = 500
            sentFR.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            let sent = try ctx.fetch(sentFR)
            
            let onlyMostRecentAll = computeOnlyMostRecentAll(sent: sent, received: received, pubkey: pubkey)
            let onlyMostRecentAccepted = computeOnlyMostRecentAccepted(onlyMostRecentAll)
            let onlyMostRecentRequests = computeOnlyMostRecentRequests(onlyMostRecentAll)
            let newUnreadDMsAccepted = computeOnlyMostRecentAcceptedTotalUnread(onlyMostRecentAccepted)
            let newUnreadDMRequests = computeRequestTotalUnread(onlyMostRecentRequests)
            
            // Only set if changed. (else rerender because _nm changed.)
            if newUnreadDMsAccepted != unreadDMsAccepted {
                unreadDMsAccepted = min(newUnreadDMsAccepted,9999)
            }
            
            if newUnreadDMRequests != unreadDMRequests {
                unreadDMRequests = min(newUnreadDMRequests,9999)
            }
        }
        catch {
            print("🔴🔴 problem checking DM notifications")
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
}
