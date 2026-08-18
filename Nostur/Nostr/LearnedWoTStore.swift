//
//  LearnedWoTStore.swift
//  Nostur
//

import CloudKit
import Combine
import Foundation

enum LearnedWoTInteractionKind: String, Codable, CaseIterable, Sendable {
    case reply
    case reaction
}

struct LearnedWoTEntry: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    let pubkey: String
    var firstInteractionAt: Date
    var lastInteractionAt: Date
    var interactionKinds: Set<LearnedWoTInteractionKind>
    var isRemoved: Bool
    var changedAt: Date

    var id: String { pubkey }

    init(
        pubkey: String,
        interaction: LearnedWoTInteractionKind,
        date: Date = .now
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.pubkey = pubkey
        self.firstInteractionAt = date
        self.lastInteractionAt = date
        self.interactionKinds = [interaction]
        self.isRemoved = false
        self.changedAt = date
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case pubkey
        case firstInteractionAt
        case lastInteractionAt
        case interactionKinds
        case isRemoved
        case changedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        pubkey = try container.decode(String.self, forKey: .pubkey)
        firstInteractionAt = try container.decode(Date.self, forKey: .firstInteractionAt)
        lastInteractionAt = try container.decode(Date.self, forKey: .lastInteractionAt)
        interactionKinds = try container.decodeIfPresent(Set<LearnedWoTInteractionKind>.self, forKey: .interactionKinds) ?? []
        isRemoved = try container.decodeIfPresent(Bool.self, forKey: .isRemoved) ?? false
        changedAt = try container.decodeIfPresent(Date.self, forKey: .changedAt) ?? lastInteractionAt
    }
}

private struct LearnedWoTState: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var entries: [String: LearnedWoTEntry] = [:]
    var pendingCloudPubkeys: Set<String> = []

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case entries
        case pendingCloudPubkeys
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        entries = try container.decodeIfPresent([String: LearnedWoTEntry].self, forKey: .entries) ?? [:]
        pendingCloudPubkeys = try container.decodeIfPresent(Set<String>.self, forKey: .pendingCloudPubkeys) ?? Set(entries.keys)
    }
}

/// Global, account-independent trust learned from deliberate outgoing interactions.
/// Filtering reads only the in-memory snapshot. File and CloudKit work stay on utility queues.
final class LearnedWoTStore: ObservableObject, @unchecked Sendable {
    static let shared = LearnedWoTStore()

    @Published private(set) var entries: [LearnedWoTEntry] = []

    private let stateQueue = DispatchQueue(label: "com.nostur.learned-wot.state", qos: .utility)
    private let snapshotLock = NSLock()
    private var allowedPubkeys: Set<String> = []
    private var state = LearnedWoTState()
    private var saveWorkItem: DispatchWorkItem?
    private var cloudWorkItem: DispatchWorkItem?
    private var subscriptions = Set<AnyCancellable>()
    private let configuredFileURL: URL?
    private var resolvedFileURL: URL?
    private var mayPersist = true
    private let cloudSync: LearnedWoTCloudSync?

    init(fileURL: URL? = nil, cloudSyncEnabled: Bool = true) {
        configuredFileURL = fileURL

        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        cloudSync = cloudSyncEnabled && !isRunningTests && !isPreview ? LearnedWoTCloudSync() : nil

        NotificationCenter.default.publisher(for: .scenePhaseActive)
            .sink { [weak self] _ in
                self?.scheduleCloudSync(delay: 0.25)
            }
            .store(in: &subscriptions)

        stateQueue.async { [weak self] in
            self?.loadFromDisk()
        }
    }

    func contains(_ pubkey: String) -> Bool {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return allowedPubkeys.contains(pubkey)
    }

    func currentPubkeys() -> Set<String> {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return allowedPubkeys
    }

    func learn(_ pubkey: String, interaction: LearnedWoTInteractionKind, at date: Date = .now) {
        guard Self.isValidPubkey(pubkey) else { return }
        guard !AccountsState.shared.bgAccountPubkeys.contains(pubkey) else { return }

        // Make the filtering decision effective before any persistence or cloud work.
        snapshotLock.lock()
        allowedPubkeys.insert(pubkey)
        snapshotLock.unlock()

        stateQueue.async { [weak self] in
            guard let self else { return }
            if var existing = self.state.entries[pubkey] {
                existing.schemaVersion = LearnedWoTEntry.currentSchemaVersion
                existing.firstInteractionAt = min(existing.firstInteractionAt, date)
                existing.lastInteractionAt = max(existing.lastInteractionAt, date)
                existing.interactionKinds.insert(interaction)
                existing.isRemoved = false
                existing.changedAt = date
                self.state.entries[pubkey] = existing
            }
            else {
                self.state.entries[pubkey] = LearnedWoTEntry(pubkey: pubkey, interaction: interaction, date: date)
            }
            self.state.pendingCloudPubkeys.insert(pubkey)
            self.publishSnapshot()
            self.scheduleSave()
            self.scheduleCloudSync()
        }
    }

