//
//  NotificationsViewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/09/2023.
//

import SwiftUI
import Combine
import CoreData

class NotificationsViewModel: ObservableObject {
    
    static let shared = NotificationsViewModel()
    
    private init() {
        startTimer()
        setupSubscriptions()
        checkRelays()
        if IS_CATALYST {
            setupBadgeNotifications()
        }
    }
    
    // Total for the notifications tab on the main tab bar
    public var unread: Int {
        unreadMentions + (muteReactions ? 0 : unreadReactions) + (muteZaps ? 0 : (unreadZaps + unreadFailedZaps)) + (muteFollows ? 0 : unreadNewFollowers) + (muteReposts ? 0 : unreadReposts)
    }
    
    public var unreadMentions:Int { unreadMentions_ }
        
    public var unreadNewFollowers:Int {
        guard !muteFollows else { return 0 }
        return unreadNewFollowers_
    }
    
    public var unreadReposts:Int {
        guard !muteReposts else { return 0 }
        return unreadReposts_
    }
    
    public var unreadReactions:Int {
        guard !muteReactions else { return 0 }
        return unreadReactions_
    }
    
    public var unreadZaps:Int {
        guard !muteZaps else { return 0 }
        return unreadZaps_
    }
    
    public var unreadFailedZaps:Int { unreadFailedZaps_ }
    
    
    // Don't read these @Published vars, only set them. Use the computed above instead because they correctly return 0 when muted
    @Published var unreadMentions_:Int = 0 {      // 1,9802,30023
        didSet {
            if unreadMentions_ > oldValue {
                sendNotification(.newMentions)
            }
//            sendNotification(.updateNotificationsCount, unread)
        }
    }
    @Published var unreadNewFollowers_:Int = 0 {  // custom
        didSet {
            if unreadNewFollowers_ > oldValue {
                sendNotification(.newFollowers)
            }
        }
    }
    @Published var unreadReposts_:Int = 0 {     // 6
        didSet {
            if unreadReposts_ > oldValue {
                sendNotification(.newReposts)
            }
        }
    }
    @Published var unreadReactions_:Int = 0 {  // 7
        didSet {
            if unreadReactions_ > oldValue {
                sendNotification(.newReactions)
            }
        }
    }
    @Published var unreadZaps_:Int = 0 {       // 9735
        didSet {
            if unreadZaps_ > oldValue {
                sendNotification(.newZaps)
            }
        }
    }
    @Published var unreadFailedZaps_:Int = 0  // custom
    
    @AppStorage("selected_tab") var selectedTab = "Main"
    @AppStorage("selected_notifications_tab") var selectedNotificationsTab = "Mentions"
    
    @AppStorage("notifications_mute_follows") var muteFollows:Bool = false
    @AppStorage("notifications_mute_reactions") var muteReactions:Bool = false
    @AppStorage("notifications_mute_reposts") var muteReposts:Bool = false
    @AppStorage("notifications_mute_zaps") var muteZaps:Bool = false
    @AppStorage("notifications_mute_new_followers") var muteNewFollowers:Bool = false
    
    private var subscriptions = Set<AnyCancellable>()
    private var timer: Timer?
    
    private let q = NotificationFetchRequests()
    
    // TODO: kind 6 reposts, should check if the reposted post is actually from .pubkey, not just mentioned in p
    
    private func setupSubscriptions() {
        // listen for account changes
        receiveNotification(.activeAccountChanged)
            .sink { [unowned self] _ in
                self.unreadMentions_ = 0
                self.unreadNewFollowers_ = 0
                self.unreadReposts_ = 0
                self.unreadReactions_ = 0
                self.unreadZaps_ = 0
                self.unreadFailedZaps_ = 0
            }
            .store(in: &subscriptions)
    }
    
