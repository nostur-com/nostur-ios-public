import Foundation
import NostrEssentials

/// Original public event fields, independent of Core Data and its import transformations.
struct YearReviewEvent: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let pubkey: String
    let createdAt: Int64
    let kind: Int
    let tags: [[String]]
    let content: String
    let sig: String

    enum CodingKeys: String, CodingKey {
        case id, pubkey, kind, tags, content, sig
        case createdAt = "created_at"
    }

    var parentId: String? {
        guard YearReviewKinds.replies.contains(kind) else { return nil }
        if kind == 1111 || kind == 1244 { return tagValues("a").first ?? tagValues("e").first }
        let references = tags.filter { $0.count >= 2 && $0[0] == "e" }
        if let reply = references.first(where: { $0.count >= 4 && $0[3] == "reply" }) {
            return reply[1]
        }
        if let root = references.first(where: { $0.count >= 4 && $0[3] == "root" }) {
            return root[1]
        }
        // Unmarked legacy e-tags encode root first, immediate parent last.
        // Explicit mention tags must never turn a quote into a reply.
        return references.last(where: { $0.count < 4 || $0[3].isEmpty })?[1]
    }

    var rootId: String? {
        guard YearReviewKinds.replies.contains(kind) else { return nil }
        if kind == 1111 || kind == 1244 { return tagValues("A").first ?? tagValues("E").first }
        let references = tags.filter { $0.count >= 2 && $0[0] == "e" }
        if let root = references.first(where: { $0.count >= 4 && $0[3] == "root" }) { return root[1] }
        let legacy = references.filter { $0.count < 4 || $0[3].isEmpty }
        return legacy.count > 1 ? legacy.first?[1] : nil
    }

    var coordinate: String? {
        guard kind >= 30000 && kind < 40000 else { return nil }
        return "\(kind):\(pubkey):\(tagValues("d").first ?? "")"
    }

    var preview: String {
        let title = tagValues("title").first
        if let title, !title.isEmpty { return String(title.prefix(600)) }
        if kind == 1222 || kind == 1244 { return String(localized: "Voice message") }
        if !content.isEmpty { return String(content.prefix(600)) }
        switch kind {
        case 20: return String(localized: "Picture post")
        case 21, 22, 34235, 34236: return String(localized: "Video post")
        case 1222, 1244: return String(localized: "Voice message")
        default: return String(localized: "Public post")
        }
    }

    func tagValues(_ name: String) -> [String] {
        tags.compactMap { $0.count >= 2 && $0[0] == name ? $0[1] : nil }
    }

    func verified() -> Bool {
        guard Self.isHex(id, length: 64), Self.isHex(pubkey, length: 64),
              Self.isHex(sig, length: 128), YearReviewKinds.archived.contains(kind),
              createdAt >= 0, tags.count <= 512, content.utf8.count <= 256_000 else { return false }
        guard let data = try? JSONEncoder().encode(self), data.count <= 512_000,
              let event = try? JSONDecoder().decode(NEvent.self, from: data) else { return false }
        // Cached display transformations and damaged archive entries are expected
        // validation failures. Reject them without emitting one log per event.
        return (try? event.verified(logInvalidID: false)) == true
    }

    static func isCoordinate(_ value: String) -> Bool {
        let parts = value.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, let kind = Int(parts[0]), (30000..<40000).contains(kind),
              isHex(String(parts[1]), length: 64), parts[2].utf8.count <= 1024 else { return false }
        return true
    }

    static func isHex(_ value: String, length: Int) -> Bool {
        value.utf8.count == length && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

struct YearReviewPeriod: Codable, Equatable, Sendable {
    let year: Int
    let timeZoneIdentifier: String
    let start: Int64
    let end: Int64 // Exclusive, including for a year-to-date snapshot.
    let isYearToDate: Bool
    let monthLimit: Int?
    let monthStart: Int?

    static var currentYear: Int { Calendar(identifier: .gregorian).component(.year, from: Date()) }

    static func defaultYear(now: Date = .now) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: now)
        return calendar.component(.month, from: now) == 1 ? year - 1 : year
    }

    init(year: Int, now: Date = .now, timeZone: TimeZone = .current, monthLimit: Int? = nil, monthStart: Int? = nil) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startDate = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        let endDate = calendar.date(byAdding: .year, value: 1, to: startDate)!
        let firstMonth = monthLimit == nil ? 1 : max(1, min(12, monthStart ?? 1))
        let limitedStart = calendar.date(byAdding: .month, value: firstMonth - 1, to: startDate)!
        let limitedEnd = monthLimit.map { min(endDate, calendar.date(byAdding: .month, value: max(1, min(12, $0)), to: limitedStart)!) } ?? endDate
        self.monthLimit = monthLimit
        self.monthStart = monthLimit == nil ? nil : firstMonth
        self.year = year
        timeZoneIdentifier = timeZone.identifier
        start = Int64(limitedStart.timeIntervalSince1970)
        end = max(start, Int64(min(now, limitedEnd).timeIntervalSince1970))
        isYearToDate = now < endDate || limitedEnd < endDate
    }

    static func testMonthStart(year: Int, now: Date = .now, timeZone: TimeZone = .current, choice: Int) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let currentYear = calendar.component(.year, from: now)
        let lastMonth = year < currentYear ? 12 : year == currentYear ? calendar.component(.month, from: now) : 1
        return 1 + max(0, choice) % max(1, lastMonth - 1)
    }

    func contains(_ timestamp: Int64) -> Bool { timestamp >= start && timestamp < end }

    var cutoffDate: Date { Date(timeIntervalSince1970: TimeInterval(max(start, end - 1))) }

    var calendarDays: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let first = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(start)))
        let last = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(max(start, end - 1))))
        return max(1, (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1)
    }

    var monthFormat: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.month(.wide)
        style.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return style
    }

    var dateFormat: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.day().month().year()
        style.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return style
    }
}