    func remove(_ pubkey: String, at date: Date = .now) {
        snapshotLock.lock()
        allowedPubkeys.remove(pubkey)
        snapshotLock.unlock()

        stateQueue.async { [weak self] in
            guard let self, var entry = self.state.entries[pubkey] else { return }
            entry.isRemoved = true
            entry.changedAt = date
            self.state.entries[pubkey] = entry
            self.state.pendingCloudPubkeys.insert(pubkey)
            self.publishSnapshot()
            self.scheduleSave()
            self.scheduleCloudSync()
        }
    }

    func removeAll(at date: Date = .now) {
        snapshotLock.lock()
        allowedPubkeys.removeAll(keepingCapacity: true)
        snapshotLock.unlock()

        stateQueue.async { [weak self] in
            guard let self else { return }
            for pubkey in self.state.entries.keys {
                self.state.entries[pubkey]?.isRemoved = true
                self.state.entries[pubkey]?.changedAt = date
                self.state.pendingCloudPubkeys.insert(pubkey)
            }
            self.publishSnapshot()
            self.scheduleSave()
            self.scheduleCloudSync()
        }
    }

    private static func isValidPubkey(_ pubkey: String) -> Bool {
        pubkey.count == 64 && pubkey.unicodeScalars.allSatisfy { scalar in
            (48...57).contains(scalar.value) || (65...70).contains(scalar.value) || (97...102).contains(scalar.value)
        }
    }

