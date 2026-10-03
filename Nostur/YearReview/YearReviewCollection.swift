import Foundation
import CoreData
import NostrEssentials

struct YearReviewWork: Codable, Equatable, Sendable {
    enum Category: String, Codable, Sendable { case authored, incoming, references, parents, outgoing, rootIncoming, quoteReferences, addressReferences, outgoingZaps, supportIncoming }
    let relay: String
    let category: Category
    let since: Int64
    let until: Int64
    var ids: [String] = []
    var kinds: [Int]? = nil

    func filter(owner: String) -> [String: Any] {
        var result: [String: Any] = ["limit": 500]
        if category != .parents { result["since"] = since; result["until"] = until }
        switch category {
        case .authored: result["authors"] = [owner]; result["kinds"] = kinds ?? Array(YearReviewKinds.archived).sorted()
        case .incoming: result["#p"] = [owner]; result["kinds"] = kinds ?? Array(YearReviewKinds.content.union(YearReviewKinds.support)).sorted()
        case .supportIncoming: result["#p"] = [owner]; result["kinds"] = kinds ?? [6, 7, 16, 9735]
        case .rootIncoming: result["#P"] = [owner]; result["kinds"] = kinds ?? [1111, 1244]
        case .outgoing: result["authors"] = [owner]; result["kinds"] = kinds ?? [6, 7, 16]
        case .outgoingZaps: result["#P"] = [owner]; result["kinds"] = [9735]
        case .references: result["#e"] = ids; result["kinds"] = kinds ?? Array(YearReviewKinds.content.union(YearReviewKinds.support)).sorted()
        case .quoteReferences: result["#q"] = ids; result["kinds"] = Array(YearReviewKinds.content).sorted()
        case .addressReferences: result["#a"] = ids; result["kinds"] = Array(YearReviewKinds.content.union(YearReviewKinds.support)).sorted()
        case .parents:
            if ids.allSatisfy({ YearReviewEvent.isHex($0, length: 64) }) { result["ids"] = ids }
            else {
                let parts = ids.first?.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false) ?? []
                if parts.count == 3, ids.first.map(YearReviewEvent.isCoordinate) == true { result["authors"] = [String(parts[1])]; result["kinds"] = [Int(parts[0]) ?? 0]; result["#d"] = [String(parts[2])] }
                else { result["ids"] = [String(repeating: "0", count: 64)] }
            }
        }
        return result
    }

    func accepts(_ event: YearReviewEvent, owner: String) -> Bool {
        if category != .parents && (event.createdAt < since || event.createdAt > until) { return false }
        if let kinds, !kinds.contains(event.kind) { return false }
        switch category {
        case .authored: return event.pubkey == owner && YearReviewKinds.archived.contains(event.kind)
        case .incoming: return YearReviewKinds.content.union(YearReviewKinds.support).contains(event.kind) && event.tagValues("p").contains(owner)
        case .supportIncoming: return YearReviewKinds.support.contains(event.kind) && event.tagValues("p").contains(owner)
        case .rootIncoming: return [1111, 1244].contains(event.kind) && event.tagValues("P").contains(owner)
        case .outgoing: return event.pubkey == owner && [6, 7, 16].contains(event.kind)
        case .outgoingZaps: return event.kind == 9735 && event.tagValues("P").contains(owner)
        case .references: return YearReviewKinds.archived.contains(event.kind) && !Set(event.tagValues("e")).isDisjoint(with: ids)
        case .quoteReferences: return YearReviewKinds.content.contains(event.kind) && !Set(event.tagValues("q")).isDisjoint(with: ids)
        case .addressReferences: return YearReviewKinds.archived.contains(event.kind) && !Set(event.tagValues("a")).isDisjoint(with: ids)
        case .parents: return YearReviewKinds.content.contains(event.kind) && (ids.contains(event.id) || event.coordinate.map { ids.contains($0) } == true)
        }
    }

    /// Walk backward even when the relay silently imposes a smaller page cap.
    /// Probe the oldest second separately so equal timestamps are never skipped.
    func continuation(events: [YearReviewEvent], exhaustive: Bool) -> [Self] {
        guard category != .parents, !exhaustive,
              let oldest = events.map(\.createdAt).min(), oldest >= since, oldest <= until else { return [] }
        if since == until { return [] }
        var next = [Self(relay: relay, category: category, since: oldest, until: oldest, ids: ids, kinds: kinds)]
        if oldest > since { next.append(Self(relay: relay, category: category, since: since, until: oldest - 1, ids: ids, kinds: kinds)) }
        return next
    }

    /// A short response finishes its bucket; capped responses split without gaps.
    func adaptiveSubdivisions(timeZoneIdentifier: String) -> [Self] {
        guard category != .parents, until > since else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let duration = until - since + 1
        let days = duration > 7 * 86_400 ? 7 : duration > 86_400 ? 1 : 0
        guard days > 0 else { return subdivisions }
        var result: [Self] = []
        var start = since
        while start <= until {
            guard let next = calendar.date(byAdding: .day, value: days,
                to: Date(timeIntervalSince1970: Double(start))) else { return subdivisions }
            let end = min(until, Int64(next.timeIntervalSince1970) - 1)
            guard end >= start else { return subdivisions }
            result.append(Self(relay: relay, category: category, since: start, until: end, ids: ids, kinds: kinds))
            start = end + 1
        }
        return result.count > 1 ? result : subdivisions
    }

    /// Split inclusive ranges without losing events with identical timestamps.
    /// A capped one-second range cannot be safely advanced and is reported partial.
    var subdivisions: [Self] {
        guard category != .parents, until > since else { return [] }
        let middle = since + (until - since) / 2
        return [Self(relay: relay, category: category, since: since, until: middle, ids: ids, kinds: kinds),
                Self(relay: relay, category: category, since: middle + 1, until: until, ids: ids, kinds: kinds)]
    }
}