struct YearReviewPerson: Identifiable, Equatable, Sendable {
    let pubkey: String
    var sent = 0
    var received = 0
    var mentions = 0
    var interactions = 0
    var reactions = 0
    var reposts = 0
    var quotes = 0
    var zaps = 0
    var millisats: Int64 = 0
    var supportCount: Int { reactions + reposts + zaps }

    var id: String { pubkey }
}

struct YearReviewPostPreview: Equatable, Sendable {
    let text: String
    let thumbnail: URL?
    let extraCount: Int
    let isVideo: Bool
}

struct YearReviewPost: Identifiable, Equatable, Sendable {
    let id: String
    let content: String
    var replies: Int
    var respondents: Int
    var kind = 1
    var coordinate: String? = nil
    var reactions = 0
    var zaps = 0
    var millisats: Int64 = 0
}

struct YearReviewActiveDay: Equatable, Sendable {
    let date: Date
    let posts: Int
}

struct YearReviewReport: Equatable, Sendable {
    let period: YearReviewPeriod
    let gang: [YearReviewPerson]
    let conversation: YearReviewPost?
    let mentionedBy: YearReviewPerson?
    let ownPostCount: Int
    let unresolvedParents: Int
    let excludedAuthors: Int
    var mostActiveDay: YearReviewActiveDay? = nil
    var mostReacted: YearReviewPost? = nil
    var mostZapped: YearReviewPost? = nil
    var mostZapValue: YearReviewPost? = nil
    var mostInteracted: [YearReviewPerson] = []
    var mostTalked: [YearReviewPerson] = []
    var topReplyGuy: YearReviewPerson? = nil
    var supporters: [YearReviewPerson] = []
    var reactedBy: [YearReviewPerson] = []
    var liked: [YearReviewPerson] = []
    var zappedBy: [YearReviewPerson] = []
    var zapped: [YearReviewPerson] = []
    var amplifiedBy: [YearReviewPerson] = []
    var unverifiedZaps = 0
    var anonymousZaps = 0

    var averagePostsPerDay: Double { Double(ownPostCount) / Double(period.calendarDays) }

    var people: Set<String> {
        Set((gang + mostInteracted + mostTalked + supporters + reactedBy + liked + zappedBy + zapped + amplifiedBy
            + [mentionedBy, topReplyGuy].compactMap { $0 }).map(\.pubkey))
    }
}

enum YearReviewAnalyzer {
    struct ContentIndex {
        let pubkey: String
        let parent: String?
        let root: String?
        let createdAt: Int64
        let kind: Int
        let coordinate: String?
        let publishedAt: Int64
        let preview: String
    }