    private func loadFromDisk() {
        do {
            let fileURL = try learnedWoTFileURL()
            resolvedFileURL = fileURL
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                publishSnapshot()
                scheduleCloudSync(delay: 0.1)
                return
            }

            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder.learnedWoT.decode(LearnedWoTState.self, from: data)
            guard decoded.schemaVersion <= LearnedWoTState.currentSchemaVersion else {
                mayPersist = false
                L.og.error("Learned WoT data is from a newer schema version; preserving it without changes")
                return
            }
            state = decoded
            publishSnapshot()
            scheduleCloudSync(delay: 0.1)
        }
        catch {
            L.og.error("Failed to load Learned WoT: \(error.localizedDescription)")
            publishSnapshot()
            scheduleCloudSync(delay: 0.1)
        }
    }

    private func learnedWoTFileURL() throws -> URL {
        if let configuredFileURL { return configuredFileURL }
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("Nostur", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("learned-web-of-trust.json")
    }

    private func publishSnapshot() {
        let visibleEntries = state.entries.values
            .filter { !$0.isRemoved }
            .sorted { lhs, rhs in
                if lhs.lastInteractionAt != rhs.lastInteractionAt {
                    return lhs.lastInteractionAt > rhs.lastInteractionAt
                }
                return lhs.pubkey < rhs.pubkey
            }
        let pubkeys = Set(visibleEntries.map(\.pubkey))

        snapshotLock.lock()
        allowedPubkeys = pubkeys
        snapshotLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.entries = visibleEntries
        }
    }

    private func scheduleSave(delay: TimeInterval = 0.75) {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        saveWorkItem = workItem
        stateQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func saveNow() {
        guard mayPersist else { return }
        do {
            let fileURL = try resolvedFileURL ?? learnedWoTFileURL()
            resolvedFileURL = fileURL
            let data = try JSONEncoder.learnedWoT.encode(state)
            try data.write(to: fileURL, options: [.atomic])
#if os(iOS)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: fileURL.path
            )
#endif
        }
        catch {
            L.og.error("Failed to save Learned WoT: \(error.localizedDescription)")
        }
    }

    private func scheduleCloudSync(delay: TimeInterval = 1.5) {
        guard cloudSync != nil else { return }
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.cloudWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.syncWithCloud()
            }
            self.cloudWorkItem = workItem
            self.stateQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func syncWithCloud() {
        guard let cloudSync else { return }
        cloudSync.fetchAll { [weak self] result in
            guard let self else { return }
            self.stateQueue.async {
                switch result {
                case .success(let remoteEntries):
                    self.merge(remoteEntries: remoteEntries)
                    self.uploadPending(using: cloudSync)
                case .failure(let error):
#if DEBUG
                    L.cloud.debug("Learned WoT CloudKit sync unavailable: \(error.localizedDescription)")
#endif
                    // A brand-new CloudKit record type cannot be queried until its first
                    // record exists in development. Trying pending saves is also harmless
                    // when the failure is simply an offline device; those remain pending.
                    self.uploadPending(using: cloudSync)
                }
            }
        }
    }

    private func uploadPending(using cloudSync: LearnedWoTCloudSync) {
        let pendingEntries = state.pendingCloudPubkeys.compactMap { state.entries[$0] }
        guard !pendingEntries.isEmpty else {
            publishSnapshot()
            scheduleSave(delay: 0)
            return
        }
        let uploadedDates = Dictionary(uniqueKeysWithValues: pendingEntries.map { ($0.pubkey, $0.changedAt) })
        cloudSync.save(pendingEntries) { [weak self] savedPubkeys in
            guard let self else { return }
            self.stateQueue.async {
                for pubkey in savedPubkeys where self.state.entries[pubkey]?.changedAt == uploadedDates[pubkey] {
                    self.state.pendingCloudPubkeys.remove(pubkey)
                }
                self.scheduleSave(delay: 0)
            }
        }
    }

    private func merge(remoteEntries: [LearnedWoTEntry]) {
        var changed = false
        for remote in remoteEntries {
            guard Self.isValidPubkey(remote.pubkey) else { continue }
            guard let local = state.entries[remote.pubkey] else {
                state.entries[remote.pubkey] = remote
                changed = true
                continue
            }

            if remote.changedAt > local.changedAt {
                state.entries[remote.pubkey] = remote
                state.pendingCloudPubkeys.remove(remote.pubkey)
                changed = true
            }
            else if local.changedAt > remote.changedAt {
                state.pendingCloudPubkeys.insert(local.pubkey)
            }
            else if !local.isRemoved && !remote.isRemoved {
                var merged = local
                merged.firstInteractionAt = min(local.firstInteractionAt, remote.firstInteractionAt)
                merged.lastInteractionAt = max(local.lastInteractionAt, remote.lastInteractionAt)
                merged.interactionKinds.formUnion(remote.interactionKinds)
                if merged != local {
                    state.entries[local.pubkey] = merged
                    state.pendingCloudPubkeys.insert(local.pubkey)
                    changed = true
                }
            }
        }

        if changed {
            publishSnapshot()
            scheduleSave(delay: 0)
        }
    }

    // Test support: wait for queued loading/mutations and force the durable write.
    func flushForTesting() async {
        await withCheckedContinuation { continuation in
            stateQueue.async { [weak self] in
                self?.saveWorkItem?.cancel()
                self?.saveNow()
                continuation.resume()
            }
        }
    }

    func waitUntilLoadedForTesting() async {
        await withCheckedContinuation { continuation in
            stateQueue.async {
                continuation.resume()
            }
        }
    }

    func entriesForTesting() async -> [LearnedWoTEntry] {
        await withCheckedContinuation { continuation in
            stateQueue.async { [weak self] in
                continuation.resume(returning: self.map { Array($0.state.entries.values) } ?? [])
            }
        }
    }
}

final class InteractionRecorder {
    static let shared = InteractionRecorder()

    private init() {}

    func recordDirectInteraction(with pubkey: String, kind: LearnedWoTInteractionKind) {
        LearnedWoTStore.shared.learn(pubkey, interaction: kind)
    }
}