@available(iOS 17.0, *)
struct YearReviewActivity: Equatable, Sendable {
    enum Step: Equatable, Sendable {
        case pacing, relayInfo, fetching, saving
        var label: LocalizedStringResource {
            switch self {
            case .pacing: "Waiting for the relay pacing interval"
            case .relayInfo: "Checking relay limits"
            case .fetching: "Waiting for relay response"
            case .saving: "Verifying and saving response"
            }
        }
    }
    let work: YearReviewWork
    let timeZoneIdentifier: String
    var step: Step
    var received = 0
    var startedAt: Date = .now

    var monthName: String {
        var style = Date.FormatStyle.dateTime.month(.wide).year()
        style.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return Date(timeIntervalSince1970: Double(work.until)).formatted(style)
    }

    var dateRange: String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        style.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let start = Date(timeIntervalSince1970: Double(work.since)).formatted(style)
        let end = Date(timeIntervalSince1970: Double(work.until)).formatted(style)
        return start == end ? start : "\(start) – \(end)"
    }
}

struct YearReviewMonthProgress: Identifiable, Equatable, Sendable {
    struct Pass: Equatable, Sendable {
        var completed = 0
        var pending = 0
        var failed = 0
        var failedRelays: [String] = []
        var active = false
        var finished: Bool { pending == 0 && failed == 0 }
        var fraction: Double { Double(completed) / Double(max(1, completed + pending + failed)) }
    }
    let month: Int
    let date: Date
    let timeZoneIdentifier: String
    let available: Bool
    var received = 0
    var own: Pass
    var others: Pass
    var id: Int { month }
}

