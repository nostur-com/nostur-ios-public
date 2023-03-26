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
    
    let FETCH_LIMIT = 300
    
    static let shared = NotificationsManager()
    
    @Published var unreadMentions = 0 {
        didSet {
            sendNotification(.updateNotificationsCount, unread)
        }
    }
    @Published var unreadReactions = 0 {
        didSet {
            sendNotification(.updateNotificationsCount, unread)
        }
    }
    @Published var unreadZaps = 0 {
        didSet {
            sendNotification(.updateNotificationsCount, unread)
        }
    }
    @Published var unreadDMsAccepted = 0 {
        didSet {
            sendNotification(.updateDMsCount, unreadDMs)
        }
    }
    @Published var unreadDMRequests = 0 {
        didSet {
            sendNotification(.updateDMsCount, unreadDMs)
        }
    }
    
    // Notifications tab
    var unread:Int {
        unreadMentions + unreadReactions + unreadZaps
    }
    
    // DMs tab
    var unreadDMs:Int {
        unreadDMsAccepted + unreadDMRequests
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
//        checkForNewDMRequests()
//        checkForNewDMsAccepted()
        
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
                                    "AND NOT replyToRootId IN %@ " +
                                    "AND NOT replyToId IN %@",
                                    account.lastSeenPostCreatedAt,
                                    blockedPubkeys + [pubkey],
                                    serializedP(pubkey),
                                    mutedRootIds,
                                    mutedRootIds,
                                    mutedRootIds)
        
        r2.fetchLimit = FETCH_LIMIT
        r2.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        r2.resultType = .countResultType
        
        let unreadMentions = try? DataProvider.shared().viewContext.count(for: r2)
        self.unreadMentions = unreadMentions ?? 0
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
                                    "AND reactionTo.contact.pubkey == %@",
                                    account.lastSeenReactionCreatedAt,
                                    blockedPubkeys + [pubkey],
                                    pubkey)
        r2.fetchLimit = FETCH_LIMIT
        r2.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        r2.resultType = .countResultType
        let unreadReactions = try? DataProvider.shared().viewContext.count(for: r2)
        self.unreadReactions = unreadReactions ?? 0
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
                                    "AND kind == 9735 " + // ONLY ZAPS
                                    "AND zappedContactPubkey == %@" + // ONLY TO ME
                                    "AND NOT zapFromRequest.pubkey IN %@", // NOT FROM BLOCKED PUBKEYS
                                    account.lastSeenZapCreatedAt,
                                    pubkey,
                                    blockedPubkeys)
        r2.fetchLimit = FETCH_LIMIT
        r2.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        r2.resultType = .countResultType
        let unreadZaps = try? DataProvider.shared().viewContext.count(for: r2)
        
        self.unreadZaps = unreadZaps ?? 0

    }
    
    func checkForEverything() {
        guard !Importer.shared.isImporting else { return }
        SocketPool
            .shared
            .sendMessage(
                ClientMessage(
                    type: .REQ,
                    message:
                        RequestMessage
                        .getMentions(
                            pubkeys: [ns.activeAccountPublicKey], subscriptionId: "Notifications")
                )
                , subscriptionId: "Notifications"
            )
        checkForNewPosts()
        checkForNewReactions()
        checkForNewZaps()
        checkForNewDMRequests()
        checkForNewDMsAccepted()
    }
    
    func checkForNewDMRequests() {
        guard let account = ns.account else { return }
        let pubkey = account.publicKey
        let blockedPubkeys = account.blockedPubkeys_
        
        
        // Same query as in DirectMessages.init. should be kept in sync, refactor to 1 function source someday
        // except oldestCreatedAt = lastSeenDMRequestCreatedAt
        let r2 = Event.fetchRequest()
        r2.predicate = NSPredicate(
            format:
                "created_at > %i " + // AFTER LAST SEEN
                "AND kind == 4 " +
                "AND tagsSerialized CONTAINS %@ " +
                "AND contact.dmAccepted == false " +
                "AND NOT pubkey IN %@",
            account.lastSeenDMRequestCreatedAt,
            serializedP(pubkey),
            blockedPubkeys)
        r2.fetchLimit = FETCH_LIMIT
        r2.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        r2.resultType = .countResultType
        let unreadDMRequests = try? DataProvider.shared().viewContext.count(for: r2)
        self.unreadDMRequests = unreadDMRequests ?? 0
    }
    
    func checkForNewDMsAccepted() {
        guard let account = ns.account else { return }
        let pubkey = account.publicKey
        let blockedPubkeys = account.blockedPubkeys_
        
        
        // Same query as in DirectMessages.init. should be kept in sync, refactor to 1 function source someday
        // except oldestCreatedAt = lastSeenDMRequestCreatedAt
        let r2 = Event.fetchRequest()
        r2.predicate = NSPredicate(
            format:
                "created_at > %i " + // AFTER LAST SEEN
                "AND kind == 4 " +
                "AND tagsSerialized CONTAINS %@ " +
                "AND contact.dmAccepted == true " +
                "AND NOT pubkey IN %@",
            account.lastSeenDMCreatedAt,
            serializedP(pubkey),
            blockedPubkeys)
        r2.fetchLimit = FETCH_LIMIT
        r2.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        r2.resultType = .countResultType
        let unreadDMsAccepted = try? DataProvider.shared().viewContext.count(for: r2)
        self.unreadDMsAccepted = unreadDMsAccepted ?? 0
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
