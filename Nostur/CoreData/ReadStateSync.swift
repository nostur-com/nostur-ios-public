import Combine
import CoreData
import UIKit

/// Read progress only moves forward. Keep a local high-water mark as well as the
/// CloudKit value, so a delayed/offline writer cannot resurrect old unreads.
/// All managed objects here belong to the main context; recounts use snapshots.
@MainActor
final class ReadStateSync {
    static let shared = ReadStateSync(context: viewContext(), defaults: .standard)

    let changedAccounts = PassthroughSubject<Set<String>, Never>()
    private let context: NSManagedObjectContext
    private let defaults: UserDefaults
    private var subscriptions = Set<AnyCancellable>()
    private var saveScheduled = false

    init(context: NSManagedObjectContext, defaults: UserDefaults) {
        precondition(context.concurrencyType == .mainQueueConcurrencyType)
        self.context = context
        self.defaults = defaults
    }

    func start() {
        guard subscriptions.isEmpty else { return }
        NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)
            .sink { [weak self] notification in
                Task { @MainActor in
                    let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSRefreshedObjectsKey]
                    let objects = keys.flatMap { notification.userInfo?[$0] as? Set<NSManagedObject> ?? [] }
                    self?.reconcile(objects)
                }
            }
            .store(in: &subscriptions)

        DataProvider.shared().cloudStoreRemoteChangeSubject
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] in
                Task { @MainActor in self?.refresh() }
            }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            .store(in: &subscriptions)
        refresh()
    }

    /// Also observes context merges: a remote-store notification can arrive
    /// before automaticallyMergesChangesFromParent has updated the main context.
    func refresh() {
        let accounts = (try? context.fetch(CloudAccount.fetchRequest())) ?? []
        let conversations = (try? context.fetch(CloudDMState.fetchRequest())) ?? []
        reconcile(accounts + conversations.map { $0 as NSManagedObject })
    }

    func reconcile(_ objects: [NSManagedObject]) {
        var affected = Set<String>()
        var progressChanged = false
        for object in objects where !object.isDeleted && object.managedObjectContext === context {
            if let account = object as? CloudAccount, !account.publicKey.isEmpty {
                for key in Self.accountKeys {
                    let value = account.value(forKey: key) as? Int64 ?? 0
                    let merged = merge(Double(value), key: "account.\(account.publicKey).\(key)")
                    if Int64(merged) != value {
                        account.setValue(Int64(merged), forKey: key)
                        progressChanged = true
                    }
                    // A new local read also needs to be saved, even when no repair
                    // was necessary. Other pending profile edits are not the trigger.
                    if account.changedValues()[key] != nil { progressChanged = true }
                }
                affected.insert(account.publicKey)
            }
            else if let conversation = object as? CloudDMState,
                    let pubkey = conversation.accountPubkey_, !pubkey.isEmpty,
                    !conversation.conversationId.isEmpty {
                let value = conversation.markedReadAt_?.timeIntervalSince1970 ?? 0
                let merged = merge(value, key: "dm.\(pubkey).\(conversation.conversationId)")
                if merged > value {
                    conversation.markedReadAt_ = Date(timeIntervalSince1970: merged)
                    progressChanged = true
                }
                if conversation.changedValues()["markedReadAt_"] != nil { progressChanged = true }
                affected.insert(pubkey)
            }
        }
        if progressChanged { scheduleSave() }
        if !affected.isEmpty { changedAccounts.send(affected) }
    }

    private static let accountKeys = [
        "lastSeenPostCreatedAt", "lastSeenRepostCreatedAt",
        "lastSeenReactionCreatedAt", "lastSeenZapCreatedAt", "lastSeenDMRequestCreatedAt"
    ]

    private func merge(_ value: Double, key: String) -> Double {
        let defaultsKey = "readStateSync.v1.\(key)"
        let previous = defaults.double(forKey: defaultsKey)
        let merged = max(previous, value)
        if merged > previous { defaults.set(merged, forKey: defaultsKey) }
        return merged
    }

    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.saveScheduled = false
            guard self.context.hasChanges else { return }
            do { try self.context.save() }
            catch { L.og.error("Could not save synced read state: \(error)") }
        }
    }
}

extension CloudDMState {
    @MainActor
    func markRead(at date: Date = .now) {
        guard date > (markedReadAt_ ?? .distantPast), let context = managedObjectContext else { return }
        markedReadAt_ = date
        // Do not queue read progress behind the importer or the general save debounce.
        context.perform {
            guard context.hasChanges else { return }
            do { try context.save() }
            catch { L.og.error("Could not save DM read state: \(error)") }
        }
    }
}
