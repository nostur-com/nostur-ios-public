import Foundation
import UIKit
import BackgroundTasks
import Network

struct WoTRefreshContactList: Codable {
    let createdAt: Int
    let follows: Set<String>
}

/// A completed batch is durable; failed or interrupted batches stay pending.
struct WoTRefreshCheckpoint: Codable {
    let account: String
    let authors: Set<String>
    let dunbarNumber: Int
    var pending: Set<String>
    var lists: [String: WoTRefreshContactList]

    mutating func merge(_ incoming: [String: WoTRefreshContactList]) {
        for (author, list) in incoming where lists[author].map({ $0.createdAt < list.createdAt }) ?? true {
            lists[author] = list
        }
    }

    var allowed: Set<String> {
        authors.reduce(into: Set<String>()) { result, author in
            guard let list = lists[author], dunbarNumber == 0 || list.follows.count <= dunbarNumber else { return }
            result.formUnion(list.follows)
        }
    }
}

enum WoTBackgroundRefresh {
    static let identifier = "com.nostur.wot-refresh"
    static func successKey(_ account: String) -> String { "wot_auto_refresh_success_\(account)" }
    static func pendingKey(_ account: String) -> String { "wot_auto_refresh_pending_\(account)" }

    /// Utility/background-context callers only: newest signed lists remain
    /// available to local rebuilds even though maintenance bypasses the importer.
    static func completedLists(account: String) -> [String: WoTRefreshContactList] {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let data = try? Data(contentsOf: directory.appendingPathComponent("Nostur/wot-follow-lists-\(account).json")),
              let saved = try? JSONDecoder().decode(WoTRefreshCheckpoint.self, from: data),
              saved.account == account, saved.pending.isEmpty else { return [:] }
        return saved.lists
    }

    @MainActor
    static func schedule() {
        guard !IS_CATALYST,
              SettingsStore.shared.webOfTrustLevel != SettingsStore.WebOfTrustLevel.off.rawValue,
              let account = UserDefaults.standard.string(forKey: SettingsStore.Keys.mainWoTaccountPubkey),
              !account.isEmpty else { return }
        let lastSuccess = UserDefaults.standard.double(forKey: successKey(account))
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = Date(timeIntervalSince1970: max(Date().timeIntervalSince1970, lastSuccess + 86_400))
        do { try BGTaskScheduler.shared.submit(request) }
        catch { L.maintenance.error("Could not schedule WoT refresh: \(error.localizedDescription)") }
    }

    @MainActor
    static func run() async -> Bool {
        guard SettingsStore.shared.webOfTrustLevel != SettingsStore.WebOfTrustLevel.off.rawValue,
              let pubkey = UserDefaults.standard.string(forKey: SettingsStore.Keys.mainWoTaccountPubkey),
              let account = try? CloudAccount.fetchAccount(publicKey: pubkey, context: viewContext()) else { return true }
        let lastSuccess = UserDefaults.standard.double(forKey: successKey(pubkey))
        guard Date().timeIntervalSince1970 - lastSuccess >= 86_400 else { return true }
        let authors = account.getFollowingPublicKeys(includeBlocked: true).subtracting(account.privateFollowingPubkeys).subtracting([pubkey])
        guard authors.count > 10 else { return true }
        let dunbar = UserDefaults.standard.object(forKey: "wotDunbarNumber") as? Int ?? 1000
        let relays = Set(CloudRelay.fetchAll(context: viewContext()).map { $0.toStruct() }
            .filter { $0.read && !$0.excludedPubkeys.contains(pubkey) }.sorted { $0.url < $1.url }.prefix(2))
        guard !relays.isEmpty else { return false }
        // No synchronous network/Core Data waits in this UI-facing entry point.
        let work = Task.detached(priority: .utility) {
            await refresh(account: pubkey, authors: authors, dunbar: dunbar, relays: relays)
        }
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }

