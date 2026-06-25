//
//  DMsVM.swift
//  Nostur
//
//  Created by Fabian Lachman on 09/12/2025.
//

import SwiftUI
import Combine
import NostrEssentials

class DMsVM: ObservableObject, Equatable, Hashable {
    private final class WeakDMsVMBox {
        weak var value: DMsVM?
        
        init(_ value: DMsVM) {
            self.value = value
        }
    }
    
    @MainActor private static var liveInstances: [ObjectIdentifier: WeakDMsVMBox] = [:]
    
    static func == (lhs: DMsVM, rhs: DMsVM) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    @Published var ncNotSupported = false
    @Published var ready = false
    
    @Published var tab = "Accepted"
    
    // Short uuid
    let id: String = String(UUID().uuidString.prefix(48))
    
    public var isMain: Bool {
        self.id == Self.shared.id
    }
    
    // Tracks the conversationId currently visible to the user (Mac only)
    var activeConversationId: String? = nil
    
    // Shared is for the main / currently logged in account
    static let shared = DMsVM()
    
    static func restoreSubscriptions() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            cleanupLiveInstances()
            for vm in liveInstances.values.compactMap(\.value) {
                vm.restoreSubscriptions()
            }
        }
    }
    
    @MainActor
    private static func register(_ vm: DMsVM) {
        cleanupLiveInstances()
        liveInstances[ObjectIdentifier(vm)] = WeakDMsVMBox(vm)
    }
    
    @MainActor
    private static func unregister(_ id: ObjectIdentifier) {
        liveInstances.removeValue(forKey: id)
    }
    
    @MainActor
    private static func cleanupLiveInstances() {
        liveInstances = liveInstances.filter { $0.value.value != nil }
    }
    
    public var dmStates: [CloudDMState] = []
    {
        didSet {
            allowedWoT = Set(dmStates.filter { $0.accepted }.compactMap { $0.contactPubkey_ })
        }
    }
    
    // pubkeys we started a conv with (but maybe not in WoT), should be allowed in DM WoT
    // Add this to WoT
    public var allowedWoT: Set<String> = []
    
    public var accountPubkey: String

    
    @Published var conversationRows: [CloudDMState] = [] {
        didSet { updateUnreadsCount() }
    }
    @Published var requestRows: [CloudDMState] = [] {
        didSet { updateUnreadsCount() }
    }
    @Published var requestRowsNotWoT: [CloudDMState] = [] {
        didSet { updateUnreadsCount() }
    }
    
    @Published var showNotWoT = false {
        didSet {
            if showNotWoT {
                requestRows = requestRows + requestRowsNotWoT
            }
            else {
                self.reloadConversations()
            }
        }
    }
    
    @Published var showUpgradeNotice = false
     
    @Published var unread: Int = 0
    @Published var unreadNewRequestsCount: Int = 0
    @Published var unreadNewRequestsNotWoTCount: Int = 0
    
    @MainActor
    private func updateUnreads() async {
        self.objectWillChange.send()
        var unreadCount = 0
        for conversationRow in conversationRows {
            unreadCount += await conversationRow.getUnread()
        }
        self.unread = unreadCount
        
        var newRequestsCount = 0
        for requestRow in requestRows {
            newRequestsCount += await requestRow.getUnread()
        }
        self.unreadNewRequestsCount = newRequestsCount
        
        self.unreadNewRequestsNotWoTCount = requestRowsNotWoT.count
    }
    
    private func sortedDMRows(_ rows: [CloudDMState]) -> [CloudDMState] {
        rows.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            
            return (lhs.lastMessageTimestamp_ ?? .distantPast) > (rhs.lastMessageTimestamp_ ?? .distantPast)
        }
    }
    
    private func updateSorting() {
        self.conversationRows = sortedDMRows(self.conversationRows)
        self.requestRows = sortedDMRows(self.requestRows)
        self.requestRowsNotWoT = sortedDMRows(self.requestRowsNotWoT)
    }
    
    public var hiddenDMs: Int {
        dmStates.count { $0.isHidden }
    }
    
    private var subscriptions = Set<AnyCancellable>()
    
    init(accountPubkey: String? = nil) {
        self.accountPubkey = accountPubkey ?? AccountsState.shared.activeAccountPublicKey
        
        receiveNotification(.WoTReady)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.load()
                }
            }
            .store(in: &self.subscriptions)
        
        self._reloadConversations
            .debounce(for: 1.5, scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.loadConversations()
                }
            }
            .store(in: &self.subscriptions)
        
        self._updateUnreadsCount
            .debounce(for: 0.25, scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.updateUnreads()
                }
            }
            .store(in: &self.subscriptions)
        
        receiveNotification(.blockListUpdated)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.showNotWoT = false
                    self?.loadConversations()
                }
            }
            .store(in: &self.subscriptions)
        
        
        
        Task { @MainActor [weak self] in
            if let self {
                Self.register(self)
            }
            self?.setupAccountChangedListener()
            if IS_CATALYST {
                self?.setupBadgeNotifications()
            }
        }
    }
    
    // For .shared/main account
    // .load is called from:
    // AccountsState on startup if WoT is disabled
    // receiveNotification(.WoTReady) if WoT is enabled, after WoT has loaded
    
    // For per account columns: .onAppear/.task of column
    @MainActor
    public func load(force: Bool = false) async {
        syncMainAccountPubkeyIfNeeded()
        guard !accountPubkey.isEmpty else { return }
        guard force || !ready else { return }
        if let account = AccountsState.shared.accounts.first(where: { $0.publicKey == self.accountPubkey }) {
            ncNotSupported = account.isNC
        }
        
        showUpgradeNotice = false
        conversationRows = []
        requestRows = []
        requestRowsNotWoT = []
        
        if ncNotSupported {
            return
        }
        
        self.fetchDMrelays()
        self.loadDMStates()
        self.loadConversations()
        // do 3 month scan if we have no messages (probably first time)
        // longer 36 month scan is in settings
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if (self.conversationRows.count == 0 && self.requestRows.count == 0) {
                self.rescanForMissingDMs(3)
            }
        }
        ready = true
        showUpgradeNotice = await shouldShowUpgradeNotice(accountPubkey: self.accountPubkey)
        self.listenForNewMessages()
        
    
        // Always delay 1.5 second so more important other reqs go first at launch / reopen from bg
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        guard !Task.isCancelled else { return }
        self.fetchNip04DMs()
        self.fetchGiftWraps()
        self.startGiftWrapsTimer()
    }

    private func fetchDMrelays() {
        let reqFilters = Filters(
            authors: [accountPubkey],
            kinds: [10050],
            limit: 1
        )
        nxReq(
            reqFilters,
            subscriptionId: "DM-DMsVM" + UUID().uuidString.prefix(48),
            relayType: .READ
        )
    }
    
    // NIP-17 / NIP-59 randomize the gift wrap (kind 1059) created_at up to 2 days into the past,
    // so to avoid missing messages we look back 2 days before our newest known NIP-17 message
    // instead of re-fetching a fixed 6-day window every session/refresh. The lookback is clamped
    // to at most 6 days so a stale inbox (newest message is weeks old) doesn't re-pull a huge
    // range on every 60s timer refresh.
    private static let nip17RandomizationWindow: TimeInterval = 2 * 24 * 60 * 60 // 48 hours
    private static let maxGiftWrapLookback: TimeInterval = 6 * 24 * 60 * 60 // 6 days

    private var lastGiftWrapAt: Int {
        let oldestAllowed = Date(timeIntervalSinceNow: -Self.maxGiftWrapLookback)
        let newestNip17 = dmStates
            .filter { $0.version == 17 }
            .compactMap { $0.lastMessageTimestamp_ }
            .max()
        guard let newestNip17 else {
            return Int(oldestAllowed.timeIntervalSince1970) // no NIP-17 history yet
        }
        // 2 days before our newest NIP-17 message, but never older than 6 days ago.
        let since = max(newestNip17.addingTimeInterval(-Self.nip17RandomizationWindow), oldestAllowed)
        return Int(since.timeIntervalSince1970)
    }
    
    private var giftWrapSubscriptionId: String {
        "-OPEN-59-" + self.id
    }
    
    private var sentDMSubscriptionId: String {
        "-OPEN-DM-S-" + self.id
    }
    
    private var receivedDMSubscriptionId: String {
        "-OPEN-DM-R-" + self.id
    }
    
    private var giftWrapsTimer: Timer? = nil
    private func startGiftWrapsTimer() {
        guard giftWrapsTimer == nil else { return }
        self.giftWrapsTimer?.invalidate()
        self.giftWrapsTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.fetchGiftWraps(forceRefresh: true)
        }
        self.giftWrapsTimer?.tolerance = 15.0
    }
    
    @MainActor
    public func restoreSubscriptions() {
        guard ready, !ncNotSupported, !accountPubkey.isEmpty else { return }
        loadConversations(fullReload: true)
        fetchDMrelays()
        ConnectionPool.shared.closeSubscription(sentDMSubscriptionId)
        ConnectionPool.shared.closeSubscription(receivedDMSubscriptionId)
        fetchNip04DMs()
        fetchGiftWraps(forceRefresh: true)
    }
    
    public func fetchGiftWraps(forceRefresh: Bool = false) {
        let accountPubkey = self.accountPubkey
        let reqFilters = Filters(
            kinds: [1059],
            tagFilter: TagFilter(tag: "p", values: [accountPubkey]),
            since: lastGiftWrapAt
        )
        let subscriptionId = self.giftWrapSubscriptionId
        Task { [weak self] in
            guard let self else { return }
            let dmRelays = await self.giftWrapReadRelays(accountPubkey: accountPubkey)
            await MainActor.run {
                if forceRefresh {
                    ConnectionPool.shared.closeSubscription(subscriptionId)
                }
                
                guard !dmRelays.isEmpty else {
                    nxReq(
                        reqFilters,
                        subscriptionId: subscriptionId,
                        isActiveSubscription: true,
                        relayType: .READ
                    )
                    return
                }

                let dmRelayData: Set<RelayData> = Set(dmRelays.map {
                    RelayData.new(url: $0, read: false, write: false, search: false, auth: false)
                })

                // Ensure explicit relay-limited REQs can use DM relays even if they are not global read relays.
                dmRelayData.forEach { relay in
                    ConnectionPool.shared.addConnection(relay)
                }

                nxReq(
                    reqFilters,
                    subscriptionId: subscriptionId,
                    isActiveSubscription: true,
                    relays: dmRelayData,
                    relayType: .READ
                )
            }
        }
    }

    private func giftWrapReadRelays(accountPubkey: String) async -> Set<String> {
        let accountDMRelays: Set<String> = await MainActor.run {
            guard let account = AccountsState.shared.accounts.first(where: { $0.publicKey == accountPubkey }) else { return [] }
            return Set(account.accountRelays.filter { $0.dm }.map { $0.url })
        }
        let kind10050Relays = await getDMrelays(for: accountPubkey)
        return accountDMRelays.union(kind10050Relays)
    }
    
    private var lastNip04Since: Int {
        get {
            let key = accountSpecificKey(accountPubkey, forKey: "last_nip04_since")
            return UserDefaults.standard.integer(forKey: key)
        }
        set {
            let key = accountSpecificKey(accountPubkey, forKey: "last_nip04_since")
            UserDefaults.standard.setValue(newValue, forKey: key)
        }
    }
    
    private static let maxNip04Lookback: TimeInterval = 6 * 24 * 60 * 60 // 6 days
    
    private var nip04Since: Int {
        let oldestAllowed = Int(Date(timeIntervalSinceNow: -Self.maxNip04Lookback).timeIntervalSince1970)

        // since last, but never older than 6 days ago.
        let since = max(lastNip04Since, oldestAllowed)
        return since
    }
    
    public func fetchNip04DMs() {
        // TODO: Add "since" per account, store timestamp in user defaults
        nxReq(
            Filters(
                authors: [accountPubkey],
                kinds: [4],
                since: lastNip04Since,
                limit: 999,
            ),
            subscriptionId: sentDMSubscriptionId
        )
        
        nxReq(
            Filters(
                kinds: [4],
                tagFilter: TagFilter(tag: "p", values: [accountPubkey]),
                since: lastNip04Since,
                limit: 999
            ),
            subscriptionId: receivedDMSubscriptionId
        )
        
        // TODO: Should actually check if REQ was succuess and not disconnected etc
        lastNip04Since = Int(Date().timeIntervalSince1970)
    }
    
    deinit {
        let sentDMSubscriptionId = self.sentDMSubscriptionId
        let receivedDMSubscriptionId = self.receivedDMSubscriptionId
        let giftWrapSubscriptionId = self.giftWrapSubscriptionId
        let instanceId = ObjectIdentifier(self)
        Task { @MainActor in
            Self.unregister(instanceId)
            ConnectionPool.shared.closeSubscription(sentDMSubscriptionId)
            ConnectionPool.shared.closeSubscription(receivedDMSubscriptionId)
            ConnectionPool.shared.closeSubscription(giftWrapSubscriptionId)
        }
    }
    
    private var accountChangedSubscription: AnyCancellable?
    
    private func setupAccountChangedListener() {
        guard isMain && accountChangedSubscription == nil else { return }
        accountChangedSubscription = receiveNotification(.activeAccountChanged)
            .sink { [weak self] notification in
                Task { @MainActor in
                    let account = notification.object as! CloudAccount
                    guard self?.accountPubkey != account.publicKey || !(self?.ready ?? false) else { return }
                    await self?.reload(accountPubkey: account.publicKey)
                }
            }
    }

    @MainActor
    private func syncMainAccountPubkeyIfNeeded() {
        guard isMain && accountPubkey.isEmpty else { return }
        let activeAccountPubkey = AccountsState.shared.activeAccountPublicKey
        guard !activeAccountPubkey.isEmpty else { return }
        accountPubkey = activeAccountPubkey
    }
    
    public func loadAfterWoT() {
        guard isMain else { return }
        
    }
    
    private func listenForNewMessages() {
        Importer.shared.importedDMSub // (conversationId: groupId, event: savedEvent, nEvent: nEvent)
            .filter { $0.nEvent.pTags().contains(self.accountPubkey) || $0.nEvent.publicKey == self.accountPubkey }
            .sink { (conversationId, event, nEvent, newDMStateCreated) in
                
                if newDMStateCreated {
                    Task { @MainActor in
#if DEBUG
                        L.og.debug("💌💌 DMsVM.loadConversations(fullReload: true) (newDMStateCreated)")
#endif
                        self.loadConversations(fullReload: true)
                    }
                }
                
                self.updateUnreadsCount()
                
                Task { @MainActor in
                    self.updateSorting()
                }
                
                // Only do notifications for logged in account
                guard self.isMain else { return }
                // Don't send notification if it is our own message
                guard nEvent.publicKey != self.accountPubkey else { return }
                
                guard nEvent.createdAt.timestamp > self.lastNip04Since else { return }
                
                let followingPubkeys = account(by: self.accountPubkey)?.followingPubkeys ?? []
                
                // Only continue if either limit to follows is not enabled, or if we are following the sender
                guard !SettingsStore.shared.receiveLocalNotificationsLimitToFollows || followingPubkeys.contains(event.pubkey) else { return }
                
                // Only continue if sender is in WoT, or if WoT is disabled
                guard (!WOT_FILTER_ENABLED()) || WebOfTrust.shared.isAllowed(nEvent.publicKey) else {
                    return
                }
                
                // Don't create notification if blocked
                guard !blocks().contains(nEvent.publicKey) else { return }
        
                // Show notification on Mac: Only if the conversation is not currently in view
                // On iOS: Only if app is in background
                let conversationIsActive = IS_CATALYST && !AppState.shared.appIsInBackground && self.activeConversationId == conversationId
                if !conversationIsActive && (IS_CATALYST || AppState.shared.appIsInBackground) {
                    let accountPubkey = self.accountPubkey
                    bg().perform { [weak self] in // contactUsername() needs access to event from bg
                        let name = contactUsername(fromPubkey: nEvent.publicKey, event: event)
                        scheduleDMNotification(name: name, pubkey: accountPubkey)
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    @MainActor
    private func loadDMStates() {
        self.dmStates = CloudDMState.fetchByAccount(self.accountPubkey, context: viewContext())
    }
    
    @MainActor
    public func removeDMState(_ dmState: CloudDMState) {
        self.dmStates.removeAll(where: { $0.conversationId == dmState.conversationId })
        withAnimation {
            self.conversationRows.removeAll(where: { $0.conversationId == dmState.conversationId })
            self.requestRows.removeAll(where: { $0.conversationId == dmState.conversationId })
            self.requestRowsNotWoT.removeAll(where: { $0.conversationId == dmState.conversationId })
        }
        // delete after 6 seconds (maybe messages come in after delay or whatever)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            if dmState.lastMessageTimestamp_ == nil {
                viewContext().delete(dmState)
            }
        }
    }
    
    // add to list if it doesn't already exist
    // when viewing a conversation, probably always a new conversation
    @MainActor
    public func addDMState(_ dmState: CloudDMState) {
        self.objectWillChange.send() // <-- not sure why this is needed. conversationRows/requestRows/requestRowsNotWoT are @Published and DMsVM is @ObservedObject. Should work but doesn't.
        if !self.dmStates.contains(where: { $0.conversationId == dmState.conversationId }) {
            self.dmStates.append(dmState)
        }
        withAnimation { // we are viewing it, so remove from notWoT
            self.requestRowsNotWoT.removeAll(where: { $0.conversationId == dmState.conversationId })
        }
        if dmState.accepted { // if accepted add to conversation list
            if !self.conversationRows.contains(where: { $0.conversationId == dmState.conversationId }) {
                withAnimation {
                    self.conversationRows = sortedDMRows(self.conversationRows + [dmState])
                }
            }
            else { // or only resort
                withAnimation {
                    self.conversationRows = sortedDMRows(self.conversationRows)
                }
            }
        }
        else { // if not accepted add to requests list
            if !self.requestRows.contains(where: { $0.conversationId == dmState.conversationId }) {
                withAnimation {
                    self.requestRows = sortedDMRows(self.requestRows + [dmState])
                }
            }
            else { // or only resort
                withAnimation {
                    self.requestRows = sortedDMRows(self.requestRows)
                }
            }
        }
    }
    
    @MainActor
    public func reload(accountPubkey: String) async {
        self.accountPubkey = accountPubkey
        await self.load(force: true)
    }
    
    @MainActor
    public func markAcceptedAsRead() {
        objectWillChange.send()
        for dmState in conversationRows {
            dmState.markedReadAt_ = Date.now
        }
        self.updateUnreadsCount()
    }
    
    @MainActor
    public func markRequestsAsRead() {
        objectWillChange.send()
        for dmState in requestRows {
            dmState.markedReadAt_ = Date.now
        }
        if showNotWoT {
            for dmState in requestRowsNotWoT {
                dmState.markedReadAt_ = Date.now
            }
        }
        self.updateUnreadsCount()
    }
    
    
    public func reloadConversations() { _reloadConversations.send() }
    private var _reloadConversations = PassthroughSubject<Void, Never>()
    
    public func updateUnreadsCount() { _updateUnreadsCount.send() }
    private var _updateUnreadsCount = PassthroughSubject<Void, Never>()
    
    @MainActor
    public func loadConversations(fullReload: Bool = false) {
        if fullReload {
            self.loadDMStates()
        }
        let blockedPubkeys = blocks()
        
        let accepted = dmStates
            .filter { dmState in
                
                if !dmState.accepted || dmState.isHidden { return false } // only accepted and not hidden
                
                // not blocked (for 1 on 1). In group conversations need to block in the detail view
                if dmState.participantPubkeys.count == 2, let contactPubkey = dmState.participantPubkeys.subtracting([accountPubkey]).first, blockedPubkeys.contains(contactPubkey) {
                    return false
                }
                
                return true
            }
        
        let requests = dmStates
            .filter { dmState in
                if dmState.accepted || dmState.isHidden { return false } // only requests (not accepted), or not hidden
                
                
                if dmState.participantPubkeys.count == 2, let contactPubkey = dmState.participantPubkeys.subtracting([accountPubkey]).first {
                    
                    // not blocked (for 1 on 1). In group conversations need to block in the detail view
                    if blockedPubkeys.contains(contactPubkey) {
                        return false
                    }
                   
                    // only in WoT (if WoT is enabled)
                    if (!WOT_FILTER_ENABLED()) { return true }
                    return WebOfTrust.shared.isAllowed(contactPubkey)
                }
                
                return true
            }
        
        conversationRows = sortedDMRows(accepted)
        requestRows = sortedDMRows(requests)
        
        guard WOT_FILTER_ENABLED() else { return }
        
        let outsideWoT = dmStates
            .filter { dmState in
                if dmState.accepted || dmState.isHidden { return false } // only requests (not accepted), or not hidden
                
                if dmState.participantPubkeys.count == 2, let contactPubkey = dmState.participantPubkeys.subtracting([accountPubkey]).first {
                    // not blocked
                    if blockedPubkeys.contains(contactPubkey) {
                        return false
                    }
                   
                    // only not in WoT
                    return !WebOfTrust.shared.isAllowed(contactPubkey)
                }
                
                return false
            }

        requestRowsNotWoT = sortedDMRows(outsideWoT)
    }
    
    @MainActor
    public func acceptConversation(dmState: CloudDMState) {
        
        dmState.accepted = true
        
        let accepted = conversationRows + [dmState]
        
        let requests = requestRows.filter { $0.id != dmState.id }
        
        self.objectWillChange.send() // <-- not sure why this is needed. conversationRows/requestRows/requestRowsNotWoT are @Published and DMsVM is @ObservedObject. Should work but doesn't.
        
        conversationRows = sortedDMRows(accepted)
        
        requestRows = sortedDMRows(requests)
        
        guard WOT_FILTER_ENABLED() else { return }
        
        let requestsNotWoT = requestRowsNotWoT.filter { $0.id != dmState.id }

        requestRowsNotWoT = sortedDMRows(requestsNotWoT)
    }
    
    public func unhideAll() {
        for dmState in dmStates {
            if dmState.isHidden {
                dmState.isHidden = false
            }
        }
        self.reloadConversations()
    }
    
    @Published var scanningMonthsAgo: Int = 0
    
    public func rescanForMissingDMs(_ monthsAgo: Int) {
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
                        Filters(authors: Set([accountPubkey]), kinds: [4], since: ago.since, until: ago.until),
                        // DMs received
                        Filters(kinds: [4,1059], tagFilter: TagFilter(tag: "p", values: [accountPubkey]), since: ago.since, until: ago.until)
                    ]
                ).json() {
                    req(message)
                }
                
                if i+1 == monthsAgo {
#if DEBUG
                    L.maintenance.info("Running Manual DM fix")
#endif
                    Maintenance.runUpgradeDMs(force: true, context: viewContext(), onlyForAccount: accountPubkey)
                    try? viewContext().save()
                    
                    self.loadConversations(fullReload: true)
                }
            }
        }
    }
    
    private func monthsAgoRange(_ months:Int) -> (since: Int, until: Int) {
        return (
            since: NTimestamp(date: Date().addingTimeInterval(Double(months + 1) * -2_592_000)).timestamp,
            until: NTimestamp(date: Date().addingTimeInterval(Double(months) * -2_592_000)).timestamp
        )
    }
    
    private func setupBadgeNotifications() { // Copy pasta from NotificationsViewModel
        guard self.isMain else { return }
        
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.badge, .provisional]) { [weak self] granted, error in
            guard let self else { return }
            if error == nil {
                // Provisional authorization granted.
                self.objectWillChange
                    .sink { [weak self] _ in
                        guard let self else { return }
                        let notificationsCount = NotificationsViewModel.shared.unread
                        setAppIconBadgeCount((self.unread + self.unreadNewRequestsCount) + notificationsCount, center: center)
                    }
                    .store(in: &self.subscriptions)
                
                let notificationsCount = NotificationsViewModel.shared.unread
                setAppIconBadgeCount((self.unread + self.unreadNewRequestsCount) + notificationsCount)
            }
        }
    }
}
