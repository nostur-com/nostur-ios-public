//
//  DirectMessageViewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/09/2023.
//

import SwiftUI
import NostrEssentials
import Combine

class DirectMessageViewModelOld: ObservableObject {
    
    private var lastDMLocalNotifcationAt: Int {
        get { UserDefaults.standard.integer(forKey: "last_dm_local_notification_timestamp") }
        set { UserDefaults.standard.setValue(newValue, forKey: "last_dm_local_notification_timestamp") }
    }
    
    static public let `default` = DirectMessageViewModelOld()
    
    public var dmStates: [CloudDMState] = [] {
        didSet {
            if didLoad {
                // normally we load in LoggedInAccount.setupAccount() after WoT or not.
                // Once we loaded once, didLoad is set, and then we can reload on
                // .dmStates being set (which only happens after external iCloud sync on AppView)
                // so this .load() updates the unread counts after sync
                Task { @MainActor in
                    self.load()
                }
            }
            allowedWoT = Set(dmStates.filter { $0.accepted }.compactMap { $0.receiverPubkeys.first })
        }
    }
    
    // pubkeys we started a conv with (but maybe not in WoT), should be allowed in DM WoT
    // Add this to WoT
    public var allowedWoT: Set<String> = []
    
    var pubkey: String?
    var lastNotificationReceivedAt: Date? = nil
    var didLoad = false
    
    @Published var conversationRows: [Conversation] = [] {
        didSet {
            NotificationsViewModel.shared.unreadPublisher.send(NotificationsViewModel.shared.unread)
        }
    }
    @Published var requestRows: [Conversation] = [] {
        didSet {
            NotificationsViewModel.shared.unreadPublisher.send(NotificationsViewModel.shared.unread)
        }
    }
    @Published var requestRowsNotWoT: [Conversation] = [] {
        didSet {
            NotificationsViewModel.shared.unreadPublisher.send(NotificationsViewModel.shared.unread)
        }
    }
    
    @Published var showNotWoT = false {
        didSet {
            if showNotWoT {
                requestRows = requestRows + requestRowsNotWoT
            }
            else {
                self.reloadMessageRequests()
            }
        }
    }
     
    var unread: Int {
        conversationRows.reduce(0) { $0 + $1.unread }
    }
    var newRequests: Int {
        requestRows.reduce(0) { $0 + $1.unread }
    }
    
    var newRequestsNotWoT: Int {
        requestRowsNotWoT.count
    }
    
    public var hiddenDMs: Int {
        dmStates.count { $0.accountPubkey_ == self.pubkey && $0.isHidden }
    }
    
    private var subscriptions = Set<AnyCancellable>()
    
    private init() {
        self._reloadAccepted
            .debounce(for: 1.5, scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.loadAcceptedConversations()
            }
            .store(in: &self.subscriptions)
        
        self._reloadMessageRequests
            .debounce(for: 2.0, scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.loadMessageRequests()
            }
            .store(in: &self.subscriptions)
        
        self._reloadMessageRequestsNotWot
            .debounce(for: 2.5, scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.loadOutSideWoT()
            }
            .store(in: &self.subscriptions)
        
        receiveNotification(.blockListUpdated)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.showNotWoT = false
                self?.reloadAccepted()
                self?.reloadMessageRequests()
                self?.reloadMessageRequestsNotWot()
            }
            .store(in: &self.subscriptions)
        
