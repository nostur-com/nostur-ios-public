import Foundation
import SQLite3

enum YearReviewError: LocalizedError {
    case database(String)
    case archiveLimit
    case relay(String)

    var errorDescription: String? {
        switch self {
        case .database: return String(localized: "Your history archive could not be opened or saved.")
        case .archiveLimit: return String(localized: "This history collection reached its storage limit. Your saved history is still available.")
        case .relay(let message): return message
        }
    }
}

struct YearReviewImportResult: Sendable {
    var added = 0
    var addedFromYou = 0
    var addedFromOthers = 0
    var invalid = 0
}

struct YearReviewArchivedCounts: Sendable, Equatable {
    var fromYou = 0
    var fromOthers = 0
}

struct YearReviewDetailPage: Sendable {
    let cursor: String
    let events: [YearReviewEvent]
    let replyIds: Set<String>
}

struct YearReviewInventory: Sendable {
    let count: Int
    let ownPostIds: [String]
    let missingParentIds: [String]
    var ownCoordinates: [String] = []
    var outgoingTargets: [String] = []
}

/// This database is independent of the feed store and CloudKit. Connections exist
/// only during an operation; all validation, queries, and file I/O run on this actor.
actor YearReviewArchive {
    static var storageDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YearReview", isDirectory: true)
    }
    static let maximumEvents = 2_000_000
    static let maximumBytes = 4_000_000_000
    private let owner: String
    private let fileURL: URL
    private let byteLimit: Int
    private var statistics: (count: Int, bytes: Int)?
    private var exportURLs = Set<URL>()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(owner: String, fileURL: URL? = nil, maximumBytes: Int = YearReviewArchive.maximumBytes) {
        self.owner = owner
        self.fileURL = fileURL ?? Self.storageDirectory.appendingPathComponent(owner + ".sqlite")
        byteLimit = maximumBytes
    }

    private func withDatabase<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let isNew = !FileManager.default.fileExists(atPath: fileURL.path)
        var database: OpaquePointer?
        guard sqlite3_open_v2(fileURL.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database else {
            if let database { sqlite3_close(database) }
            throw YearReviewError.database("open")
        }
        defer { sqlite3_close(database) }
#if os(iOS)
        if isNew {
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: fileURL.path)
        }