private extension JSONEncoder {
    static var learnedWoT: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var learnedWoT: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private final class LearnedWoTCloudSync {
    private static let containerIdentifier = "iCloud.com.nostur.data"
    private static let recordType = "LearnedWoTContact"
    private static let zoneID = CKRecordZone.ID(zoneName: "LearnedWoT", ownerName: CKCurrentUserDefaultName)

    private let database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
    private let lock = NSLock()
    private var zoneIsReady = false

    func fetchAll(completion: @escaping (Result<[LearnedWoTEntry], Error>) -> Void) {
        ensureZone { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.fetchPage(cursor: nil, accumulated: [], completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func save(_ entries: [LearnedWoTEntry], completion: @escaping (Set<String>) -> Void) {
        guard !entries.isEmpty else {
            completion([])
            return
        }
        ensureZone { [weak self] result in
            guard let self else { return }
            guard case .success = result else {
                completion([])
                return
            }

            self.saveBatch(entries, previouslySaved: [], completion: completion)
        }
    }

    private func saveBatch(
        _ entries: [LearnedWoTEntry],
        previouslySaved: Set<String>,
        completion: @escaping (Set<String>) -> Void
    ) {
        let batchSize = min(entries.count, 200)
        let batch = Array(entries.prefix(batchSize))
        let remaining = Array(entries.dropFirst(batchSize))
        let records = batch.map(record(from:))
        let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        operation.savePolicy = .changedKeys
        operation.isAtomic = false
        let resultLock = NSLock()
        var savedPubkeys = previouslySaved
        operation.perRecordSaveBlock = { _, result in
            guard case .success(let record) = result, let pubkey = record["pubkey"] as? String else { return }
            resultLock.lock()
            savedPubkeys.insert(pubkey)
            resultLock.unlock()
        }
        operation.modifyRecordsResultBlock = { [weak self] _ in
            resultLock.lock()
            let saved = savedPubkeys
            resultLock.unlock()
            if remaining.isEmpty || self == nil {
                completion(saved)
            }
            else {
                self?.saveBatch(remaining, previouslySaved: saved, completion: completion)
            }
        }
        database.add(operation)
    }

    private func ensureZone(completion: @escaping (Result<Void, Error>) -> Void) {
        lock.lock()
        let ready = zoneIsReady
        lock.unlock()
        if ready {
            completion(.success(()))
            return
        }

        let zone = CKRecordZone(zoneID: Self.zoneID)
        let operation = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
        operation.modifyRecordZonesResultBlock = { [weak self] result in
            if case .failure(let error) = result {
                completion(.failure(error))
                return
            }
            self?.lock.lock()
            self?.zoneIsReady = true
            self?.lock.unlock()
            completion(.success(()))
        }
        database.add(operation)
    }

    private func fetchPage(
        cursor: CKQueryOperation.Cursor?,
        accumulated: [LearnedWoTEntry],
        completion: @escaping (Result<[LearnedWoTEntry], Error>) -> Void
    ) {
        let operation: CKQueryOperation
        if let cursor {
            operation = CKQueryOperation(cursor: cursor)
        }
        else {
            operation = CKQueryOperation(query: CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true)))
            operation.zoneID = Self.zoneID
        }
        operation.resultsLimit = CKQueryOperation.maximumResults

        let resultLock = NSLock()
        var entries = accumulated
        operation.recordMatchedBlock = { _, result in
            guard case .success(let record) = result else { return }
            guard let entry = Self.entry(from: record) else { return }
            resultLock.lock()
            entries.append(entry)
            resultLock.unlock()
        }
        operation.queryResultBlock = { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let cursor):
                if let cursor, let self {
                    self.fetchPage(cursor: cursor, accumulated: entries, completion: completion)
                }
                else {
                    completion(.success(entries))
                }
            }
        }
        database.add(operation)
    }

    private func record(from entry: LearnedWoTEntry) -> CKRecord {
        let recordID = CKRecord.ID(recordName: entry.pubkey, zoneID: Self.zoneID)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["schemaVersion"] = entry.schemaVersion as CKRecordValue
        record["pubkey"] = entry.pubkey as CKRecordValue
        record["firstInteractionAt"] = entry.firstInteractionAt as CKRecordValue
        record["lastInteractionAt"] = entry.lastInteractionAt as CKRecordValue
        record["interactionKinds"] = entry.interactionKinds.map(\.rawValue).sorted().joined(separator: ",") as CKRecordValue
        record["isRemoved"] = entry.isRemoved as CKRecordValue
        record["changedAt"] = entry.changedAt as CKRecordValue
        return record
    }

    private static func entry(from record: CKRecord) -> LearnedWoTEntry? {
        guard
            let pubkey = record["pubkey"] as? String,
            let firstInteractionAt = record["firstInteractionAt"] as? Date,
            let lastInteractionAt = record["lastInteractionAt"] as? Date,
            let changedAt = record["changedAt"] as? Date
        else { return nil }

        let rawKinds = (record["interactionKinds"] as? String ?? "")
            .split(separator: ",")
            .compactMap { LearnedWoTInteractionKind(rawValue: String($0)) }
        var entry = LearnedWoTEntry(
            pubkey: pubkey,
            interaction: rawKinds.first ?? .reaction,
            date: firstInteractionAt
        )
        entry.schemaVersion = record["schemaVersion"] as? Int ?? 1
        entry.firstInteractionAt = firstInteractionAt
        entry.lastInteractionAt = lastInteractionAt
        entry.interactionKinds = Set(rawKinds)
        entry.isRemoved = record["isRemoved"] as? Bool ?? false
        entry.changedAt = changedAt
        return entry
    }
}