    private func setupBadgeNotifications() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.badge, .provisional]) { granted, error in
            if error == nil {
                // Provisional authorization granted.
                self.objectWillChange
                    .sink { _ in
                        Task {
                            let dmsCount = (DirectMessageViewModel.default.unread + DirectMessageViewModel.default.newRequests)
                            try? await center.setBadgeCount(self.unread + dmsCount)
                        }
                    }
                    .store(in: &self.subscriptions)
                Task {
                    let dmsCount = (DirectMessageViewModel.default.unread + DirectMessageViewModel.default.newRequests)
                    try? await center.setBadgeCount(self.unread + dmsCount)
                }
            }
        }
    }
    
    private func checkRelays() {
        // Check relays for newest messages NOW // NEEDED ("Notifications") realtime
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.relayCheckNewestNotifications()
        }
        
        // Check relays for since... later
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { // TODO: Change to event based instead of timer. (after instant feed finished)
            self.relayCheckSinceNotifications()
        }
    }
    
    // From now, stays active
    private func relayCheckNewestNotifications() {
        let calendar = Calendar.current
        let ago = calendar.date(byAdding: .minute, value: -1, to: Date())!
        let sinceNTimestamp = NTimestamp(date: ago)
        req(RM.getMentions(pubkeys: [NRState.shared.activeAccountPublicKey],
                           subscriptionId: "Notifications", since: sinceNTimestamp),
            activeSubscriptionId: "Notifications")
    }
    
    // Check since last notification
    private func relayCheckSinceNotifications() {
        // THIS ONE IS TO CATCH UP, WILL CLOSE AFTER EOSE:
        guard NRState.shared.activeAccountPublicKey != "" else { return }
        guard let since = account()?.lastNotificationReceivedAt else { return }
    
        let sinceNTimestamp = NTimestamp(date: since)
        let dmSinceNTimestamp = NTimestamp(timestamp: Int(DirectMessageViewModel.default.lastNotificationReceivedAt?.timeIntervalSince1970 ?? 0))
        L.og.info("checking notifications since: \(since.description(with: .current))")
        
        let ago = since.agoString
        
        req(RM.getMentions(pubkeys: [NRState.shared.activeAccountPublicKey], kinds:[1,6,7,9735,9802,30023], subscriptionId: "Notifications-CATCHUP-\(ago)", since: sinceNTimestamp))
        req(RM.getMentions(pubkeys: [NRState.shared.activeAccountPublicKey], kinds:[4], subscriptionId: "DMs-CATCHUP-\(ago)", since: dmSinceNTimestamp))
    }
    
    
    // PLAN:
    // Query events for counts
    // But only fetch and parse recent to show on screen.
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] timer in
            self?.checkForEverything()
        }
        timer?.tolerance = 5.0
    }
    
    private func stopTimer() {
        timer?.invalidate()
    }
    
    
    private func checkForEverything() {
        guard account() != nil else { return }
        guard NRState.shared.activeAccountPublicKey != "" else { return }
        
        bg().perform {
            guard !Importer.shared.isImporting else {
                L.og.info("⏳ Still importing, new notifications check skipped.");
                return
            }

            self.relayCheckNewestNotifications() // or wait 3 seconds?
            
            bg().perform { self.checkForUnreadMentions() }
            bg().perform {
                guard !self.muteReposts else { return }
                self.checkForUnreadReposts()
            }
            bg().perform {
                guard !self.muteFollows else { return }
                self.checkForUnreadNewFollowers()
            }
            bg().perform {
                guard !self.muteReactions else { return }
                self.checkForUnreadReactions()
            }
            bg().perform {
                guard !self.muteZaps else { return }
                self.checkForUnreadZaps()
            }
            bg().perform { self.checkForUnreadFailedZaps() }
            
            OfflinePosts.checkForOfflinePosts() // Not really part of notifications but easy to add here and reuse the same timer
        }
    }
    
    
    private func checkForUnreadMentions() {
        //TODO: Should check if there is actual mention in .content
        shouldBeBg()
        
        guard let fetchRequest = q.unreadMentionsQuery(resultType: .managedObjectResultType) else { return }
         
        let unreadMentions = ((try? bg().fetch(fetchRequest)) ?? [])
            .filter { !$0.isSpam } // need to filter so can't use .countResultType
            .count
        
        DispatchQueue.main.async {
            if unreadMentions != self.unreadMentions_ {
                if self.selectedTab == "Notifications" && self.selectedNotificationsTab == "Posts" {
                    self.unreadMentions_ = 0
                }
                else {
                    self.unreadMentions_ = min(unreadMentions,9999)
                }
            }
        }
    }
    
    private func checkForUnreadReposts() {
        //TODO: Should check if there is actual mention in .content
        shouldBeBg()
        
        guard let fetchRequest = q.unreadRepostsQuery(resultType: .managedObjectResultType) else { return }
         
        let unreadReposts = ((try? bg().fetch(fetchRequest)) ?? [])
            .filter { !$0.isSpam } // Need to filter so can't use .countResultType
            .count
        
        DispatchQueue.main.async {
            if unreadReposts != self.unreadReposts_ {
                if self.selectedTab == "Notifications" && self.selectedNotificationsTab == "Posts" {
                    self.unreadReposts_ = 0
                }
                else {
                    self.unreadReposts_ = min(unreadReposts,9999)
                }
            }
        }
    }
    
    private func checkForUnreadNewFollowers() {
        shouldBeBg()
        
        guard let fetchRequest = q.unreadNewFollowersQuery() else { return }
        
        let unreadNewFollowers = (try? bg().count(for: fetchRequest)) ?? 0
        
        DispatchQueue.main.async {
            if unreadNewFollowers != self.unreadNewFollowers_ {
                if self.selectedTab == "Notifications" && self.selectedNotificationsTab == "Posts" {
                    self.unreadNewFollowers_ = 0
                }
                else {
                    self.unreadNewFollowers_ = min(unreadNewFollowers,9999)
                }
            }
        }
    }
    
    private func checkForUnreadReactions() {
        shouldBeBg()
    
        guard let fetchRequest = q.unreadReactionsQuery(resultType: .managedObjectResultType) else { return }
    
        let unreadReactions = ((try? bg().fetch(fetchRequest)) ?? [])
            .filter { !$0.isSpam } // Need to filter so can't use .countResultType
            .count
        
        DispatchQueue.main.async {
            if unreadReactions != self.unreadReactions_ {
                if self.selectedTab == "Notifications" && self.selectedNotificationsTab == "Reactions" {
                    self.unreadReactions_ = 0
                }
                else {
                    self.unreadReactions_ = min(unreadReactions,9999)
                }
            }
        }
    }
    
    private func checkForUnreadZaps() {
        shouldBeBg()
        
        guard let fetchRequest = q.unreadZapsQuery(resultType: .managedObjectResultType) else { return }
        
        let unreadZaps = ((try? bg().fetch(fetchRequest)) ?? [])
            .filter { !$0.isSpam } // Need to filter so can't use .countResultType
            .count
        
        DispatchQueue.main.async {
            if unreadZaps != self.unreadZaps_ {
                if self.selectedTab == "Notifications" && self.selectedNotificationsTab == "Zaps" {
                    self.unreadZaps_ = 0
                }
                else {
                    self.unreadZaps_ = min(unreadZaps,9999)
                }
            }
        }
    }
    
    private func checkForUnreadFailedZaps() {
        shouldBeBg()
        
        guard let fetchRequest = q.unreadFailedZapsQuery() else { return }
        
        let unreadFailedZaps = (try? bg().count(for: fetchRequest)) ?? 0
        
        DispatchQueue.main.async {
            if unreadFailedZaps != self.unreadFailedZaps_ {
                if self.selectedTab == "Notifications" && self.selectedNotificationsTab == "Zaps" {
                    self.unreadFailedZaps_ = 0
                }
                else {
                    self.unreadFailedZaps_ = min(unreadFailedZaps,9999)
                }
            }
        }
    }
    
    // -- MARK: Mark as read
    
    @MainActor public func markMentionsAsRead() {
        self.unreadMentions_ = 0
        
        bg().perform { [weak self] in
            guard let self = self else { return }
            guard let account = Nostur.account() else { return }
            guard let r = q.unreadMentionsQuery(resultType: .managedObjectResultType) 
            else {
                account.lastSeenPostCreatedAt = Int64(Date.now.timeIntervalSince1970)
                return
            }
            r.fetchLimit = 1
            
            if let mostRecent = try? bg().fetch(r).first {
                if account.lastSeenPostCreatedAt != mostRecent.created_at {
                    account.lastSeenPostCreatedAt = mostRecent.created_at
                }
            }
            else {
                let twoDaysAgoOrNewer = max(account.lastSeenPostCreatedAt, (Int64(Date.now.timeIntervalSince1970) - (2 * 3600 * 24)))
                if account.lastSeenPostCreatedAt != twoDaysAgoOrNewer {
                    account.lastSeenPostCreatedAt = twoDaysAgoOrNewer
                }
            }
            bgSave()
            DispatchQueue.main.async { // Maybe another query was running in parallel, so set to 0 again here.
                self.unreadMentions_ = 0
            }
        }
    }
    
    @MainActor public func markRepostsAsRead() {
        self.unreadReposts_ = 0
        
        bg().perform { [weak self] in
            guard let self = self else { return }
            guard let account = Nostur.account() else { return }
            guard let r = q.unreadRepostsQuery(resultType: .managedObjectResultType)
            else {
                account.lastSeenRepostCreatedAt = Int64(Date.now.timeIntervalSince1970)
                return
            }
            r.fetchLimit = 1
            
            if let mostRecent = try? bg().fetch(r).first {
                if account.lastSeenRepostCreatedAt != mostRecent.created_at {
                    account.lastSeenRepostCreatedAt = mostRecent.created_at
                }
            }
            else {
                let twoDaysAgoOrNewer = max(account.lastSeenRepostCreatedAt, (Int64(Date.now.timeIntervalSince1970) - (2 * 3600 * 24)))
                if account.lastSeenRepostCreatedAt != twoDaysAgoOrNewer {
                    account.lastSeenRepostCreatedAt = twoDaysAgoOrNewer
                }
            }
            bgSave()
            DispatchQueue.main.async { // Maybe another query was running in parallel, so set to 0 again here.
                self.unreadReposts_ = 0
            }
        }
    }
    
    @MainActor public func markReactionsAsRead() {
        self.unreadReactions_ = 0
        
        bg().perform { [weak self] in
            guard let self = self else { return }
            guard let account = Nostur.account() else { return }
            guard let r = q.unreadReactionsQuery(resultType: .managedObjectResultType)
            else {
                account.lastSeenReactionCreatedAt = Int64(Date.now.timeIntervalSince1970)
                return
            }
            r.fetchLimit = 1
            
            if let mostRecent = try? bg().fetch(r).first {
                if account.lastSeenReactionCreatedAt != mostRecent.created_at {
                    account.lastSeenReactionCreatedAt = mostRecent.created_at
                }
            }
            else {
                let twoDaysAgoOrNewer = max(account.lastSeenReactionCreatedAt, (Int64(Date.now.timeIntervalSince1970) - (2 * 3600 * 24)))
                if account.lastSeenReactionCreatedAt != twoDaysAgoOrNewer {
                    account.lastSeenReactionCreatedAt = twoDaysAgoOrNewer
                }
            }
            bgSave()
            DispatchQueue.main.async { // Maybe another query was running in parallel, so set to 0 again here.
                self.unreadReactions_ = 0
            }
        }
    }
    
    @MainActor public func markZapsAsRead() {
        self.unreadZaps_ = 0
        self.unreadFailedZaps_ = 0
        
        bg().perform { [weak self] in
            guard let self = self else { return }
            guard let account = Nostur.account() else { return }
            let pubkey = account.publicKey
            
            guard let r = q.unreadZapsQuery(resultType: .managedObjectResultType)
            else {
                account.lastSeenZapCreatedAt = Int64(Date.now.timeIntervalSince1970)
                return
            }
            
            r.fetchLimit = 1
            
            if let mostRecent = try? bg().fetch(r).first {
                if account.lastSeenZapCreatedAt != mostRecent.created_at {
                    account.lastSeenZapCreatedAt = mostRecent.created_at
                }
            }
            else {
                let twoDaysAgoOrNewer = max(account.lastSeenZapCreatedAt, (Int64(Date.now.timeIntervalSince1970) - (2 * 3600 * 24)))
                if account.lastSeenZapCreatedAt != twoDaysAgoOrNewer {
                    account.lastSeenZapCreatedAt = twoDaysAgoOrNewer
                }
            }
            
            // Also do failed zap notifications
            let r3 = NSBatchUpdateRequest(entityName: "PersistentNotification")
            r3.propertiesToUpdate = ["readAt": NSDate()]
            r3.predicate = NSPredicate(format: "readAt == nil AND pubkey == %@ AND type_ IN %@", pubkey, [PNType.failedLightningInvoice.rawValue,PNType.failedZap.rawValue,PNType.failedZaps.rawValue,PNType.failedZapsTimeout.rawValue])
            r3.resultType = .updatedObjectIDsResultType

            let _ = try? bg().execute(r3) as? NSBatchUpdateResult

            bgSave()
            DispatchQueue.main.async { // Maybe another query was running in parallel, so set to 0 again here.
                self.unreadZaps_ = 0
                self.unreadFailedZaps_ = 0
            }
        }
    }
    
    @MainActor public func markNewFollowersAsRead() {
        self.unreadNewFollowers_ = 0
        
        bg().perform { [weak self] in
            guard let self = self else { return }
            guard let account = Nostur.account() else { return }
            let pubkey = account.publicKey
                    
            let r3 = NSBatchUpdateRequest(entityName: "PersistentNotification")
            r3.propertiesToUpdate = ["readAt": NSDate()]
            r3.predicate = NSPredicate(format: "readAt == nil AND pubkey == %@ AND type_ == %@",
                                       pubkey, PNType.newFollowers.rawValue)
            r3.resultType = .updatedObjectIDsResultType

            let _ = try? bg().execute(r3) as? NSBatchUpdateResult

            bgSave()
            DispatchQueue.main.async { // Maybe another query was running in parallel, so set to 0 again here.
                self.unreadNewFollowers_ = 0
            }
        }
    }
    
}