struct YearReviewCollection: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable { case primary, references, parents, finished }
    let schemaVersion: Int
    let owner: String
    let period: YearReviewPeriod
    let relays: [RelayDataSnapshot]
    let trusted: Set<String>
    var pending: [YearReviewWork]
    var failed: [YearReviewWork] = []
    var phase: Phase = .primary
    var requestsChecked = 0
    var referenceQueriesChecked: Int? = nil
    var monthlyQueries: [String: Int]? = nil
    var monthlyReceived: [String: Int]? = nil
    var estimatedResponses = 0
    var invalidEvents = 0
    var issues: [String] = []
    var parentsLimited = false
    var pacing: YearReviewRelayPacing? = nil

    init(owner: String, period: YearReviewPeriod, relays: [RelayData], trusted: Set<String>) {
        schemaVersion = 3
        self.owner = owner
        self.period = period
        self.relays = relays.map { RelayDataSnapshot(url: $0.url, auth: $0.auth) }
        self.trusted = trusted
        let windows = Self.monthWindows(period: period).reversed()
        // Finish all authored months before gathering incoming activity.
        self.pending = []
        for authored in [true, false] {
            for window in windows {
                for relay in relays {
                    let categories: [YearReviewWork.Category] = authored ? [.authored] : [.incoming, .rootIncoming, .outgoingZaps]
                    for category in categories {
                        self.pending.append(YearReviewWork(relay: relay.url, category: category,
                            since: window.since, until: window.until,
                            kinds: category == .authored ? Array(YearReviewKinds.archived).sorted() : nil))
                    }
                }
            }
        }
    }

    static func monthWindows(period: YearReviewPeriod) -> [(since: Int64, until: Int64)] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: period.timeZoneIdentifier) ?? .current
        var start = period.start
        var windows: [(since: Int64, until: Int64)] = []
        while start < period.end {
            guard let next = calendar.date(byAdding: .month, value: 1,
                to: Date(timeIntervalSince1970: Double(start))) else { break }
            let end = min(period.end, Int64(next.timeIntervalSince1970))
            guard end > start else { break }
            windows.append((start, end - 1))
            start = end
        }
        return windows
    }

    /// Keep a month/pass together, with at most one request per relay.
    func nextBatch(excluding unavailable: Set<String>, maximum: Int = 20, now: Date = .now) -> [YearReviewWork] {
        guard let first = pending.first(where: { !unavailable.contains($0.relay) }) else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: period.timeZoneIdentifier) ?? .current
        let month = calendar.dateComponents([.year, .month], from: Date(timeIntervalSince1970: Double(first.until)))
        let authored = first.category == .authored
        var relays = Set<String>()
        let currentPacing = pacing ?? YearReviewRelayPacing()
        let candidates = pending.filter {
            !unavailable.contains($0.relay) && ($0.category == .authored) == authored &&
            calendar.dateComponents([.year, .month], from: Date(timeIntervalSince1970: Double($0.until))) == month
        }
        var selected: [YearReviewWork] = []
        for work in candidates where currentPacing.delay(for: work.relay, now: now) == 0 {
            if relays.insert(work.relay).inserted { selected.append(work) }
            if selected.count == maximum { break }
        }
        return selected.isEmpty ? [first] : selected
    }

    func nextWork(for relay: String, inMonthOf anchor: YearReviewWork) -> YearReviewWork? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: period.timeZoneIdentifier) ?? .current
        let month = calendar.dateComponents([.year, .month], from: Date(timeIntervalSince1970: Double(anchor.until)))
        return pending.first {
            $0.relay == relay && ($0.category == .authored) == (anchor.category == .authored) &&
            calendar.dateComponents([.year, .month], from: Date(timeIntervalSince1970: Double($0.until))) == month
        }
    }

    static func canContinueSupplementaryWork(phase: Phase, startedAt: Date, now: Date = .now) -> Bool {
        let limit: TimeInterval
        switch phase {
        case .references: limit = 60
        case .parents: limit = 30
        case .primary, .finished: return true
        }
        return now.timeIntervalSince(startedAt) < limit
    }

    static func isPrimary(_ category: YearReviewWork.Category) -> Bool {
        [.authored, .incoming, .rootIncoming, .outgoingZaps, .supportIncoming, .outgoing].contains(category)
    }

    mutating func recordMonthlyQuery(_ work: YearReviewWork) {
        guard Self.isPrimary(work.category) else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: period.timeZoneIdentifier) ?? .current
        let month = calendar.component(.month, from: Date(timeIntervalSince1970: Double(work.until)))
        let key = "\(month)-\(work.category == .authored ? "own" : "others")"
        if monthlyQueries == nil { monthlyQueries = [:] }
        monthlyQueries?[key, default: 0] += 1
    }

    /// Raw response traffic, including duplicate and subsequently rejected events.
    mutating func recordMonthlyReceived(_ work: YearReviewWork, count: Int) {
        guard Self.isPrimary(work.category), count > 0 else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: period.timeZoneIdentifier) ?? .current
        let month = calendar.component(.month, from: Date(timeIntervalSince1970: Double(work.until)))
        if monthlyReceived == nil { monthlyReceived = [:] }
        monthlyReceived?[String(month), default: 0] += count
    }

    /// Calendar activity covers the whole month operation, including checkpoint
    /// writes and request handoffs, rather than only live relay subscriptions.
    func calendarActivity(active: [YearReviewWork], running: Bool) -> [YearReviewWork] {
        guard running, phase == .primary else { return [] }
        let current = active.filter { Self.isPrimary($0.category) }
        if !current.isEmpty { return current }
        return pending.first(where: { Self.isPrimary($0.category) }).map { [$0] } ?? []
    }

    func monthProgress(active: [YearReviewWork], received: [(YearReviewWork, Int)] = []) -> [YearReviewMonthProgress] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: period.timeZoneIdentifier) ?? .current
        var months = (1...12).map { month in
            YearReviewMonthProgress(month: month,
                date: calendar.date(from: DateComponents(year: period.year, month: month, day: 1))!,
                timeZoneIdentifier: period.timeZoneIdentifier,
                available: calendar.date(from: DateComponents(year: period.year, month: month, day: 1))!.timeIntervalSince1970 < Double(period.end)
                    && calendar.date(from: DateComponents(year: period.year, month: month + 1, day: 1))!.timeIntervalSince1970 > Double(period.start),
                received: monthlyReceived?[String(month)] ?? 0,
                own: .init(completed: monthlyQueries?["\(month)-own"] ?? 0),
                others: .init(completed: monthlyQueries?["\(month)-others"] ?? 0))
        }
        for (work, count) in received where Self.isPrimary(work.category) {
            let index = calendar.component(.month, from: Date(timeIntervalSince1970: Double(work.until))) - 1
            if months.indices.contains(index) { months[index].received += count }
        }
        for (works, kind) in [(pending, 0), (failed, 1), (active, 2)] {
            for work in works where Self.isPrimary(work.category) {
                let index = calendar.component(.month, from: Date(timeIntervalSince1970: Double(work.until))) - 1
                guard months.indices.contains(index) else { continue }
                if work.category == .authored {
                    if kind == 0 { months[index].own.pending += 1 }
                    else if kind == 1 {
                        months[index].own.failed += 1
                        if !months[index].own.failedRelays.contains(work.relay) { months[index].own.failedRelays.append(work.relay) }
                    }
                    else { months[index].own.active = true }
                } else {
                    if kind == 0 { months[index].others.pending += 1 }
                    else if kind == 1 {
                        months[index].others.failed += 1
                        if !months[index].others.failedRelays.contains(work.relay) { months[index].others.failedRelays.append(work.relay) }
                    }
                    else { months[index].others.active = true }
                }
            }
        }
        return months
    }

    func readyWorkIndex(excluding unavailable: Set<String>, now: Date = .now) -> Int? {
        let currentPacing = pacing ?? YearReviewRelayPacing()
        return pending.firstIndex { !unavailable.contains($0.relay) && currentPacing.delay(for: $0.relay, now: now) == 0 }
    }

    mutating func recordIssue(_ message: String) {
        if !issues.contains(message) && issues.count < 12 { issues.append(message) }
    }

    struct RelayDataSnapshot: Codable, Equatable, Sendable {
        let url: String
        let auth: Bool
        var relayData: RelayData { .new(url: url, read: true, auth: auth) }
    }
}

