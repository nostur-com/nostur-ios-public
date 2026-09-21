//
//  WebOfTrust.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/06/2023.
//

// Where should we handle spam?
// Nostur does not have global, so that is not a problem
// Posts are loaded from people you follow, unfollow if they spam
// Replies are shown from all, here we need to stop spam
// Notifications (#p) can be spam
// DM's can have spam (new requests)
// So basically just 3 places to filter

// We can search hashtag, but follow hashtag is not a thing yet so low prio

// PLAN: What do we white list:
// Follows + Follows of follows
// Web of Trust setting: on (follows + follows of follows) or off.

// In the future we could have more data points (badges, nip05, post counts, interactions with followers, etc
// Could also add quality check, don't use follows from people who follow too many people

import SwiftUI
import FileProvider
import Foundation
import Combine

struct WebOfTrustSnapshotStore {
    private let fileManager: FileManager
    private let applicationSupportDirectory: URL
    private let cachesDirectory: URL

    init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.applicationSupportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.cachesDirectory = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    init(fileManager: FileManager = .default, applicationSupportDirectory: URL, cachesDirectory: URL) {
        self.fileManager = fileManager
        self.applicationSupportDirectory = applicationSupportDirectory
        self.cachesDirectory = cachesDirectory
    }

    func snapshotURL(for pubkey: String) throws -> URL {
        let directory = applicationSupportDirectory.appendingPathComponent("Nostur", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("web-of-trust-\(pubkey).bin")
    }

    func legacySnapshotURL(for pubkey: String) -> URL {
        cachesDirectory.appendingPathComponent("web-of-trust-\(pubkey).bin")
    }

    @discardableResult
    func migrateLegacySnapshotIfNeeded(for pubkey: String) throws -> URL {
        let destination = try snapshotURL(for: pubkey)
        guard !fileManager.fileExists(atPath: destination.path) else { return destination }

        let legacy = legacySnapshotURL(for: pubkey)
        guard fileManager.fileExists(atPath: legacy.path) else { return destination }
        try fileManager.moveItem(at: legacy, to: destination)
        return destination
    }

    func containsSnapshot(for pubkey: String) -> Bool {
        guard let url = try? migrateLegacySnapshotIfNeeded(for: pubkey) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    func read(for pubkey: String) throws -> Set<String> {
        let url = try migrateLegacySnapshotIfNeeded(for: pubkey)
        let data = try Data(contentsOf: url)
        guard let values = try NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [NSArray.self, NSString.self],
            from: data
        ) as? [String] else {
            throw CocoaError(.coderReadCorrupt)
        }
        return Set(values)
    }

    func write(_ pubkeys: Set<String>, for pubkey: String) throws {
        let url = try snapshotURL(for: pubkey)
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: Array(pubkeys),
            requiringSecureCoding: false
        )
        try data.write(to: url, options: .atomic)
    }

    func modificationDate(for pubkey: String) throws -> Date {
        let url = try migrateLegacySnapshotIfNeeded(for: pubkey)
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let date = attributes[.modificationDate] as? Date else {
            throw CocoaError(.fileReadUnknown)
        }
        return date
    }

    func removeSnapshot(for pubkey: String) throws {
        let urls = [try snapshotURL(for: pubkey), legacySnapshotURL(for: pubkey)]
        for url in urls where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}

class WebOfTrust: ObservableObject {
    
    static let shared = WebOfTrust()
 
    private let ENABLE_THRESHOLD = 2000 // To not degrade onboarding/new user experience, we should have more contacts in WoT than this threshold before the filter is active
    private let snapshotStore = try? WebOfTrustSnapshotStore()
    private let rebuildStateLock = NSLock()
    private var needsDeferredRebuild = false
    private var maintenanceRebuildActive = false
    private var maintenanceBatches: [[String]] = []
    private var maintenanceCompleted = 0
    private var maintenanceTotal = 0
    private var maintenanceRelays: Set<RelayData> = []
    private var deferredRebuildTask: Task<Void, Never>?