    private static func refresh(account: String, authors: Set<String>, dunbar: Int, relays: Set<RelayData>) async -> Bool {
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Nostur", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("wot-refresh-\(account).json")
            var checkpoint: WoTRefreshCheckpoint
            if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(WoTRefreshCheckpoint.self, from: data),
               saved.account == account, saved.authors == authors, saved.dunbarNumber == dunbar {
                checkpoint = saved
            } else {
                let context = DataProvider.shared().newTaskContext()
                let lists = try await context.perform {
                    let request = Event.fetchRequest()
                    request.predicate = NSPredicate(format: "kind == 3 AND pubkey IN %@", authors)
                    var lists: [String: WoTRefreshContactList] = [:]
                    for event in try context.fetch(request) {
                        let list = WoTRefreshContactList(createdAt: Int(event.created_at), follows: Set(event.fastPs.map { $0.1 }))
                        if lists[event.pubkey].map({ $0.createdAt < list.createdAt }) ?? true { lists[event.pubkey] = list }
                    }
                    return lists
                }
                checkpoint = WoTRefreshCheckpoint(account: account, authors: authors, dunbarNumber: dunbar, pending: authors, lists: lists)
                checkpoint.merge(completedLists(account: account).filter { authors.contains($0.key) })
            }
            try JSONEncoder().encode(checkpoint).write(to: url, options: .atomic)
            UserDefaults.standard.set(checkpoint.pending.count, forKey: pendingKey(account))
            let monitor = NWPathMonitor()
            monitor.start(queue: DispatchQueue(label: "com.nostur.wot.network", qos: .utility))
            defer { monitor.cancel() }
            try await Task.sleep(nanoseconds: 500_000_000)
            guard monitor.currentPath.status == .satisfied, !monitor.currentPath.isExpensive, !monitor.currentPath.isConstrained else { return false }
            await ConnectionPool.shared.connectFeedRelays(relays: relays)
            defer {
                Task { @MainActor in
                    if UIApplication.shared.applicationState == .background {
                        for relay in relays { ConnectionPool.shared.disconnectRelay(relay.id) }
                    }
                }
            }
            guard await ConnectionPool.shared.waitForAnyConnectedRelay(in: relays) else { return false }
            while !checkpoint.pending.isEmpty {
                try Task.checkCancellation()
                let canContinue = await MainActor.run {
                    UIApplication.shared.applicationState == .background &&
                    SettingsStore.shared.webOfTrustLevel != SettingsStore.WebOfTrustLevel.off.rawValue &&
                    UserDefaults.standard.string(forKey: SettingsStore.Keys.mainWoTaccountPubkey) == account
                }
                guard canContinue, monitor.currentPath.status == .satisfied,
                      !monitor.currentPath.isExpensive, !monitor.currentPath.isConstrained else { return false }
                let batch = Array(checkpoint.pending.sorted().prefix(20))
                var completed = false
                // Query at most two relays. A batch needs EOSE from at least one;
                // CLOSED, timeout, invalid signatures and oversized responses fail.
                for relay in relays.sorted(by: { $0.url < $1.url }) {
                    try Task.checkCancellation()
                    if let lists = try? await WoTRefreshRelayInbox.shared.fetch(authors: Set(batch), relay: relay, account: account) {
                        checkpoint.merge(lists)
                        completed = true
                    }
                }
                guard completed else { return false }
                checkpoint.pending.subtract(batch)
                try JSONEncoder().encode(checkpoint).write(to: url, options: .atomic)
                UserDefaults.standard.set(checkpoint.pending.count, forKey: pendingKey(account))
            }
            try Task.checkCancellation()
            let stillValid = await MainActor.run {
                guard UIApplication.shared.applicationState == .background,
                      SettingsStore.shared.webOfTrustLevel != SettingsStore.WebOfTrustLevel.off.rawValue,
                      UserDefaults.standard.string(forKey: SettingsStore.Keys.mainWoTaccountPubkey) == account,
                      (UserDefaults.standard.object(forKey: "wotDunbarNumber") as? Int ?? 1000) == dunbar,
                      let current = try? CloudAccount.fetchAccount(publicKey: account, context: viewContext()) else { return false }
                return current.getFollowingPublicKeys(includeBlocked: true).subtracting(current.privateFollowingPubkeys).subtracting([account]) == authors
            }
            guard stillValid else { return false }
            try Task.checkCancellation()
            let completedURL = directory.appendingPathComponent("wot-follow-lists-\(account).json")
            try JSONEncoder().encode(checkpoint).write(to: completedURL, options: .atomic)
            try Task.checkCancellation()
            try WebOfTrustSnapshotStore().write(checkpoint.allowed, for: account)
            let now = Date()
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: successKey(account))
            try? FileManager.default.removeItem(at: url)
            await WebOfTrust.shared.installAutomaticRefresh(checkpoint.allowed, account: account, date: now)
            L.maintenance.info("Completed automatic WoT refresh for \(authors.count) follow lists")
            return true
        } catch {
            L.maintenance.error("WoT refresh deferred: \(error.localizedDescription)")
            return false
        }
    }
}