/// Reads private-context objects in bounded batches, and returns values only.
enum YearReviewLocalSeed {
    struct Batch: Sendable {
        let events: [YearReviewEvent]
        let deletedIds: Set<String>
        let fetchedCount: Int
    }

    static func batch(owner: String, period: YearReviewPeriod, offset: Int,
                      context: NSManagedObjectContext) async throws -> Batch {
        try await context.perform {
            let request = Event.fetchRequest()
            request.predicate = NSPredicate(format: "kind IN %@ AND created_at >= %lld AND created_at < %lld AND sig != nil AND (pubkey == %@ OR tagsSerialized CONTAINS %@ OR tagsSerialized CONTAINS %@ OR (kind == 9735 AND fromPubkey == %@))",
                                            Array(YearReviewKinds.archived), period.start, period.end, owner, serializedP(owner), "[\"P\",\"" + owner + "\"", owner)
            request.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]
            request.fetchLimit = 200
            request.fetchOffset = offset
            let fetched = try context.fetch(request)
            let values = Batch(events: fetched.filter { $0.deletedById == nil }.map(snapshot),
                               deletedIds: Set(fetched.filter { $0.deletedById != nil }.map(\.id)), fetchedCount: fetched.count)
            context.reset()
            return values
        }
    }

    static func parents(ids: [String], context: NSManagedObjectContext) async throws -> Batch {
        guard !ids.isEmpty else { return Batch(events: [], deletedIds: [], fetchedCount: 0) }
        return try await context.perform {
            let request = Event.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@ AND sig != nil", ids)
            request.fetchLimit = 200
            let fetched = try context.fetch(request)
            let values = Batch(events: fetched.filter { $0.deletedById == nil }.map(snapshot),
                               deletedIds: Set(fetched.filter { $0.deletedById != nil }.map(\.id)), fetchedCount: fetched.count)
            context.reset()
            return values
        }
    }

    /// The regular importer replaces receipt.content with the payer's message.
    /// Recover the NIP-57 empty-content original only when its original signature verifies.
    static func restoreReceipt(_ event: YearReviewEvent) -> YearReviewEvent {
        guard event.kind == 9735, !event.verified() else { return event }
        let original = YearReviewEvent(id: event.id, pubkey: event.pubkey, createdAt: event.createdAt,
            kind: event.kind, tags: event.tags, content: "", sig: event.sig)
        return original.verified() ? original : event
    }

    private static func snapshot(_ event: Event) -> YearReviewEvent {
        restoreReceipt(YearReviewEvent(id: event.id, pubkey: event.pubkey, createdAt: event.created_at,
                        kind: Int(event.kind), tags: event.tags().map { $0.tag },
                        content: event.content ?? "", sig: event.sig ?? ""))
    }
}