    private struct FilteringSnapshot {
        var mainPubkey = ""
        var followingPubkeys: Set<String> = []
        var followingFollowingPubkeys: Set<String> = []
        var learnedPubkeys: Set<String> = []
        var isLoaded = false
        // Computing three large Set unions in isAllowed() made every feed row
        // pay O(total WoT size) before its O(1) membership checks.
        var allowedKeysCount = 0
    }

    private let filteringSnapshotLock = NSLock()
    private var filteringSnapshot = FilteringSnapshot()
    
    public var tresholdReached: Bool {
        allowedKeysCount >= ENABLE_THRESHOLD
    }
    
    @AppStorage("wotDunbarNumber") private var wotDunbarNumber: Int = 1000
    
    // UserDefaults can be slow and its called every .isAllowed() so cache the value in .mainAccountWoTpubkey
    @AppStorage("main_wot_account_pubkey") private var _mainAccountWoTpubkey = "" {
        didSet {
            mainAccountWoTpubkey = _mainAccountWoTpubkey
        }
    }
    
    // cached
    private var mainAccountWoTpubkey: String = ""
    
    // For views
    @Published public var lastUpdated: Date? = nil
    
    @Published public var allowedKeysCount: Int = 0
    
    @Published public var updatingWoT = false

    @Published public private(set) var rebuildQueued = false

    @Published public private(set) var rebuildProgress: (completed: Int, total: Int)?
    
    // Only accessed from bg thread
    // Keep separate lists for faster filtering
    
    // follows of follows
    private var followingFollowingPubkeys: Set<String> = [] {
        didSet {
            self.updateViewData()
        }
    }
    
    // Only follows
    private var followingPubkeys: Set<String> = [] {
        didSet {
            self.updateViewData()
        }
    }

    public func updateViewData(localSnapshotLoaded: Bool = false) {
        let learnedPubkeys = LearnedWoTStore.shared.currentPubkeys()
        filteringSnapshotLock.lock()
        if filteringSnapshot.mainPubkey != mainAccountWoTpubkey {
            filteringSnapshot = FilteringSnapshot(mainPubkey: mainAccountWoTpubkey)
        }
        filteringSnapshot.followingPubkeys = followingPubkeys
        filteringSnapshot.followingFollowingPubkeys = followingFollowingPubkeys
        filteringSnapshot.learnedPubkeys = learnedPubkeys
        filteringSnapshot.isLoaded = filteringSnapshot.isLoaded || localSnapshotLoaded
        filteringSnapshot.allowedKeysCount = followingPubkeys
            .union(followingFollowingPubkeys)
            .union(learnedPubkeys)
            .count
        let allowedKeysCount = filteringSnapshot.allowedKeysCount
        filteringSnapshotLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.allowedKeysCount = self.mainAccountWoTpubkey == "" || SettingsStore.shared.webOfTrustLevel == SettingsStore.WebOfTrustLevel.off.rawValue ? 0 : allowedKeysCount
        }
    }
    
    public var theWoTisReady = false
    
    private func woTisReady() {
        theWoTisReady = true
        sendNotification(.WoTReady)
    }
    
    private var backlog = Backlog(timeout: 60, auto: true, backlogDebugName: "WebOfTrust")
    private var subscriptions = Set<AnyCancellable>()
    
    private init() {
        mainAccountWoTpubkey = UserDefaults.standard.string(forKey: SettingsStore.Keys.mainWoTaccountPubkey) ?? ""
        if _mainAccountWoTpubkey == "" {
            DispatchQueue.main.async { [weak self] in
                self?.guessMainAccount()
            }
        }
        updateWoTonNewFollowing()
        LearnedWoTStore.shared.$entries
            .dropFirst()
            .sink { [weak self] _ in
                self?.updateViewData()
            }
            .store(in: &subscriptions)
    }

