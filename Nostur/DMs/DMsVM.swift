//
//  DMsVM.swift
//  Nostur
//
//  Created by Fabian Lachman on 09/12/2025.
//

import SwiftUI
import Combine
import NostrEssentials

class DMsVM: ObservableObject {
    
    @Published var ncNotSupported = false
    @Published var ready = false
    
    @Published var tab = "Accepted"
    
    // Short uuid
    let id: String = String(UUID().uuidString.prefix(48))
    
    public var isMain: Bool {
        self.id == Self.shared.id
    }
    
    // Only for main
    private var lastDMLocalNotifcationAt: Int {
        get { UserDefaults.standard.integer(forKey: "last_dm_local_notification_timestamp") }
        set { UserDefaults.standard.setValue(newValue, forKey: "last_dm_local_notification_timestamp") }
    }
    var lastNotificationReceivedAt: Date? = nil
    
    // Shared is for the main / currently logged in account
    static let shared = DMsVM()
    
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
        didSet { self.unread = self.unread_ }
    }
    @Published var requestRows: [CloudDMState] = [] {
        didSet { self.newRequests = self.newRequests_ }
    }
    @Published var requestRowsNotWoT: [CloudDMState] = [] {
        didSet { self.newRequestsNotWoT = self.newRequestsNotWoT_ }
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
    @Published var newRequests: Int = 0
    @Published var newRequestsNotWoT: Int = 0
    
    var unread_: Int {
        conversationRows.reduce(0) { $0 + $1.unread(for: self.accountPubkey) }
    }
    var newRequests_: Int {
        requestRows.reduce(0) { $0 + $1.unread(for: self.accountPubkey) }
    }
    var newRequestsNotWoT_: Int {
        requestRowsNotWoT.count
    }
    
    public func updateUnreads() {
        self.unread = self.unread_
        self.newRequests = self.newRequests_
        self.newRequestsNotWoT = self.newRequestsNotWoT_
    }
    
    public var hiddenDMs: Int {
        dmStates.count { $0.isHidden }
    }
    
    private var subscriptions = Set<AnyCancellable>()
    
    init(accountPubkey: String? = nil) {
        self.accountPubkey = accountPubkey ?? AccountsState.shared.activeAccountPublicKey
        self._reloadConversations
            .debounce(for: 1.5, scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.loadConversations()
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
        self.fetchGiftWraps()
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
    
    private var lastGiftWrapAt = Int(Date().timeIntervalSince1970) - (48 * 60 * 60)  // 48
    
    private var giftWrapsTimer: Timer? = nil
    private func startGiftWrapsTimer() {
        guard giftWrapsTimer == nil else { return }
        self.giftWrapsTimer?.invalidate()
        self.giftWrapsTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.fetchGiftWraps()
        }
        self.giftWrapsTimer?.tolerance = 15.0
    }
    
    public func fetchGiftWraps() {
        let reqFilters = Filters(
            kinds: [1059],
            tagFilter: TagFilter(tag: "p", values: [accountPubkey]),
            since: lastGiftWrapAt,
            limit: 500
        )
        nxReq(
            reqFilters,
            subscriptionId: "-OPEN-59-" + self.id,
            relayType: .READ
        )
    }
    
    private var accountChangedSubscription: AnyCancellable?
    
    private func setupAccountChangedListener() {
        guard isMain && accountChangedSubscription == nil else { return }
        accountChangedSubscription = receiveNotification(.activeAccountChanged)
            .sink { [weak self] notification in
                Task { @MainActor in
                    let account = notification.object as! CloudAccount
                    await self?.reload(accountPubkey: account.publicKey)
                }
            }
    }
    
    public func loadAfterWoT() {
        guard isMain else { return }
        receiveNotification(.WoTReady)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.load()
                }
            }
            .store(in: &self.subscriptions)
    }
    
    private func listenForNewMessages() {
        Importer.shared.importedDMSub // (conversationId: groupId, event: savedEvent, nEvent: nEvent)
            .filter { $0.nEvent.pTags().contains(self.accountPubkey) }
            .sink { (_, event, nEvent, newDMStateCreated) in
                
                if newDMStateCreated {
                    Task { @MainActor in
#if DEBUG
                        L.og.debug("💌💌 DMsVM.loadDMStates() (newDMStateCreated)")
#endif
                        self.loadDMStates()
                    }
                }
                
                Task { @MainActor in
                    self.updateUnreads()
                }
                
                // Only do notifications for logged in account
                guard self.isMain else { return }
                
                guard nEvent.createdAt.timestamp > self.lastDMLocalNotifcationAt else { return }
                
                let followingPubkeys = account(by: self.accountPubkey)?.followingPubkeys ?? []
                
                // Only continue if either limit to follows is not enabled, or if we are following the sender
                guard !SettingsStore.shared.receiveLocalNotificationsLimitToFollows || followingPubkeys.contains(event.pubkey) else { return }
                
                // Only continue if sender is in WoT, or if WoT is disabled
                guard (!WOT_FILTER_ENABLED()) || WebOfTrust.shared.isAllowed(nEvent.publicKey) else {
                    return
                }
        
                // Show notification on Mac: ALWAYS
                // On iOS: Only if app is in background
                if (IS_CATALYST || AppState.shared.appIsInBackground)  {
                    let name = contactUsername(fromPubkey: event.pubkey, event: event)
                    scheduleDMNotification(name: name)
                }
            }
            .store(in: &subscriptions)
    }
    
    @MainActor
    private func loadDMStates() {
        self.dmStates = CloudDMState.fetchByAccount(self.accountPubkey, context: viewContext())
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
        self.unread = self.unread_
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
        self.newRequests = self.newRequests_
        self.newRequestsNotWoT = self.newRequestsNotWoT_
    }
    
    
    public func reloadConversations() { _reloadConversations.send() }
    private var _reloadConversations = PassthroughSubject<Void, Never>()
    
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
        
        conversationRows = accepted
            .sorted(by: { $0.isPinned != $1.isPinned })
        requestRows = requests
            .sorted(by: { $0.isPinned != $1.isPinned })
        
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

        requestRowsNotWoT = outsideWoT
            .sorted(by: { $0.isPinned != $1.isPinned })
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
                    Maintenance.runUpgradeDMs(force: true, context: viewContext())
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
                        setAppIconBadgeCount((self.unread + self.newRequests) + notificationsCount, center: center)
                    }
                    .store(in: &self.subscriptions)
                
                let notificationsCount = NotificationsViewModel.shared.unread
                setAppIconBadgeCount((self.unread + self.newRequests) + notificationsCount)
            }
        }
    }
}
