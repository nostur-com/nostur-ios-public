import Foundation
import CoreData

struct YearReviewArchiveUsage: Identifiable, Equatable, Sendable {
    let owner: String
    let bytes: Int64
    var id: String { owner }
}

/// One writer per account, shared by passive capture and explicit report collection.
actor YearReviewArchives {
    static let shared = YearReviewArchives()
    private var archives: [String: YearReviewArchive] = [:]
    private let directory: URL?

    init(directory: URL? = nil) { self.directory = directory }

    func archive(owner: String) -> YearReviewArchive {
        if let archive = archives[owner] { return archive }
        let archive = YearReviewArchive(owner: owner, fileURL: directory?.appendingPathComponent(owner + ".sqlite"))
        archives[owner] = archive
        return archive
    }
    func usage() async throws -> [YearReviewArchiveUsage] {
        let root = directory ?? YearReviewArchive.storageDirectory
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var result: [YearReviewArchiveUsage] = []
        for file in files where file.pathExtension == "sqlite" {
            let owner = file.deletingPathExtension().lastPathComponent
            guard YearReviewEvent.isHex(owner, length: 64) else { continue }
            let bytes = try await archive(owner: owner).storageBytes()
            if bytes > 0 { result.append(YearReviewArchiveUsage(owner: owner, bytes: bytes)) }
        }
        return result.sorted { $0.bytes == $1.bytes ? $0.owner < $1.owner : $0.bytes > $1.bytes }
    }

    func delete(owner: String) async throws {
        try await archive(owner: owner).delete()
    }

    func clear(owner: String) async throws {
        try? await LiveHistoryRecorder.shared.flush()
        LiveHistoryRecorder.shared.discardQueuedHistory(owner: owner)
        if directory == nil {
            try await HistoryArchiveSync.shared.clear(owner: owner, archive: archive(owner: owner))
        } else { try await delete(owner: owner) }
    }

}

/// Original public relay payloads are copied before duplicate detection or import
/// transforms. The socket callback never waits for decoding, signatures or disk.
final class LiveHistoryRecorder: @unchecked Sendable {
    struct Entry: Sendable {
        let text: String
        let source: String
        let owner: String
        let accounts: Set<String>
    }
    static let shared = LiveHistoryRecorder()
    private let lock = NSLock()
    private var accounts = Set<String>()
    private var pending: [Entry] = []
    private var failedBatch: [Entry] = []
    private var pendingBytes = 0
    private var running = false
    private var waiters: [CheckedContinuation<Void, Error>] = []
    private var failure: Error?
    private let writer: @Sendable ([Entry]) async throws -> Void
    private let header = try! NSRegularExpression(pattern: "^\\s*\\[\\s*\"EVENT\"\\s*,")

    init(archives: YearReviewArchives = .shared, writer: (@Sendable ([Entry]) async throws -> Void)? = nil) {
        self.writer = writer ?? { try await Self.persist($0, archives: archives) }
    }

    func setAccounts(_ accounts: Set<String>) {
        lock.lock()
        self.accounts = accounts
        lock.unlock()
        if self === Self.shared { Task { await HistoryArchiveSync.shared.start() } }
    }

    func receive(text: String, source: String, owner: String) {
        guard YearReviewEvent.isHex(owner, length: 64), text.utf8.count <= 600_000,
              header.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil else { return }
        let bytes = text.utf8.count
        lock.lock()
        // Ordinary imports still retain overflow in Core Data. The mandatory
        // pre-cleanup backfill below archives that cache before it can be pruned.
        guard pending.count < 4096, pendingBytes + bytes <= 32_000_000 else {
            lock.unlock()
            L.maintenance.error("History capture buffer full; cached events will be preserved before cleanup")
            return
        }
        pending.append(Entry(text: text, source: source, owner: owner, accounts: accounts))
        pendingBytes += bytes
        let start = !running
        running = true
        lock.unlock()
        if start { Task.detached(priority: .utility) { await self.drain() } }
    }

    func discardQueuedHistory(owner: String) {
        lock.lock()
        func excludingOwner(_ entry: Entry) -> Entry {
            Entry(text: entry.text, source: entry.source, owner: entry.owner == owner ? "" : entry.owner,
                accounts: entry.accounts.subtracting([owner]))
        }
        pending = pending.map(excludingOwner)
        failedBatch = failedBatch.map(excludingOwner)
        lock.unlock()
    }

    func flush() async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if running {
                waiters.append(continuation)
                lock.unlock()
            } else {
                let error = failure
                lock.unlock()
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private func takeBatch() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        if !failedBatch.isEmpty {
            let batch = failedBatch
            failedBatch.removeAll()
            return batch
        }
        let batch = Array(pending.prefix(64))
        pending.removeFirst(batch.count)
        pendingBytes -= batch.reduce(0) { $0 + $1.text.utf8.count }
        return batch
    }