    static func analyze(events: [YearReviewEvent], owner: String, period: YearReviewPeriod,
                        trusted: Set<String>, blocked: Set<String>, locallyDeleted: Set<String> = [],
                        zapperKeys: [String: Set<String>] = [:]) -> YearReviewReport {
        let unique = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return try! analyze(scan: { visit in unique.values.forEach(visit) }, owner: owner, period: period,
                            trusted: trusted, blocked: blocked, locallyDeleted: locallyDeleted, zapperKeys: zapperKeys)
    }

    /// Two streaming passes retain compact content references, never full archive JSON.
    static func analyze(scan: (_ visit: (YearReviewEvent) -> Void) throws -> Void,
                        owner: String, period: YearReviewPeriod, trusted: Set<String>, blocked: Set<String>,
                        locallyDeleted: Set<String>, zapperKeys: [String: Set<String>]) throws -> YearReviewReport {
        var index: [String: ContentIndex] = [:]
        var latest: [String: String] = [:]
        var versions: [String: Set<String>] = [:]
        var deletions: [(String, [String], Int64)] = []
        try scan { event in
            if event.kind == 5 { deletions.append((event.pubkey, event.tagValues("e") + event.tagValues("a"), event.createdAt)); return }
            guard YearReviewKinds.content.contains(event.kind), event.createdAt < period.end else { return }
            index[event.id] = ContentIndex(pubkey: event.pubkey, parent: event.parentId, root: event.rootId, createdAt: event.createdAt,
                kind: event.kind, coordinate: event.coordinate, publishedAt: event.tagValues("published_at").first.flatMap(Int64.init).flatMap { $0 > 0 && $0 <= event.createdAt ? $0 : nil } ?? event.createdAt, preview: event.pubkey == owner ? event.preview : "")
            if let address = event.coordinate {
                versions[address, default: []].insert(event.id)
                if let old = latest[address], let existing = index[old],
                   existing.createdAt > event.createdAt || existing.createdAt == event.createdAt && old < event.id { return }
                latest[address] = event.id
            }
        }
        var deleted = locallyDeleted
        for (author, ids, cutoff) in deletions {
            for id in ids {
                if index[id]?.pubkey == author { deleted.insert(id) }
                for version in versions[id, default: []] {
                    if let item = index[version], item.pubkey == author, item.createdAt <= cutoff { deleted.insert(version) }
                }
            }
        }
        func canonical(_ reference: String) -> String? {
            if let id = latest[reference] { return deleted.contains(id) ? nil : id }
            guard let item = index[reference], !deleted.contains(reference) else { return nil }
            if let address = item.coordinate, let id = latest[address] { return deleted.contains(id) ? nil : id }
            return reference
        }
        var allowed = trusted.union([owner])
        for (id, item) in index where item.pubkey == owner && !deleted.contains(id) {
            if let parent = item.parent.flatMap(canonical).flatMap({ index[$0] }) { allowed.insert(parent.pubkey) }
        }
        allowed.subtract(blocked)
        var people: [String: YearReviewPerson] = [:]
        var liked: [String: YearReviewPerson] = [:]
        var zapped: [String: YearReviewPerson] = [:]
        var posts: [String: YearReviewPost] = [:]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: period.timeZoneIdentifier) ?? .current
        var postingDays: [Date: Int] = [:]
        for (id, item) in index where item.pubkey == owner && period.contains(item.publishedAt) && canonical(id) == id {
            posts[id] = YearReviewPost(id: id, content: item.preview, replies: 0, respondents: 0, kind: item.kind, coordinate: item.coordinate)
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(item.publishedAt)))
            postingDays[day, default: 0] += 1
        }
        var replies: [String: Set<String>] = [:]
        var days: [String: Set<Int64>] = [:]
        var reactions = Set<String>()
        var reposts = Set<String>()
        var payments = Set<String>()
        var excluded = Set<String>()
        var unresolved = 0
        var unverifiedZaps = 0
        var anonymousZaps = 0
        try scan { event in
            guard period.contains(event.createdAt), !deleted.contains(event.id) else { return }
            // The last e-tag is the actual target; earlier tags may only be
            // inherited thread references. Never fall back to an earlier known post.
            let target = (event.tagValues("e").last ?? event.tagValues("a").last).flatMap(canonical)
            if event.kind == 9735 {
                guard let zap = YearReviewZap.validate(event, authorized: zapperKeys) else { unverifiedZaps += 1; return }
                guard payments.insert(zap.paymentHash).inserted, !blocked.contains(zap.recipient) else { return }
                if let sender = zap.sender, blocked.contains(sender) { return }
                let postId = zap.target.flatMap(canonical)
                if zap.recipient == owner {
                    if let postId, let existing = posts[postId], zap.millisats > Int64.max - existing.millisats { unverifiedZaps += 1; return }
                    if let sender = zap.sender, let existing = people[sender], zap.millisats > Int64.max - existing.millisats { unverifiedZaps += 1; return }
                    // A verified paid receipt counts even when its sender is outside WoT.
                    // Blocks and payment/provider validation still apply above.
                    if let sender = zap.sender, sender != owner {
                        people[sender, default: YearReviewPerson(pubkey: sender)].zaps += 1
                        people[sender, default: YearReviewPerson(pubkey: sender)].millisats += zap.millisats
                    } else if zap.sender == nil { anonymousZaps += 1 }
                    if let postId, posts[postId] != nil {
                        posts[postId]!.zaps += 1; posts[postId]!.millisats += zap.millisats
                    }
                } else if zap.sender == owner {
                    if let existing = zapped[zap.recipient], zap.millisats > Int64.max - existing.millisats { unverifiedZaps += 1; return }
                    zapped[zap.recipient, default: YearReviewPerson(pubkey: zap.recipient)].zaps += 1
                    zapped[zap.recipient, default: YearReviewPerson(pubkey: zap.recipient)].millisats += zap.millisats
                }
                return
            }
            guard allowed.contains(event.pubkey) else { excluded.insert(event.pubkey); return }
            if YearReviewKinds.content.contains(event.kind) {
                guard canonical(event.id) == event.id else { return }
                // Content mentions in comments are explicit; inherited threading p/P tags are not.
                if event.pubkey != owner, (event.kind != 1 || event.parentId == nil), mentions(event, pubkey: owner) {
                    people[event.pubkey, default: YearReviewPerson(pubkey: event.pubkey)].mentions += 1
                    days[event.pubkey, default: []].insert(event.createdAt / 86_400)
                }
                let quotes = event.tagValues("q") + event.tags.compactMap { tag -> String? in
                    tag.count >= 4 && tag[0] == "e" && tag[3] == "mention" ? tag[1] : nil
                }
                if event.pubkey != owner && quotes.compactMap(canonical).contains(where: { index[$0]?.pubkey == owner }) {
                    people[event.pubkey, default: YearReviewPerson(pubkey: event.pubkey)].quotes += 1
                }
                // A conversation includes descendants, while relationship cards below
                // continue to count only direct exchanges. Root tags also bridge gaps
                // when a relay has not returned an intermediate parent.
                var pending = [event.parentId, event.rootId].compactMap { $0 }
                var visited: Set<String> = [event.id]
                while let reference = pending.popLast() {
                    guard let ancestorId = canonical(reference), visited.insert(ancestorId).inserted,
                          let ancestor = index[ancestorId] else { continue }
                    if posts[ancestorId] != nil {
                        posts[ancestorId]!.replies += 1
                        replies[ancestorId, default: []].insert(event.pubkey)
                    }
                    pending.append(contentsOf: [ancestor.parent, ancestor.root].compactMap { $0 })
                }
                if let reference = event.parentId {
                    guard let parentId = canonical(reference), let parent = index[parentId] else { unresolved += 1; return }
                    if parent.pubkey != event.pubkey && allowed.contains(parent.pubkey) {
                        if event.pubkey == owner { people[parent.pubkey, default: YearReviewPerson(pubkey: parent.pubkey)].sent += 1 }
                        else if parent.pubkey == owner {
                            people[event.pubkey, default: YearReviewPerson(pubkey: event.pubkey)].received += 1
                        }
                    }
                }
            } else if event.kind == 7, event.content != "-", let target, let post = index[target], post.pubkey != event.pubkey {
                guard reactions.insert(event.pubkey + ":" + target).inserted else { return }
                if post.pubkey == owner {
                    people[event.pubkey, default: YearReviewPerson(pubkey: event.pubkey)].reactions += 1
                    if posts[target] != nil { posts[target]!.reactions += 1 }
                } else if event.pubkey == owner && !blocked.contains(post.pubkey) {
                    liked[post.pubkey, default: YearReviewPerson(pubkey: post.pubkey)].reactions += 1
                }
            } else if [6, 16].contains(event.kind), let target, index[target]?.pubkey == owner, event.pubkey != owner {
                if reposts.insert(event.pubkey + ":" + target).inserted {
                    people[event.pubkey, default: YearReviewPerson(pubkey: event.pubkey)].reposts += 1
                }
            }
        }
        for id in posts.keys { posts[id]!.respondents = replies[id]?.count ?? 0 }
        func rank(_ values: [YearReviewPerson], by score: (YearReviewPerson) -> Int) -> [YearReviewPerson] {
            Array(values.filter { score($0) > 0 }.sorted { score($0) == score($1) ? $0.pubkey < $1.pubkey : score($0) > score($1) }.prefix(3))
        }
        func best(_ score: (YearReviewPost) -> Int64) -> YearReviewPost? {
            posts.values.filter { score($0) > 0 }.sorted { score($0) == score($1) ? $0.id < $1.id : score($0) > score($1) }.first
        }
        let all = Array(people.values)
        let gang = all.filter { $0.sent > 0 && $0.received > 0 }.sorted {
            let lhs = min($0.sent, $0.received), rhs = min($1.sent, $1.received)
            if lhs != rhs { return lhs > rhs }
            return $0.sent + $0.received == $1.sent + $1.received ? $0.pubkey < $1.pubkey : $0.sent + $0.received > $1.sent + $1.received
        }
        var interactions = people
        for person in interactions.values {
            interactions[person.pubkey]!.interactions = person.sent + person.received + person.supportCount + person.quotes + person.mentions
        }
        for person in Array(liked.values) + Array(zapped.values) {
            interactions[person.pubkey, default: YearReviewPerson(pubkey: person.pubkey)].interactions += person.reactions + person.zaps
        }
        let mentionedBy = all.filter { $0.mentions >= 11 }.sorted {
            if $0.mentions != $1.mentions { return $0.mentions > $1.mentions }
            let lhs = days[$0.pubkey, default: []].count, rhs = days[$1.pubkey, default: []].count
            return lhs == rhs ? $0.pubkey < $1.pubkey : lhs > rhs
        }.first
        let mostActiveDay = postingDays.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }.first.map { YearReviewActiveDay(date: $0.key, posts: $0.value) }
        return YearReviewReport(period: period, gang: Array(gang.prefix(5)), conversation: best { Int64($0.replies) },
            mentionedBy: mentionedBy, ownPostCount: posts.count, unresolvedParents: unresolved, excludedAuthors: excluded.count,
            mostActiveDay: mostActiveDay, mostReacted: best { Int64($0.reactions) }, mostZapped: best { Int64($0.zaps) }, mostZapValue: best { $0.millisats },
            mostInteracted: rank(Array(interactions.values)) { $0.interactions },
            mostTalked: rank(all) { $0.sent + $0.received }, topReplyGuy: rank(all) { $0.received }.first,
            supporters: rank(all) { $0.supportCount }, reactedBy: rank(all) { $0.reactions },
            liked: rank(Array(liked.values)) { $0.reactions }, zappedBy: rank(all) { $0.zaps },
            zapped: rank(Array(zapped.values)) { $0.zaps }, amplifiedBy: rank(all) { $0.reposts + $0.quotes },
            unverifiedZaps: unverifiedZaps, anonymousZaps: anonymousZaps)
    }

    static func mentions(_ event: YearReviewEvent, pubkey: String) -> Bool {
        // Decode identity references; names and inherited p-tags are not evidence.
        guard let regex = try? NSRegularExpression(pattern: "(?i)(?<![a-z0-9])(?:nostr:)?(?:npub1|nprofile1)[a-z0-9]+") else { return false }
        let text = event.content as NSString
        for match in regex.matches(in: event.content, range: NSRange(location: 0, length: text.length)) {
            if ScannedProfile.parse(text.substring(with: match.range))?.pubkey == pubkey { return true }
        }
        // NIP-08 legacy indexed p-tag mentions are explicit only when present in content.
        for (index, tag) in event.tags.enumerated() where tag.count >= 2 && tag[0] == "p" && tag[1] == pubkey {
            if event.content.contains("#[\(index)]") { return true }
        }
        return false
    }
}