struct YearReviewFetchResult: Sendable {
    let work: YearReviewWork
    let limit: Int
    let dispatchedAt: Date
    let result: Result<YearReviewRelayPage, Error>
}


extension YearReviewPostPreview {
    /// Call only inside this private context's perform; return immutable display data.
    static func build(snapshot: YearReviewEvent, context: NSManagedObjectContext) throws -> Self {
        let event = Event.fromNEvent(nEvent: try JSONDecoder().decode(NEvent.self, from: JSONEncoder().encode(snapshot)), context: context)
        let parsed = NRTextParser.shared.copyPasteText(fastTags: event.fastTags, event: event, text: event.content ?? "").text
        let (elements, _, gallery) = NRContentElementBuilder.shared.buildElements(input: event.noteTextPrepared,
            fastTags: event.fastTags, event: event, previewImages: event.previewImages, previewVideos: event.previewVideos, isPreviewContext: true)
        let videos = elements.compactMap { element -> URL? in
            if case .video(let media) = element { return media.url }
            return nil
        }
        let images = gallery.map { $0.url }
        var text = parsed
        for url in images + videos { text = text.replacingOccurrences(of: url.absoluteString, with: "") }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if [30023, 1222, 1244].contains(snapshot.kind) { text = snapshot.preview }
        if text.isEmpty && images.isEmpty && videos.isEmpty { text = snapshot.preview }
        return YearReviewPostPreview(text: text, thumbnail: images.first ?? videos.first,
            extraCount: max(0, images.count + videos.count - 1), isVideo: images.isEmpty)
    }
}
