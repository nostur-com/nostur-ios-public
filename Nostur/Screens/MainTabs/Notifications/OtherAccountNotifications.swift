import Combine
import CoreData
import NostrEssentials

/// In-app counts for saved accounts. The active account owns live subscriptions
/// and system notifications. Keep these catch-up requests short and serial.
@MainActor
final class OtherAccountNotifications: ObservableObject {
    static let shared = OtherAccountNotifications()

    @Published private(set) var counts: [String: Int] = [:]
    private var check: Task<Void, Never>?
    private var lastRelayAttempt: [String: Date] = [:]
    private var lastRelayCheck: [String: Date] = [:]

    private let accounts = AccountsState.shared
    private init() {}

    func total(excluding activePubkey: String) -> Int {
        inactiveAccounts(excluding: activePubkey).reduce(0) { $0 + counts[$1.publicKey, default: 0] }
    }

    private func inactiveAccounts(excluding activePubkey: String) -> [CloudAccount] {
        accounts.accounts.filter {
            !$0.isDeleted && $0.managedObjectContext != nil && $0.isFullAccount &&
            !$0.publicKey.isEmpty && $0.publicKey != activePubkey && $0.publicKey != GUEST_ACCOUNT_PUBKEY
        }
    }

    func schedule(afterChecking activePubkey: String) {
        guard check == nil, canCheck(activePubkey) else { return }
        let inactive = inactiveAccounts(excluding: activePubkey)
        let keys = Set(inactive.map(\.publicKey))
        let validCounts = counts.filter { keys.contains($0.key) }
        if validCounts != counts { counts = validCounts }
        lastRelayAttempt = lastRelayAttempt.filter { keys.contains($0.key) }
        lastRelayCheck = lastRelayCheck.filter { keys.contains($0.key) }
        guard !inactive.isEmpty else { return }

        check = Task(priority: .utility) {
            defer { check = nil }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard canCheck(activePubkey) else { return }

            // Only pass immutable data across executors, and give each account a
            // separate turn so a large account list cannot monopolize Core Data.
            let snapshots = inactiveAccounts(excluding: activePubkey).map { $0.toStruct() }
            let context = DataProvider.shared().newTaskContext()
            for snapshot in snapshots {
                guard canCheck(activePubkey) else { return }
                await updateCount(for: snapshot, activePubkey: activePubkey, context: context)
            }
            for snapshot in snapshots {
                guard canCheck(activePubkey) else { return }
                if await fetchIfDue(snapshot, activePubkey: activePubkey) {
                    await updateCount(for: snapshot, activePubkey: activePubkey, context: context)
                }
            }
        }
    }

    private func updateCount(for snapshot: AccountData, activePubkey: String, context: NSManagedObjectContext) async {
        let count = await context.perform {
            Self.unreadCount(for: snapshot, context: context)
        }
        guard canCheck(activePubkey),
              let current = inactiveAccounts(excluding: activePubkey).first(where: { $0.publicKey == snapshot.publicKey }),
              current.toStruct() == snapshot else { return }
        if counts[snapshot.publicKey] != count { counts[snapshot.publicKey] = count }
    }

    private func canCheck(_ activePubkey: String) -> Bool {
        !activePubkey.isEmpty && accounts.activeAccountPublicKey == activePubkey &&
        (!AppState.shared.appIsInBackground || IS_CATALYST)
    }

    private func fetchIfDue(_ snapshot: AccountData, activePubkey: String) async -> Bool {
        let pubkey = snapshot.publicKey
        let now = Date.now
        guard !Importer.shared.hasPendingImportPasses,
              now.timeIntervalSince(lastRelayAttempt[pubkey] ?? .distantPast) >= 60 else { return false }

        let relays = await Task.detached(priority: .utility) {
            ConnectionPool.shared.connectedReadRelaysForMaintenance()
        }.value
        guard !relays.isEmpty, canCheck(activePubkey),
              inactiveAccounts(excluding: activePubkey).contains(where: { $0.publicKey == pubkey }) else { return false }

        let weekAgo = Int64(now.timeIntervalSince1970) - 604_800
        let oldestRead = min(snapshot.lastSeenPostCreatedAt, snapshot.lastSeenRepostCreatedAt,
                             snapshot.lastSeenReactionCreatedAt, snapshot.lastSeenZapCreatedAt)
        let recentCheck = lastRelayCheck[pubkey].map { Int64($0.timeIntervalSince1970) - 60 } ?? weekAgo
        let since = Int(max(weekAgo, oldestRead, recentCheck))
        lastRelayAttempt[pubkey] = now

        let id = "OtherAccountNotifications-" + UUID().uuidString
        defer { ConnectionPool.shared.closeSubscription(id) }
        if (try? await relayReq(
            Filters(kinds: Set(NotificationsViewModel.publicNotificationKinds),
                    tagFilter: TagFilter(tag: "p", values: [pubkey]), since: since, limit: 100),
            timeout: 4, debounceTime: 0.75, relays: relays, subscriptionId: id
        )) != nil {
            lastRelayCheck[pubkey] = now
        }
        // A timed-out request can still have imported some events.
        return true
    }

    private nonisolated static func unreadCount(for account: AccountData, context: NSManagedObjectContext) -> Int {
        let q = NotificationFetchRequests()
        let settings = UserDefaults.standard
        var count = q.unreadMentions(accountData: account, context: context).count
        if !settings.bool(forKey: "notifications_mute_reposts") {
            let request = q.unreadRepostsQuery(resultType: .managedObjectResultType, accountData: account)
            count += ((try? context.fetch(request)) ?? []).filter { !$0.isSpam }.count
        }
        if !settings.bool(forKey: "notifications_mute_reactions") {
            count += q.unreadReactionCount(accountData: account, context: context)
        }
        if !settings.bool(forKey: "notifications_mute_zaps") {
            let request = q.unreadZapsQuery(resultType: .managedObjectResultType, accountData: account)
            count += ((try? context.fetch(request)) ?? []).filter { !$0.isSpam }.count
            count += (try? context.count(for: q.unreadFailedZapsQuery(accountPubkey: account.publicKey))) ?? 0
        }
        if !settings.bool(forKey: "notifications_mute_follows") {
            count += (try? context.count(for: q.unreadNewFollowersQuery(accountPubkey: account.publicKey))) ?? 0
        }
        return count
    }
}