#endif
        sqlite3_busy_timeout(database, 1_000)
        try execute(database, "CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, pubkey TEXT NOT NULL, created_at INTEGER NOT NULL, kind INTEGER NOT NULL, json TEXT NOT NULL)")
        try execute(database, "CREATE INDEX IF NOT EXISTS events_date ON events(created_at)")
        try execute(database, "CREATE INDEX IF NOT EXISTS events_author ON events(pubkey, kind)")
        try execute(database, "CREATE TABLE IF NOT EXISTS sources (event_id TEXT NOT NULL, relay TEXT NOT NULL, PRIMARY KEY(event_id, relay))")
        try execute(database, "CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, json TEXT NOT NULL)")
        try execute(database, "CREATE TABLE IF NOT EXISTS verified_zaps (receipt_id TEXT PRIMARY KEY, version INTEGER NOT NULL, json TEXT NOT NULL)")
        try execute(database, "CREATE TABLE IF NOT EXISTS sync_outbox (sequence INTEGER PRIMARY KEY AUTOINCREMENT, event_id TEXT UNIQUE NOT NULL)")
        // Migrate existing archives once, including history captured before sync existed.
        try execute(database, "INSERT OR IGNORE INTO sync_outbox(event_id) SELECT id FROM events WHERE NOT EXISTS (SELECT 1 FROM metadata WHERE key = 'sync-outbox-v1')")
        try execute(database, "INSERT OR IGNORE INTO metadata(key, json) VALUES ('sync-outbox-v1', 'true')")
        try execute(database, "CREATE TABLE IF NOT EXISTS thread_refs (event_id TEXT NOT NULL, target TEXT NOT NULL, PRIMARY KEY(event_id, target))")
        try execute(database, "CREATE INDEX IF NOT EXISTS thread_refs_target ON thread_refs(target)")
        try execute(database, "CREATE TABLE IF NOT EXISTS detail_refs (event_id TEXT NOT NULL, target TEXT NOT NULL, PRIMARY KEY(event_id, target))")
        try execute(database, "CREATE INDEX IF NOT EXISTS detail_refs_target ON detail_refs(target)")
        return try operation(database)
    }

    private func execute(_ database: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw YearReviewError.database(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func statement(_ database: OpaquePointer, _ sql: String) throws -> OpaquePointer {
        var result: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &result, nil) == SQLITE_OK, let result else {
            throw YearReviewError.database("prepare")
        }
        return result
    }

    private func bind(_ value: String, at index: Int32, to statement: OpaquePointer) {
        sqlite3_bind_text(statement, index, value, -1, transient)
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    /// Parallel relay dispatches may persist snapshots in either order.
    /// Never allow an older snapshot to shorten another relay’s pacing/cooldown.
    func savePacing(_ incoming: YearReviewRelayPacing) throws {
        var merged = try load(YearReviewRelayPacing.self, key: "relay-pacing") ?? YearReviewRelayPacing()
        for (relay, date) in incoming.nextRequest { merged.nextRequest[relay] = max(date, merged.nextRequest[relay, default: .distantPast]) }
        for (relay, count) in incoming.failures { merged.failures[relay] = max(count, merged.failures[relay, default: 0]) }
        try save(merged, key: "relay-pacing")
    }

    func archivedCounts() throws -> YearReviewArchivedCounts {
        try withDatabase { database in
            let query = try statement(database, "SELECT COUNT(*), COALESCE(SUM(CASE WHEN pubkey = ? THEN 1 ELSE 0 END), 0) FROM events")
            defer { sqlite3_finalize(query) }
            bind(owner, at: 1, to: query)
            guard sqlite3_step(query) == SQLITE_ROW else { throw YearReviewError.database("counts") }
            let total = Int(sqlite3_column_int64(query, 0))
            let own = Int(sqlite3_column_int64(query, 1))
            return YearReviewArchivedCounts(fromYou: own, fromOthers: total - own)
        }
    }

    func ingest(_ events: [YearReviewEvent], source: String) throws -> YearReviewImportResult {
        try withDatabase { database in
            if statistics == nil {
                let size = try statement(database, "SELECT COUNT(*), COALESCE(SUM(length(CAST(json AS BLOB))), 0) FROM events")
                defer { sqlite3_finalize(size) }
                guard sqlite3_step(size) == SQLITE_ROW else { throw YearReviewError.database("size") }
                statistics = (Int(sqlite3_column_int64(size, 0)), Int(sqlite3_column_int64(size, 1)))
            }
            var count = statistics!.count
            var bytes = statistics!.bytes
            let exists = try statement(database, "SELECT json FROM events WHERE id = ?")
            let insert = try statement(database, "INSERT INTO events(id, pubkey, created_at, kind, json) VALUES (?, ?, ?, ?, ?)")
            let provenance = try statement(database, "INSERT OR IGNORE INTO sources(event_id, relay) VALUES (?, ?)")
            defer { sqlite3_finalize(exists); sqlite3_finalize(insert); sqlite3_finalize(provenance) }
            try execute(database, "BEGIN IMMEDIATE")
            do {
                var result = YearReviewImportResult()
                for event in events {
                    try Task.checkCancellation()
                    guard let json = try? JSONEncoder().encode(event), json.count <= 512_000,
                          let string = String(data: json, encoding: .utf8) else {
                        result.invalid += 1
                        continue
                    }
                    sqlite3_reset(exists)
                    bind(event.id, at: 1, to: exists)
                    let status = sqlite3_step(exists)
                    guard status == SQLITE_ROW || status == SQLITE_DONE else { throw YearReviewError.database("exists") }
                    if status == SQLITE_ROW {
                        // Reuse verification only for exactly the same signed fields.
                        // An attacker reusing a known ID with altered content is rejected.
                        let stored = try JSONDecoder().decode(YearReviewEvent.self, from: Data(text(exists, 0).utf8))
                        guard stored == event else { result.invalid += 1; continue }
                    } else {
                        guard event.verified() else { result.invalid += 1; continue }
                        guard count < Self.maximumEvents, bytes + json.count <= byteLimit else {
                            throw YearReviewError.archiveLimit
                        }
                        sqlite3_reset(insert)
                        bind(event.id, at: 1, to: insert)
                        bind(event.pubkey, at: 2, to: insert)
                        sqlite3_bind_int64(insert, 3, event.createdAt)
                        sqlite3_bind_int(insert, 4, Int32(event.kind))
                        bind(string, at: 5, to: insert)
                        guard sqlite3_step(insert) == SQLITE_DONE else { throw YearReviewError.database("insert") }
                        if !source.hasPrefix("icloud:") {
                            let outbox = try statement(database, "INSERT OR IGNORE INTO sync_outbox(event_id) VALUES (?)")
                            defer { sqlite3_finalize(outbox) }
                            bind(event.id, at: 1, to: outbox)
                            guard sqlite3_step(outbox) == SQLITE_DONE else { throw YearReviewError.database("outbox") }
                        }
                        count += 1
                        bytes += json.count
                        result.added += 1
                        if event.pubkey == owner { result.addedFromYou += 1 }
                        else { result.addedFromOthers += 1 }
                    }
                    try indexThread(event, database: database)
                    sqlite3_reset(provenance)
                    bind(event.id, at: 1, to: provenance)
                    bind(source, at: 2, to: provenance)
                    guard sqlite3_step(provenance) == SQLITE_DONE else { throw YearReviewError.database("source") }
                }
                try execute(database, "COMMIT")
                statistics = (count, bytes)
                return result
            } catch {
                try? execute(database, "ROLLBACK")
                throw error
            }
        }
    }

    private func indexThread(_ event: YearReviewEvent, database: OpaquePointer) throws {
        let threadReferences = Set([event.parentId, event.rootId].compactMap { $0 })
        var detailReferences = Set<String>()
        if YearReviewKinds.support.contains(event.kind), let target = event.tagValues("e").last ?? event.tagValues("a").last {
            detailReferences.insert(target)
        }
        if YearReviewKinds.content.contains(event.kind) {
            detailReferences.formUnion(event.tagValues("q"))
            detailReferences.formUnion(event.tags.compactMap { $0.count >= 4 && $0[0] == "e" && $0[3] == "mention" ? $0[1] : nil })
        }
        for (table, references) in [("thread_refs", threadReferences), ("detail_refs", detailReferences)] where !references.isEmpty {
            let insert = try statement(database, "INSERT OR IGNORE INTO \(table)(event_id, target) VALUES (?, ?)")
            defer { sqlite3_finalize(insert) }
            for reference in references {
                sqlite3_reset(insert)
                bind(event.id, at: 1, to: insert)
                bind(reference, at: 2, to: insert)
                guard sqlite3_step(insert) == SQLITE_DONE else { throw YearReviewError.database("detail index") }
            }
        }
    }

    /// Backfill older archives in small actor operations, yielding between pages.
    private func ensureThreadIndex() async throws {
        if try load(Bool.self, key: "detail-index-complete-v2") == true { return }
        var cursor = try load(String.self, key: "detail-index-cursor-v2") ?? ""
        while true {
            try Task.checkCancellation()
            let page: [YearReviewEvent] = try withDatabase { database in
                let query = try statement(database, "SELECT json FROM events WHERE id > ? ORDER BY id LIMIT 200")
                defer { sqlite3_finalize(query) }
                bind(cursor, at: 1, to: query)
                try execute(database, "BEGIN IMMEDIATE")
                defer { try? execute(database, "ROLLBACK") }
                var events: [YearReviewEvent] = []
                var status = sqlite3_step(query)
                while status == SQLITE_ROW {
                    let event = try JSONDecoder().decode(YearReviewEvent.self, from: Data(text(query, 0).utf8))
                    try indexThread(event, database: database)
                    events.append(event)
                    status = sqlite3_step(query)
                }
                guard status == SQLITE_DONE else { throw YearReviewError.database("thread index migration") }
                try execute(database, "COMMIT")
                return events
            }
            guard let last = page.last else { break }
            cursor = last.id
            try save(cursor, key: "detail-index-cursor-v2")
            await Task.yield()
        }
        try save(true, key: "detail-index-complete-v2")
    }

    /// Only the opened highlight's descendants and directly related interactions.
    /// Quotes are support, not thread edges; recursive UNION also terminates cycles.
    func detailPage(to id: String, coordinate: String? = nil, after cursor: String = "") async throws -> YearReviewDetailPage {
        try await ensureThreadIndex()
        let deleted = try deletionIds()
        return try withDatabase { database in
            let query = try statement(database, "WITH RECURSIVE seeds(id) AS (SELECT ? UNION SELECT ? WHERE ? != ''), linked(id) AS (SELECT id FROM seeds UNION SELECT r.event_id FROM thread_refs r JOIN linked l ON r.target = l.id), related(id) AS (SELECT id FROM linked UNION SELECT r.event_id FROM detail_refs r JOIN seeds s ON r.target = s.id) SELECT e.json, EXISTS (SELECT 1 FROM linked l WHERE l.id = e.id) FROM events e JOIN related r ON e.id = r.id WHERE e.id != ? AND e.id > ? ORDER BY e.id LIMIT 200")
            defer { sqlite3_finalize(query) }
            bind(id, at: 1, to: query)
            bind(coordinate ?? "", at: 2, to: query)
            bind(coordinate ?? "", at: 3, to: query)
            bind(id, at: 4, to: query)
            bind(cursor, at: 5, to: query)
            var events: [YearReviewEvent] = []
            var last = cursor
            var replyIds = Set<String>()
            var status = sqlite3_step(query)
            while status == SQLITE_ROW {
                let event = try JSONDecoder().decode(YearReviewEvent.self, from: Data(text(query, 0).utf8))
                last = event.id
                if !deleted.contains(event.id) {
                    events.append(event)
                    if sqlite3_column_int(query, 1) != 0 { replyIds.insert(event.id) }
                }
                status = sqlite3_step(query)
            }
            guard status == SQLITE_DONE else { throw YearReviewError.database("detail page") }
            return YearReviewDetailPage(cursor: last, events: events, replyIds: replyIds)
        }
    }

    /// One query per sync pass, avoiding opening SQLite for every completed file.
    func syncBatchKeys(prefix: String) throws -> Set<String> {
        try withDatabase { database in
            let query = try statement(database, "SELECT key FROM metadata WHERE substr(key, 1, length(?)) = ?")
            defer { sqlite3_finalize(query) }
            bind(prefix, at: 1, to: query)
            bind(prefix, at: 2, to: query)
            var result = Set<String>()
            var status = sqlite3_step(query)
            while status == SQLITE_ROW {
                result.insert(text(query, 0))
                status = sqlite3_step(query)
            }
            guard status == SQLITE_DONE else { throw YearReviewError.database("sync batch keys") }
            return result
        }
    }

    /// Bounded incremental export; downloaded batches never enter this outbox.
    func syncPage(after cursor: Int64) throws -> (cursor: Int64, events: [YearReviewEvent]) {
        try withDatabase { database in
            let query = try statement(database, "SELECT o.sequence, e.json FROM sync_outbox o JOIN events e ON e.id = o.event_id WHERE o.sequence > ? ORDER BY o.sequence LIMIT 200")
            defer { sqlite3_finalize(query) }
            sqlite3_bind_int64(query, 1, cursor)
            var last = cursor
            var events: [YearReviewEvent] = []
            var bytes = 0
            var status = sqlite3_step(query)
            while status == SQLITE_ROW {
                let json = text(query, 1)
                if !events.isEmpty && bytes + json.utf8.count > 2_000_000 { break }
                last = sqlite3_column_int64(query, 0)
                events.append(try JSONDecoder().decode(YearReviewEvent.self, from: Data(json.utf8)))
                bytes += json.utf8.count
                status = sqlite3_step(query)
            }
            guard status == SQLITE_DONE || status == SQLITE_ROW else { throw YearReviewError.database("sync page") }
            return (last, events)
        }
    }

    func event(id: String) throws -> YearReviewEvent? {
        try withDatabase { database in
            let query = try statement(database, "SELECT json FROM events WHERE id = ?")
            defer { sqlite3_finalize(query) }
            bind(id, at: 1, to: query)
            let status = sqlite3_step(query)
            if status == SQLITE_DONE { return nil }
            guard status == SQLITE_ROW else { throw YearReviewError.database("read") }
            return try JSONDecoder().decode(YearReviewEvent.self, from: Data(text(query, 0).utf8))
        }
    }

    /// All verified positive reaction events currently known for this exact post.
    func reactionCount(to id: String, blocked: Set<String>) async throws -> Int {
        try await ensureThreadIndex()
        let deleted = try deletionIds()
        let coordinate = try event(id: id)?.coordinate
        return try withDatabase { database in
            let query = try statement(database, "SELECT DISTINCT e.json FROM events e JOIN detail_refs r ON r.event_id = e.id WHERE e.kind = 7 AND (r.target = ? OR r.target = ?)")
            defer { sqlite3_finalize(query) }
            bind(id, at: 1, to: query)
            bind(coordinate ?? "", at: 2, to: query)
            var count = 0
            var status = sqlite3_step(query)
            while status == SQLITE_ROW {
                let event = try JSONDecoder().decode(YearReviewEvent.self, from: Data(text(query, 0).utf8))
                if event.content != "-", (event.tagValues("e").last == id || event.tagValues("e").isEmpty && coordinate != nil && event.tagValues("a").last == coordinate),
                   !blocked.contains(event.pubkey), !deleted.contains(event.id),
                   !event.tagValues("k").contains(where: { ["4", "14", "15"].contains($0) }) { count += 1 }
                status = sqlite3_step(query)
            }
            guard status == SQLITE_DONE else { throw YearReviewError.database("reaction count") }
            return count
        }
    }

    /// Retrieve only support for the opened post, never hydrate the whole archive.
    func reactions(to id: String, limit: Int = 500) throws -> [YearReviewEvent] {
        try withDatabase { database in
            let query = try statement(database, "SELECT json FROM events WHERE kind = 7 AND EXISTS (SELECT 1 FROM json_each(events.json, '$.tags') WHERE json_extract(value, '$[0]') = 'e' AND json_extract(value, '$[1]') = ?) ORDER BY created_at DESC, id LIMIT ?")
            defer { sqlite3_finalize(query) }
            bind(id, at: 1, to: query)
            sqlite3_bind_int(query, 2, Int32(max(1, min(limit, 500))))
            let deleted = try deletionIds()
            var result: [YearReviewEvent] = []
            var status = sqlite3_step(query)
            while status == SQLITE_ROW {
                try Task.checkCancellation()
                let event = try JSONDecoder().decode(YearReviewEvent.self, from: Data(text(query, 0).utf8))
                if event.tagValues("e").last == id && !deleted.contains(event.id) { result.append(event) }
                status = sqlite3_step(query)
            }
            guard status == SQLITE_DONE else { throw YearReviewError.database("read reactions") }
            return result
        }
    }

    func events(before end: Int64, textNotesOnly: Bool = false) throws -> [YearReviewEvent] {
        try withDatabase { database in
            let restriction = textNotesOnly ? " AND kind IN (1,5)" : ""
            let request = try statement(database, "SELECT json FROM events WHERE created_at < ?" + restriction + " ORDER BY created_at, id")
            defer { sqlite3_finalize(request) }
            sqlite3_bind_int64(request, 1, end)
            var events: [YearReviewEvent] = []
            var status = sqlite3_step(request)
            while status == SQLITE_ROW {
                try Task.checkCancellation()
                let event = try JSONDecoder().decode(YearReviewEvent.self, from: Data(text(request, 0).utf8))
                events.append(event)
                status = sqlite3_step(request)
            }
            guard status == SQLITE_DONE else { throw YearReviewError.database("read") }
            return events
        }
    }

    private func scan(before end: Int64, visit: (YearReviewEvent) -> Void) throws {
        try withDatabase { database in try scan(database: database, before: end, visit: visit) }
    }

    private func scan(database: OpaquePointer, before end: Int64, visit: (YearReviewEvent) -> Void) throws {
        let query = try statement(database, "SELECT json FROM events WHERE created_at < ? ORDER BY created_at, id")
        defer { sqlite3_finalize(query) }
        sqlite3_bind_int64(query, 1, end)
        var status = sqlite3_step(query)
        while status == SQLITE_ROW {
            try Task.checkCancellation()
            try autoreleasepool {
                visit(try JSONDecoder().decode(YearReviewEvent.self, from: Data(text(query, 0).utf8)))
            }
            status = sqlite3_step(query)
        }
        guard status == SQLITE_DONE else { throw YearReviewError.database("scan") }
    }

    func report(owner: String, period: YearReviewPeriod, trusted: Set<String>, blocked: Set<String>,
                zapperKeys: [String: Set<String>] = [:]) throws -> YearReviewReport {
        let deleted = try deletionIds()
        return try withDatabase { database in
            try execute(database, "BEGIN")
            do {
                let report = try YearReviewAnalyzer.analyze(scan: { try scan(database: database, before: Int64.max, visit: $0) },
                    owner: owner, period: period, trusted: trusted, blocked: blocked, locallyDeleted: deleted, zapperKeys: zapperKeys,
                    verifiedZap: { receipt in
                        // A derived cache failure must never change receipt eligibility.
                        do { return try self.verifiedZap(receipt, authorized: zapperKeys, database: database) }
                        catch { return YearReviewZap.validate(receipt, authorized: zapperKeys) }
                    })
                try execute(database, "COMMIT")
                return report
            } catch {
                try? execute(database, "ROLLBACK")
                throw error
            }
        }
    }

    private func verifiedZap(_ receipt: YearReviewEvent, authorized: [String: Set<String>], database: OpaquePointer) throws -> YearReviewZap? {
        let query = try statement(database, "SELECT json FROM verified_zaps WHERE receipt_id = ? AND version = ?")
        defer { sqlite3_finalize(query) }
        bind(receipt.id, at: 1, to: query)
        sqlite3_bind_int(query, 2, Int32(YearReviewZap.validationVersion))
        let status = sqlite3_step(query)
        if status == SQLITE_ROW,
           let cached = try? JSONDecoder().decode(YearReviewZap.self, from: Data(text(query, 0).utf8)) { return cached }
        guard status == SQLITE_ROW || status == SQLITE_DONE else { throw YearReviewError.database("zap cache") }
        guard let validated = YearReviewZap.validate(receipt, authorized: authorized) else { return nil }
        let insert = try statement(database, "INSERT OR REPLACE INTO verified_zaps(receipt_id, version, json) VALUES (?, ?, ?)")
        defer { sqlite3_finalize(insert) }
        bind(receipt.id, at: 1, to: insert)
        sqlite3_bind_int(insert, 2, Int32(YearReviewZap.validationVersion))
        bind(String(decoding: try JSONEncoder().encode(validated), as: UTF8.self), at: 3, to: insert)
        guard sqlite3_step(insert) == SQLITE_DONE else { throw YearReviewError.database("zap cache save") }
        return validated
    }

    func zapSigners(period: YearReviewPeriod) throws -> [String: Set<String>] {
        let deleted = try deletionIds()
        return try withDatabase { database in
            let query = try statement(database, "SELECT e.json, z.json FROM events e LEFT JOIN verified_zaps z ON z.receipt_id = e.id AND z.version = ? WHERE e.kind = 9735 AND e.created_at >= ? AND e.created_at < ?")
            defer { sqlite3_finalize(query) }
            sqlite3_bind_int(query, 1, Int32(YearReviewZap.validationVersion))
            sqlite3_bind_int64(query, 2, period.start); sqlite3_bind_int64(query, 3, period.end)
            var result: [String: Set<String>] = [:]
            var status = sqlite3_step(query)
            while status == SQLITE_ROW {
                try Task.checkCancellation()
                if (try? JSONDecoder().decode(YearReviewZap.self, from: Data(text(query, 1).utf8))) != nil {
                    status = sqlite3_step(query)
                    continue
                }
                let event = try JSONDecoder().decode(YearReviewEvent.self, from: Data(text(query, 0).utf8))
                if deleted.contains(event.id) { status = sqlite3_step(query); continue }
                if let recipient = event.tagValues("p").first, YearReviewEvent.isHex(recipient, length: 64) { result[recipient, default: []].insert(event.pubkey) }
                status = sqlite3_step(query)
            }
            guard status == SQLITE_DONE else { throw YearReviewError.database("signers") }
            return result
        }
    }

    func recordLocalDeletions(_ ids: Set<String>) throws {
        guard !ids.isEmpty else { return }
        let existing = try load(Set<String>.self, key: "local-deletions") ?? []
        try save(existing.union(ids), key: "local-deletions")
    }

    func inventory(owner: String, period: YearReviewPeriod) throws -> YearReviewInventory {
        let deleted = try deletionIds()
        var known = Set<String>()
        var own = Set<String>()
        var coordinates = Set<String>()
        var missing = Set<String>()
        var outgoing = Set<String>()
        var count = 0
        try scan(before: period.end) { event in
            count += 1
            known.insert(event.id)
            if let address = event.coordinate { known.insert(address) }
            guard !deleted.contains(event.id) else { return }
            if YearReviewKinds.content.contains(event.kind), period.contains(event.createdAt) {
                if event.pubkey == owner {
                    own.insert(event.id)
                    if let address = event.coordinate { coordinates.insert(address) }
                }
                if let parent = event.parentId,
                   YearReviewEvent.isHex(parent, length: 64) || YearReviewEvent.isCoordinate(parent) { missing.insert(parent) }
            }
            if [6, 7, 16].contains(event.kind), event.pubkey == owner, period.contains(event.createdAt) {
                outgoing.formUnion((event.tagValues("e") + event.tagValues("a")).filter { YearReviewEvent.isHex($0, length: 64) || YearReviewEvent.isCoordinate($0) })
            }
        }
        return YearReviewInventory(count: count, ownPostIds: own.sorted(),
            missingParentIds: missing.union(outgoing).subtracting(known).sorted(),
            ownCoordinates: coordinates.sorted(), outgoingTargets: outgoing.sorted())
    }

    private func deletionIds() throws -> Set<String> {
        var deleted = try load(Set<String>.self, key: "local-deletions") ?? []
        // Deletions learned after a report year still suppress that year's content.
        try withDatabase { database in
            let request = try statement(database, "SELECT json FROM events WHERE kind = 5")
            let author = try statement(database, "SELECT pubkey FROM events WHERE id = ?")
            defer { sqlite3_finalize(request); sqlite3_finalize(author) }
            var status = sqlite3_step(request)
            while status == SQLITE_ROW {
                let deletion = try JSONDecoder().decode(YearReviewEvent.self, from: Data(text(request, 0).utf8))
                for id in deletion.tagValues("e") {
                    sqlite3_reset(author)
                    bind(id, at: 1, to: author)
                    if sqlite3_step(author) == SQLITE_ROW && text(author, 0) == deletion.pubkey { deleted.insert(id) }
                }
                for address in deletion.tagValues("a") {
                    let parts = address.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
                    guard parts.count == 3, String(parts[1]) == deletion.pubkey, let kind = Int32(parts[0]) else { continue }
                    let versions = try statement(database, "SELECT id, json FROM events WHERE pubkey = ? AND kind = ? AND created_at <= ?")
                    defer { sqlite3_finalize(versions) }
                    bind(deletion.pubkey, at: 1, to: versions)
                    sqlite3_bind_int(versions, 2, kind)
                    sqlite3_bind_int64(versions, 3, deletion.createdAt)
                    var versionStatus = sqlite3_step(versions)
                    while versionStatus == SQLITE_ROW {
                        let event = try JSONDecoder().decode(YearReviewEvent.self, from: Data(text(versions, 1).utf8))
                        if event.coordinate == address { deleted.insert(event.id) }
                        versionStatus = sqlite3_step(versions)
                    }
                    guard versionStatus == SQLITE_DONE else { throw YearReviewError.database("versions") }
                }
                status = sqlite3_step(request)
            }
            guard status == SQLITE_DONE else { throw YearReviewError.database("deletions") }
        }
        return deleted
    }

    func save<T: Encodable & Sendable>(_ value: T, key: String) throws {
        let data = try JSONEncoder().encode(value)
        try withDatabase { database in
            let request = try statement(database, "INSERT OR REPLACE INTO metadata(key, json) VALUES (?, ?)")
            defer { sqlite3_finalize(request) }
            bind(key, at: 1, to: request)
            bind(String(decoding: data, as: UTF8.self), at: 2, to: request)
            guard sqlite3_step(request) == SQLITE_DONE else { throw YearReviewError.database("save") }
        }
    }

    func load<T: Decodable & Sendable>(_ type: T.Type, key: String) throws -> T? {
        try withDatabase { database in
            let request = try statement(database, "SELECT json FROM metadata WHERE key = ?")
            defer { sqlite3_finalize(request) }
            bind(key, at: 1, to: request)
            let status = sqlite3_step(request)
            if status == SQLITE_DONE { return nil }
            guard status == SQLITE_ROW else { throw YearReviewError.database("load") }
            return try JSONDecoder().decode(type, from: Data(text(request, 0).utf8))
        }
    }

    func export() throws -> URL {
        let deleted = try deletionIds()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("YearReviewExports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(UUID().uuidString + ".jsonl")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        do {
            try withDatabase { database in
                let request = try statement(database, "SELECT json, id FROM events ORDER BY created_at, id")
                defer { sqlite3_finalize(request) }
                var status = sqlite3_step(request)
                while status == SQLITE_ROW {
                    try Task.checkCancellation()
                    if !deleted.contains(text(request, 1)) {
                        try handle.write(contentsOf: Data((text(request, 0) + "\n").utf8))
                    }
                    status = sqlite3_step(request)
                }
                guard status == SQLITE_DONE else { throw YearReviewError.database("export") }
            }
            exportURLs.insert(url)
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func storageBytes() throws -> Int64 {
        var total: Int64 = 0
        for suffix in ["", "-journal", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: fileURL.path + suffix)
            if FileManager.default.fileExists(atPath: url.path) {
                total += Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            }
        }
        return total
    }

    func delete() throws {
        statistics = nil
        for suffix in ["", "-journal", "-wal", "-shm"] {
            let path = fileURL.path + suffix
            if FileManager.default.fileExists(atPath: path) { try FileManager.default.removeItem(atPath: path) }
        }
        for url in exportURLs { try? FileManager.default.removeItem(at: url) }
        exportURLs.removeAll()
    }
}
