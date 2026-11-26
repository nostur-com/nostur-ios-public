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

    var isRestricted: Bool { tags.contains { $0.first == "-" } }

    var isHistoryEvent: Bool {
        YearReviewKinds.archived.contains(kind)
            && !(kind == 7 && tagValues("k").contains { ["4", "14", "15"].contains($0) })
    }

    var isPublicHistoryEvent: Bool { isHistoryEvent && !isRestricted }

    func isEligibleForReport(includeRestricted: Bool) -> Bool {
        isHistoryEvent && (includeRestricted || !isRestricted)
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

    /// Zap Cooking publishes recipes as kind 30023 with an exact `zapcooking` or `nostrcooking` tag.
    /// Category tags such as `zapcooking-easy` stay articles, matching Zap Cooking's own filter.
    var isZapCookingRecipe: Bool {
        kind == 30023 && tagValues("t").contains { ["zapcooking", "nostrcooking"].contains($0.lowercased()) }
    }

    var writingTitle: String {
        if let title = tagValues("title").first?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return String(title.prefix(120))
        }
        guard let line = content.split(whereSeparator: \.isNewline).lazy
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty }) else { return "" }
        let stripped = line.first == "#" ? line.drop { $0 == "#" || $0.isWhitespace } : Substring(line)
        return String(stripped.prefix(120))
    }

    static func wordCount(_ content: String) -> Int {
        content.split { $0.isWhitespace }.count
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
    var start: Int64
    var end: Int64 // Exclusive, including for a year-to-date snapshot.
    let isYearToDate: Bool
    let monthLimit: Int?
    let monthStart: Int?
    var includedMonths: Set<Int>? = nil

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

    func contains(_ timestamp: Int64) -> Bool {
        guard timestamp >= start && timestamp < end else { return false }
        guard let includedMonths else { return true }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return includedMonths.contains(calendar.component(.month, from: Date(timeIntervalSince1970: Double(timestamp))))
    }

    mutating func includeMonth(_ month: Int, now: Date = .now) {
        guard (1...12).contains(month) else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              first < now, let next = calendar.date(byAdding: .month, value: 1, to: first) else { return }
        if contains(Int64(first.timeIntervalSince1970)) { return }
        if includedMonths == nil {
            includedMonths = Set((1...12).filter {
                let date = calendar.date(from: DateComponents(year: year, month: $0, day: 1))!
                return contains(Int64(date.timeIntervalSince1970))
            })
        }
        includedMonths?.insert(month)
        start = min(start, Int64(first.timeIntervalSince1970))
        end = max(end, Int64(min(next, now).timeIntervalSince1970))
    }

    /// Presentation only: the report still counts through its actual cutoff.
    var showsYearToDateLabel: Bool {
        guard isYearToDate else { return false }
        if monthLimit != nil { return true }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let sharingStart = calendar.date(from: DateComponents(year: year, month: 12, day: 15))!
        return end < Int64(sharingStart.timeIntervalSince1970)
    }

    var cutoffDate: Date { Date(timeIntervalSince1970: TimeInterval(max(start, end - 1))) }

    var calendarDays: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let first = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(start)))
        let last = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(max(start, end - 1))))
        if includedMonths != nil {
            var day = first
            var count = 0
            while day <= last {
                if contains(Int64(day.timeIntervalSince1970)) { count += 1 }
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
            return max(1, count)
        }
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

struct YearReviewPerson: Codable, Identifiable, Equatable, Sendable {
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

struct YearReviewPostPreview: Codable, Equatable, Sendable {
    let text: String
    let thumbnail: URL?
    let extraCount: Int
    let isVideo: Bool
}

struct YearReviewPost: Codable, Identifiable, Equatable, Sendable {
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

struct YearReviewActiveDay: Codable, Equatable, Sendable {
    let date: Date
    let posts: Int
}

struct YearReviewPollActivity: Codable, Equatable, Sendable {
    let created: Int
    let voters: Int
    let votedIn: Int
    let mostVoted: YearReviewPost?
    let mostVotedCount: Int
}

struct YearReviewPublication: Codable, Equatable, Sendable, Identifiable {
    let post: YearReviewPost
    let title: String

    var id: String { post.id }
}

struct YearReviewPublications: Codable, Equatable, Sendable {
    let count: Int
    let words: Int
    let highlights: [YearReviewPublication]
}

struct YearReviewThreadStory: Codable, Equatable, Sendable {
    let post: YearReviewPost
    let activeDays: [Date]
    let newConversations: Int
}

struct YearReviewReport: Codable, Equatable, Sendable {
    let period: YearReviewPeriod
    let gang: [YearReviewPerson]
    let conversation: YearReviewPost?
    let mentionedBy: YearReviewPerson?
    let ownPostCount: Int
    let unresolvedParents: Int
    let excludedAuthors: Int
    var mostActiveDay: YearReviewActiveDay? = nil
    var longestPostingStreak = 0
    var longestPostingBreak = 0
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
    var polls: YearReviewPollActivity? = nil
    var returningThread: YearReviewThreadStory? = nil
    var newConversations: YearReviewThreadStory? = nil
    var articles: YearReviewPublications? = nil
    var recipes: YearReviewPublications? = nil

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
        let recipe: Bool
        let words: Int
        let title: String
    }

    static func analyze(events: [YearReviewEvent], owner: String, period: YearReviewPeriod,
                        trusted: Set<String>, blocked: Set<String>, locallyDeleted: Set<String> = [],
                        zapperKeys: [String: Set<String>] = [:], includeRestricted: Bool = false) -> YearReviewReport {
        let unique = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return try! analyze(scan: { visit in unique.values.forEach(visit) }, owner: owner, period: period,
                            trusted: trusted, blocked: blocked, locallyDeleted: locallyDeleted, zapperKeys: zapperKeys,
                            includeRestricted: includeRestricted)
    }

    /// Two streaming passes retain compact content references, never full archive JSON.
    static func analyze(scan: (_ visit: (YearReviewEvent) -> Void) throws -> Void,
                        owner: String, period: YearReviewPeriod, trusted: Set<String>, blocked: Set<String>,
                        locallyDeleted: Set<String>, zapperKeys: [String: Set<String>], includeRestricted: Bool = false,
                        verifiedZap: ((YearReviewEvent) -> YearReviewZap?)? = nil) throws -> YearReviewReport {
        var index: [String: ContentIndex] = [:]
        var polls: [String: NostrPoll] = [:]
        var latest: [String: String] = [:]
        var versions: [String: Set<String>] = [:]
        var deletions: [(String, [String], Int64)] = []
        var restrictedContent = Set<String>()
        try scan { event in
            if event.kind == 5 { deletions.append((event.pubkey, event.tagValues("e") + event.tagValues("a"), event.createdAt)); return }
            if !includeRestricted, event.isRestricted, YearReviewKinds.content.contains(event.kind) {
                restrictedContent.insert(event.id)
                if let coordinate = event.coordinate { restrictedContent.insert(coordinate) }
            }
            guard event.isEligibleForReport(includeRestricted: includeRestricted), YearReviewKinds.content.contains(event.kind),
                  event.createdAt < period.end else { return }
            if event.kind == 1068 {
                let poll = NostrPoll(id: event.id, createdAt: Int(event.createdAt), tags: event.tags)
                if poll.isSupported { polls[event.id] = poll }
            }
            let longform = event.pubkey == owner && event.kind == 30023
            index[event.id] = ContentIndex(pubkey: event.pubkey, parent: event.parentId, root: event.rootId, createdAt: event.createdAt,
                kind: event.kind, coordinate: event.coordinate, publishedAt: event.tagValues("published_at").first.flatMap(Int64.init).flatMap { $0 > 0 && $0 <= event.createdAt ? $0 : nil } ?? event.createdAt, preview: event.pubkey == owner ? event.preview : "",
                recipe: longform && event.isZapCookingRecipe, words: longform ? YearReviewEvent.wordCount(event.content) : 0,
                title: longform ? event.writingTitle : "")
            if let address = event.coordinate {
                versions[address, default: []].insert(event.id)
                if let old = latest[address], let existing = index[old],
                   existing.createdAt > event.createdAt || existing.createdAt == event.createdAt && old < event.id { return }
                latest[address] = event.id
            }
        }
        var deleted = locallyDeleted
        var deletionAuthors: [String: Set<String>] = [:]
        for (author, ids, cutoff) in deletions {
            for id in ids {
                deletionAuthors[id, default: []].insert(author)
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
        // Look before the report window too: earlier saved replies can rule out
        // a "first exchange" even if they do not contribute to this year's count.
        var firstExchanges: [String: (timestamp: Int64, id: String)] = [:]
        for (id, item) in index where canonical(id) == id {
            guard let parentId = item.parent.flatMap(canonical), let parent = index[parentId],
                  item.pubkey != parent.pubkey, item.createdAt >= parent.createdAt,
                  item.pubkey == owner || parent.pubkey == owner,
                  !blocked.contains(item.pubkey), !blocked.contains(parent.pubkey) else { continue }
            let peer = item.pubkey == owner ? parent.pubkey : item.pubkey
            if let first = firstExchanges[peer], (first.timestamp, first.id) <= (item.createdAt, id) { continue }
            firstExchanges[peer] = (item.createdAt, id)
        }
        var threadDays: [String: Set<Date>] = [:]
        var newPeople: [String: Int] = [:]
        var postingDays: [Date: Int] = [:]
        for (id, item) in index where item.pubkey == owner && period.contains(item.publishedAt) && canonical(id) == id {
            posts[id] = YearReviewPost(id: id, content: item.preview, replies: 0, respondents: 0, kind: item.kind, coordinate: item.coordinate)
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(item.publishedAt)))
            postingDays[day, default: 0] += 1
        }
        var replies: [String: Set<String>] = [:]
        var days: [String: Set<Int64>] = [:]
        var reactions = Set<String>()
        var postReactions = Set<String>()
        var reposts = Set<String>()
        var payments = Set<String>()
        var excluded = Set<String>()
        var unresolved = 0
        var unverifiedZaps = 0
        var anonymousZaps = 0
        var pollVotes: [String: [String: PollVote]] = [:]
        let pollCutoff = Int(min(period.end - 1, Int64(Date.now.timeIntervalSince1970)))
        try scan { event in
            guard event.isEligibleForReport(includeRestricted: includeRestricted),
                  !deleted.contains(event.id), deletionAuthors[event.id]?.contains(event.pubkey) != true else { return }
            if YearReviewKinds.support.contains(event.kind),
               let target = event.tagValues("e").last ?? event.tagValues("a").last,
               restrictedContent.contains(target) { return }
            if event.kind == 1018 {
                guard !blocked.contains(event.pubkey), let target = event.tagValues("e").first,
                      let poll = polls[target], !deleted.contains(target),
                      event.createdAt >= poll.createdAt, event.createdAt <= pollCutoff,
                      poll.endsAt == nil || event.createdAt <= poll.endsAt! else { return }
                let vote = PollVote(id: event.id, pubkey: event.pubkey, createdAt: Int(event.createdAt), responses: event.tagValues("response"))
                if let old = pollVotes[target]?[event.pubkey],
                   old.createdAt > vote.createdAt || old.createdAt == vote.createdAt && old.id <= vote.id { return }
                pollVotes[target, default: [:]][event.pubkey] = vote
                return // Votes never become replies, reactions, or relationship scores.
            }
            // Post highlights use the same positive reaction-event total as detail.
            // Trust, unique people and the year boundary remain relationship rules.
            let reactionTarget = event.tagValues("e").last ?? event.tagValues("a").last.flatMap(canonical)
            if event.kind == 7, event.content != "-", !blocked.contains(event.pubkey),
               !event.tagValues("k").contains(where: { ["4", "14", "15"].contains($0) }),
               let reactionTarget, posts[reactionTarget] != nil,
               postReactions.insert(event.id).inserted {
                posts[reactionTarget]!.reactions += 1
            }
            guard period.contains(event.createdAt) else { return }
            // The last e-tag is the actual target; earlier tags may only be
            // inherited thread references. Never fall back to an earlier known post.
            let target = (event.tagValues("e").last ?? event.tagValues("a").last).flatMap(canonical)
            if event.kind == 9735 {
                guard YearReviewZap.involves(event, owner: owner) else { return }
                let checkedZap: YearReviewZap?
                if let verifiedZap { checkedZap = verifiedZap(event) }
                else { checkedZap = YearReviewZap.validate(event, authorized: zapperKeys) }
                guard let zap = checkedZap else { unverifiedZaps += 1; return }
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
                let day = calendar.startOfDay(for: Date(timeIntervalSince1970: Double(event.createdAt)))
                var pending = [event.parentId, event.rootId].compactMap { $0 }
                var visited: Set<String> = [event.id]
                while let reference = pending.popLast() {
                    guard let ancestorId = canonical(reference), visited.insert(ancestorId).inserted,
                          let ancestor = index[ancestorId] else { continue }
                    if posts[ancestorId] != nil {
                        posts[ancestorId]!.replies += 1
                        replies[ancestorId, default: []].insert(event.pubkey)
                        if event.pubkey != owner, ancestor.parent == nil, ancestor.root == nil,
                           event.createdAt >= ancestor.createdAt {
                            threadDays[ancestorId, default: []].insert(day)
                            // A first direct reply to the owner can be nested under this post.
                            if firstExchanges[event.pubkey]?.id == event.id {
                                newPeople[ancestorId, default: 0] += 1
                            }
                        }
                    }
                    pending.append(contentsOf: [ancestor.parent, ancestor.root].compactMap { $0 })
                }
                if let reference = event.parentId {
                    guard !restrictedContent.contains(reference) else { return }
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
        var voters = Set<String>()
        var votedIn = 0
        var mostVoted: YearReviewPost?
        var mostVotedCount = 0
        for (id, poll) in polls where !deleted.contains(id) && !blocked.contains(index[id]?.pubkey ?? "") {
            let tally = PollTally(poll: poll, votes: Array(pollVotes[id, default: [:]].values), now: pollCutoff)
            if tally.votes.contains(where: { $0.pubkey == owner && period.contains(Int64($0.createdAt)) }) { votedIn += 1 }
            guard let post = posts[id] else { continue }
            voters.formUnion(tally.votes.map(\.pubkey))
            if tally.totalVoters > mostVotedCount || (tally.totalVoters == mostVotedCount && tally.totalVoters > 0 && id < (mostVoted?.id ?? id)) {
                mostVoted = post
                mostVotedCount = tally.totalVoters
            }
        }
        let createdPolls = polls.keys.filter { posts[$0] != nil }.count
        let pollActivity = createdPolls > 0 || votedIn > 0
            ? YearReviewPollActivity(created: createdPolls, voters: voters.count, votedIn: votedIn, mostVoted: mostVoted, mostVotedCount: mostVotedCount) : nil
        func threadStory(_ post: YearReviewPost?) -> YearReviewThreadStory? {
            post.map {
                YearReviewThreadStory(post: $0, activeDays: (threadDays[$0.id] ?? []).sorted(),
                    newConversations: newPeople[$0.id] ?? 0)
            }
        }
        let returningThread = threadStory(best {
            let count = threadDays[$0.id]?.count ?? 0
            return count >= 5 ? Int64(count) : 0
        })
        let newConversations = threadStory(best {
            let count = newPeople[$0.id] ?? 0
            return count >= 4 ? Int64(count) : 0
        })
        // Missing months split runs. Only count a break bounded by saved posts.
        var longestStreak = 0
        var longestBreak = 0
        var streak = 0
        var gap = 0
        var hasPosted = false
        var day = calendar.startOfDay(for: Date(timeIntervalSince1970: Double(period.start)))
        while day <= period.cutoffDate {
            if !period.contains(Int64(day.timeIntervalSince1970)) {
                streak = 0
                gap = 0
                hasPosted = false
            } else if postingDays[day] != nil {
                streak += 1
                longestStreak = max(longestStreak, streak)
                longestBreak = max(longestBreak, gap)
                gap = 0
                hasPosted = true
            } else {
                streak = 0
                if hasPosted { gap += 1 }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        let publications = publicationSummaries(index: index, posts: posts, owner: owner, period: period, canonical: canonical)
        return YearReviewReport(period: period, gang: Array(gang.prefix(5)), conversation: best { Int64($0.replies) },
            mentionedBy: mentionedBy, ownPostCount: posts.count, unresolvedParents: unresolved, excludedAuthors: excluded.count,
            mostActiveDay: mostActiveDay, longestPostingStreak: longestStreak, longestPostingBreak: longestBreak, mostReacted: best { Int64($0.reactions) }, mostZapped: best { Int64($0.zaps) }, mostZapValue: best { $0.millisats },
            mostInteracted: rank(Array(interactions.values)) { $0.interactions },
            mostTalked: rank(all) { $0.sent + $0.received }, topReplyGuy: rank(all) { $0.received }.first,
            supporters: rank(all) { $0.supportCount }, reactedBy: rank(all) { $0.reactions },
            liked: rank(Array(liked.values)) { $0.reactions }, zappedBy: rank(all) { $0.zaps },
            zapped: rank(Array(zapped.values)) { $0.zaps }, amplifiedBy: rank(all) { $0.reposts + $0.quotes },
            unverifiedZaps: unverifiedZaps, anonymousZaps: anonymousZaps, polls: pollActivity,
            returningThread: returningThread, newConversations: newConversations, articles: publications.articles, recipes: publications.recipes)
    }

    /// Articles and Zap Cooking recipes are the latest kind 30023 version whose publish date falls in the year.
    /// Recipes are the tagged subset and are not also counted as articles.
    private static func publicationSummaries(index: [String: ContentIndex], posts: [String: YearReviewPost], owner: String,
                                             period: YearReviewPeriod, canonical: (String) -> String?)
        -> (articles: YearReviewPublications?, recipes: YearReviewPublications?) {
        struct Piece {
            let post: YearReviewPost
            let title: String
            let recipe: Bool
            let words: Int
            let publishedAt: Int64
        }
        var pieces: [Piece] = []
        pieces.reserveCapacity(posts.count)
        for (id, item) in index where item.kind == 30023 && item.pubkey == owner && period.contains(item.publishedAt) && canonical(id) == id {
            guard let post = posts[id] else { continue }
            pieces.append(Piece(post: post, title: item.title, recipe: item.recipe, words: item.words, publishedAt: item.publishedAt))
        }
        func summarize(_ items: [Piece]) -> YearReviewPublications? {
            guard !items.isEmpty else { return nil }
            let ranked = items.filter { !$0.title.isEmpty }.sorted { lhs, rhs in
                if lhs.post.reactions != rhs.post.reactions { return lhs.post.reactions > rhs.post.reactions }
                if lhs.post.zaps != rhs.post.zaps { return lhs.post.zaps > rhs.post.zaps }
                if lhs.post.millisats != rhs.post.millisats { return lhs.post.millisats > rhs.post.millisats }
                if lhs.publishedAt != rhs.publishedAt { return lhs.publishedAt > rhs.publishedAt }
                return lhs.post.id < rhs.post.id
            }
            let highlights = ranked.prefix(3).map { YearReviewPublication(post: $0.post, title: $0.title) }
            return YearReviewPublications(count: items.count, words: items.reduce(0) { $0 + $1.words }, highlights: highlights)
        }
        return (summarize(pieces.filter { !$0.recipe }), summarize(pieces.filter(\.recipe)))
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