    /// Installs the persisted WoT before feed views and relay subscriptions start.
    /// A network refresh can happen later; filtering uses this local snapshot immediately.
    public func loadLocalSnapshotAtStartup() async {
        guard SettingsStore.shared.webOfTrustLevel != SettingsStore.WebOfTrustLevel.off.rawValue else {
            updateViewData(localSnapshotLoaded: true)
            return
        }

        let startupData: (mainPubkey: String, followingPubkeys: Set<String>, ownFollowingPubkeys: Set<String>)? = await MainActor.run {
            if self.mainAccountWoTpubkey.isEmpty {
                self.guessMainAccount()
            }

            let mainPubkey = self.mainAccountWoTpubkey
            guard !mainPubkey.isEmpty else { return nil }

            let accounts = AccountsState.shared.accounts.isEmpty
                ? CloudAccount.fetchAccounts(context: context())
                : AccountsState.shared.accounts
            guard let mainAccount = accounts.first(where: { $0.publicKey == mainPubkey }) else { return nil }

            let followingPubkeys = mainAccount.getFollowingPublicKeys(includeBlocked: true)
            let activeAccountPubkey = AccountsState.shared.activeAccountPublicKey.isEmpty
                ? UserDefaults.standard.string(forKey: "activeAccountPublicKey") ?? ""
                : AccountsState.shared.activeAccountPublicKey
            let ownFollowingPubkeys = accounts
                .first(where: { $0.publicKey == activeAccountPubkey && $0.publicKey != mainPubkey })?
                .followingPubkeys ?? []
            return (mainPubkey, followingPubkeys, ownFollowingPubkeys)
        }

        guard let startupData else { return }

        let startupSnapshot = await bg().perform {
            self.followingPubkeys = startupData.followingPubkeys.union(startupData.ownFollowingPubkeys)
            self.followingFollowingPubkeys = self.loadData(startupData.mainPubkey)
            // Check after loading so legacy .txt migration and corrupt-snapshot
            // removal are reflected in the rebuild decision.
            let hadPersistedSnapshot = self.snapshotStore?.containsSnapshot(for: startupData.mainPubkey) == true
            self.updateViewData(localSnapshotLoaded: true)
            self.filteringSnapshotLock.lock()
            let count = self.filteringSnapshot.allowedKeysCount
            self.filteringSnapshotLock.unlock()
            return (allowedKeysCount: count, hadPersistedSnapshot: hadPersistedSnapshot)
        }

        await MainActor.run {
            // Set this synchronously before startNosturing continues. The @Published
            // value remains view state, while filtering reads the locked snapshot.
            self.allowedKeysCount = startupSnapshot.allowedKeysCount
            if !startupSnapshot.hadPersistedSnapshot {
                self.rebuildStateLock.lock()
                self.needsDeferredRebuild = true
                self.rebuildStateLock.unlock()
                self.rebuildQueued = true
            }
            self.woTisReady()
        }
    }

