import Foundation
import CryptoKit

/// Immutable, bounded event batches. No SQLite file is ever opened in iCloud Drive.
struct HistoryArchiveBatch: Codable, Sendable {
    let version: Int
    let owner: String
    let generation: String
    let events: [YearReviewEvent]
    let deletions: Set<String>
}

/// All sync and cloud deletion operations are queued, including across suspension points.
actor HistoryArchiveSync {
    static let shared = HistoryArchiveSync()
    private var tail: Task<Void, Error>?
    private var loop: Task<Void, Never>?
    private var kicked = false
    private var started = false
    private let engine = HistoryArchiveSyncEngine()

    func start() async {
        guard !started else { return }
        started = true
        // Poll on the utility executor. A live metadata query retains metadata
        // for the whole archive and can exhaust sandbox extensions on macOS.
        loop = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                do { try await self.sync() }
                catch { L.maintenance.error("History iCloud sync will retry: \(error.localizedDescription)") }
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    func kick() async {
        guard !kicked else { return }
        kicked = true
        do { try await sync() }
        catch { L.maintenance.error("History iCloud sync will retry: \(error.localizedDescription)") }
        kicked = false
    }

    func sync() async throws {
        let previous = tail
        let engine = engine
        let task = Task.detached(priority: .utility) {
            _ = try? await previous?.value
            try await engine.sync()
        }
        tail = task
        try await task.value
    }

    func clear(owner: String, archive: YearReviewArchive) async throws {
        let previous = tail
        let engine = engine
        let task = Task.detached(priority: .utility) {
            _ = try? await previous?.value
            try await engine.clear(owner: owner, archive: archive)
        }
        tail = task
        try await task.value
        Task { await self.kick() }
    }
}

actor HistoryArchiveSyncEngine {
    private struct State: Codable {
        var generation = "initial"
        var cursor: Int64 = 0
        var pendingReset = false
        var deletionHash = ""
    }
    private let archives: YearReviewArchives
    private let localRoot: URL
    private let suppliedCloudRoot: URL?
    private let testing: Bool
    private let device: String

    init(archives: YearReviewArchives = .shared, localRoot: URL? = nil, cloudRoot: URL? = nil) {
        self.archives = archives
        self.localRoot = localRoot ?? YearReviewArchive.storageDirectory.appendingPathComponent("Sync", isDirectory: true)
        suppliedCloudRoot = cloudRoot
        testing = localRoot != nil
        let key = "history-sync-device"
        if localRoot != nil { device = UUID().uuidString }
        else if let saved = UserDefaults.standard.string(forKey: key) { device = saved }
        else {
            device = UUID().uuidString
            UserDefaults.standard.set(device, forKey: key)
        }
    }

    private func cloudRoot() -> URL? {
        if testing { return suppliedCloudRoot }
        return FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.nostur.data")?
            .appendingPathComponent("Documents/HistoryArchive-v1", isDirectory: true)
    }

    private func stateURL(owner: String) throws -> URL {
        // Switching iCloud accounts must not reuse the previous account's upload cursor.
        let identity: String
        if testing { identity = "test" }
        else if let token = FileManager.default.ubiquityIdentityToken,
                let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false) {
            identity = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        } else { identity = "offline" }
        let directory = localRoot.appendingPathComponent(identity, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(owner + ".json")
    }

    private func state(owner: String) throws -> State {
        let url = try stateURL(owner: owner)
        guard FileManager.default.fileExists(atPath: url.path) else { return State() }
        return try JSONDecoder().decode(State.self, from: Data(contentsOf: url))
    }

    private func save(_ state: State, owner: String) throws {
        try JSONEncoder().encode(state).write(to: stateURL(owner: owner), options: .atomic)
    }

    /// Save the reset locally first so deleting while offline cannot resurrect history.
    func clear(owner: String, archive: YearReviewArchive) async throws {
        var value = State()
        value.generation = String(format: "%020lld", Int64(Date().timeIntervalSince1970 * 1_000_000)) + "-" + UUID().uuidString
        value.pendingReset = true
        try save(value, owner: owner)
        // A pending reset is independent of iCloud sign-in identity.
        try FileManager.default.createDirectory(at: localRoot, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: localRoot.appendingPathComponent(owner + ".reset"), options: .atomic)
        try await archive.delete()
    }

    func sync() async throws {
        guard let cloud = cloudRoot() else { return }
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        var owners = Set(try await archives.usage().map(\.owner))
        for name in try FileManager.default.contentsOfDirectory(atPath: cloud.path) {
            if YearReviewEvent.isHex(name, length: 64) { owners.insert(name) }
        }
        if FileManager.default.fileExists(atPath: localRoot.path) {
            for url in try FileManager.default.contentsOfDirectory(at: localRoot, includingPropertiesForKeys: nil) where url.pathExtension == "reset" {
                owners.insert(url.deletingPathExtension().lastPathComponent)
            }
        }
        for owner in owners.sorted() {
            try Task.checkCancellation()
            do { try await sync(owner: owner, cloud: cloud) }
            catch { L.maintenance.error("History batch sync deferred for \(owner.prefix(8)): \(error.localizedDescription)") }
        }
    }

    private func sync(owner: String, cloud: URL) async throws {
        guard YearReviewEvent.isHex(owner, length: 64) else { return }
        let archive = await archives.archive(owner: owner)
        let directory = cloud.appendingPathComponent(owner, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var value = try state(owner: owner)
        let pendingURL = localRoot.appendingPathComponent(owner + ".reset")
        if FileManager.default.fileExists(atPath: pendingURL.path) {
            value = try JSONDecoder().decode(State.self, from: Data(contentsOf: pendingURL))
            try write(Data(value.generation.utf8), to: directory.appendingPathComponent(value.generation + ".reset"))
            value.pendingReset = false
            try save(value, owner: owner)
            try FileManager.default.removeItem(at: pendingURL)
        }
        let files = try Self.cloudNames(in: directory)
        // The reset generation is carried in the immutable filename, even before download.
        let latest = files.filter { $0.hasSuffix(".reset") }.map { String($0.dropLast(6)) }.max() ?? "initial"
        if latest != value.generation {
            try await archive.delete()
            value = State(generation: latest)
            try save(value, owner: owner)
        }
        let generation = directory.appendingPathComponent(value.generation, isDirectory: true)
        try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true)
        let metadataKey = "icloud-batch:" + value.generation + ":"
        let completed = try await archive.syncBatchKeys(prefix: metadataKey)
        for url in try pendingBatches(in: generation, completed: completed, prefix: metadataKey) {
                do {
                    guard let data = try read(url) else { continue }
                    let batch = try JSONDecoder().decode(HistoryArchiveBatch.self, from: data)
                    guard batch.version == 1, batch.owner == owner, batch.generation == value.generation,
                          batch.events.count <= 200, batch.deletions.count <= 200,
                          batch.events.allSatisfy({ Self.publicEvent($0) && $0.verified() }),
                          batch.deletions.allSatisfy({ YearReviewEvent.isHex($0, length: 64) }) else {
                        throw YearReviewError.database("invalid cloud batch")
                    }
                    _ = try await archive.ingest(batch.events, source: "icloud:" + url.lastPathComponent)
                    try await archive.recordLocalDeletions(batch.deletions)
                    try await archive.save(true, key: metadataKey + url.path.replacingOccurrences(of: generation.path + "/", with: ""))
                } catch {
                    // One damaged or unavailable file must not prevent local uploads.
                    L.maintenance.error("History cloud batch deferred: \(error.localizedDescription)")
                }
        }
        // Bound each pass, preserving the cursor only after every file is written.
        for _ in 0..<20 {
            let page = try await archive.syncPage(after: value.cursor)
            if page.events.isEmpty { break }
            let groups = Dictionary(grouping: page.events, by: Self.month)
            for (month, allEvents) in groups {
                let events = allEvents.filter(Self.publicEvent)
                if events.isEmpty { continue }
                let folder = generation.appendingPathComponent(month, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let name = "\(device)-\(value.cursor)-\(page.cursor).json"
                let batch = HistoryArchiveBatch(version: 1, owner: owner, generation: value.generation, events: events, deletions: [])
                try write(JSONEncoder().encode(batch), to: folder.appendingPathComponent(name))
                try await archive.save(true, key: metadataKey + month + "/" + name)
            }
            value.cursor = page.cursor
            try save(value, owner: owner)
        }
        let deletions = try await archive.load(Set<String>.self, key: "local-deletions") ?? []
        let hash = SHA256.hash(data: Data(deletions.sorted().joined().utf8)).map { String(format: "%02x", $0) }.joined()
        if !deletions.isEmpty && hash != value.deletionHash {
            // Partition deletion metadata as well; no unbounded cloud document.
            for (index, ids) in deletions.sorted().chunks(ofCount: 200).enumerated() {
                let batch = HistoryArchiveBatch(version: 1, owner: owner, generation: value.generation, events: [], deletions: Set(ids))
                try write(JSONEncoder().encode(batch), to: generation.appendingPathComponent("deletions-\(device)-\(hash)-\(index).json"))
            }
        }
        value.deletionHash = hash
        try save(value, owner: owner)
        // Old generations cannot be imported. Reclaim their cloud space after reset.
        for name in files where value.generation != "initial" && !name.hasSuffix(".reset")
            && (name == "initial" || name < value.generation) {
            try coordinated(directory.appendingPathComponent(name), writing: true) { try FileManager.default.removeItem(at: $0) }
        }
    }

    private func pendingBatches(in directory: URL, completed: Set<String>, prefix: String) throws -> [URL] {
        var urls: [URL] = []
        // The schema has only root deletion files and YYYY-MM batch folders.
        // Enumerate names, not resource URLs for every already-imported file:
        // only the bounded pending set needs iCloud sandbox access.
        let names = try Self.cloudNames(in: directory)
        for name in names.sorted() {
            let paths: [String]
            if name.hasSuffix(".json") { paths = [name] }
            else if name.range(of: "^[0-9]{4}-[0-9]{2}$", options: .regularExpression) != nil {
                paths = try Self.cloudNames(in: directory.appendingPathComponent(name))
                    .filter { $0.hasSuffix(".json") }.map { name + "/" + $0 }
            } else { continue }
            for path in paths where !completed.contains(prefix + path) {
                urls.append(directory.appendingPathComponent(path))
                if urls.count == 8 { return urls }
            }
        }
        return urls
    }

    /// Undownloaded iCloud documents may appear as .<filename>.icloud on disk.
    static func cloudNames(in directory: URL) throws -> [String] {
        try autoreleasepool {
            let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            return Set(names.map { name in
                name.hasPrefix(".") && name.hasSuffix(".icloud") ? String(name.dropFirst().dropLast(7)) : name
            }).sorted()
        }
    }

    private static func publicEvent(_ event: YearReviewEvent) -> Bool {
        YearReviewKinds.archived.contains(event.kind) && !(event.kind == 7 && event.tagValues("k").contains(where: { ["4", "14", "15"].contains($0) }))
    }

    private static func month(_ event: YearReviewEvent) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: TimeInterval(event.createdAt))
        return String(format: "%04d-%02d", calendar.component(.year, from: date), calendar.component(.month, from: date))
    }

    private func read(_ url: URL) throws -> Data? {
        if !testing {
            let status = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus
            if status != nil && status != .current {
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
                return nil
            }
        }
        var data: Data?
        try coordinated(url, writing: false) {
            let size = try $0.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 3_000_000 else { throw YearReviewError.database("cloud batch too large") }
            data = try Data(contentsOf: $0)
        }
        return data
    }

    private func write(_ data: Data, to url: URL) throws {
        guard data.count <= 3_000_000 else { throw YearReviewError.database("cloud batch too large") }
        try coordinated(url, writing: true) { try data.write(to: $0, options: .atomic) }
    }

    /// Coordination can wait for iCloud; this engine only runs on a utility executor.
    private func coordinated(_ url: URL, writing: Bool, operation: (URL) throws -> Void) throws {
        if testing { try operation(url); return }
        try autoreleasepool {
            var coordinationError: NSError?
            var operationError: Error?
            let accessor: (URL) -> Void = { location in
                do { try operation(location) } catch { operationError = error }
            }
            let coordinator = NSFileCoordinator()
            if writing { coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError, byAccessor: accessor) }
            else { coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError, byAccessor: accessor) }
            if let error = coordinationError ?? operationError as NSError? { throw error }
        }
    }
}
