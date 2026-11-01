import Foundation

/// Signed poll events kept outside the feed database and This Year in Nostr.
/// Our own polls and votes stay here, plus result votes fetched for our polls.
actor PollArchive {
    static let shared = PollArchive()
    static let maximumEvents = 20_000
    static let maximumBytes = 32_000_000

    private struct Record: Codable, Equatable {
        var id: String
        var kind: Int
        var pubkey: String
        var pollID: String
        var json: String
    }

    private let root: URL
    private let maximumEvents: Int
    private let maximumBytes: Int
    private var cache: [String: [String: Record]] = [:]
    private var loaded = Set<String>()

    init(root: URL? = nil, maximumEvents: Int = PollArchive.maximumEvents, maximumBytes: Int = PollArchive.maximumBytes) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PollArchive", isDirectory: true)
        self.maximumEvents = maximumEvents
        self.maximumBytes = maximumBytes
    }

    /// Keeps a poll we just signed, or a vote we just signed. Returns before the file is written.
    nonisolated static func remember(_ event: NEvent) {
        guard event.kind == .poll || event.kind == .pollResponse else { return }
        let json = event.eventJson()
        let owner = event.publicKey
        Task { await PollArchive.shared.save(owner: owner, json: json) }
    }

    @discardableResult
    func save(owner: String, json: String) -> Bool {
        guard let record = Self.verified(json: json, owner: owner, allowingOtherVoters: false) else { return false }
        return store(record, owner: owner, allowWhenFull: true)
    }

    /// Verified votes cast on one of our polls, including votes by other people.
    @discardableResult
    func saveResults(owner: String, pollID: String, jsons: [String]) -> Int {
        var saved = Set<String>()
        for json in jsons {
            guard let record = Self.verified(json: json, owner: owner, allowingOtherVoters: true),
                  record.kind == 1018, record.pollID == pollID,
                  store(record, owner: owner, allowWhenFull: record.pubkey == owner) else { continue }
            saved.insert(record.id)
        }
        return saved.count
    }

    func votes(owner: String, pollID: String) -> [PollVote] {
        load(owner)
        return cache[owner, default: [:]].values.compactMap { record in
            guard record.kind == 1018, record.pollID == pollID,
                  let event = Self.event(record.json) else { return nil }
            return PollVote(event: event)
        }
    }

    private func store(_ record: Record, owner: String, allowWhenFull: Bool) -> Bool {
        guard Self.isPubkey(owner) else { return false }
        load(owner)
        if cache[owner]?[record.id] != nil { return true }
        let count = cache[owner, default: [:]].count
        let url = fileURL(owner)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if !allowWhenFull && (count >= maximumEvents || bytes >= maximumBytes) { return false }
        if bytes >= maximumBytes * 2 { return false }
        guard let line = try? JSONEncoder().encode(record) else { return false }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let isNew = !FileManager.default.fileExists(atPath: url.path)
            if isNew {
                try (line + Data([0x0A])).write(to: url, options: .atomic)
                #if os(iOS)
                try? FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: url.path)
                #endif
            } else {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line + Data([0x0A]))
            }
        } catch {
            return false
        }
        cache[owner, default: [:]][record.id] = record
        return true
    }

    private func load(_ owner: String) {
        guard Self.isPubkey(owner), loaded.insert(owner).inserted else { return }
        guard let text = try? String(contentsOf: fileURL(owner), encoding: .utf8) else {
            cache[owner] = cache[owner] ?? [:]
            return
        }
        var records: [String: Record] = cache[owner] ?? [:]
        for line in text.split(separator: "\n") where !line.isEmpty {
            guard let stored = try? JSONDecoder().decode(Record.self, from: Data(line.utf8)),
                  let record = Self.verified(json: stored.json, owner: owner, allowingOtherVoters: true),
                  record.id == stored.id else { continue }
            records[record.id] = record
        }
        cache[owner] = records
    }

    private func fileURL(_ owner: String) -> URL {
        root.appendingPathComponent(owner + ".jsonl")
    }

    private static func verified(json: String, owner: String, allowingOtherVoters: Bool) -> Record? {
        guard Self.isPubkey(owner), let event = event(json),
              (try? event.verified(logInvalidID: false)) == true else { return nil }
        let kind = event.kind.id
        if kind == 1068 {
            guard event.publicKey == owner else { return nil }
            return Record(id: event.id, kind: kind, pubkey: event.publicKey, pollID: event.id, json: json)
        }
        guard kind == 1018, allowingOtherVoters || event.publicKey == owner,
              let pollID = event.tags.first(where: { $0.type == "e" })?.value, Self.isEventID(pollID) else { return nil }
        return Record(id: event.id, kind: kind, pubkey: event.publicKey, pollID: pollID, json: json)
    }

    private static func event(_ json: String) -> NEvent? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NEvent.self, from: data)
    }

    private static func isPubkey(_ value: String) -> Bool { isEventID(value) }

    private static func isEventID(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