fileprivate class NotificationFetchRequests {
    
    static let FETCH_LIMIT = 999
    
    func unreadMentionsQuery(resultType:NSFetchRequestResultType = .countResultType) -> NSFetchRequest<Event>? {
        guard let account = account() else { return nil }
        let mutedRootIds = account.mutedRootIds_
        let pubkey = account.publicKey
        let blockedPubkeys = account.blockedPubkeys_
        let lastSeenPostCreatedAt = account.lastSeenPostCreatedAt

        let r = Event.fetchRequest()
        r.predicate = NSPredicate(format:
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
        
        r.fetchLimit = Self.FETCH_LIMIT
        r.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        r.resultType = resultType
        
        return r
    }
    
    func unreadRepostsQuery(resultType:NSFetchRequestResultType = .countResultType) -> NSFetchRequest<Event>? {
        guard let account = account() else { return nil }
        let mutedRootIds = account.mutedRootIds_
        let pubkey = account.publicKey
        let blockedPubkeys = account.blockedPubkeys_
        let lastSeenPostCreatedAt = account.lastSeenRepostCreatedAt

        let r = Event.fetchRequest()
        r.predicate = NSPredicate(format:
                                    "created_at > %i " +
                                    "AND otherPubkey == %@ " +
                                    "AND kind == 6 " +
                                    "AND NOT pubkey IN %@ " +
                                    "AND NOT id IN %@ ",
                                    lastSeenPostCreatedAt,
                                    pubkey,
                                    (blockedPubkeys + [pubkey]),
                                    mutedRootIds)
        
        r.fetchLimit = Self.FETCH_LIMIT
        r.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        r.resultType = resultType
        
        return r
    }
    
    func unreadNewFollowersQuery(resultType:NSFetchRequestResultType = .countResultType) -> NSFetchRequest<PersistentNotification>? {
        guard let account = account() else { return nil }
        let pubkey = account.publicKey

        let r = PersistentNotification.fetchRequest()
        r.predicate = NSPredicate(format: "readAt == nil AND type_ == %@ AND pubkey == %@", PNType.newFollowers.rawValue, pubkey)
        r.fetchLimit = Self.FETCH_LIMIT
        r.sortDescriptors = [NSSortDescriptor(keyPath:\PersistentNotification.createdAt, ascending: false)]
        r.resultType = .countResultType
        r.resultType = resultType
         
        return r
    }
    
    func unreadReactionsQuery(resultType:NSFetchRequestResultType = .countResultType) -> NSFetchRequest<Event>? {
        guard let account = account() else { return nil }
        let pubkey = account.publicKey
        let blockedPubkeys = account.blockedPubkeys_

        let r = Event.fetchRequest()
        r.predicate = NSPredicate(format:
                                    "created_at > %i " +
                                    "AND otherPubkey == %@ " +
                                    "AND NOT pubkey IN %@ " +
                                    "AND kind == 7",
                                    account.lastSeenReactionCreatedAt,
                                    pubkey,
                                    (blockedPubkeys + [pubkey]))
        r.fetchLimit = Self.FETCH_LIMIT
        r.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        r.resultType = resultType
        
        return r
    }
    
    func unreadZapsQuery(resultType:NSFetchRequestResultType = .countResultType) -> NSFetchRequest<Event>? {
        guard let account = account() else { return nil }
        let pubkey = account.publicKey
        let blockedPubkeys = account.blockedPubkeys_

        let r = Event.fetchRequest()
        r.predicate = NSPredicate(format:
                                    "created_at > %i " + // AFTER LAST SEEN
                                    "AND otherPubkey == %@" + // ONLY TO ME
                                    "AND kind == 9735 " + // ONLY ZAPS
                                    "AND NOT zapFromRequest.pubkey IN %@", // NOT FROM BLOCKED PUBKEYS. TODO: Maybe need another index like .otherPubkey
                                    account.lastSeenZapCreatedAt,
                                    pubkey,
                                    blockedPubkeys)
        r.fetchLimit = Self.FETCH_LIMIT
        r.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        r.resultType = resultType
        
        return r
    }
    
    func unreadFailedZapsQuery(resultType:NSFetchRequestResultType = .countResultType) -> NSFetchRequest<PersistentNotification>? {
        guard let account = account() else { return nil }
        let pubkey = account.publicKey
        
        let r = PersistentNotification.fetchRequest()
        r.predicate = NSPredicate(format: "readAt == nil AND pubkey == %@ AND type_ IN %@", 
                                  pubkey,
                                  [
                                    PNType.failedZap.rawValue,
                                    PNType.failedZaps.rawValue, // Error
                                    PNType.failedZapsTimeout.rawValue, // Timeout
                                    PNType.failedLightningInvoice.rawValue
                                  ]
        )
        r.fetchLimit = Self.FETCH_LIMIT
        r.sortDescriptors = [NSSortDescriptor(keyPath:\PersistentNotification.createdAt, ascending: false)]
        r.resultType = resultType
                
        return r
    }
}


class OfflinePosts {
    static func checkForOfflinePosts(_ maxAgo:TimeInterval = 3600 * 24 * 3) { // 3 days
        guard SocketPool.shared.anyConnected else { return }
        guard let account = account() else { return }
        let pubkey = account.publicKey
        let xDaysAgo = Date.now.addingTimeInterval(-(maxAgo))
        
        let r1 = Event.fetchRequest()
        // X days ago, from our pubkey, only kinds that we can create+send
        r1.predicate = NSPredicate(format:
                                    "created_at > %i " +
                                    "AND pubkey = %@ " +
                                    "AND kind IN {0,1,3,4,5,6,7,9802} " +
                                    "AND relays = \"\"" +
                                    "AND NOT flags IN {\"nsecbunker_unsigned\",\"awaiting_send\",\"draft\"}" +
                                    "AND sig != nil",
                                    Int64(xDaysAgo.timeIntervalSince1970),
                                    pubkey)
        r1.fetchLimit = 100 // sanity
        r1.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        
        if let offlinePosts = try? bg().fetch(r1) {
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
}


struct NotificationsDebugger: View {
    @EnvironmentObject var nvm:NotificationsViewModel
    
    var body: some View {
        HStack {
            VStack {
                Text("mentions")
                Text(String(nvm.unreadMentions))
            }
            VStack {
                Text("new followers")
                Text(String(nvm.unreadNewFollowers))
            }
            VStack {
                Text("reposts")
                Text(String(nvm.unreadReposts))
            }
            VStack {
                Text("reactions")
                Text(String(nvm.unreadReactions))
            }
            VStack {
                Text("zaps")
                Text(String(nvm.unreadZaps))
            }
            VStack {
                Text("failed zaps")
                Text(String(nvm.unreadFailedZaps))
            }
        }
        .font(.caption)
    }
}