    private func finish(error: Error? = nil) -> Bool {
        lock.lock()
        if error == nil, !pending.isEmpty { lock.unlock(); return false }
        running = false
        failure = error
        let completions = waiters
        waiters.removeAll()
        lock.unlock()
        for completion in completions {
            if let error { completion.resume(throwing: error) }
            else { completion.resume() }
        }
        return true
    }

    private func retainFailed(_ batch: [Entry]) {
        lock.lock()
        failedBatch = batch
        lock.unlock()
    }

    private func drain() async {
        while true {
            let batch = takeBatch()
            if batch.isEmpty {
                if finish() { return }
                continue
            }
            do { try await writer(batch) }
            catch {
                // Do not let a failed archive write authorize database pruning.
                L.maintenance.error("Public history archive write failed: \(error.localizedDescription)")
                retainFailed(batch)
                _ = finish(error: error)
                return
            }
        }
    }

    static func event(from text: String) -> YearReviewEvent? {
        guard let data = text.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [Any], message.count == 3,
              message[0] as? String == "EVENT",
              let fields = message[2] as? [String: Any],
              let json = try? JSONSerialization.data(withJSONObject: fields),
              let event = try? JSONDecoder().decode(YearReviewEvent.self, from: json),
              YearReviewKinds.archived.contains(event.kind),
              !(event.kind == 7 && event.tagValues("k").contains(where: { ["4", "14", "15"].contains($0) })) else { return nil }
        return event
    }

    static func owners(for event: YearReviewEvent, active: String, accounts: Set<String>) -> Set<String> {
        var owners = accounts.intersection(Set(event.tagValues("p") + event.tagValues("P") + [event.pubkey])).filter { YearReviewEvent.isHex($0, length: 64) }
        if YearReviewEvent.isHex(active, length: 64) { owners.insert(active) }
        return owners
    }

    private static func persist(_ entries: [Entry], archives: YearReviewArchives) async throws {
        var batches: [String: [String: [YearReviewEvent]]] = [:]
        for entry in entries {
            guard let event = event(from: entry.text) else { continue }
            for owner in owners(for: event, active: entry.owner, accounts: entry.accounts) {
                batches[owner, default: [:]][entry.source, default: []].append(event)
            }
        }
        for (owner, sources) in batches {
            let archive = await archives.archive(owner: owner)
            for (source, events) in sources { _ = try await archive.ingest(events, source: source) }
        }
    }

    /// A bounded private-context scan protects events cached before this feature
    /// existed, and recovers normal cache events deferred by a busy live writer.
    static func preserveCache(active: String, accounts: Set<String>, context: NSManagedObjectContext, archives: YearReviewArchives = .shared) async throws {
        guard !accounts.isEmpty || YearReviewEvent.isHex(active, length: 64) else { return }
        var cursor = ""
        while true {
            try Task.checkCancellation()
            let after = cursor
            let batch = try await context.perform { () -> (events: [YearReviewEvent], deleted: Set<String>, last: String?) in
                let request = Event.fetchRequest()
                request.predicate = NSPredicate(format: "kind IN %@ AND id > %@ AND sig != nil AND otherId == nil AND groupId == nil AND NOT (kind == 7 AND kTag IN {4,14,15})",
                    Array(YearReviewKinds.archived), after)
                request.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]
                request.fetchLimit = 200
                let rows = try context.fetch(request)
                let snapshots = rows.filter { $0.deletedById == nil }.map { event in
                    YearReviewLocalSeed.restoreReceipt(YearReviewEvent(id: event.id, pubkey: event.pubkey,
                        createdAt: event.created_at, kind: Int(event.kind), tags: event.tags().map { $0.tag },
                        content: event.content ?? "", sig: event.sig ?? ""))
                }
                let result = (snapshots, Set(rows.filter { $0.deletedById != nil }.map(\.id)), rows.last?.id)
                context.reset()
                return result
            }
            guard let last = batch.last else { break }
            cursor = last
            var grouped: [String: [YearReviewEvent]] = [:]
            for event in batch.events {
                for owner in owners(for: event, active: active, accounts: accounts) { grouped[owner, default: []].append(event) }
            }
            for owner in accounts.union(YearReviewEvent.isHex(active, length: 64) ? [active] : []) where YearReviewEvent.isHex(owner, length: 64) {
                let archive = await archives.archive(owner: owner)
                if let events = grouped[owner] { _ = try await archive.ingest(events, source: "local-cache-maintenance") }
                if !batch.deleted.isEmpty { try await archive.recordLocalDeletions(batch.deleted) }
            }
        }
    }
}