        if IS_CATALYST {
            setupBadgeNotifications()
        }
    }
    
    private func setupBadgeNotifications() { // Copy pasta from NotificationsViewModel
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.badge, .provisional]) { [weak self] granted, error in
            guard let self else { return }
            if error == nil {
                // Provisional authorization granted.
                self.objectWillChange
                    .sink { [weak self] _ in
                        guard let self else { return }
                        let notificationsCount = NotificationsViewModel.shared.unread
                        setAppIconBadgeCount((self.unread + self.newRequests) + notificationsCount, center: center)
                    }
                    .store(in: &self.subscriptions)
                
                let notificationsCount = NotificationsViewModel.shared.unread
                setAppIconBadgeCount((self.unread + self.newRequests) + notificationsCount)
            }
        }
    }
    
    // .load is called from:
    // NRState on startup if WoT is disabled
    // receiveNotification(.WoTReady) if WoT is enabled, after WoT has loaded
    @MainActor
    public func load() {
        guard !AccountsState.shared.activeAccountPublicKey.isEmpty else { return }
        conversationRows = []
        requestRows = []
        requestRowsNotWoT = []
        self.pubkey = AccountsState.shared.activeAccountPublicKey
        self.loadAcceptedConversations()
        self.loadMessageRequests()
        self.loadOutSideWoT() // even if we don't show it, we need to load to show how many there are in toggle.
        didLoad = true
    }
    
    public func loadAfterWoT() {
        receiveNotification(.WoTReady)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.load()
                }
            }
            .store(in: &self.subscriptions)
    }
    
    public func markAcceptedAsRead() {
        objectWillChange.send()
        for conv in conversationRows {
            conv.unread = 0
            conv.dmState.markedReadAt_ = Date.now
            conv.dmState.didUpdate.send()
        }
    }
    
    public func markRequestsAsRead() {
        objectWillChange.send()
        for conv in requestRows {
            conv.unread = 0
            conv.dmState.markedReadAt_ = Date.now
            conv.dmState.didUpdate.send()
        }
        if showNotWoT {
            for conv in requestRowsNotWoT {
                conv.unread = 0
                conv.dmState.markedReadAt_ = Date.now
                conv.dmState.didUpdate.send()
            }
        }
            
    }
    
    
    public func reloadAccepted() { _reloadAccepted.send() }
    private var _reloadAccepted = PassthroughSubject<Void, Never>()
    

    public func reloadMessageRequests() { _reloadMessageRequests.send() }
    private var _reloadMessageRequests = PassthroughSubject<Void, Never>()
    
    private func reloadMessageRequestsNotWot() { _reloadMessageRequestsNotWot.send() }
    private var _reloadMessageRequestsNotWot = PassthroughSubject<Void, Never>()
    
    private func loadAcceptedConversations() {
        guard let pubkey = self.pubkey else { return }
        let blockedPubkeys = blocks()
        
        let conversations = dmStates
            .filter { !$0.isHidden && $0.accountPubkey_ == pubkey }
            .filter { $0.accepted && !blockedPubkeys.contains($0.receiverPubkeys.first ?? "HMMICECREAMSOGOOD") }
        
        var lastNotificationReceivedAt: Date? = nil
        
        var conversationRows = [Conversation]()
        
        
        for conv in conversations {
            guard let accountPubkey = conv.accountPubkey_, let contactPubkey = conv.receiverPubkeys.first
            else {
                L.og.error("Conversation is missing account or contact pubkey, something wrong \(conv.debugDescription)")
                continue
            }
            let convMarkedReadAt = conv.markedReadAt_
            let accepted = conv.accepted
            
            bg().perform {
                let mostRecentSent = Event.fetchMostRecentEventBy(pubkey: accountPubkey, andOtherPubkey: contactPubkey, andKinds: [4,14], context: bg())
                
                let unreadSince = (convMarkedReadAt ?? (mostRecentSent?.date ?? Date(timeIntervalSince1970: 0)))
                
                // Not just most recent, but all so we can also count unread
                let allReceived = Event.fetchEventsBy(pubkey: contactPubkey, andKinds: [4,14], context: bg())
                    .filter { $0.pTags().contains(where: { $0 == pubkey }) }
                
                let mostRecent = ([mostRecentSent] + allReceived)
                    .compactMap({ $0 })
                    .sorted(by: { $0.created_at > $1.created_at })
                    .first
                
                if let mostRecent, lastNotificationReceivedAt == nil { // set most recent if we dont have it set yet
                    lastNotificationReceivedAt = mostRecent.date
                }
                else if let mostRecent, let currentMostRecent = lastNotificationReceivedAt, mostRecent.date > currentMostRecent { // set if this one is more recent
                    lastNotificationReceivedAt = mostRecent.date
                }
                
                // Unread count is based on (in the following fallback order):
                // - 0 if last message is sent by own account
                // - Manual markedReadAt date
                // - Most recent DM sent (by own account) date
                // - Since beginning of time (all)
                
                let lastMessageByOwnAccount = mostRecent?.pubkey == pubkey
                
                let unread = lastMessageByOwnAccount
                ? 0
                : allReceived.count { $0.date > unreadSince }
                
                let nrContact: NRContact = NRContact.instance(of: contactPubkey)
                
                guard let mostRecent = mostRecent else { return }
                
                conversationRows
                    .append(Conversation(contactPubkey: contactPubkey, nrContact: nrContact, mostRecentMessage: mostRecent.noteText, mostRecentDate: mostRecent.date, mostRecentEvent: mostRecent, unread: unread, dmState: conv, accepted: accepted))
            }
        }
        
        // Wrap in bg().perform so it happens after the last bg() loop above
        bg().perform { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                if let lastNotificationReceivedAt, self.lastNotificationReceivedAt == nil { // set most recent if we dont have it set yet
                    self.lastNotificationReceivedAt = lastNotificationReceivedAt
                }
                else if let lastNotificationReceivedAt, let currentMostRecent = self.lastNotificationReceivedAt, lastNotificationReceivedAt > currentMostRecent { // set if this one is more recent
                    self.lastNotificationReceivedAt = lastNotificationReceivedAt
                }
                
                self.conversationRows = conversationRows
                    .sorted(by: { $0.mostRecentDate > $1.mostRecentDate })
                    .sorted(by: { $0.dmState.isPinned && !$1.dmState.isPinned })
            }
        }
    }
    
    private func loadMessageRequests() {
        guard let pubkey = self.pubkey else { return }
        let blockedPubkeys = blocks()
        
        let conversations = dmStates
            .filter { !$0.isHidden && $0.accountPubkey_ == pubkey }
            .filter { !$0.accepted && !blockedPubkeys.contains($0.receiverPubkeys.first ?? "HMMICECREAMSOGOOD") }
            .filter { dmState in
                if (!WOT_FILTER_ENABLED()) { return true }
                guard let contactPubkey = dmState.receiverPubkeys.first else { return false }
                return WebOfTrust.shared.isAllowed(contactPubkey)
            }
            
        var lastNotificationReceivedAt:Date? = nil

        var conversationRows = [Conversation]()
        
        for conv in conversations {
            guard let contactPubkey = conv.receiverPubkeys.first
            else {
                L.og.error("Conversation is missing account or contact pubkey, something wrong \(conv.debugDescription)")
                continue
            }
            
            let unreadSince = conv.markedReadAt_ ?? Date(timeIntervalSince1970: 0)
            let accepted = conv.accepted
            
            bg().perform {
                // Not just most recent, but all so we can also count unread
                let allReceived = Event.fetchEventsBy(pubkey: contactPubkey, andKinds: [4,14], context: bg())
                    .filter { $0.pTags().contains(where: { $0 == pubkey }) }

                let mostRecent = allReceived.first
                
                if let mostRecent, lastNotificationReceivedAt == nil { // set most recent if we dont have it set yet
                    lastNotificationReceivedAt = mostRecent.date
                }
                else if let mostRecent, let currentMostRecent = lastNotificationReceivedAt, mostRecent.date > currentMostRecent { // set if this one is more recent
                    lastNotificationReceivedAt = mostRecent.date
                }
                
                // Unread count is based on (in the following fallback order):
                // - Manual markedReadAt date
                // - Since beginning of time (all)
                
                let unread = allReceived.count { $0.date > unreadSince }
                
                let nrContact: NRContact = NRContact.instance(of: contactPubkey)

                guard let mostRecent = mostRecent else { return }
                
                conversationRows
                    .append(Conversation(contactPubkey: contactPubkey, nrContact: nrContact, mostRecentMessage: mostRecent.noteText, mostRecentDate: mostRecent.date, mostRecentEvent: mostRecent, unread: unread, dmState: conv, accepted: accepted))
            }
        }

        // Wrap in bg().perform so it happens after the last bg() loop above
        bg().perform { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                
                if let lastNotificationReceivedAt, self.lastNotificationReceivedAt == nil { // set most recent if we dont have it set yet
                    self.lastNotificationReceivedAt = lastNotificationReceivedAt
                }
                else if let lastNotificationReceivedAt, let currentMostRecent = self.lastNotificationReceivedAt, lastNotificationReceivedAt > currentMostRecent { // set if this one is more recent
                    self.lastNotificationReceivedAt = lastNotificationReceivedAt
                }
                
                self.requestRows = conversationRows
                    .sorted(by: { $0.mostRecentDate > $1.mostRecentDate })
                    .sorted(by: { $0.dmState.isPinned && !$1.dmState.isPinned })
            }
        }
    }
    
    private func loadOutSideWoT() {
        guard WOT_FILTER_ENABLED() else { return }
        guard let pubkey = self.pubkey else { return }
        let blockedPubkeys = blocks()
        
        let conversations = dmStates
            .filter { !$0.isHidden && $0.accountPubkey_ == pubkey }
            .filter { !$0.accepted && !blockedPubkeys.contains($0.receiverPubkeys.first ?? "HMMICECREAMSOGOOD") }
            .filter { dmState in
                guard let contactPubkey = dmState.receiverPubkeys.first else { return false }
                return !WebOfTrust.shared.isAllowed(contactPubkey)
            }
        
        var conversationRows = [Conversation]()
        
        for conv in conversations {
            guard let contactPubkey = conv.receiverPubkeys.first
            else {
                L.og.error("Conversation is missing account or contact pubkey, something wrong \(conv.debugDescription)")
                continue
            }
            
            let unreadSince = conv.markedReadAt_ ?? Date(timeIntervalSince1970: 0)
            let accepted = conv.accepted
            
            bg().perform {
                // Not just most recent, but all so we can also count unread
                let allReceived = Event.fetchEventsBy(pubkey: contactPubkey, andKinds: [4,14], context: bg())
                    .filter { $0.pTags().contains(where: { $0 == pubkey }) }

                let mostRecent = allReceived.first
                
                // Unread count is based on (in the following fallback order):
                // - Manual markedReadAt date
                // - Since beginning of time (all)
                
                let unread = allReceived.count { $0.date > unreadSince }
                
                let nrContact: NRContact = NRContact.instance(of: contactPubkey)
                
                guard let mostRecent = mostRecent else { return }
                
                conversationRows
                    .append(Conversation(contactPubkey: contactPubkey, nrContact: nrContact, mostRecentMessage: mostRecent.noteText, mostRecentDate: mostRecent.date, mostRecentEvent: mostRecent, unread: unread, dmState: conv, accepted: accepted))
            }
        }

        // Wrap in bg().perform so it happens after the last bg() loop above
        bg().perform { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.requestRowsNotWoT = conversationRows
                    .sorted(by: { $0.mostRecentDate > $1.mostRecentDate })
                    .sorted(by: { $0.dmState.isPinned && !$1.dmState.isPinned })
                
                if self.showNotWoT {
                    self.requestRows = self.requestRows + self.requestRowsNotWoT
                }
            }
        }
    }
    
    public func unhideAll() {
        for dmState in dmStates {
            if dmState.isHidden {
                dmState.isHidden = false
            }
        }
    }
    
    public func newMessage() {
        guard let pubkey = self.pubkey else { return }
        Task { @MainActor in
            self.dmStates = CloudDMState.fetchByAccount(pubkey, context: viewContext())
            self.reloadAccepted()
            self.reloadMessageRequests()
            self.reloadMessageRequestsNotWot()
        }
    }
    
    public func checkNeedsNotification(_ event: Event) {
        guard let account = account() else { return }
        guard let firstP = event.firstP() else { return }
        guard firstP == AccountsState.shared.activeAccountPublicKey else { return }
        guard event.created_at > lastDMLocalNotifcationAt else { return }
        
        // Only continue if either limit to follows is not enabled, or if we are following the sender
        guard !SettingsStore.shared.receiveLocalNotificationsLimitToFollows || account.followingPubkeys.contains(event.pubkey) else { return }
        
        // Only continue if sender is in WoT, or if WoT is disabled
        guard (!WOT_FILTER_ENABLED()) || WebOfTrust.shared.isAllowed(event.pubkey) else {
            return
        }
                
        // Show notification on Mac: ALWAYS
        // On iOS: Only if app is in background
        if (IS_CATALYST || AppState.shared.appIsInBackground)  {
            let name = contactUsername(fromPubkey: event.pubkey, event: event)
            scheduleDMNotification(name: name)
        }
    }
    
    private func monthsAgoRange(_ months:Int) -> (since: Int, until: Int) {
        return (
            since: NTimestamp(date: Date().addingTimeInterval(Double(months + 1) * -2_592_000)).timestamp,
            until: NTimestamp(date: Date().addingTimeInterval(Double(months) * -2_592_000)).timestamp
        )
    }
    
    @Published var scanningMonthsAgo = 0
    
    public func rescanForMissingDMs(_ monthsAgo: Int) {
        guard let pubkey else { return }
        guard scanningMonthsAgo == 0 else { return }
        
        for i in 0...monthsAgo {
            let ago = monthsAgoRange(monthsAgo - i)
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(3 * i)) { [weak self] in
                guard let self else { return }
                self.scanningMonthsAgo = i+1 == (monthsAgo + 1) ? 0 : i+1
                
                if let message = CM(
                    type: .REQ,
                    filters: [
                        // DMs sent
                        Filters(authors: Set([pubkey]), kinds: [4,1059], since: ago.since, until: ago.until),
                        // DMs received
                        Filters(kinds: [4,1059], tagFilter: TagFilter(tag: "p", values: [pubkey]), since: ago.since, until: ago.until)
                    ]
                ).json() {
                    req(message)
                }
                
                if i+1 == monthsAgo {
#if DEBUG
                    L.maintenance.info("Running Manual DM fix")
#endif
                    Maintenance.runFixMissingDMStates(force: true, context: viewContext())
                    Maintenance.runUpgradeDMformat(force: true, context: viewContext())
                    try? viewContext().save()
                }
            }
        }
    }
}