    /// A missing snapshot is repaired after the first feed and notification work has
    /// had time to enter the network/import pipeline. This task never blocks startup.
    public func scheduleDeferredRebuildIfNeeded() {
        rebuildStateLock.lock()
        let shouldSchedule = needsDeferredRebuild && deferredRebuildTask == nil
        rebuildStateLock.unlock()
        guard shouldSchedule else { return }

        let task = Task(priority: .utility) { [weak self] in
            // Let the first visible feed and notification requests win the initial
            // connection/import burst after a restore.
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled else { return }

            // Require a short quiet window. If interactive imports resume, the
            // maintenance rebuild remains queued instead of competing with them.
            var quietChecks = 0
            while !Task.isCancelled && quietChecks < 2 {
                if Importer.shared.hasPendingImportPasses {
                    quietChecks = 0
                }
                else {
                    quietChecks += 1
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.loadWoT(force: true)
            }
        }

        rebuildStateLock.lock()
        deferredRebuildTask = task
        rebuildStateLock.unlock()
    }
    
    // For first time guessing the main account, user can change actual main account in Settings
    public func guessMainAccount() {
        guard _mainAccountWoTpubkey == "" else { return }
        // in preferred order:
        // 1. full account with most follows, and >50 follows
        // 2. read-only account currently logged and >50 follows

        // this ignores full accounts that are test accounts
        // and it ignores "login as someone else" accounts
        
        // so the main account is likely the currently logged in read-only account at start OR
        // any full-account with more than 50 follows, so we know its probably not a test throwaway account
        
        // never use the built-in guest account
        
        if let fullAccount = AccountsState.shared.accounts
            .filter({ $0.isFullAccount && $0.followingPubkeys.count > 50 && $0.publicKey != GUEST_ACCOUNT_PUBKEY }) // only full accounts with 50+ follows (exclude guest account)
            .sorted(by: { $0.followingPubkeys.count > $1.followingPubkeys.count }).first // sorted to get the one with the most follows
        {
#if DEBUG
            L.og.info("🕸️🕸️ WebOfTrust: Main WoT full account guessed: \(fullAccount.publicKey)")
#endif
            _mainAccountWoTpubkey = fullAccount.publicKey
        }
        // the currently logged in read only account, if it has 50+ follows but not if its the guest account
        else if let readOnlyAccount = AccountsState.shared.accounts
            .first(where: { $0.publicKey == AccountsState.shared.activeAccountPublicKey && $0.followingPubkeys.count > 50 && $0.publicKey != GUEST_ACCOUNT_PUBKEY })
        {
#if DEBUG
            L.og.info("🕸️🕸️ WebOfTrust: Main WoT read account guessed: \(readOnlyAccount.publicKey)")
#endif
            _mainAccountWoTpubkey = readOnlyAccount.publicKey
        }
    }
    
    public func loadWoT(force: Bool = false, mainWoTpubkey: String? = nil) {
        if let mainWoTpubkey {
            _mainAccountWoTpubkey = mainWoTpubkey
        }
        guard mainAccountWoTpubkey != "" else {
            self.woTisReady()
            return
        }
        guard SettingsStore.shared.webOfTrustLevel != SettingsStore.WebOfTrustLevel.off.rawValue else {
            self.woTisReady()
            return
        }
        guard let account = AccountsState.shared.accounts.first(where: { $0.publicKey == mainAccountWoTpubkey }) ?? (try? CloudAccount.fetchAccount(publicKey: mainAccountWoTpubkey, context: context())) else {
            self.woTisReady()
            return
        }
#if DEBUG
        L.og.info("🕸️🕸️ WebOfTrust: Main account: \(account.anyName)")
#endif
        
        let wotFollowingPubkeys = account.getFollowingPublicKeys(includeBlocked: true).subtracting(account.privateFollowingPubkeys) // We don't include silent follows in WoT
        let followingPubkeys = account.getFollowingPublicKeys(includeBlocked: true)
        
        bg().perform { [weak self] in
            guard let self else { return }
            self.followingPubkeys = followingPubkeys
            guard wotFollowingPubkeys.count > 10 else {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.woTisReady()
                    self.updatingWoT = false
                }
#if DEBUG
                L.og.info("🕸️🕸️ WebOfTrust: Not enough follows to build WoT. Maybe still onboarding and contact list not received yet")
#endif
                return
            }
            
            if SettingsStore.shared.webOfTrustLevel == SettingsStore.WebOfTrustLevel.off.rawValue {
#if DEBUG
                L.og.info("🕸️🕸️ WebOfTrust: Disabled")
#endif
                self.woTisReady()
                self.updatingWoT = false
            }
            else {
#if DEBUG
                L.og.info("🕸️🕸️ WebOfTrust: On")
#endif
                bg().perform { [weak self] in
                    self?.loadNormal(wotFollowingPubkeys: wotFollowingPubkeys, force: force)
                }
            }
        }
    }
    
    // If currently logged in account is not main WoT account
    // Also add our of follows to the main WoT.
    // BUT only after main WoT is loaded! so follows + follows-of-follows, and then add own follows
    // SO NOT: follows + add own follows, and then follows-of-follows
    // Order matters.
    private func addOwnFollowsIfNeeded() {
        guard let account = Nostur.account() else { return }
        guard mainAccountWoTpubkey != account.publicKey else { return }
        let ownFollows = account.followingPubkeys
        self.followingPubkeys = self.followingPubkeys.union(ownFollows)
    }
    
