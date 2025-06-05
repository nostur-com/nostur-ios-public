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
    
    private var lastLocalNotificationAt: Int {
        get { UserDefaults.standard.integer(forKey: "last_local_notification_timestamp") }
        set { UserDefaults.standard.setValue(newValue, forKey: "last_local_notification_timestamp") }
    }
    
    // TODO: Make separate req for kind:4
    static let UNREAD_KINDS: Set<Int> = Set([1,4,6,7,20,9735,9802,30023,34235]) // posts, dms, reposts, reactions, zaps, highlights, articles, video
    
    static let shared = NotificationsViewModel()
    
    private init() {
        startTimer()
        setupSubscriptions()
        if IS_CATALYST {
            setupBadgeNotifications()
        }
    }
    
    public var needsUpdate: Bool = true // Importer or other parts will set this flag to true if anything incoming is part of a notification. Only then the notification queries will run. (instead of before, every 15 sec, even for no reason)
    // is true at start, then false after each notification check
    
    public func checkNeedsUpdate(_ notification: PersistentNotification) {
        guard let account = account() else { return }
        if notification.pubkey == account.publicKey {
            bg().perform { [weak self] in
                self?.needsUpdate = true
            }
        }
    }
    
    public func checkNeedsUpdate(_ event: Event) {
        guard let account = account() else { return }
        switch event.kind {
        case 1,4,20,9802,30023,34235: // TODO: Should check if not muted or blocked
            let before = needsUpdate
            needsUpdate = event.flags != "is_update" && event.fastPs.contains(where: { $0.1 == account.publicKey })
            if needsUpdate && needsUpdate != before {
                self.checkForUnreadMentions()
            }
        case 6:
            needsUpdate = (event.otherPubkey == account.publicKey) // TODO: Should ignore blocked or muted
        case 7:
            needsUpdate = (event.otherPubkey == account.publicKey) // TODO: Should ignore if blocked? (NOT zapFromRequest.pubkey IN %@)
        case 9735:
            needsUpdate = (event.otherPubkey == account.publicKey) // TODO: Should ignore if blocked? (NOT zapFromRequest.pubkey IN %@)
        default:
            return
        }
    }
    
    // Total for the notifications tab on the main tab bar
    public var unread: Int {
        unreadMentions + (muteNewPosts ? 0 : unreadNewPosts) + (muteReactions ? 0 : unreadReactions) + (muteZaps ? 0 : (unreadZaps + unreadFailedZaps)) + (muteFollows ? 0 : unreadNewFollowers) + (muteReposts ? 0 : unreadReposts)
    }
    
    public var unreadPublisher = PassthroughSubject<Int, Never>()
    
    public var unreadMentions: Int { unreadMentions_ }
    
    public var unreadNewPosts: Int {
        guard !muteNewPosts else { return 0 }
        return unreadNewPosts_
    }
        
    public var unreadNewFollowers: Int {
        guard !muteFollows else { return 0 }
        return unreadNewFollowers_
    }
    
    public var unreadReposts: Int {
        guard !muteReposts else { return 0 }
        return unreadReposts_
    }
    
    public var unreadReactions: Int {
        guard !muteReactions else { return 0 }
        return unreadReactions_
    }
    
    public var unreadZaps: Int {
        guard !muteZaps else { return 0 }
        return unreadZaps_
    }
    
    public var unreadFailedZaps: Int { unreadFailedZaps_ }
    
    
    // Don't read these @Published vars, only set them. Use the computed above instead because they correctly return 0 when muted
    @Published var unreadMentions_: Int = 0 {      // 1,20,9802,30023,34235
        didSet {
            if unreadMentions_ > oldValue {
                sendNotification(.newMentions)
            }
            unreadPublisher.send(unread)
        }
    }
    @Published var unreadNewPosts_: Int = 0 {      // 1,20,9802,30023,34235
        didSet {
            if unreadNewPosts_ > oldValue {
                sendNotification(.unreadNewPosts)
            }
            unreadPublisher.send(unread)
        }
    }
    @Published var unreadNewFollowers_: Int = 0 {  // custom
        didSet {
            if unreadNewFollowers_ > oldValue {
                sendNotification(.newFollowers)
            }
            unreadPublisher.send(unread)
        }
    }
    @Published var unreadReposts_: Int = 0 {     // 6
        didSet {
            if unreadReposts_ > oldValue {
                sendNotification(.newReposts)
            }
            unreadPublisher.send(unread)
        }
    }
    @Published var unreadReactions_: Int = 0 {  // 7
        didSet {
            if unreadReactions_ > oldValue {
                sendNotification(.newReactions)
            }
            unreadPublisher.send(unread)
        }
    }
    @Published var unreadZaps_: Int = 0 {       // 9735
        didSet {
            if unreadZaps_ > oldValue {
                sendNotification(.newZaps)
            }
            unreadPublisher.send(unread)
        }
    }
    @Published var unreadFailedZaps_: Int = 0 {  // custom
        didSet {
            unreadPublisher.send(unread)
        }
    }
    
    private var selectedTab: String {
        get { UserDefaults.standard.string(forKey: "selected_tab") ?? "Main" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_tab") }
    }
    
    private var selectedNotificationsTab: String {
        get { UserDefaults.standard.string(forKey: "selected_notifications_tab") ?? "Mentions" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_notifications_tab") }
    }
    
    public var muteFollows: Bool {
        get { UserDefaults.standard.bool(forKey: "notifications_mute_follows") }
        set { UserDefaults.standard.setValue(newValue, forKey: "notifications_mute_follows") }
    }
    
    public var muteReactions: Bool {
        get { UserDefaults.standard.bool(forKey: "notifications_mute_reactions") }
        set { UserDefaults.standard.setValue(newValue, forKey: "notifications_mute_reactions") }
    }
    
    public var muteReposts: Bool {
        get { UserDefaults.standard.bool(forKey: "notifications_mute_reposts") }
        set { UserDefaults.standard.setValue(newValue, forKey: "notifications_mute_reposts") }
    }
    
    public var muteZaps: Bool {
        get { UserDefaults.standard.bool(forKey: "notifications_mute_zaps") }
        set { UserDefaults.standard.setValue(newValue, forKey: "notifications_mute_zaps") }
    }
    
    public var muteNewPosts: Bool {
        get { UserDefaults.standard.bool(forKey: "notifications_mute_new_posts") }
        set { UserDefaults.standard.setValue(newValue, forKey: "notifications_mute_new_posts") }
    }
    
    private var restoreSubscriptionsSubject = PassthroughSubject<Void, Never>()
    private var subscriptions = Set<AnyCancellable>()
    private var timer: Timer?
    
    private let q = NotificationFetchRequests()
    
    // TODO: kind 6 reposts, should check if the reposted post is actually from .pubkey, not just mentioned in p
    
    private func setupSubscriptions() {
        // listen for account changes
        receiveNotification(.activeAccountChanged)
            .sink { [weak self] _ in
                bg().perform {
                    self?.needsUpdate = true
                }
                self?.unreadMentions_ = 0
                self?.unreadNewPosts_ = 0
                self?.unreadNewFollowers_ = 0
                self?.unreadReposts_ = 0
                self?.unreadReactions_ = 0
                self?.unreadZaps_ = 0
                self?.unreadFailedZaps_ = 0
                NotificationsViewModel.shared.restoreSubscriptions()
            }
            .store(in: &subscriptions)
        
        restoreSubscriptionsSubject
            .debounce(for: .seconds(0.2), scheduler: RunLoop.main)
            .throttle(for: .seconds(10.0), scheduler: RunLoop.main, latest: false)
            .sink { [weak self] _ in
                self?.relayCheckNewestNotifications()
                self?.relayCheckSinceNotifications()
            }
            .store(in: &subscriptions)
    }
    
    public func restoreSubscriptions() {
        restoreSubscriptionsSubject.send()
    }
    
    private func setupBadgeNotifications() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.badge, .provisional]) { [weak self] granted, error in
            guard let self else { return }
            if error == nil {
                // Provisional authorization granted.
                self.unreadPublisher // TODO: Also do .unreadPublisher for DMs to fix badge/unread mismatch
                    .sink { [weak self] _ in
                        guard let self else { return }
                        let dmsCount = (DirectMessageViewModel.default.unread + DirectMessageViewModel.default.newRequests)
                        setAppIconBadgeCount(self.unread + dmsCount, center: center)
                    }
                    .store(in: &self.subscriptions)
                
                let dmsCount = (DirectMessageViewModel.default.unread + DirectMessageViewModel.default.newRequests)
                setAppIconBadgeCount(self.unread + dmsCount)
            }
        }
    }
    
    // From now, stays active
    private func relayCheckNewestNotifications() {
        guard AccountsState.shared.activeAccountPublicKey != "" else { return }
        let calendar = Calendar.current
        let ago = calendar.date(byAdding: .minute, value: -1, to: Date())!
        let sinceNTimestamp = NTimestamp(date: ago)
        req(RM.getMentions(pubkeys: [AccountsState.shared.activeAccountPublicKey], kinds:Array(Self.UNREAD_KINDS),
                           subscriptionId: "Notifications", since: sinceNTimestamp),
            activeSubscriptionId: "Notifications")
    }
    
    public var requestSince: Int64 { // TODO: If event .created_at, is in the future don't save date
        let oneWeekAgo = (Int64(Date.now.timeIntervalSince1970) - 604_800)
        guard let account = account() else { return oneWeekAgo }
        return [
            oneWeekAgo,
            account.lastSeenRepostCreatedAt,
            account.lastSeenPostCreatedAt,
            account.lastSeenZapCreatedAt,
            account.lastSeenReactionCreatedAt,
            (DirectMessageViewModel.default.lastNotificationReceivedAt?.timeIntervalSince1970 as? Int64) ?? oneWeekAgo
        ].sorted(by: >).first!
    }
    
    // Check since last notification
    private func relayCheckSinceNotifications() {
        // THIS ONE IS TO CATCH UP, WILL CLOSE AFTER EOSE:
        guard AccountsState.shared.activeAccountPublicKey != "" else { return }
                
        let since = NTimestamp(timestamp: Int(self.requestSince))
        bg().perform { [weak self] in
            self?.needsUpdate = true
            
            DispatchQueue.main.async {
                req(RM.getMentions(pubkeys: [AccountsState.shared.activeAccountPublicKey], kinds:Array(Self.UNREAD_KINDS), subscriptionId: "Notifications-CATCHUP", since: since))
            }
        }
    }
    
    
    // PLAN:
    // Query events for counts
    // But only fetch and parse recent to show on screen.
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] timer in
            guard AccountsState.shared.activeAccountPublicKey != "" else { return }
            bg().perform { [weak self] in
                if (AppState.shared.appIsInBackground && !IS_CATALYST) {
                    self?.checkForUnreadMentions()
                }
                else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { // Give time for AUTH / "auth-required:"
                        bg().perform { [weak self] in
                            self?.checkForEverything()
                        }
                    }
                }
            }
        }
        timer?.tolerance = 5.0
    }
    
    private func checkForEverything() {
        guard (!AppState.shared.appIsInBackground || IS_CATALYST) else {
#if DEBUG
            L.og.debug("NotificationViewModel.checkForEverything(): skipping, app in background.");
#endif
            return
        }
        shouldBeBg()
        
        OfflinePosts.checkForOfflinePosts() // Not really part of notifications but easy to add here and reuse the same timer
        
        guard needsUpdate else { return }
        guard account() != nil else { return }
                
        guard !Importer.shared.isImporting else {
#if DEBUG
            L.og.debug("⏳ NotificationsViewModelcheckForEverything() Still importing, new notifications check skipped.");
#endif
            return
        }
        
        needsUpdate = false // don't check again. Wait for something to set needsUpdate to true to check again.
#if DEBUG
        L.og.debug("💜 NotificationsViewModel.checkForEverything() needsUpdate, updating unread counts...")
#endif

        self.relayCheckNewestNotifications() // or wait 3 seconds?
        
//        if bg().hasChanges { // No idea why after needsUpdate = true, unread badge doesn't update, maybe because .checkNeedsUpdate() is run before bg save, it runs in bg, but different block, so save is needed? so lets try saving here to be sure.
//            do {
//                try bg().save()
//            }
//            catch {
//                L.og.error("🔴🔴 Could not save bgContext \(error)")
//            }
//        }
        
        bg().perform { [weak self] in self?.checkForUnreadMentions() }
        bg().perform { [weak self] in
            guard let self else { return }
            guard !self.muteNewPosts else { return }
            self.checkForUnreadNewPosts()
        }
        bg().perform { [weak self] in
            guard let self else { return }
            guard !self.muteReposts else { return }
            self.checkForUnreadReposts()
        }
        bg().perform { [weak self] in
            guard let self else { return }
            guard !self.muteFollows else { return }
            self.checkForUnreadNewFollowers()
        }
        bg().perform { [weak self] in
            guard let self else { return }
            guard !self.muteReactions else { return }
            self.checkForUnreadReactions()
        }
        bg().perform { [weak self] in
            guard let self else { return }
            guard !self.muteZaps else { return }
            self.checkForUnreadZaps()
        }
        bg().perform { [weak self] in
            self?.checkForUnreadFailedZaps()
        }
    }
    
    public func checkForUnreadMentions() {
        //TODO: Should check if there is actual mention in .content
        shouldBeBg()
        guard let account = account() else { return }
        let accountData = account.toStruct()
        guard let fetchRequest = q.unreadMentionsQuery(resultType: .managedObjectResultType, accountData: accountData) else { return }
         
        let unreadMentions = ((try? bg().fetch(fetchRequest)) ?? [])
            .filter { !$0.isSpam } // need to filter so can't use .countResultType - Also we use it for local notifications now.
        
            // Hellthread handling
            .filter {
            
                // check if actual mention is in content (if there are more than 20 Ps, potential hellthread)
                if $0.fastPs.count > 20 {
                    // but always allow if its a root post
                    if $0.replyToId == nil && $0.replyToRootId == nil {
                        return true
                    }
                    
                    // but always allow if direct reply to own post
                    if let replyToId = $0.replyToId {
                        if let replyTo = Event.fetchEvent(id: replyToId, context: bg()) {
                            if replyTo.pubkey == account.publicKey { // direct reply to our post
                                return true
                            }
                            // direct reply to someone elses post, check if we are actually mentioned in content. (we don't check old [0], [1] style...)
                            return $0.content != nil && $0.content!.contains(account.npub)
                        }
                        // We don't have our own event? Maybe new app user
                        return false // fallback to false
                    }
                    
                    // our npub is in content? (we don't check old [0], [1] style...)
                    return $0.content != nil && $0.content!.contains(account.npub)
                }
                
                return true
            }
            
        let unreadMentionsCount = unreadMentions.count
        
        // For notifications we don't need to total unread, we need total new since last notification, because we don't want to repeat the same notification
        // Most accurate would be to track per mention if we already had a local notification for it. (TODO)
        // For now we just track the timestamp since last notification. (potential problems: inaccurate timestamps? time zones? not account-based?)
        let mentionsForNotification = unreadMentions
            .filter { ($0.created_at > lastLocalNotificationAt) && (!SettingsStore.shared.receiveLocalNotificationsLimitToFollows || account.followingPubkeys.contains($0.pubkey)) }
            .map { Mention(name: $0.contact?.anyName ?? "", message: $0.plainText ) }
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if unreadMentionsCount != self.unreadMentions_ {
                if SettingsStore.shared.receiveLocalNotifications {
                    
                    // Show notification on Mac: ALWAYS
                    // On iOS: Only if app is in background
                    if (IS_CATALYST || AppState.shared.appIsInBackground) && !mentionsForNotification.isEmpty {
                        scheduleMentionNotification(mentionsForNotification)
                    }
                }
                
                
                if self.selectedTab == "Notifications" && self.selectedNotificationsTab == "Posts" {
                    self.unreadMentions_ = 0
                }
                else {
                    self.unreadMentions_ = min(unreadMentionsCount,9999)
                }
            }
        }
    }    
    
    // async for background fetch, copy paste of checkForUnreadMentions() with withCheckedContinuation added
    public func checkForUnreadMentionsBackground(accountData: AccountData) async {
#if DEBUG
        L.og.debug("NotificationsViewModel.checkForUnreadMentionsBackground()")
#endif
        await withCheckedContinuation { [weak self] continuation in
            bg().perform {
                guard let self else { return }
                guard let fetchRequest = self.q.unreadMentionsQuery(resultType: .managedObjectResultType, accountData: accountData) else { continuation.resume(); return }
                 
                let unreadMentionsWithSpam = ((try? bg().fetch(fetchRequest)) ?? [])
                let unreadMentions = unreadMentionsWithSpam
                    .filter { !$0.isSpam } // need to filter so can't use .countResultType - Also we use it for local notifications now.
                    
                let unreadMentionsCount = unreadMentions.count
                
#if DEBUG
                L.og.debug("NotificationsViewModel.checkForUnreadMentionsBackground(): unreadMentionsCount \(unreadMentionsCount), with spam: \(unreadMentionsWithSpam.count)")
#endif
                
                // For notifications we don't need to total unread, we need total new since last notification, because we don't want to repeat the same notification
                // Most accurate would be to track per mention if we already had a local notification for it. (TODO)
                // For now we just track the timestamp since last notification. (potential problems: inaccurate timestamps? time zones? not account-based?)
                let mentionsForNotification = unreadMentions
                    .filter { ($0.created_at > self.lastLocalNotificationAt) && (!SettingsStore.shared.receiveLocalNotificationsLimitToFollows || accountData.followingPubkeys.contains($0.pubkey)) }
                    .map { Mention(name: $0.contact?.anyName ?? "", message: $0.plainText ) }
                
#if DEBUG
                L.og.debug("NotificationsViewModel.checkForUnreadMentionsBackground(): mentions for notifications: \(mentionsForNotification.count)")
#endif
                
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if unreadMentionsCount != self.unreadMentions_ {
                        if SettingsStore.shared.receiveLocalNotifications {
                            
                            // Show notification on Mac: ALWAYS
                            // On iOS: Only if app is in background
                            if (IS_CATALYST || AppState.shared.appIsInBackground) && !mentionsForNotification.isEmpty {
                                scheduleMentionNotification(mentionsForNotification)
                            }
                        }
                        
                        if self.selectedTab == "Notifications" && self.selectedNotificationsTab == "Posts" {
                            self.unreadMentions_ = 0
                        }
                        else {
                            self.unreadMentions_ = min(unreadMentionsCount,9999)
                        }
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    private func checkForUnreadNewPosts() {
        shouldBeBg()
        
        guard let fetchRequest = q.unreadNewPostsQuery() else { return }
        
        let unreadNewPosts = (try? bg().count(for: fetchRequest)) ?? 0
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if unreadNewPosts != self.unreadNewPosts_ {
                if self.selectedTab == "Notifications" && self.selectedNotificationsTab == "New Posts" {
                    self.unreadNewPosts_ = 0
                }
                else {
                    self.unreadNewPosts_ = min(unreadNewPosts,9999)
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
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
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
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
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
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
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
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
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
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
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
            guard let r = q.unreadMentionsQuery(resultType: .managedObjectResultType, accountData: account.toStruct())
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
#if DEBUG
                L.og.info("🔴🔴 markMentionsAsRead() - Falling back to 2 days before (should not happen)")
#endif
                let twoDaysAgoOrNewer = max(account.lastSeenPostCreatedAt, (Int64(Date.now.timeIntervalSince1970) - 172_800))
                if account.lastSeenPostCreatedAt != twoDaysAgoOrNewer {
                    account.lastSeenPostCreatedAt = twoDaysAgoOrNewer
                }
            }
            bgSave()
            DispatchQueue.main.async { [weak self] in // Maybe another query was running in parallel, so set to 0 again here.
                self?.unreadMentions_ = 0
            }
        }
    }
    
    @MainActor public func markNewPostsAsRead() {
        self.unreadNewPosts_ = 0
        
        bg().perform { [weak self] in
            guard let self = self else { return }
            guard let account = Nostur.account() else { return }
            let pubkey = account.publicKey
                    
            let r3 = NSBatchUpdateRequest(entityName: "PersistentNotification")
            r3.propertiesToUpdate = ["readAt": NSDate()]
            r3.predicate = NSPredicate(format: "readAt == nil AND pubkey == %@ AND type_ == %@ AND NOT id == nil",
                                       pubkey, PNType.newPosts.rawValue)
            r3.resultType = .updatedObjectIDsResultType

            let _ = try? bg().execute(r3) as? NSBatchUpdateResult

            bgSave()
            DispatchQueue.main.async { [weak self] in // Maybe another query was running in parallel, so set to 0 again here.
                self?.unreadNewPosts_ = 0
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
                let twoDaysAgoOrNewer = max(account.lastSeenRepostCreatedAt, (Int64(Date.now.timeIntervalSince1970) - 172_800))
                if account.lastSeenRepostCreatedAt != twoDaysAgoOrNewer {
                    account.lastSeenRepostCreatedAt = twoDaysAgoOrNewer
                }
            }
            bgSave()
            DispatchQueue.main.async { [weak self] in // Maybe another query was running in parallel, so set to 0 again here.
                self?.unreadReposts_ = 0
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
                let twoDaysAgoOrNewer = max(account.lastSeenReactionCreatedAt, (Int64(Date.now.timeIntervalSince1970) - 172_800))
                if account.lastSeenReactionCreatedAt != twoDaysAgoOrNewer {
                    account.lastSeenReactionCreatedAt = twoDaysAgoOrNewer
                }
            }
            bgSave()
            DispatchQueue.main.async { [weak self] in // Maybe another query was running in parallel, so set to 0 again here.
                self?.unreadReactions_ = 0
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
                let twoDaysAgoOrNewer = max(account.lastSeenZapCreatedAt, (Int64(Date.now.timeIntervalSince1970) - 172_800))
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
            DispatchQueue.main.async { [weak self] in // Maybe another query was running in parallel, so set to 0 again here.
                self?.unreadZaps_ = 0
                self?.unreadFailedZaps_ = 0
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
            r3.predicate = NSPredicate(format: "readAt == nil AND pubkey == %@ AND type_ == %@ AND NOT id == nil",
                                       pubkey, PNType.newFollowers.rawValue)
            r3.resultType = .updatedObjectIDsResultType

            let _ = try? bg().execute(r3) as? NSBatchUpdateResult

            bgSave()
            DispatchQueue.main.async { [weak self] in // Maybe another query was running in parallel, so set to 0 again here.
                self?.unreadNewFollowers_ = 0
            }
        }
    }
    
}


fileprivate class NotificationFetchRequests {
    
    static let FETCH_LIMIT = 999
    
    func unreadMentionsQuery(resultType: NSFetchRequestResultType = .countResultType, accountData: AccountData) -> NSFetchRequest<Event>? {
        let mutedRootIds = AppState.shared.bgAppState.mutedRootIds
        let blockedPubkeys = AppState.shared.bgAppState.blockedPubkeys

        let r = Event.fetchRequest()
        r.predicate = NSPredicate(format:
                                    "created_at > %i " +
                                    "AND NOT pubkey IN %@ " +
                                    "AND kind IN {1,20,9802,30023,34235} " +
                                    "AND tagsSerialized CONTAINS %@ " +
                                    "AND NOT id IN %@ " + // mutedRootIds
                                    "AND (replyToRootId == nil OR NOT replyToRootId IN %@) " + // mutedRootIds
                                    "AND (replyToId == nil OR NOT replyToId IN %@) " + // mutedRootIds
                                    "AND flags != \"is_update\" ",
                                    accountData.lastSeenPostCreatedAt,
                                    blockedPubkeys + [accountData.publicKey],
                                    serializedP(accountData.publicKey),
                                    mutedRootIds,
                                    mutedRootIds,
                                    mutedRootIds)
        
        r.fetchLimit = Self.FETCH_LIMIT
        r.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        r.resultType = resultType
        
        return r
    }
    
    func unreadNewPostsQuery(resultType: NSFetchRequestResultType = .countResultType) -> NSFetchRequest<PersistentNotification>? {
        guard let account = account() else { return nil }
        let pubkey = account.publicKey

        let r = PersistentNotification.fetchRequest()
        r.predicate = NSPredicate(format: "readAt == nil AND type_ == %@ AND pubkey == %@ AND NOT id == nil", PNType.newPosts.rawValue, pubkey)
        r.fetchLimit = Self.FETCH_LIMIT
        r.sortDescriptors = [NSSortDescriptor(keyPath:\PersistentNotification.createdAt, ascending: false)]
        r.resultType = .countResultType
        r.resultType = resultType
         
        return r
    }
    
    func unreadRepostsQuery(resultType: NSFetchRequestResultType = .countResultType) -> NSFetchRequest<Event>? {
        guard let account = account() else { return nil }
        let mutedRootIds = AppState.shared.bgAppState.mutedRootIds
        let pubkey = account.publicKey
        let blockedPubkeys = AppState.shared.bgAppState.blockedPubkeys
        let lastSeenRepostCreatedAt = account.lastSeenRepostCreatedAt

        let r = Event.fetchRequest()
        r.predicate = NSPredicate(format:
                                    "created_at > %i " +
                                    "AND otherPubkey == %@ " +
                                    "AND kind == 6 " +
                                    "AND NOT pubkey IN %@ " +
                                    "AND NOT id IN %@ ",
                                    lastSeenRepostCreatedAt,
                                    pubkey,
                                    (blockedPubkeys + [pubkey]),
                                    mutedRootIds)
        
        r.fetchLimit = Self.FETCH_LIMIT
        r.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        r.resultType = resultType
        
        return r
    }
    
    func unreadNewFollowersQuery(resultType: NSFetchRequestResultType = .countResultType) -> NSFetchRequest<PersistentNotification>? {
        guard let account = account() else { return nil }
        let pubkey = account.publicKey

        let r = PersistentNotification.fetchRequest()
        r.predicate = NSPredicate(format: "readAt == nil AND type_ == %@ AND pubkey == %@ AND NOT id == nil", PNType.newFollowers.rawValue, pubkey)
        r.fetchLimit = Self.FETCH_LIMIT
        r.sortDescriptors = [NSSortDescriptor(keyPath:\PersistentNotification.createdAt, ascending: false)]
        r.resultType = .countResultType
        r.resultType = resultType
         
        return r
    }
    
    func unreadReactionsQuery(resultType: NSFetchRequestResultType = .countResultType) -> NSFetchRequest<Event>? {
        guard let account = account() else { return nil }
        let pubkey = account.publicKey
        let blockedPubkeys = AppState.shared.bgAppState.blockedPubkeys

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
    
    func unreadZapsQuery(resultType: NSFetchRequestResultType = .countResultType) -> NSFetchRequest<Event>? {
        guard let account = account() else { return nil }
        let pubkey = account.publicKey
        let blockedPubkeys = AppState.shared.bgAppState.blockedPubkeys

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
    
    func unreadFailedZapsQuery(resultType: NSFetchRequestResultType = .countResultType) -> NSFetchRequest<PersistentNotification>? {
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
    
    
    static func checkForOfflinePosts(_ maxAgo: TimeInterval = 259_200) { // 3 days
        DispatchQueue.main.async {
            guard ConnectionPool.shared.anyConnected else { return }
            let pubkey = AccountsState.shared.activeAccountPublicKey
            
            bg().perform {
                let xDaysAgo = Date.now.addingTimeInterval(-(maxAgo))
                
                let r1 = Event.fetchRequest()
                // X days ago, from our pubkey, only kinds that we can create+send
                r1.predicate = NSPredicate(format:
                                            "created_at > %i " +
                                            "AND pubkey = %@ " +
                                            "AND kind IN {0,1,3,4,5,6,7,20,9802,34235} " +
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
                        let nEvent = offlinePost.toNEvent()

                        // don't publish restricted events
                        guard !nEvent.isRestricted else { continue }
                        // make sure that event is older than 15 seconds to prevent interfering with undo timer
                        guard offlinePost.created_at < Int64(Date.now.timeIntervalSince1970 - 15) else { continue }
#if DEBUG
                        L.og.debug("Publishing offline post: \(offlinePost.id)")
#endif
                        DispatchQueue.main.async {
                            Unpublisher.shared.publishNow(nEvent)
                        }
                    }
                }
            }
        }
    }
}


struct NotificationsDebugger: View {
    @EnvironmentObject var nvm: NotificationsViewModel
    
    var body: some View {
        HStack {
            VStack {
                Text("mentions")
                Text(String(nvm.unreadMentions))
            }            
            VStack {
                Text("new posts")
                Text(String(nvm.unreadNewPosts))
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