    private func updateWoTonNewFollowing() {
        receiveNotification(.followingAdded)
            .debounce(for: .seconds(8.0), scheduler: RunLoop.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                guard SettingsStore.shared.webOfTrustLevel != SettingsStore.WebOfTrustLevel.off.rawValue else { return }

                self.loadWoT(force: true)
            }
            .store(in: &subscriptions)
    }
    
    private func updateWoTwithFollowsOf(_ pubkey: String) {
        // Fetch kind 3 for pubkey
        let task = ReqTask(
            subscriptionId: "RM.getAuthorContactsList",
            reqCommand: { taskId in
#if DEBUG
                L.sockets.debug("🕸️🕸️ WebOfTrust/WoTFol: updateWoTwithFollowsOf - Fetching contact list for \(pubkey)")
#endif
                req(RM.getAuthorContactsList(pubkey: pubkey, subscriptionId: taskId))
            },
            processResponseCommand: { [weak self] taskId, _, _ in
#if DEBUG
                L.sockets.debug("🕸️🕸️ WebOfTrust/WoTFol: updateWoTwithFollowsOf - Received contact list")
#endif
                self?.regenerateWoTWithFollowsOf(pubkey)
            },
            timeoutCommand: { [weak self] _ in
#if DEBUG
                L.sockets.debug("🕸️🕸️ WebOfTrust/WoTFol: updateWoTwithFollowsOf - Time-out")
#endif
                self?.regenerateWoTWithFollowsOf(pubkey)
            })

        backlog.add(task)
        task.fetch()
    }
    
    private func regenerateWoTWithFollowsOf(_ otherPubkey: String) {
        guard mainAccountWoTpubkey != "" else { return }
        var followsOfPubkey = Set<String>()
        bg().perform { [weak self] in
            guard let self = self else { return }
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "kind == 3 AND pubkey == %@", otherPubkey)
            fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: true)]
            if let list = try? bg().fetch(fr).first {
                followsOfPubkey = followsOfPubkey.union( Set(list.fastPs.map { $0.1 }) )
            }
            if wotDunbarNumber == 0 || followsOfPubkey.count <= wotDunbarNumber {
                self.followingFollowingPubkeys = self.followingFollowingPubkeys.union(followsOfPubkey)
#if DEBUG
                L.sockets.debug("🕸️🕸️ WebOfTrust/WoTFol: allowList now has \(self.followingPubkeys.count) + \(self.followingFollowingPubkeys.count) pubkeys")
#endif
                self.storeData(pubkeys: self.followingFollowingPubkeys, pubkey: mainAccountWoTpubkey)
            }
        }
    }
    
    public var webOfTrustLevel: String = SettingsStore.WebOfTrustLevel.normalized(UserDefaults.standard.string(forKey: SettingsStore.Keys.webOfTrustLevel)) // Faster then querying UserDefaults so cache here
    
    public func isAllowed(_ pubkey: String) -> Bool {
        guard mainAccountWoTpubkey != "" else { return true }
        guard webOfTrustLevel != SettingsStore.WebOfTrustLevel.off.rawValue else { return true }

        filteringSnapshotLock.lock()
        let snapshot = filteringSnapshot
        filteringSnapshotLock.unlock()

        // WoT-enabled feeds must not fail open while the persisted snapshot is loading.
        guard snapshot.isLoaded else { return false }
        if snapshot.allowedKeysCount < ENABLE_THRESHOLD { return true }

        if snapshot.followingPubkeys.contains(pubkey) { return true }
        if snapshot.learnedPubkeys.contains(pubkey) { return true }
        if snapshot.followingFollowingPubkeys.contains(pubkey) { return true }
        
        // Also allow outgoing DM conv pubkeys we initiated
        if DMsVM.shared.isAllowedByWoT(pubkey) {
            return true
        }
        
        return false
    }

    public func allowedPubkeysSnapshot() -> Set<String> {
        guard webOfTrustLevel != SettingsStore.WebOfTrustLevel.off.rawValue else { return [] }
        filteringSnapshotLock.lock()
        let snapshot = filteringSnapshot
        filteringSnapshotLock.unlock()
        return snapshot.followingPubkeys.union(snapshot.followingFollowingPubkeys)
    }
    
    // Load follows + follows of follows
    public func loadNormal(wotFollowingPubkeys: Set<String>, force: Bool = false) { // force = true to force fetching (update)
        guard mainAccountWoTpubkey != "" else {
            self.woTisReady()
            return
        }
        self.loadFollowingFollowing(wotFollowingPubkeys:wotFollowingPubkeys, force: force)
        if let lastUpdated = lastUpdatedDate(mainAccountWoTpubkey) {
#if DEBUG
            L.og.debug("🕸️🕸️ WebOfTrust/WoTFol: lastUpdatedDate: web-of-trust-\(self.mainAccountWoTpubkey).bin --> \(lastUpdated.description)")
#endif
            DispatchQueue.main.async { [weak self] in
                self?.lastUpdated = lastUpdated
            }
        }
    }
    
    // force = true to force fetching (update) - else will only use what is already on disk
    private func loadFollowingFollowing(wotFollowingPubkeys: Set<String>, force: Bool = false) {
        guard mainAccountWoTpubkey != "" else {
            self.woTisReady()
            return
        }
        // Load from disk
        self.followingFollowingPubkeys = self.loadData(mainAccountWoTpubkey)
        self.addOwnFollowsIfNeeded()
        self.updateViewData(localSnapshotLoaded: true)

        var pubkeys = wotFollowingPubkeys
        pubkeys.remove(mainAccountWoTpubkey)
        
        guard self.followingFollowingPubkeys.count < ENABLE_THRESHOLD || force == true else {
            self.woTisReady()
#if DEBUG
            L.sockets.debug("🕸️🕸️ WebOfTrust/WoTFol: already have loaded enough from file")
#endif
            return
        }
        
        guard !theWoTisReady || force == true else {
            self.woTisReady()
#if DEBUG
            L.sockets.debug("🕸️🕸️ WebOfTrust/WoTFol: already didWot")
#endif
            return
        }
        self.woTisReady()
        self.startMaintenanceRebuild(pubkeys: pubkeys)
    }

    /// Fetches contact lists in small batches. Each batch waits for interactive
    /// importer work to drain, so a restore cannot monopolize feeds or notifications.
    private func startMaintenanceRebuild(pubkeys: Set<String>) {
        rebuildStateLock.lock()
        guard !maintenanceRebuildActive else {
            rebuildStateLock.unlock()
            return
        }
        maintenanceRebuildActive = true
        needsDeferredRebuild = false
        deferredRebuildTask = nil
        maintenanceCompleted = 0
        maintenanceTotal = pubkeys.count
        let sorted = pubkeys.sorted()
        maintenanceBatches = stride(from: 0, to: sorted.count, by: 20).map { start in
            return Array(sorted[start..<min(start + 20, sorted.count)])
        }
        maintenanceRelays = ConnectionPool.shared.connectedReadRelaysForMaintenance(limit: 2)
        let hasRelays = !maintenanceRelays.isEmpty
        rebuildStateLock.unlock()

        guard hasRelays else {
            rebuildStateLock.lock()
            maintenanceRebuildActive = false
            needsDeferredRebuild = true
            deferredRebuildTask = nil
            rebuildStateLock.unlock()
            DispatchQueue.main.async { [weak self] in
                self?.rebuildQueued = true
                self?.updatingWoT = false
            }
            scheduleDeferredRebuildIfNeeded()
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.rebuildQueued = false
            self?.updatingWoT = true
            self?.rebuildProgress = (0, pubkeys.count)
        }

        // Restored Core Data usually already contains many kind-3 events. Rebuild
        // from those first so the usable snapshot returns before network refreshes.
        generateWoT(markUpdateFinished: false, persistSnapshot: false) { [weak self] in
            self?.fetchNextMaintenanceBatchWhenIdle()
        }
    }

    private func fetchNextMaintenanceBatchWhenIdle() {
        if Importer.shared.hasPendingImportPasses {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) { [weak self] in
                bg().perform {
                    self?.fetchNextMaintenanceBatchWhenIdle()
                }
            }
            return
        }

        rebuildStateLock.lock()
        guard maintenanceRebuildActive else {
            rebuildStateLock.unlock()
            return
        }
        guard !maintenanceBatches.isEmpty else {
            rebuildStateLock.unlock()
            finishMaintenanceRebuild()
            return
        }
        let batch = maintenanceBatches.removeFirst()
        let relays = maintenanceRelays
        rebuildStateLock.unlock()

        let task = ReqTask(
            debounceTime: 2.0,
            timeout: 15.0,
            prefix: "WoTFol-M-",
            reqCommand: { taskId in
#if DEBUG
                L.sockets.debug("🕸️🕸️ WebOfTrust/WoTFol: Maintenance batch for \(batch.count) contacts")
#endif
                req(
                    RM.getAuthorContactsLists(pubkeys: batch, limit: batch.count, subscriptionId: taskId),
                    relays: relays
                )
            },
            processResponseCommand: { [weak self] _, _, _ in
                self?.maintenanceBatchFinished(batch.count)
            },
            timeoutCommand: { [weak self] _ in
                self?.maintenanceBatchFinished(batch.count)
            }
        )
        backlog.add(task)
        task.fetch()
    }

    private func maintenanceBatchFinished(_ count: Int) {
        rebuildStateLock.lock()
        maintenanceCompleted += count
        let progress = (completed: maintenanceCompleted, total: maintenanceTotal)
        rebuildStateLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.rebuildProgress = progress
        }
        fetchNextMaintenanceBatchWhenIdle()
    }

    private func finishMaintenanceRebuild() {
        generateWoT(markUpdateFinished: true) { [weak self] in
            guard let self else { return }
            self.rebuildStateLock.lock()
            self.maintenanceRebuildActive = false
            self.maintenanceBatches.removeAll()
            self.maintenanceRelays.removeAll()
            self.rebuildStateLock.unlock()
            DispatchQueue.main.async {
                self.rebuildQueued = false
                self.rebuildProgress = nil
            }
        }
    }
    
    public func localReload(wotFollowingPubkeys: Set<String>) {
        guard mainAccountWoTpubkey != "" else {
            self.woTisReady()
            return
        }
        // Load from disk
        self.followingFollowingPubkeys = self.loadData(mainAccountWoTpubkey)

        var pubkeys = wotFollowingPubkeys
        pubkeys.remove(mainAccountWoTpubkey)

        generateWoT()
    }
    
    private func generateWoT(
        markUpdateFinished: Bool = true,
        persistSnapshot: Bool = true,
        completion: (() -> Void)? = nil
    ) {
        guard mainAccountWoTpubkey != "" else {
            self.woTisReady()
            if markUpdateFinished {
                updatingWoT = false
            }
            completion?()
            return
        }
        bg().perform { [weak self] in
            guard let self = self else { return }
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "kind == 3 AND pubkey IN %@", followingPubkeys)
            var followFollows = Set<String>()
            if let contactLists = try? bg().fetch(fr) {
                for list in contactLists {
                    let pubkeys = Set(list.fastPs.map { $0.1 })
                    if wotDunbarNumber == 0 || pubkeys.count <= wotDunbarNumber {
                        followFollows = followFollows.union(pubkeys)
                    }
                }
            }
            self.followingFollowingPubkeys = followFollows
            self.addOwnFollowsIfNeeded()
#if DEBUG
            L.sockets.debug("🕸️🕸️ WebOfTrust/WoTFol: allowList now has \(self.followingPubkeys.count) + \(self.followingFollowingPubkeys.count) pubkeys")
#endif
            if persistSnapshot {
                self.storeData(pubkeys: self.followingFollowingPubkeys, pubkey: mainAccountWoTpubkey)
            }
            completion?()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.woTisReady()
                if markUpdateFinished {
                    self.updatingWoT = false
                }
            }
        }
    }
    
    private func storeData(pubkeys: Set<String>, pubkey: String) {
        do {
            guard let snapshotStore else { return }
            try snapshotStore.write(pubkeys, for: pubkey)

            if let lastUpdated = lastUpdatedDate(pubkey) {
#if DEBUG
                L.og.info("🕸️🕸️ WebOfTrust/WoTFol: lastUpdatedDate: web-of-trust-\(pubkey).bin --> \(lastUpdated.description)")
#endif
                DispatchQueue.main.async { [weak self] in
                    self?.lastUpdated = lastUpdated
                }
            }
        }
        catch {
#if DEBUG
            L.og.error("🕸️🕸️ WebOfTrust/WoTFol: Failed to write file: web-of-trust-\(pubkey).bin: \(error)")
#endif
        }
    }
    
    // Get data from documents directory
    private func loadData(_ pubkey: String) -> Set<String> {
        do {
            migrateDataIfNeeded(pubkey)
            guard let snapshotStore else { return [] }
            let pubkeys = try snapshotStore.read(for: pubkey)
            if pubkeys.count < 2 {
                // Something wrong, delete corrupt file
                try snapshotStore.removeSnapshot(for: pubkey)
#if DEBUG
                L.og.error("🕸️🕸️ WebOfTrust/WoTFol: Something wrong, deleting corrupt snapshot")
#endif
                return []
            }
            return pubkeys
        }
        catch {
#if DEBUG
            L.og.error("🕸️🕸️ WebOfTrust/WoTFol: Failed to read file: web-of-trust-\(pubkey).bin: \(error)")
#endif
            return Set<String>()
        }
    }
    
    private func migrateDataIfNeeded(_ pubkey: String) {
        let fileManager = FileManager.default
        let cachesDirectory = try! fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let txtFilename = cachesDirectory.appendingPathComponent("web-of-trust-\(pubkey).txt")
        
        if fileManager.fileExists(atPath: txtFilename.path) {
            // Migrate from .txt to .bin
            do {
                let input = try String(contentsOf: txtFilename)
                let pubkeys = Set(input.split(separator: "\n").map { String($0) })
                storeData(pubkeys: pubkeys, pubkey: pubkey)
                try fileManager.removeItem(at: txtFilename)
#if DEBUG
                L.og.info("🕸️🕸️ WebOfTrust/WoTFol: Successfully migrated data from .txt to .bin for pubkey: \(pubkey)")
#endif
            } catch {
#if DEBUG
                L.og.error("🕸️🕸️ WebOfTrust/WoTFol: Migration failed for pubkey: \(pubkey): \(error)")
#endif
            }
        }
    }
    
    public func loadLastUpdatedDate() {
        guard mainAccountWoTpubkey != "" else { return }
        if let date = self.lastUpdatedDate(mainAccountWoTpubkey) {
            DispatchQueue.main.async { [weak self] in
                self?.lastUpdated = date
            }
        }
    }
    
    private func lastUpdatedDate(_ pubkey: String) -> Date? {
        do {
            guard let snapshotStore else { return nil }
            return try snapshotStore.modificationDate(for: pubkey)
        }
        catch {
#if DEBUG
            L.og.debug("🕸️🕸️ WebOfTrust/WoTFol: lastUpdatedDate? doesn't exist yet: web-of-trust-\(pubkey).bin")
#endif
            return nil
        }
    }
}

func WOT_FILTER_ENABLED() -> Bool {
#if DEBUG
    if NSClassFromString("XCTestCase") != nil { return false }
    if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
        return false
    }
#endif
    return WebOfTrust.shared.webOfTrustLevel != SettingsStore.WebOfTrustLevel.off.rawValue
}

extension NEvent {
    var inWoT: Bool { // Similar as in Event
        if kind == .zapNote, let zapReq = Event.extractZapRequest(tags: self.tags) {
            return WebOfTrust.shared.isAllowed(zapReq.publicKey)
        }
        return WebOfTrust.shared.isAllowed(publicKey)
    }
}
