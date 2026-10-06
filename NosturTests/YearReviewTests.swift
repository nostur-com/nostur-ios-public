import XCTest
import NostrEssentials
import CryptoKit
import CoreData
import SQLite3
@testable import Nostur

final class YearReviewTests: XCTestCase {
    private let owner = String(repeating: "a", count: 64)
    private let alice = String(repeating: "b", count: 64)
    private let bob = String(repeating: "c", count: 64)
    private var period: YearReviewPeriod {
        YearReviewPeriod(year: 2026, now: Date(timeIntervalSince1970: 1_800_000_000), timeZone: TimeZone(secondsFromGMT: 0)!)
    }

    private func note(_ id: String, by pubkey: String, parent: String? = nil, content: String = "",
                      tags: [[String]] = [], timestamp: Int64? = nil, kind: Int = 1) -> YearReviewEvent {
        let replyTags = parent.map { [["e", $0, "", "reply"]] } ?? []
        return YearReviewEvent(id: id, pubkey: pubkey, createdAt: timestamp ?? period.start + 1,
                               kind: kind, tags: tags + replyTags, content: content, sig: "")
    }

    private func analyze(_ events: [YearReviewEvent], trusted: Set<String> = [], blocked: Set<String> = []) -> YearReviewReport {
        YearReviewAnalyzer.analyze(events: events, owner: owner, period: period, trusted: trusted, blocked: blocked)
    }

    func testMostActiveDayCountsPublicContentButNotInteractionsOrDeletedPosts() {
        let first = period.start + 3600
        let second = first + 86400
        let original = note("article-old", by: owner, tags: [["d", "article"], ["published_at", String(first)]], timestamp: first, kind: 30023)
        let revision = note("article-new", by: owner, tags: [["d", "article"], ["published_at", String(first)]], timestamp: second, kind: 30023)
        let picture = note("picture", by: owner, timestamp: first, kind: 20)
        let events = [original, revision, picture, picture,
            note("reply", by: owner, parent: "picture", timestamp: first),
            note("video", by: owner, timestamp: second, kind: 22),
            note("voice", by: owner, timestamp: second, kind: 1222),
            note("deleted", by: owner, timestamp: second),
            note("delete", by: owner, tags: [["e", "deleted"]], timestamp: second + 1, kind: 5),
            note("like", by: owner, tags: [["e", "picture"]], timestamp: second, kind: 7),
            note("repost", by: owner, tags: [["e", "picture"]], timestamp: second, kind: 6),
            note("someone-else", by: alice, timestamp: second)]
        let report = analyze(events, trusted: [alice])
        XCTAssertEqual(report.ownPostCount, 5)
        XCTAssertEqual(report.mostActiveDay?.posts, 3)
        XCTAssertEqual(report.mostActiveDay?.date, Date(timeIntervalSince1970: TimeInterval(period.start)))
        XCTAssertNil(analyze([]).mostActiveDay)
    }

    func testMostActiveDayUsesReportTimeZoneAndBreaksTiesByEarliestDate() {
        let zone = TimeZone(secondsFromGMT: 7200)!
        let localPeriod = YearReviewPeriod(year: 2026, now: Date(timeIntervalSince1970: 1_800_000_000), timeZone: zone)
        // These two timestamps span UTC midnight but belong to the same local day.
        let day = localPeriod.start + 86400
        let events = [note("late", by: owner, timestamp: day + 3600),
            note("early", by: owner, timestamp: day + 3 * 3600),
            note("next-a", by: owner, timestamp: day + 86400 + 3600),
            note("next-b", by: owner, timestamp: day + 86400 + 3 * 3600),
            note("outside", by: owner, timestamp: localPeriod.start - 1)]
        let report = YearReviewAnalyzer.analyze(events: events.reversed(), owner: owner, period: localPeriod, trusted: [], blocked: [])
        XCTAssertEqual(report.mostActiveDay?.posts, 2)
        XCTAssertEqual(report.mostActiveDay?.date, Date(timeIntervalSince1970: TimeInterval(day)))
        XCTAssertEqual(report.ownPostCount, 4)
    }

    func testPostReactionTotalsMatchDetailWhilePeopleRankingsStayTrustedAndYearly() {
        let events = [note("mine", by: owner),
            note("like-a", by: alice, content: "+", tags: [["e", "mine"]], kind: 7),
            note("like-a-again", by: alice, content: "❤️", tags: [["e", "mine"]], kind: 7),
            note("like-untrusted", by: bob, content: "+", tags: [["e", "mine"]], kind: 7),
            note("like-later", by: bob, content: "+", tags: [["e", "mine"]], timestamp: period.end, kind: 7)]
        XCTAssertEqual(analyze(events, trusted: [alice]).mostReacted?.reactions, 4)
        XCTAssertEqual(analyze(events, trusted: [alice, bob]).mostReacted?.reactions, 4)
        XCTAssertEqual(analyze(events, trusted: [alice]).reactedBy.map(\.pubkey), [alice])
        XCTAssertEqual(analyze(events, trusted: [alice, bob]).reactedBy.first { $0.pubkey == alice }?.reactions, 1)
    }

    func testReactionsNeverFallBackToAnInheritedKnownPost() {
        let events = [note("mine", by: owner),
            note("wrong-target", by: alice, tags: [["e", "mine"], ["e", "missing-actual-target"]], kind: 7),
            note("real-like", by: bob, tags: [["e", "mine"]], kind: 7)]
        let report = analyze(events, trusted: [alice, bob])
        XCTAssertEqual(report.mostReacted?.reactions, 1)
        XCTAssertEqual(report.reactedBy.map(\.pubkey), [bob])
    }

    func testPostingAverageIncludesQuietDaysAndHandlesDaylightSaving() {
        let zone = TimeZone(identifier: "Europe/Amsterdam")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let cutoff = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))!
        let reviewPeriod = YearReviewPeriod(year: 2026, now: cutoff, timeZone: zone)
        let events = (0..<9).map { note("post-\($0)", by: owner, timestamp: reviewPeriod.start + 1) }
        let report = YearReviewAnalyzer.analyze(events: events, owner: owner, period: reviewPeriod, trusted: [], blocked: [])
        XCTAssertEqual(reviewPeriod.calendarDays, 90)
        XCTAssertEqual(report.averagePostsPerDay, 0.1, accuracy: 0.00001)
        let full = YearReviewPeriod(year: 2026, now: Date(timeIntervalSince1970: 1_800_000_000), timeZone: zone)
        XCTAssertEqual(full.calendarDays, 365)
        XCTAssertEqual(analyze([]).averagePostsPerDay, 0)
    }

    func testMutualGangAndDirectReplyCountsDeduplicateEvents() {
        let post = note("mine", by: owner)
        let theirPost = note("theirs", by: alice)
        let sent = note("sent", by: owner, parent: "theirs")
        let received = note("received", by: alice, parent: "mine")
        let nested = note("nested", by: alice, parent: "received")
        let selfReply = note("self", by: owner, parent: "mine")
        let result = analyze([post, theirPost, sent, received, received, nested, selfReply])
        XCTAssertEqual(result.gang, [YearReviewPerson(pubkey: alice, sent: 1, received: 1)])
        XCTAssertEqual(result.conversation?.replies, 3)
        XCTAssertEqual(result.conversation?.respondents, 2)
    }

    func testConversationIncludesNestedRepliesAndRootTagsAcrossMissingParents() {
        let events = [note("mine", by: owner),
            note("direct", by: alice, parent: "mine"),
            note("nested", by: bob, parent: "direct", tags: [["e", "mine", "", "root"]]),
            note("deeper", by: alice, parent: "nested"),
            note("missing-parent", by: bob, parent: "missing", tags: [["e", "mine", "", "root"]]),
            note("comment", by: alice, tags: [["E", "mine"], ["e", "missing-comment"]], kind: 1111),
            note("spam", by: String(repeating: "d", count: 64), parent: "nested"),
            note("quote-only", by: bob, tags: [["e", "mine", "", "mention"]]),
            note("outside", by: alice, parent: "mine", timestamp: period.end)]
        let report = analyze(events + [events[2]], trusted: [alice, bob])
        XCTAssertEqual(report.conversation?.id, "mine")
        XCTAssertEqual(report.conversation?.replies, 5)
        XCTAssertEqual(report.conversation?.respondents, 2)
        XCTAssertEqual(report.topReplyGuy?.received, 1)
        XCTAssertEqual(analyze(events, trusted: [alice, bob], blocked: [bob]).conversation?.replies, 3)
    }

    func testConversationAncestryCyclesTerminateWithoutCountingSelf() {
        let events = [note("mine", by: owner, parent: "reply"), note("reply", by: alice, parent: "mine")]
        let report = analyze(events, trusted: [alice])
        XCTAssertEqual(report.conversation?.replies, 1)
        XCTAssertEqual(report.conversation?.respondents, 1)
    }

    func testBalancedConversationsBeatOneSidedVolumeAndHaveStableTies() {
        var events = [note("mine", by: owner), note("alice", by: alice), note("bob", by: bob)]
        events += (0..<2).map { note("a-sent-\($0)", by: owner, parent: "alice") }
        events += (0..<2).map { note("a-received-\($0)", by: alice, parent: "mine") }
        events += [note("b-sent", by: owner, parent: "bob")]
        events += (0..<30).map { note("b-received-\($0)", by: bob, parent: "mine") }
        XCTAssertEqual(analyze(events).gang.map(\.pubkey), [alice, bob])
        XCTAssertEqual(analyze(events).gang, analyze(events.reversed()).gang)
    }

    func testIncomingSpamDoesNotEstablishTrust() {
        let events = [note("mine", by: owner), note("spam", by: bob, parent: "mine")]
        let result = analyze(events)
        XCTAssertNil(result.conversation)
        XCTAssertTrue(result.gang.isEmpty)
        XCTAssertEqual(result.excludedAuthors, 1)
    }

    func testExplicitMentionsExcludeInheritedPTagsRepliesAndQuoteOnlyReferences() throws {
        let npub = try NostrEssentials.ShareableIdentifier("npub", pubkey: owner).identifier
        let nprofile = try NostrEssentials.ShareableIdentifier("nprofile", pubkey: owner).identifier
        var events = [
            note("mine", by: owner),
            note("tag-only", by: alice, tags: [["p", owner]]),
            note("reply", by: alice, parent: "mine", content: "nostr:" + npub),
            note("explicit", by: alice, content: "nostr:\(npub) and \(npub)"),
            note("profile", by: alice, content: "nostr:" + nprofile),
            note("indexed", by: alice, content: "Hi #[0]", tags: [["p", owner]]),
            note("quote-only", by: alice, tags: [["q", "mine", "", owner]]),
            note("marked-mention", by: alice, content: "nostr:" + npub, tags: [["e", "mine", "", "mention"]])
        ]
        XCTAssertNil(analyze(events, trusted: [alice]).mentionedBy)
        events += (0..<6).map { note("extra-\($0)", by: alice, content: "nostr:" + npub) }
        XCTAssertNil(analyze(events, trusted: [alice]).mentionedBy) // Ten mentions is below the threshold.
        events.append(note("eleventh", by: alice, content: "nostr:" + npub))
        let result = analyze(events, trusted: [alice])
        XCTAssertEqual(result.mentionedBy?.pubkey, alice)
        XCTAssertEqual(result.mentionedBy?.mentions, 11)
        XCTAssertEqual(result.conversation?.replies, 1)
    }

    func testLegacyParentsAndMarkedQuotes() {
        XCTAssertEqual(note("legacy", by: alice, tags: [["e", "root"], ["e", "parent"]]).parentId, "parent")
        XCTAssertEqual(note("root", by: alice, tags: [["e", "root", "", "root"]]).parentId, "root")
        XCTAssertNil(note("quote", by: alice, tags: [["e", "quoted", "", "mention"]]).parentId)
    }

    func testBlocksAndAuthenticatedDeletionsRemoveHighlights() {
        let events = [note("mine", by: owner), note("received", by: alice, parent: "mine"),
                      note("delete", by: alice, tags: [["e", "received"]], kind: 5)]
        XCTAssertNil(analyze(events, trusted: [alice]).conversation)
        XCTAssertNil(analyze(Array(events.prefix(2)), trusted: [alice], blocked: [alice]).conversation)
        let forgedDeletion = note("forged", by: bob, tags: [["e", "received"]], kind: 5)
        XCTAssertEqual(analyze(Array(events.prefix(2)) + [forgedDeletion], trusted: [alice]).conversation?.replies, 1)
    }

    func testExclusiveYearBoundariesAndOlderParents() {
        let oldPost = note("older", by: alice, timestamp: period.start - 1)
        let events = [oldPost, note("outgoing", by: owner, parent: "older", timestamp: period.start),
                      note("mine", by: owner), note("incoming", by: alice, parent: "mine", timestamp: period.end - 1),
                      note("next-year", by: alice, parent: "mine", timestamp: period.end)]
        XCTAssertEqual(analyze(events).gang.first?.sent, 1)
        XCTAssertEqual(analyze(events).gang.first?.received, 1)
        let amsterdam = YearReviewPeriod(year: 2026, now: Date(timeIntervalSince1970: 1_800_000_000),
                                         timeZone: TimeZone(identifier: "Europe/Amsterdam")!)
        XCTAssertEqual(amsterdam.start, period.start - 3_600)
        XCTAssertEqual(amsterdam.cutoffDate.timeIntervalSince1970, TimeInterval(amsterdam.end - 1))
        XCTAssertEqual(YearReviewPeriod.defaultYear(now: Date(timeIntervalSince1970: TimeInterval(period.end + 86_400))), 2026)
    }

    func testUnresolvedParentIsNotAMentionOrConversation() throws {
        let npub = try NostrEssentials.ShareableIdentifier("npub", pubkey: owner).identifier
        let result = analyze([note("reply", by: alice, parent: "missing", content: npub)], trusted: [alice])
        XCTAssertEqual(result.unresolvedParents, 1)
        XCTAssertNil(result.mentionedBy)
        XCTAssertNil(result.conversation)
    }

    func testDateSubdivisionPreservesEveryTimestampAndNeverSplitsOneSecond() {
        let work = YearReviewWork(relay: "wss://relay.example.com", category: .incoming, since: 100, until: 200)
        XCTAssertEqual(work.subdivisions.map(\.since), [100, 151])
        XCTAssertEqual(work.subdivisions.map(\.until), [150, 200])
        XCTAssertTrue(YearReviewWork(relay: work.relay, category: .incoming, since: 100, until: 100).subdivisions.isEmpty)
        XCTAssertFalse(work.accepts(note("unrelated", by: bob, timestamp: 150), owner: owner))
    }

    func testPaginationContinuesUnderSilentRelayCapAndPreservesTimestampTies() {
        let work = YearReviewWork(relay: "wss://relay.example.com", category: .incoming, since: 100, until: 200, kinds: [1])
        let page = (0..<50).map { note("page-\($0)", by: alice, timestamp: 151 + Int64($0 / 2)) }
        let next = work.continuation(events: page, exhaustive: false)
        XCTAssertEqual(next.map(\.since), [151, 100])
        XCTAssertEqual(next.map(\.until), [151, 150])
        XCTAssertEqual(next[0].kinds, [1])
        XCTAssertTrue(work.continuation(events: [], exhaustive: false).isEmpty)
        XCTAssertTrue(work.continuation(events: page, exhaustive: true).isEmpty)
        XCTAssertTrue(next[0].continuation(events: [page[0]], exhaustive: false).isEmpty)
    }

    func testCalendarMonthsAndAdaptiveSplitsHaveNoGaps() {
        let windows = YearReviewCollection.monthWindows(period: period)
        XCTAssertEqual(windows.first?.since, period.start)
        XCTAssertEqual(windows.last?.until, period.end - 1)
        for index in 1..<windows.count { XCTAssertEqual(windows[index].since, windows[index - 1].until + 1) }
        let month = windows[0]
        let work = YearReviewWork(relay: "relay", category: .authored, since: month.since, until: month.until)
        let weeks = work.adaptiveSubdivisions(timeZoneIdentifier: "UTC")
        XCTAssertEqual(weeks.count, 5)
        XCTAssertEqual(weeks.first?.since, work.since)
        XCTAssertEqual(weeks.last?.until, work.until)
        for index in 1..<weeks.count { XCTAssertEqual(weeks[index].since, weeks[index - 1].until + 1) }
        let days = weeks[0].adaptiveSubdivisions(timeZoneIdentifier: "UTC")
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.last?.until, weeks[0].until)
        XCTAssertEqual(days[0].adaptiveSubdivisions(timeZoneIdentifier: "UTC").count, 2)
        let second = YearReviewWork(relay: "relay", category: .authored, since: 10, until: 10)
        XCTAssertTrue(second.adaptiveSubdivisions(timeZoneIdentifier: "UTC").isEmpty)
    }

    func testParallelBatchBoundsRelaysAndKeepsMonthAndPassTogether() {
        let relayData = (1...4).map { RelayData.new(url: "wss://relay\($0).example.com", read: true) }
        var job = YearReviewCollection(owner: owner, period: period, relays: relayData, trusted: [])
        let batch = job.nextBatch(excluding: [], maximum: 2)
        XCTAssertEqual(batch.count, 2)
        XCTAssertEqual(Set(batch.map(\.relay)).count, 2)
        XCTAssertTrue(batch.allSatisfy { $0.category == .authored && $0.until == period.end - 1 })
        let newest = job.pending.filter { $0.until == period.end - 1 && $0.category == .authored }
        job.pending = [newest[0], job.pending.first { $0.until < period.end - 1 }!]
        var pacing = YearReviewRelayPacing()
        pacing.started(newest[0].relay, jitter: 0)
        job.pacing = pacing
        XCTAssertEqual(job.nextBatch(excluding: []), [newest[0]]) // Never skip into an older month.
    }

    func testParallelBatchAllowsTwentyDistinctRelaysAndNeverDuplicatesOne() {
        let relays = (1...25).map { RelayData.new(url: "wss://relay\($0).example.com", read: true) }
        var job = YearReviewCollection(owner: owner, period: period, relays: relays, trusted: [])
        job.pending.insert(job.pending[0], at: 1)
        let batch = job.nextBatch(excluding: [])
        XCTAssertEqual(batch.count, 20)
        XCTAssertEqual(Set(batch.map(\.relay)).count, 20)
        XCTAssertTrue(batch.allSatisfy { $0.category == .authored && $0.until == period.end - 1 })
    }

    func testAdaptiveSplitAlwaysShrinksADaylightSavingDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25))!
        let end = calendar.date(byAdding: .day, value: 1, to: date)!
        let work = YearReviewWork(relay: "relay", category: .incoming,
            since: Int64(date.timeIntervalSince1970), until: Int64(end.timeIntervalSince1970) - 1)
        let parts = work.adaptiveSubdivisions(timeZoneIdentifier: "Europe/Amsterdam")
        XCTAssertGreaterThan(parts.count, 1)
        XCTAssertTrue(parts.allSatisfy { $0.until - $0.since < work.until - work.since })
        XCTAssertEqual(parts.first?.since, work.since)
        XCTAssertEqual(parts.last?.until, work.until)
    }

    func testCalendarRemainsActiveBetweenMonthRequestsAndDuringPacing() {
        var job = YearReviewCollection(owner: owner, period: period,
            relays: [.new(url: "wss://relay.example.com", read: true)], trusted: [])
        let first = job.pending.first!
        XCTAssertEqual(job.calendarActivity(active: [], running: true), [first])
        var pacing = YearReviewRelayPacing()
        pacing.started(first.relay)
        job.pacing = pacing
        XCTAssertEqual(job.calendarActivity(active: [], running: true), [first])
        job.pending.removeFirst()
        job.recordMonthlyQuery(first)
        let next = job.pending.first!
        let handoff = job.calendarActivity(active: [], running: true)
        XCTAssertEqual(handoff, [next])
        XCTAssertEqual(job.monthProgress(active: handoff).filter { $0.own.active }.count, 1)
        XCTAssertTrue(job.calendarActivity(active: [next], running: false).isEmpty)
        job.pending.removeAll { $0.category == .authored }
        let interactions = job.pending.first!
        XCTAssertEqual(job.calendarActivity(active: [], running: true), [interactions])
        XCTAssertEqual(job.monthProgress(active: job.calendarActivity(active: [], running: true)).filter { $0.others.active }.count, 1)
    }

    func testFinalCollectionStagesUseBusyHeaderInsteadOfRestartingCalendar() {
        var job = YearReviewCollection(owner: owner, period: period,
            relays: [.new(url: "wss://relay.example.com", read: true)], trusted: [])
        job.pending = []
        for phase in [YearReviewCollection.Phase.references, .parents, .finished] {
            job.phase = phase
            let references = YearReviewWork(relay: "wss://relay.example.com", category: .references,
                since: period.start, until: period.end - 1)
            XCTAssertTrue(job.calendarActivity(active: [references], running: true).isEmpty)
        }
    }

    func testMonthCalendarTracksTwoPassesAndIncompleteSources() {
        var job = YearReviewCollection(owner: owner, period: period,
            relays: [.new(url: "wss://relay.example.com", read: true)], trusted: [])
        let own = job.pending.first!
        let initial = job.monthProgress(active: [own])
        let currentMonth = initial.first { $0.own.active }!.month
        XCTAssertEqual(initial.count, 12)
        XCTAssertFalse(initial[currentMonth - 1].own.finished)
        job.pending.removeAll { $0 == own }
        job.recordMonthlyQuery(own)
        let firstPass = job.monthProgress(active: [])
        XCTAssertTrue(firstPass[currentMonth - 1].own.finished)
        XCTAssertFalse(firstPass[currentMonth - 1].others.finished)
        let other = job.pending.first { $0.until == own.until && $0.category == .incoming }!
        XCTAssertTrue(job.monthProgress(active: [other])[currentMonth - 1].others.active)
        let currentWork = job.pending.filter { $0.until == own.until }
        for work in currentWork { job.recordMonthlyQuery(work) }
        job.pending.removeAll { $0.until == own.until }
        XCTAssertTrue(job.monthProgress(active: [])[currentMonth - 1].others.finished)
        job.failed.append(other)
        XCTAssertFalse(job.monthProgress(active: [])[currentMonth - 1].others.finished)
        XCTAssertEqual(job.monthProgress(active: [])[currentMonth - 1].others.failedRelays, [other.relay])
        XCTAssertTrue(job.monthProgress(active: []).filter { $0.month != currentMonth }.allSatisfy { $0.others.failedRelays.isEmpty })
        job.failed.append(YearReviewWork(relay: "wss://another.example.com", category: .references,
            since: period.start, until: period.end - 1, ids: [String(repeating: "f", count: 64)]))
        XCTAssertEqual(job.monthProgress(active: [])[currentMonth - 1].others.failedRelays, [other.relay])
    }

    func testRelayFailureRecordsActualRequestAndSkippedMonthsAndSurvivesCheckpoint() throws {
        let bad = "wss://bad.example.com"
        let good = "wss://good.example.com"
        var job = YearReviewCollection(owner: owner, period: period,
            relays: [.new(url: bad, read: true), .new(url: good, read: true)], trusted: [])
        let trigger = try XCTUnwrap(job.pending.first { $0.relay == bad })
        job.markRelayUnavailable(bad, reason: "EOSE timeout", trigger: trigger, received: 37)
        XCTAssertTrue(job.pending.allSatisfy { $0.relay == good })
        XCTAssertTrue(job.failed.allSatisfy { $0.relay == bad })
        let details = try XCTUnwrap(job.sourceFailures)
        XCTAssertEqual(details.filter { $0.status == .failed }.count, 1)
        XCTAssertEqual(details.first { $0.status == .failed }?.received, 37)
        XCTAssertTrue(details.filter { $0.work != trigger }.allSatisfy {
            $0.status == .skipped && $0.trigger == trigger && $0.reason == "EOSE timeout"
        })
        let restored = try JSONDecoder().decode(YearReviewCollection.self, from: JSONEncoder().encode(job))
        XCTAssertEqual(restored.sourceFailures, details)
        XCTAssertEqual(restored.monthProgress(active: []).flatMap(\.failures).count, details.count)
    }

    func testCooldownAndLegacyCheckpointsDoNotClaimEveryMonthFailed() throws {
        var job = YearReviewCollection(owner: owner, period: period,
            relays: [.new(url: "wss://relay.example.com", read: true)], trusted: [])
        job.markRelayUnavailable(job.relays[0].url, reason: "Cooling down")
        XCTAssertTrue(try XCTUnwrap(job.sourceFailures).allSatisfy { $0.status == .coolingDown && $0.trigger == nil })
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(job)) as? [String: Any])
        legacy.removeValue(forKey: "sourceFailures")
        let restored = try JSONDecoder().decode(YearReviewCollection.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(restored.sourceFailures)
        XCTAssertTrue(restored.monthProgress(active: []).flatMap(\.failures).allSatisfy { $0.status == .unknown })
    }

    func testHistoryAuthInheritsCurrentAppSettingInsteadOfOldSnapshot() {
        let url = "wss://relay.example.com"
        let oldSnapshot = RelayData.new(url: url, read: true, auth: false)
        let appOn = RelayData.new(url: url, read: true, auth: true)
        XCTAssertTrue(YearReviewPreferences.applyingAuth(to: [oldSnapshot], configured: [appOn], overrides: [:])[0].auth)
        let appOff = RelayData.new(url: url, read: true, auth: false)
        XCTAssertFalse(YearReviewPreferences.applyingAuth(to: [appOn], configured: [appOff], overrides: [:])[0].auth)
        let reportOnly = RelayData.new(url: "wss://report-only.example.com", read: true)
        XCTAssertFalse(YearReviewPreferences.applyingAuth(to: [reportOnly], configured: [appOn], overrides: [:])[0].auth)
    }

    func testExplicitHistoryAuthOverridesAppDefaultAndResetRestoresInheritance() throws {
        let url = "wss://relay.example.com"
        let app = RelayData.new(url: url, read: true, auth: true)
        let overrides = [url: false]
        XCTAssertFalse(YearReviewPreferences.applyingAuth(to: [app], configured: [app], overrides: overrides)[0].auth)
        XCTAssertTrue(YearReviewPreferences.applyingAuth(to: [app], configured: [app], overrides: [:])[0].auth)
        let prefs = YearReviewPreferences(cards: [], hiddenPeople: [], shareFormat: .report,
            selectedRelays: [url], relays: [.init(url: url, auth: false)], relayAuthOverrides: overrides)
        let saved = try JSONDecoder().decode(YearReviewPreferences.self, from: JSONEncoder().encode(prefs))
        XCTAssertEqual(saved.relayAuthOverrides, overrides)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(prefs)) as? [String: Any])
        legacy.removeValue(forKey: "relayAuthOverrides")
        let old = try JSONDecoder().decode(YearReviewPreferences.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(old.relayAuthOverrides)
        XCTAssertTrue(YearReviewPreferences.applyingAuth(to: old.relays.map(\.relayData), configured: [app], overrides: old.relayAuthOverrides ?? [:])[0].auth)
    }

    func testReportPreferencesPersistEmptySelectionsAndStayScopedToAccount() throws {
        let suite = "year-review-preferences-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = YearReviewPreferences(cards: [], hiddenPeople: [alice], shareFormat: .gang,
            selectedRelays: [], relays: [.init(url: "wss://history.example.com", auth: true)])
        preferences.save(owner: owner, defaults: defaults)
        let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertEqual(YearReviewPreferences.load(owner: owner, defaults: reopened), preferences)
        XCTAssertNil(YearReviewPreferences.load(owner: alice, defaults: reopened))
        let changed = YearReviewPreferences(cards: [.supporters, .gang], hiddenPeople: [], shareFormat: .report,
            selectedRelays: ["wss://history.example.com"], relays: preferences.relays)
        changed.save(owner: owner, defaults: reopened)
        XCTAssertEqual(YearReviewPreferences.load(owner: owner, defaults: defaults), changed)
    }

    func testTwoMonthPeriodBoundsEveryHistoryRequestAndItsCalendar() throws {
        let zone = TimeZone(secondsFromGMT: 0)!
        let limited = YearReviewPeriod(year: 2026, now: period.cutoffDate, timeZone: zone, monthLimit: 2)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let march = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        XCTAssertEqual(limited.end, Int64(march.timeIntervalSince1970))
        XCTAssertTrue(limited.contains(limited.end - 1))
        XCTAssertFalse(limited.contains(limited.end))
        let job = YearReviewCollection(owner: owner, period: limited,
            relays: [.new(url: "wss://relay.example.com", read: true)], trusted: [])
        XCTAssertFalse(job.pending.isEmpty)
        XCTAssertTrue(job.pending.allSatisfy { $0.since >= limited.start && $0.until < limited.end })
        XCTAssertEqual(job.monthProgress(active: []).filter(\.available).map(\.month), [1, 2])
        let data = try JSONEncoder().encode(limited)
        XCTAssertEqual(try JSONDecoder().decode(YearReviewPeriod.self, from: data), limited)
        let legacy = try JSONEncoder().encode(period)
        XCTAssertNil(try JSONDecoder().decode(YearReviewPeriod.self, from: legacy).monthLimit)
    }


    func testRandomAdjacentMonthsNeverSelectFutureMonthsAndScopeRequests() {
        let zone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3))!
        let choices = (0..<100).map { YearReviewPeriod.testMonthStart(year: 2026, now: now, timeZone: zone, choice: $0) }
        XCTAssertEqual(Set(choices), Set(1...9))
        XCTAssertEqual(YearReviewPeriod.testMonthStart(year: 2025, now: now, timeZone: zone, choice: 10), 11)
        let january = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        XCTAssertEqual(YearReviewPeriod.testMonthStart(year: 2026, now: january, timeZone: zone, choice: 99), 1)
        let limited = YearReviewPeriod(year: 2026, now: now, timeZone: zone, monthLimit: 2, monthStart: 9)
        let september = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        XCTAssertEqual(limited.start, Int64(september.timeIntervalSince1970))
        XCTAssertEqual(limited.end, Int64(now.timeIntervalSince1970))
        let job = YearReviewCollection(owner: owner, period: limited, relays: [.new(url: "wss://relay.example.com", read: true)], trusted: [])
        XCTAssertEqual(job.monthProgress(active: []).filter(\.available).map(\.month), [9, 10])
        XCTAssertTrue(job.pending.allSatisfy { $0.since >= limited.start && $0.until < limited.end })
    }

    func testFastRelayCanContinueWithinMonthWhileOtherRelayStillPending() {
        var job = YearReviewCollection(owner: owner, period: period,
            relays: [.new(url: "wss://fast.example.com", read: true), .new(url: "wss://slow.example.com", read: true)], trusted: [])
        job.pending.removeAll { $0.category == .authored }
        let anchor = job.pending.first!
        let fast = job.nextWork(for: "wss://fast.example.com", inMonthOf: anchor)!
        job.pending.removeAll { $0 == fast }
        let next = job.nextWork(for: "wss://fast.example.com", inMonthOf: anchor)
        XCTAssertNotNil(next)
        XCTAssertNotEqual(next?.category, fast.category)
        XCTAssertEqual(next?.until, fast.until)
        XCTAssertTrue(job.pending.contains { $0.relay == "wss://slow.example.com" && $0.until == fast.until })
    }

    func testRelayAdditionAcceptsFabianRelayAndDistinguishesLimitsFromInvalidURL() throws {
        let relay = "wss://fabian.nostr1.com"
        let validated = try YearReviewRelayAdditionError.validate(relay, selected: [], disabled: { _ in false })
        XCTAssertEqual(validated, normalizeRelayUrl(relay))
        let selected = Set((0..<20).map { "wss://relay\($0).example.com" })
        XCTAssertThrowsError(try YearReviewRelayAdditionError.validate(relay, selected: selected, disabled: { _ in false })) {
            guard case YearReviewRelayAdditionError.selectionLimit = $0 else { return XCTFail("Wrong error") }
        }
        XCTAssertThrowsError(try YearReviewRelayAdditionError.validate(relay, selected: [], disabled: { _ in true })) {
            guard case YearReviewRelayAdditionError.disabled = $0 else { return XCTFail("Wrong error") }
        }
    }

    @available(iOS 17.0, *)
    @MainActor
    func testRelayCanBeAddedWithMoreThanTwelveAvailableSources() {
        let model = YearReviewModel.shared
        let originalRelays = model.relays
        let originalSelection = model.selectedRelays
        let originalError = model.relayAdditionError
        defer {
            model.relays = originalRelays
            model.selectedRelays = originalSelection
            model.relayAdditionError = originalError
        }
        model.relays = (1...15).map { .new(url: "wss://relay\($0).example.com", read: true) }
        model.selectedRelays = []
        let url = "wss://test-" + UUID().uuidString.lowercased() + ".example.com"
        XCTAssertTrue(model.addRelay(url))
        XCTAssertTrue(model.selectedRelays.contains(normalizeRelayUrl(url)))
        XCTAssertEqual(model.relays.count, 16)
    }

    func testParallelPacingSnapshotsCannotShortenAnotherRelayCooldown() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = YearReviewArchive(owner: owner, fileURL: directory.appendingPathComponent("archive.sqlite"))
        let now = Date(timeIntervalSince1970: 100)
        var older = YearReviewRelayPacing()
        older.started("first", now: now, jitter: 0)
        var newer = older
        newer.failed("first", now: now)
        newer.started("second", now: now, jitter: 0)
        try await archive.savePacing(newer)
        try await archive.savePacing(older)
        let restored = try await archive.load(YearReviewRelayPacing.self, key: "relay-pacing")!
        XCTAssertEqual(restored.delay(for: "first", now: now), 60)
        XCTAssertEqual(restored.delay(for: "second", now: now), 2)
    }

    func testRelayPacingAndPersistentExponentialCooldown() throws {
        let now = Date(timeIntervalSince1970: 1000)
        var pacing = YearReviewRelayPacing()
        pacing.started("relay", now: now, jitter: 0)
        XCTAssertEqual(pacing.delay(for: "relay", now: now), 2)
        XCTAssertEqual(pacing.delay(for: "other", now: now), 0)
        pacing.failed("relay", now: now)
        XCTAssertEqual(pacing.delay(for: "relay", now: now), 60)
        pacing.failed("relay", now: now)
        let restored = try JSONDecoder().decode(YearReviewRelayPacing.self, from: JSONEncoder().encode(pacing))
        XCTAssertEqual(restored.delay(for: "relay", now: now), 120)
    }

    func testCollectionSeparatesSupportFromContentAndIncludesAllPublicKinds() {
        let job = YearReviewCollection(owner: owner, period: period, relays: [.new(url: "wss://relay.example.com", read: true)], trusted: [])
        let authoredKinds = job.pending.filter { $0.category == .authored }.flatMap { $0.kinds ?? [] }
        XCTAssertTrue(YearReviewKinds.content.isSubset(of: Set(authoredKinds)))
        XCTAssertTrue(job.pending.contains { $0.category == .incoming && ($0.filter(owner: owner)["kinds"] as? [Int])?.contains(9735) == true })
        XCTAssertTrue(job.pending.contains { $0.category == .outgoingZaps })
        XCTAssertFalse(YearReviewKinds.archived.contains(4))
        XCTAssertFalse(YearReviewKinds.archived.contains(1059))
        let root = YearReviewWork(relay: "relay", category: .rootIncoming, since: period.start, until: period.end)
        XCTAssertTrue(root.accepts(note("comment", by: alice, tags: [["P", owner]], kind: 1111), owner: owner))
    }

    func testPicturesVideosVoiceAndArticlesContributeToConversationAndReactionCards() {
        for kind in [20, 21, 22, 1222, 9802, 30023, 34235, 34236] {
            let post = note("mine-\(kind)", by: owner, content: "A post", kind: kind)
            let comment = note("reply-\(kind)", by: alice, tags: [["e", post.id], ["k", String(kind)], ["P", owner]], kind: 1111)
            let voiceReply = note("voice-\(kind)", by: alice, tags: [["e", post.id], ["k", String(kind)]], kind: 1244)
            let like = note("like-\(kind)", by: alice, content: "+", tags: [["e", post.id]], kind: 7)
            let result = analyze([post, comment, voiceReply, like], trusted: [alice])
            XCTAssertEqual(result.ownPostCount, 1)
            XCTAssertEqual(result.mostActiveDay?.posts, 1)
            XCTAssertEqual(result.conversation?.replies, 2)
            XCTAssertEqual(result.conversation?.kind, kind)
            XCTAssertEqual(result.mostReacted?.reactions, 1)
            XCTAssertEqual(result.topReplyGuy?.received, 2)
        }
    }

    func testAddressableVersionsCollapseAndSupportUsesCoordinates() {
        let address = "30023:" + owner + ":article"
        let old = note("old", by: owner, content: "Old", tags: [["d", "article"]], timestamp: period.start + 1, kind: 30023)
        let updated = note("updated", by: owner, content: "New", tags: [["d", "article"]], timestamp: period.start + 2, kind: 30023)
        let comment = note("comment", by: alice, tags: [["a", address], ["e", "old"], ["k", "30023"]], kind: 1111)
        let likes = [note("like1", by: alice, tags: [["a", address]], kind: 7), note("like2", by: alice, tags: [["e", "old"]], kind: 7)]
        let result = analyze([old, updated, comment] + likes, trusted: [alice])
        XCTAssertEqual(result.ownPostCount, 1)
        XCTAssertEqual(result.conversation?.id, "updated")
        XCTAssertEqual(result.mostReacted?.reactions, 1)
        let deletion = note("delete", by: owner, tags: [["a", address]], timestamp: period.start + 3, kind: 5)
        XCTAssertEqual(analyze([old, updated, deletion]).ownPostCount, 0)
    }

    func testSupportersAndOutgoingReactionsExcludeSpamSelfAndDuplicates() {
        let events = [note("mine", by: owner), note("theirs", by: alice),
            note("like1", by: alice, tags: [["e", "mine"]], kind: 7),
            note("like2", by: alice, tags: [["e", "mine"]], kind: 7),
            note("negative", by: bob, content: "-", tags: [["e", "mine"]], kind: 7),
            note("spam", by: bob, tags: [["e", "mine"]], kind: 7),
            note("self", by: owner, tags: [["e", "mine"]], kind: 7),
            note("repost", by: alice, tags: [["e", "mine"]], kind: 6),
            note("quote", by: alice, tags: [["q", "mine"]]),
            note("outgoing", by: owner, tags: [["e", "theirs"]], kind: 7)]
        let result = analyze(events, trusted: [alice])
        XCTAssertEqual(result.supporters.first?.pubkey, alice)
        XCTAssertEqual(result.supporters.first?.supportCount, 2)
        XCTAssertEqual(result.amplifiedBy.first?.quotes, 1)
        XCTAssertEqual(result.amplifiedBy.first?.reposts, 1)
        XCTAssertEqual(result.liked.first?.reactions, 1)
        XCTAssertEqual(result.mostInteracted.first?.interactions, 4)
        XCTAssertEqual(analyze(events, trusted: [alice], blocked: [alice]).mostReacted?.reactions, 2)
    }

    func testCommentsCountExplicitMentionsWithoutCountingThreadingTags() throws {
        let npub = try NostrEssentials.ShareableIdentifier("npub", pubkey: owner).identifier
        let comments = (0..<11).map { note("comment-\($0)", by: alice, content: "nostr:" + npub,
            tags: [["e", "missing"], ["p", owner]], kind: 1111) }
        XCTAssertEqual(analyze(comments, trusted: [alice]).mentionedBy?.mentions, 11)
        let inherited = (0..<20).map { note("inherited-\($0)", by: alice, tags: [["P", owner], ["p", owner]], kind: 1111) }
        XCTAssertNil(analyze(inherited, trusted: [alice]).mentionedBy)
    }

    private func invoice(description: String, millisats: Int64, payment: UInt8 = 1) -> String {
        let paymentHash = Data(repeating: payment, count: 32).convertBits(fromBits: 8, toBits: 5, pad: true)!
        let hash = Data(SHA256.hash(data: Data(description.utf8))).convertBits(fromBits: 8, toBits: 5, pad: true)!
        var words = Data(repeating: 0, count: 7)
        words.append(contentsOf: [1, 1, 20]); words.append(paymentHash)
        words.append(contentsOf: [23, 1, 20]); words.append(hash)
        words.append(Data(repeating: 0, count: 104))
        return Bech32().encode("lnbc\(millisats * 10)p", values: words)
    }

    func testZapValidationProviderRequestAmountHashAndPaymentDeduplication() throws {
        let payer = try Keys.newKeys()
        let recipient = try Keys.newKeys()
        let provider = try Keys.newKeys()
        let post = try signedEvent(keys: recipient)
        let request = try signedEvent(content: "", kind: 9734, keys: payer,
            tags: [["p", recipient.publicKeyHex], ["e", post.id], ["amount", "21000"]])
        let description = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        let bolt = invoice(description: description, millisats: 21000)
        let tags = [["p", recipient.publicKeyHex], ["e", post.id], ["P", payer.publicKeyHex], ["description", description], ["bolt11", bolt]]
        let receipt = try signedEvent(content: "", kind: 9735, keys: provider, tags: tags)
        let duplicate = try signedEvent(content: "", kind: 9735, keys: provider, tags: tags, timestamp: period.start + 2)
        let keys = [recipient.publicKeyHex: Set([provider.publicKeyHex])]
        XCTAssertEqual(YearReviewZap.validate(receipt, authorized: keys)?.millisats, 21000)
        XCTAssertNil(YearReviewZap.validate(receipt, authorized: [:]))
        let wrongAmount = try signedEvent(content: "", kind: 9735, keys: provider,
            tags: Array(tags.dropLast()) + [["bolt11", invoice(description: description, millisats: 22000)]])
        XCTAssertNil(YearReviewZap.validate(wrongAmount, authorized: keys))
        let wrongHash = try signedEvent(content: "", kind: 9735, keys: provider,
            tags: Array(tags.dropLast()) + [["bolt11", invoice(description: "other", millisats: 21000)]])
        XCTAssertNil(YearReviewZap.validate(wrongHash, authorized: keys))
        let result = YearReviewAnalyzer.analyze(events: [post, receipt, duplicate], owner: recipient.publicKeyHex,
            period: period, trusted: [], blocked: [], zapperKeys: keys)
        XCTAssertEqual(result.mostZapped?.zaps, 1)
        XCTAssertEqual(result.mostZapValue?.millisats, 21000)
        XCTAssertEqual(result.zappedBy.first?.pubkey, payer.publicKeyHex)
        XCTAssertEqual(result.supporters.first?.zaps, 1)
        let blocked = YearReviewAnalyzer.analyze(events: [post, receipt], owner: recipient.publicKeyHex,
            period: period, trusted: [], blocked: [payer.publicKeyHex], zapperKeys: keys)
        XCTAssertTrue(blocked.zappedBy.isEmpty)
        XCTAssertTrue(blocked.supporters.isEmpty)
        let outgoing = YearReviewAnalyzer.analyze(events: [post, receipt], owner: payer.publicKeyHex,
            period: period, trusted: [], blocked: [], zapperKeys: keys)
        XCTAssertEqual(outgoing.zapped.first?.pubkey, recipient.publicKeyHex)
    }

    func testAnonymousZapsContributeToPostsWithoutIdentifyingPayerAndRejectForgedRequest() throws {
        let recipient = try Keys.newKeys()
        let provider = try Keys.newKeys()
        let post = try signedEvent(keys: recipient)
        let request = try signedEvent(content: "", kind: 9734,
            tags: [["p", recipient.publicKeyHex], ["e", post.id], ["anon"], ["amount", "1000"]])
        let description = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        let tags = [["p", recipient.publicKeyHex], ["e", post.id], ["description", description], ["bolt11", invoice(description: description, millisats: 1000)]]
        let receipt = try signedEvent(content: "", kind: 9735, keys: provider, tags: tags)
        let authorized = [recipient.publicKeyHex: Set([provider.publicKeyHex])]
        let result = YearReviewAnalyzer.analyze(events: [post, receipt], owner: recipient.publicKeyHex,
            period: period, trusted: [], blocked: [], zapperKeys: authorized)
        XCTAssertEqual(result.mostZapped?.zaps, 1)
        XCTAssertEqual(result.anonymousZaps, 1)
        XCTAssertTrue(result.zappedBy.isEmpty)
        XCTAssertTrue(result.supporters.isEmpty)
        let forged = YearReviewEvent(id: request.id, pubkey: request.pubkey, createdAt: request.createdAt,
            kind: request.kind, tags: request.tags, content: "changed", sig: request.sig)
        let invalidDescription = String(decoding: try JSONEncoder().encode(forged), as: UTF8.self)
        let invalid = try signedEvent(content: "", kind: 9735, keys: provider,
            tags: [["p", recipient.publicKeyHex], ["e", post.id], ["description", invalidDescription],
                   ["bolt11", invoice(description: invalidDescription, millisats: 1000)]])
        XCTAssertNil(YearReviewZap.validate(invalid, authorized: authorized))
    }

    func testLargerArchiveStreamsLongArticlesAndAddressDeletions() async throws {
        XCTAssertGreaterThanOrEqual(YearReviewArchive.maximumBytes, 4_000_000_000)
        XCTAssertGreaterThanOrEqual(YearReviewArchive.maximumEvents, 2_000_000)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = YearReviewArchive(owner: owner, fileURL: directory.appendingPathComponent("archive.sqlite"))
        let keys = try Keys.newKeys()
        let article = try signedEvent(content: String(repeating: "text ", count: 20_000), kind: 30023, keys: keys, tags: [["d", "article"]])
        let added = try await archive.ingest([article], source: "test")
        XCTAssertEqual(added.added, 1)
        let report = try await archive.report(owner: keys.publicKeyHex, period: period, trusted: [], blocked: [])
        XCTAssertEqual(report.ownPostCount, 1)
        let deletion = try signedEvent(content: "", kind: 5, keys: keys, tags: [["a", article.coordinate!]], timestamp: period.start + 2)
        _ = try await archive.ingest([deletion], source: "test")
        let exported = try await archive.export()
        let lines = try String(contentsOf: exported, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 1) // Only the deletion remains.
    }

    func testCloudBatchesMergeDevicesIncrementallyWithoutEchoUploads() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cloud = root.appendingPathComponent("cloud")
        let first = YearReviewArchives(directory: root.appendingPathComponent("first"))
        let second = YearReviewArchives(directory: root.appendingPathComponent("second"))
        let a = HistoryArchiveSyncEngine(archives: first, localRoot: root.appendingPathComponent("state-a"), cloudRoot: cloud)
        let b = HistoryArchiveSyncEngine(archives: second, localRoot: root.appendingPathComponent("state-b"), cloudRoot: cloud)
        let event = try signedEvent()
        let january = try signedEvent(timestamp: period.start + 1)
        let march = try signedEvent(timestamp: period.start + 70 * 86400)
        let archiveA = await first.archive(owner: owner)
        let archiveB = await second.archive(owner: owner)
        _ = try await archiveA.ingest([event, january, march], source: "relay")
        try await a.sync()
        let initialFiles = cloudJSONFiles(cloud)
        XCTAssertEqual(initialFiles.count, 2) // Separate month folders, bounded documents.
        try await b.sync()
        let found = try await archiveB.events(before: period.end)
        XCTAssertEqual(Set(found.map(\.id)), Set([event.id, january.id, march.id]))
        XCTAssertEqual(cloudJSONFiles(cloud), initialFiles) // Downloads are not echoed back.
        let other = try signedEvent(content: "second device")
        _ = try await archiveB.ingest([other, event], source: "relay")
        try await b.sync()
        try await a.sync()
        let merged = try await archiveA.events(before: period.end)
        XCTAssertEqual(merged.count, 4)
        let outboxB = try await archiveB.syncPage(after: 0)
        XCTAssertEqual(outboxB.events.map(\.id), [other.id])
        let finalFiles = cloudJSONFiles(cloud)
        try await a.sync()
        try await b.sync()
        XCTAssertEqual(cloudJSONFiles(cloud), finalFiles)
    }

    func testCloudResetPropagatesAndOfflineDeletionDoesNotResurrectHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cloud = root.appendingPathComponent("cloud")
        let first = YearReviewArchives(directory: root.appendingPathComponent("first"))
        let second = YearReviewArchives(directory: root.appendingPathComponent("second"))
        let state = root.appendingPathComponent("state-a")
        let a = HistoryArchiveSyncEngine(archives: first, localRoot: state, cloudRoot: cloud)
        let b = HistoryArchiveSyncEngine(archives: second, localRoot: root.appendingPathComponent("state-b"), cloudRoot: cloud)
        let archiveA = await first.archive(owner: owner)
        let archiveB = await second.archive(owner: owner)
        let old = try signedEvent()
        _ = try await archiveA.ingest([old], source: "relay")
        try await a.sync()
        try await b.sync()
        let offline = HistoryArchiveSyncEngine(archives: first, localRoot: state)
        try await offline.clear(owner: owner, archive: archiveA)
        try await offline.sync()
        let new = try signedEvent(content: "after deletion")
        _ = try await archiveA.ingest([new], source: "relay")
        // Restart with connectivity: the persisted reset survives, new content remains.
        let restarted = HistoryArchiveSyncEngine(archives: first, localRoot: state, cloudRoot: cloud)
        try await restarted.sync()
        try await b.sync()
        let events = try await archiveB.events(before: period.end)
        XCTAssertEqual(events.map(\.id), [new.id])
        XCTAssertFalse(cloudJSONFiles(cloud).contains(where: { $0.contains("initial/") }))
    }

    func testCloudBatchesPreserveLocalDeletionMetadata() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cloud = root.appendingPathComponent("cloud")
        let first = YearReviewArchives(directory: root.appendingPathComponent("first"))
        let second = YearReviewArchives(directory: root.appendingPathComponent("second"))
        let a = HistoryArchiveSyncEngine(archives: first, localRoot: root.appendingPathComponent("state-a"), cloudRoot: cloud)
        let b = HistoryArchiveSyncEngine(archives: second, localRoot: root.appendingPathComponent("state-b"), cloudRoot: cloud)
        let event = try signedEvent()
        let archiveA = await first.archive(owner: owner)
        _ = try await archiveA.ingest([event], source: "relay")
        try await archiveA.recordLocalDeletions([event.id])
        try await a.sync()
        try await b.sync()
        let archiveB = await second.archive(owner: owner)
        let deleted = try await archiveB.load(Set<String>.self, key: "local-deletions")
        XCTAssertEqual(deleted, [event.id])
    }

    func testCloudBatchPageIsBoundedAndImportRejectsPrivateOrInvalidEvents() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cloud = root.appendingPathComponent("cloud")
        let archives = YearReviewArchives(directory: root.appendingPathComponent("local"))
        let sync = HistoryArchiveSyncEngine(archives: archives, localRoot: root.appendingPathComponent("state"), cloudRoot: cloud)
        let directory = cloud.appendingPathComponent(owner + "/initial/2026-01")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let privateEvent = try signedEvent(kind: 4)
        let batch = HistoryArchiveBatch(version: 1, owner: owner, generation: "initial", events: [privateEvent], deletions: [])
        try JSONEncoder().encode(batch).write(to: directory.appendingPathComponent("private.json"))
        try await sync.sync()
        let archive = await archives.archive(owner: owner)
        let found = try await archive.events(before: period.end)
        XCTAssertTrue(found.isEmpty)
        try FileManager.default.removeItem(at: directory.appendingPathComponent("private.json"))
        let unsigned = note(String(repeating: "d", count: 64), by: owner)
        let invalid = HistoryArchiveBatch(version: 1, owner: owner, generation: "initial", events: [unsigned], deletions: [])
        try JSONEncoder().encode(invalid).write(to: directory.appendingPathComponent("invalid.json"))
        try await sync.sync()
        let rejected = try await archive.events(before: period.end)
        XCTAssertTrue(rejected.isEmpty)
        let events = try (0..<205).map { try signedEvent(content: "event \($0)") }
        _ = try await archive.ingest(events, source: "relay")
        let page = try await archive.syncPage(after: 0)
        XCTAssertEqual(page.events.count, 200)
        let remainder = try await archive.syncPage(after: page.cursor)
        XCTAssertEqual(remainder.events.count, 5)
    }

    func testCloudBulkExportUsesBoundedBatchesAndResumesWithoutDuplicates() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cloud = root.appendingPathComponent("cloud")
        let archives = YearReviewArchives(directory: root.appendingPathComponent("local"))
        let sync = HistoryArchiveSyncEngine(archives: archives, localRoot: root.appendingPathComponent("state"), cloudRoot: cloud)
        let archive = await archives.archive(owner: owner)
        let events = try (0..<205).map { try signedEvent(content: "bulk \($0)") }
        _ = try await archive.ingest(events, source: "relay")
        try await sync.sync()
        let files = cloudJSONFiles(cloud)
        XCTAssertEqual(files.count, 2)
        let batches = try files.map { try JSONDecoder().decode(HistoryArchiveBatch.self, from: Data(contentsOf: URL(fileURLWithPath: $0))) }
        XCTAssertTrue(batches.allSatisfy { $0.events.count <= 200 })
        XCTAssertEqual(batches.reduce(0) { $0 + $1.events.count }, 205)
        let restart = HistoryArchiveSyncEngine(archives: archives, localRoot: root.appendingPathComponent("state"), cloudRoot: cloud)
        try await restart.sync()
        XCTAssertEqual(cloudJSONFiles(cloud), files)
    }

    func testCloudImportIsBoundedAndSkipsCompletedBatchesOnNextPass() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cloud = root.appendingPathComponent("cloud")
        let archives = YearReviewArchives(directory: root.appendingPathComponent("local"))
        let sync = HistoryArchiveSyncEngine(archives: archives, localRoot: root.appendingPathComponent("state"), cloudRoot: cloud)
        let month = cloud.appendingPathComponent(owner + "/initial/2026-01")
        try FileManager.default.createDirectory(at: month, withIntermediateDirectories: true)
        for index in 0..<10 {
            let batch = HistoryArchiveBatch(version: 1, owner: owner, generation: "initial",
                events: [try signedEvent(content: "batch \(index)")], deletions: [])
            try JSONEncoder().encode(batch).write(to: month.appendingPathComponent("\(index).json"))
        }
        let archive = await archives.archive(owner: owner)
        try await sync.sync()
        let first = try await archive.events(before: period.end)
        XCTAssertEqual(first.count, 8)
        try await sync.sync()
        let second = try await archive.events(before: period.end)
        XCTAssertEqual(second.count, 10)
        try await sync.sync()
        let third = try await archive.events(before: period.end)
        XCTAssertEqual(third.count, 10)
        let outbox = try await archive.syncPage(after: 0)
        XCTAssertTrue(outbox.events.isEmpty)
    }

    func testCloudNameListingRecognizesUndownloadedPlaceholders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in [".pending.json.icloud", "current.json", ".generation.reset.icloud"] {
            try Data().write(to: root.appendingPathComponent(name))
        }
        XCTAssertEqual(try HistoryArchiveSyncEngine.cloudNames(in: root), ["current.json", "generation.reset", "pending.json"])
    }

    func testQuietVerificationStillRejectsAlteredSignedFields() throws {
        let signed = try signedEvent()
        var event = try JSONDecoder().decode(NEvent.self, from: JSONEncoder().encode(signed))
        XCTAssertTrue(try event.verified(logInvalidID: false))
        event.content = "changed"
        XCTAssertThrowsError(try event.verified(logInvalidID: false))
    }

    private func cloudJSONFiles(_ directory: URL) -> Set<String> {
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        return Set((enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "json" }.map(\.path))
    }

    func testSeasonalDiscoveryWindowAndTargetYearRespectLocalDates() {
        var calendar = Calendar(identifier: .gregorian)
        let zone = TimeZone(secondsFromGMT: 7200)!
        calendar.timeZone = zone
        func year(_ y: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Int? {
            let date = calendar.date(from: DateComponents(year: y, month: month, day: day, hour: hour))!
            return YearReviewDiscovery.seasonalYear(now: date, timeZone: zone)
        }
        XCTAssertNil(year(2026, 12, 17))
        XCTAssertEqual(year(2026, 12, 18, hour: 0), 2026)
        XCTAssertEqual(year(2026, 12, 31), 2026)
        XCTAssertEqual(year(2027, 1, 1), 2026)
        XCTAssertEqual(year(2027, 1, 14, hour: 23), 2026)
        XCTAssertNil(year(2027, 1, 15, hour: 0))
        XCTAssertNil(year(2026, 10, 3))
        XCTAssertNotEqual(YearReviewDiscovery.dismissalKey(owner: owner, year: 2026),
                          YearReviewDiscovery.dismissalKey(owner: alice, year: 2026))
        XCTAssertNotEqual(YearReviewDiscovery.dismissalKey(owner: owner, year: 2026),
                          YearReviewDiscovery.dismissalKey(owner: owner, year: 2027))
    }

    func testReportConversationRestoresElevenRepliesThreePeopleAndOnlyRelatedDetails() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let keys = try (0..<3).map { _ in try Keys.newKeys() }
        let archive = YearReviewArchive(owner: keys[0].publicKeyHex, fileURL: directory.appendingPathComponent("archive.sqlite"))
        let root = try signedEvent(keys: keys[0])
        var events = [root]
        var parent = root.id
        for i in 0..<11 {
            let reply = try signedEvent(content: "reply \(i)", keys: keys[i % 3],
                tags: [["e", parent, "", "reply"]], timestamp: period.start + 2 + Int64(i))
            events.append(reply)
            parent = reply.id
        }
        let reaction = try signedEvent(content: "+", kind: 7, tags: [["e", root.id]])
        let repost = try signedEvent(content: "", kind: 16, tags: [["e", root.id], ["k", "1"]])
        let zap = try signedEvent(content: "", kind: 9735, tags: [["e", root.id]])
        let unrelated = try signedEvent(content: "unrelated")
        let unrelatedLike = try signedEvent(content: "+", kind: 7, tags: [["e", unrelated.id]])
        let quote = try signedEvent(content: "quote", tags: [["e", root.id, "", "mention"]])
        events += [reaction, repost, zap, unrelated, unrelatedLike, quote]
        _ = try await archive.ingest(events, source: "test")
        let report = try await archive.report(owner: root.pubkey, period: period,
            trusted: Set(keys.map(\.publicKeyHex)), blocked: [])
        let highlight = try XCTUnwrap(report.conversation)
        XCTAssertEqual(highlight.id, root.id)
        XCTAssertEqual(highlight.replies, 11)
        XCTAssertEqual(highlight.respondents, 3)
        let page = try await archive.detailPage(to: root.id)
        XCTAssertEqual(page.replyIds.count, 11)
        XCTAssertFalse(page.replyIds.contains(quote.id))
        let model = DataProvider.shared().container.managedObjectModel
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        let cache = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        cache.persistentStoreCoordinator = coordinator
        try await YearReviewDetailHydrator.restore(post: highlight, archive: archive, blocked: [], context: cache)
        try await YearReviewDetailHydrator.restore(post: highlight, archive: archive, blocked: [], context: cache)
        let cached = try await cache.perform { () -> (Set<String>, Int, Int, Int) in
            let items = try cache.fetch(Event.fetchRequest())
            let replies = items.filter { $0.replyToRootId == root.id }
            let rootEvent = try XCTUnwrap(items.first { $0.id == root.id })
            return (Set(items.map(\.id)), replies.count, Set(replies.map(\.pubkey)).count, Int(rootEvent.likesCount))
        }
        XCTAssertEqual(cached.0, Set(events.map(\.id)).subtracting([unrelated.id, unrelatedLike.id]))
        XCTAssertEqual(cached.1, 11)
        XCTAssertEqual(cached.2, 3)
        XCTAssertEqual(cached.3, 1) // Restoring twice must not double the reaction count.
        let unchanged = try await archive.events(before: period.end)
        XCTAssertEqual(unchanged.count, events.count)
    }

    func testDetailPagesAdvancePastDeletedEventsAndIncludeMissingParentRootReplies() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = YearReviewArchive(owner: owner, fileURL: directory.appendingPathComponent("archive.sqlite"))
        let root = try signedEvent()
        let replies = try (0..<205).map { i in
            try signedEvent(content: "reply \(i)", tags: [["e", root.id, "", "reply"]])
        }.sorted { $0.id < $1.id }
        _ = try await archive.ingest([root] + replies, source: "test")
        try await archive.recordLocalDeletions(Set(replies.prefix(200).map(\.id)))
        let first = try await archive.detailPage(to: root.id)
        XCTAssertTrue(first.events.isEmpty)
        XCTAssertFalse(first.cursor.isEmpty)
        let second = try await archive.detailPage(to: root.id, after: first.cursor)
        XCTAssertEqual(Set(second.events.map(\.id)), Set(replies.suffix(5).map(\.id)))
        let orphan = try signedEvent(kind: 1111, tags: [["E", root.id], ["e", String(repeating: "f", count: 64)]])
        _ = try await archive.ingest([orphan], source: "test")
        let page = try await archive.detailPage(to: root.id)
        let next = try await archive.detailPage(to: root.id, after: page.cursor)
        XCTAssertTrue((page.events + next.events).contains { $0.id == orphan.id })
    }

    @MainActor
    func testDetailHydrationDoesNotBlockNavigationWhileCacheContextIsHeld() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = YearReviewArchive(owner: owner, fileURL: directory.appendingPathComponent("archive.sqlite"))
        let root = try signedEvent()
        _ = try await archive.ingest([root], source: "test")
        let highlight = YearReviewPost(id: root.id, content: root.content, replies: 0, respondents: 0)
        let cache = DataProvider.shared().newTaskContext()
        let gate = DispatchSemaphore(value: 0)
        let entered = expectation(description: "cache held")
        holdDetailCache(cache, entered: entered, gate: gate)
        defer { gate.signal() }
        await fulfillment(of: [entered], timeout: 1)
        let hydration = Task { try await YearReviewDetailHydrator.restore(post: highlight, archive: archive, blocked: [], context: cache) }
        let navigation = expectation(description: "navigation remains responsive")
        Task { @MainActor in navigation.fulfill() }
        await fulfillment(of: [navigation], timeout: 0.5)
        hydration.cancel()
        gate.signal()
        _ = try? await hydration.value
    }

    private func holdDetailCache(_ cache: NSManagedObjectContext, entered: XCTestExpectation, gate: DispatchSemaphore) {
        cache.perform { entered.fulfill(); _ = gate.wait(timeout: .now() + 5) }
    }

    func testMostLovedUsesAllThirtyThreeCachedReactionsBeforeChoosingWinner() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ownKeys = try Keys.newKeys()
        let root = try signedEvent(keys: ownKeys)
        let other = try signedEvent(content: "runner up", keys: ownKeys)
        let trustedKeys = try (0..<10).map { _ in try Keys.newKeys() }
        var reactions = try trustedKeys.map { try signedEvent(content: "+", kind: 7, keys: $0, tags: [["e", root.id]]) }
        for i in 0..<23 {
            reactions.append(try signedEvent(content: "❤️ \(i)", kind: 7, tags: [["e", root.id]], timestamp: period.end + Int64(i)))
        }
        let runnerUp = try (0..<20).map { i in try signedEvent(content: "+ \(i)", kind: 7, tags: [["e", other.id]]) }
        let archive = YearReviewArchive(owner: root.pubkey, fileURL: directory.appendingPathComponent("archive.sqlite"))
        _ = try await archive.ingest([root, other] + Array(reactions.prefix(10)) + runnerUp, source: "relay")
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: DataProvider.shared().container.managedObjectModel)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        let cache = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        cache.persistentStoreCoordinator = coordinator
        try await cache.perform {
            let originalPost = try JSONDecoder().decode(NEvent.self, from: JSONEncoder().encode(root))
            let cachedPost = Event.fromNEvent(nEvent: originalPost, context: cache)
            cachedPost.likesCount = 33
            // Ten reactions were pruned from the main cache but remain archived.
            for reaction in reactions.dropFirst(10) {
                let original = try JSONDecoder().decode(NEvent.self, from: JSONEncoder().encode(reaction))
                let row = Event.fromNEvent(nEvent: original, context: cache)
                row.reactionToId = root.id
            }
            try cache.save()
        }
        let before = try await archive.report(owner: root.pubkey, period: period, trusted: Set(trustedKeys.map(\.publicKeyHex)), blocked: [])
        XCTAssertEqual(before.mostReacted?.id, other.id)
        let seed = try await YearReviewLocalSeed.postReactions(ids: [root.id, other.id], after: "", context: cache)
        XCTAssertEqual(seed.events.count, 23)
        _ = try await archive.ingest(seed.events, source: "local-post-reactions")
        let report = try await archive.report(owner: root.pubkey, period: period, trusted: Set(trustedKeys.map(\.publicKeyHex)), blocked: [])
        XCTAssertEqual(report.mostReacted?.id, root.id)
        XCTAssertEqual(report.mostReacted?.reactions, 33)
        let count = try await archive.reactionCount(to: root.id, blocked: [])
        XCTAssertEqual(count, 33)
        XCTAssertEqual(report.reactedBy.count, 3)
        XCTAssertTrue(report.reactedBy.allSatisfy { Set(trustedKeys.map(\.publicKeyHex)).contains($0.pubkey) && $0.reactions == 1 })
        try await YearReviewDetailHydrator.restore(post: try XCTUnwrap(report.mostReacted), archive: archive, blocked: [], context: cache)
        let detail = try await cache.perform { () -> (Int64, Int) in
            let target = try XCTUnwrap(Event.fetchEvent(id: root.id, context: cache))
            let query = Event.fetchRequest()
            query.predicate = NSPredicate(format: "kind == 7 AND reactionToId == %@", root.id)
            return (target.likesCount, Set(try cache.fetch(query).map(\.id)).count)
        }
        XCTAssertEqual(detail.0, 33) // Ten restored rows must not inflate 33 to 43.
        XCTAssertEqual(detail.1, 33)
    }

    func testMostLovedExcludesBlockedPrivateDownvotesAndInheritedTargetsButCountsRepeatEmojiAndSelf() {
        let events = [note("mine", by: owner),
            note("like", by: alice, content: "+", tags: [["e", "mine"]], kind: 7),
            note("like", by: alice, content: "+", tags: [["e", "mine"]], kind: 7),
            note("emoji", by: alice, content: "❤️", tags: [["e", "mine"]], kind: 7),
            note("self", by: owner, content: "+", tags: [["e", "mine"]], kind: 7),
            note("blocked", by: bob, content: "+", tags: [["e", "mine"]], kind: 7),
            note("downvote", by: alice, content: "-", tags: [["e", "mine"]], kind: 7),
            note("private", by: alice, content: "+", tags: [["e", "mine"], ["k", "14"]], kind: 7),
            note("inherited", by: alice, content: "+", tags: [["e", "mine"], ["e", "other"]], kind: 7)]
        XCTAssertEqual(analyze(events, trusted: [alice], blocked: [bob]).mostReacted?.reactions, 3)
    }

    private func signedEvent(content: String = "original", kind: Int = 1, keys: Keys? = nil,
                             tags: [[String]] = [], timestamp: Int64? = nil) throws -> YearReviewEvent {
        let signingKeys = try keys ?? Keys.newKeys()
        var event = NEvent(publicKey: signingKeys.publicKeyHex, createdAt: NTimestamp(timestamp: timestamp ?? period.start + 1),
                           content: content, kind: NEventKind(id: kind), tags: tags.map { Nostur.NostrTag($0) })
        let signed = try event.sign(signingKeys)
        return try JSONDecoder().decode(YearReviewEvent.self, from: JSONEncoder().encode(signed))
    }

    func testArchivedCountsUseAuthorAndSurviveResumeWithoutDuplicates() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("archive.sqlite")
        let keys = try Keys.newKeys()
        let archive = YearReviewArchive(owner: keys.publicKeyHex, fileURL: file)
        let own = try signedEvent(keys: keys)
        let other = try signedEvent()
        // A receipt referring to our pubkey is still authored by its provider.
        let receipt = try signedEvent(content: "", kind: 9735, tags: [["P", keys.publicKeyHex]])
        let imported = try await archive.ingest([own, other, receipt, own], source: "local-cache")
        XCTAssertEqual(imported.addedFromYou, 1)
        XCTAssertEqual(imported.addedFromOthers, 2)
        let restored = YearReviewArchive(owner: keys.publicKeyHex, fileURL: file)
        let counts = try await restored.archivedCounts()
        XCTAssertEqual(counts, YearReviewArchivedCounts(fromYou: 1, fromOthers: 2))
        let repeated = try await restored.ingest([own, receipt], source: "wss://relay.example.com")
        XCTAssertEqual(repeated.addedFromYou, 0)
        XCTAssertEqual(repeated.addedFromOthers, 0)
        let resumedCounts = try await restored.archivedCounts()
        XCTAssertEqual(resumedCounts, counts)
        try await restored.delete()
        let empty = try await restored.archivedCounts()
        XCTAssertEqual(empty, YearReviewArchivedCounts())
    }

    func testCollectionPrioritizesRecentPostsAndUsesReadyRelayDuringCooldown() {
        let first = "wss://first.example.com"
        let second = "wss://second.example.com"
        var job = YearReviewCollection(owner: owner, period: period,
            relays: [.new(url: first, read: true), .new(url: second, read: true)], trusted: [])
        XCTAssertEqual(job.pending.first?.category, .authored)
        XCTAssertEqual(job.pending.first?.until, period.end - 1)
        XCTAssertEqual(Set(job.pending.prefix(2).map(\.relay)), [first, second])
        let now = Date(timeIntervalSince1970: 100)
        var pacing = YearReviewRelayPacing()
        pacing.started(first, now: now, jitter: 0)
        job.pacing = pacing
        let ready = job.readyWorkIndex(excluding: [], now: now)
        XCTAssertEqual(ready.map { job.pending[$0].relay }, second)
        XCTAssertNil(job.readyWorkIndex(excluding: [second], now: now))
        XCTAssertEqual(job.readyWorkIndex(excluding: [], now: now.addingTimeInterval(2)), 0)
    }

    func testArchiveLoadsOnlyActualUndeletedReactionsForOpenedPost() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = YearReviewArchive(owner: owner, fileURL: directory.appendingPathComponent("archive.sqlite"))
        let target = String(repeating: "e", count: 64)
        let keys = try Keys.newKeys()
        let actual = try signedEvent(content: "+", kind: 7, tags: [["e", target]])
        let inherited = try signedEvent(content: "+", kind: 7, tags: [["e", target], ["e", String(repeating: "f", count: 64)]])
        let removed = try signedEvent(content: "+", kind: 7, keys: keys, tags: [["e", target]])
        let deletion = try signedEvent(kind: 5, keys: keys, tags: [["e", removed.id]])
        _ = try await archive.ingest([actual, inherited, removed, deletion, actual], source: "test")
        let reactions = try await archive.reactions(to: target)
        XCTAssertEqual(reactions.map(\.id), [actual.id])
    }

    private func liveMessage(_ event: YearReviewEvent) throws -> String {
        let fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(event))
        return String(decoding: try JSONSerialization.data(withJSONObject: ["EVENT", "detail", fields]), as: UTF8.self)
    }

    func testEverydayCaptureDeduplicatesAndRoutesOwnAccountInteractions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archives = YearReviewArchives(directory: directory)
        let recorder = LiveHistoryRecorder(archives: archives)
        let otherKeys = try Keys.newKeys()
        recorder.setAccounts([owner, otherKeys.publicKeyHex])
        let event = try signedEvent(content: "+", kind: 7, keys: otherKeys, tags: [["e", String(repeating: "e", count: 64)], ["p", owner]])
        let message = try liveMessage(event)
        recorder.receive(text: message, source: "wss://relay.example.com", owner: owner)
        recorder.receive(text: message, source: "wss://relay.example.com", owner: owner)
        try await recorder.flush()
        let activeArchive = await archives.archive(owner: owner)
        let otherArchive = await archives.archive(owner: otherKeys.publicKeyHex)
        let activeCounts = try await activeArchive.archivedCounts()
        let otherCounts = try await otherArchive.archivedCounts()
        XCTAssertEqual(activeCounts, YearReviewArchivedCounts(fromYou: 0, fromOthers: 1))
        XCTAssertEqual(otherCounts, YearReviewArchivedCounts(fromYou: 1, fromOthers: 0))
        let restored = try await activeArchive.event(id: event.id)
        XCTAssertEqual(restored, event)
    }

    func testEverydayCaptureExcludesPrivateEventsAndRejectsTamperedSignatures() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archives = YearReviewArchives(directory: directory)
        let recorder = LiveHistoryRecorder(archives: archives)
        let events = [try signedEvent(kind: 4), try signedEvent(kind: 1059),
            try signedEvent(kind: 7, tags: [["k", "14"], ["e", String(repeating: "e", count: 64)]])]
        for event in events { recorder.receive(text: try liveMessage(event), source: "test", owner: owner) }
        let signed = try signedEvent()
        let tampered = YearReviewEvent(id: signed.id, pubkey: signed.pubkey, createdAt: signed.createdAt,
            kind: signed.kind, tags: signed.tags, content: "tampered", sig: signed.sig)
        recorder.receive(text: try liveMessage(tampered), source: "test", owner: owner)
        try await recorder.flush()
        let archive = await archives.archive(owner: owner)
        let counts = try await archive.archivedCounts()
        XCTAssertEqual(counts, YearReviewArchivedCounts())
    }

    @MainActor
    func testSaturatedArchiveWriterDoesNotBlockUIIngress() async throws {
        let gate = LiveHistoryWriterGate()
        let recorder = LiveHistoryRecorder(writer: { _ in await gate.block() })
        let message = try liveMessage(signedEvent())
        recorder.receive(text: message, source: "test", owner: owner)
        await gate.waitUntilBlocked()
        let began = Date.now
        recorder.receive(text: message, source: "test", owner: owner)
        XCTAssertLessThan(Date.now.timeIntervalSince(began), 0.1)
        // The main actor remains free to execute a navigation-like state update.
        var navigated = false
        let update = Task { @MainActor in navigated = true }
        await update.value
        XCTAssertTrue(navigated)
        await gate.release()
        try await recorder.flush()
    }

    func testPreCleanupBackfillSurvivesDeletingTheNormalCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archives = YearReviewArchives(directory: directory)
        let model = DataProvider.shared().container.managedObjectModel
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        let cache = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        cache.persistentStoreCoordinator = coordinator
        let event = try signedEvent(content: "+", kind: 7, tags: [["e", String(repeating: "e", count: 64)]])
        let encoded = try JSONEncoder().encode(event)
        try await cache.perform {
            let original = try JSONDecoder().decode(NEvent.self, from: encoded)
            _ = Event.fromNEvent(nEvent: original, context: cache)
            try cache.save()
        }
        try await LiveHistoryRecorder.preserveCache(active: owner, accounts: [owner], context: cache, archives: archives)
        try await cache.perform {
            for item in try cache.fetch(Event.fetchRequest()) { cache.delete(item) }
            try cache.save()
        }
        let archive = await archives.archive(owner: owner)
        let restored = try await archive.event(id: event.id)
        XCTAssertEqual(restored, event)
    }

    func testFailedLiveBatchIsRetriedWithTheNextCapture() async throws {
        let state = LiveHistoryRetryState()
        let recorder = LiveHistoryRecorder(writer: { entries in try await state.write(entries) })
        let first = try signedEvent(content: "first")
        let second = try signedEvent(content: "second")
        recorder.receive(text: try liveMessage(first), source: "test", owner: owner)
        do { try await recorder.flush(); XCTFail("First write should fail") } catch { }
        recorder.receive(text: try liveMessage(second), source: "test", owner: owner)
        try await recorder.flush()
        let ids = await state.ids
        XCTAssertEqual(ids, [first.id, second.id])
    }

    func testArchiveWriterFailureIsReportedByFlush() async throws {
        let recorder = LiveHistoryRecorder(writer: { _ in throw YearReviewError.database("test") })
        recorder.receive(text: try liveMessage(signedEvent()), source: "test", owner: owner)
        do { try await recorder.flush(); XCTFail("A failed archive write must defer cleanup") }
        catch { XCTAssertTrue(error is YearReviewError) }
    }

    func testArchiveUsageIncludesSidecarsAndDeletesOnlyTheSelectedProfile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archives = YearReviewArchives(directory: directory)
        let first = await archives.archive(owner: owner)
        let second = await archives.archive(owner: alice)
        let event = try signedEvent()
        _ = try await first.ingest([event], source: "test")
        _ = try await second.ingest([event], source: "test")
        let originalBytes = try await first.storageBytes()
        let sidecar = directory.appendingPathComponent(owner + ".sqlite-wal")
        try Data(repeating: 0, count: 37).write(to: sidecar)
        try Data().write(to: directory.appendingPathComponent("unrelated.sqlite"))
        let sizes = try await archives.usage()
        XCTAssertEqual(Set(sizes.map(\.owner)), [owner, alice])
        XCTAssertEqual(sizes.first { $0.owner == owner }?.bytes, originalBytes + 37)
        try await archives.delete(owner: owner)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.path))
        let remaining = try await archives.usage()
        XCTAssertEqual(remaining.map(\.owner), [alice])
        let retained = try await second.event(id: event.id)
        XCTAssertEqual(retained, event)
        _ = try await first.ingest([event], source: "new-activity")
        let reloaded = try await first.event(id: event.id)
        XCTAssertEqual(reloaded, event)
    }

    func testArchiveValidatesPersistsDeduplicatesAndExportsOriginals() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("archive.sqlite")
        let archive = YearReviewArchive(owner: owner, fileURL: file)
        let event = try signedEvent()
        let first = try await archive.ingest([event, event], source: "wss://first.example.com")
        XCTAssertEqual(first.added, 1)
        let second = try await archive.ingest([event], source: "wss://second.example.com")
        XCTAssertEqual(second.added, 0)
        let forgedDuplicate = YearReviewEvent(id: event.id, pubkey: event.pubkey, createdAt: event.createdAt,
            kind: event.kind, tags: event.tags, content: "different content with a known ID", sig: event.sig)
        let rejected = try await archive.ingest([forgedDuplicate], source: "wss://untrusted.example.com")
        XCTAssertEqual(rejected.invalid, 1)
        let restored = YearReviewArchive(owner: owner, fileURL: file)
        let events = try await restored.events(before: period.end)
        XCTAssertEqual(events, [event])
        let url = try await restored.export()
        defer { try? FileManager.default.removeItem(at: url) }
        let exported = try JSONDecoder().decode(YearReviewEvent.self, from: Data(contentsOf: url))
        XCTAssertEqual(exported, event)
        XCTAssertTrue(exported.verified())
        try await restored.delete()
        let empty = try await restored.events(before: period.end)
        XCTAssertTrue(empty.isEmpty)
    }

    func testArchiveRejectsTamperedEventsAndPrivateKinds() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = YearReviewArchive(owner: owner, fileURL: directory.appendingPathComponent("archive.sqlite"))
        let event = try signedEvent()
        let tampered = YearReviewEvent(id: event.id, pubkey: event.pubkey, createdAt: event.createdAt, kind: event.kind,
                                       tags: event.tags, content: "tampered", sig: event.sig)
        let privateEvent = try signedEvent(kind: 4)
        let result = try await archive.ingest([tampered, privateEvent], source: "local-cache")
        XCTAssertEqual(result.invalid, 2)
        XCTAssertEqual(result.added, 0)
    }

    func testStorageLimitPreservesExistingReportAndRejectsNewBatchAtomically() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try signedEvent()
        let archive = YearReviewArchive(owner: owner, fileURL: directory.appendingPathComponent("archive.sqlite"),
                                         maximumBytes: try JSONEncoder().encode(first).count)
        _ = try await archive.ingest([first], source: "test")
        let second = try signedEvent()
        do {
            _ = try await archive.ingest([second], source: "test")
            XCTFail("Expected the storage limit")
        } catch YearReviewError.archiveLimit {}
        let report = try await archive.report(owner: first.pubkey, period: period, trusted: [], blocked: [])
        XCTAssertEqual(report.ownPostCount, 1)
        let retained = try await archive.events(before: period.end)
        XCTAssertEqual(retained, [first])
    }

    func testCheckpointSurvivesReopeningArchive() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("archive.sqlite")
        let archive = YearReviewArchive(owner: owner, fileURL: file)
        var job = YearReviewCollection(owner: owner, period: period, relays: [.new(url: "wss://relay.example.com", read: true)], trusted: [alice])
        job.failed = [job.pending.removeFirst()]
        job.requestsChecked = 1
        try await archive.save(job, key: "collection-2026")
        let restored = YearReviewArchive(owner: owner, fileURL: file)
        let checkpoint = try await restored.load(YearReviewCollection.self, key: "collection-2026")
        XCTAssertEqual(checkpoint, job)
    }

    func testMissingParentInventoryRejectsMalformedIDs() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = YearReviewArchive(owner: owner, fileURL: directory.appendingPathComponent("archive.sqlite"))
        let malformed = try signedEvent(tags: [["e", "invalid-parent", "", "reply"]])
        let validId = String(repeating: "f", count: 64)
        let valid = try signedEvent(tags: [["e", validId, "", "reply"]])
        _ = try await archive.ingest([malformed, valid], source: "test")
        let inventory = try await archive.inventory(owner: owner, period: period)
        XCTAssertEqual(inventory.missingParentIds, [validId])
    }

    func testLocallyKnownDeletionsSuppressReportsAndExports() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = YearReviewArchive(owner: owner, fileURL: directory.appendingPathComponent("archive.sqlite"))
        let event = try signedEvent()
        _ = try await archive.ingest([event], source: "test")
        try await archive.recordLocalDeletions([event.id])
        let report = try await archive.report(owner: event.pubkey, period: period, trusted: [], blocked: [])
        XCTAssertEqual(report.ownPostCount, 0)
        let url = try await archive.export()
        XCTAssertTrue(try Data(contentsOf: url).isEmpty)
        try await archive.delete()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testDeletionLearnedAfterYearSuppressesHistoricalPost() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = YearReviewArchive(owner: owner, fileURL: directory.appendingPathComponent("archive.sqlite"))
        let keys = try Keys.newKeys()
        let post = try signedEvent(keys: keys)
        let deletion = try signedEvent(content: "", kind: 5, keys: keys, tags: [["e", post.id]], timestamp: period.end + 10)
        _ = try await archive.ingest([post, deletion], source: "test")
        let report = try await archive.report(owner: keys.publicKeyHex, period: period, trusted: [], blocked: [])
        XCTAssertEqual(report.ownPostCount, 0)
    }

    func testVerifiedZapCacheSurvivesReopenAndSkipsProviderDiscoveryButHonorsBlocksAndDeletes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("archive.sqlite")
        let payer = try Keys.newKeys()
        let recipient = try Keys.newKeys()
        let provider = try Keys.newKeys()
        let post = try signedEvent(keys: recipient)
        let request = try signedEvent(content: "", kind: 9734, keys: payer,
            tags: [["p", recipient.publicKeyHex], ["e", post.id], ["amount", "21000"]])
        let description = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        let receipt = try signedEvent(content: "", kind: 9735, keys: provider,
            tags: [["p", recipient.publicKeyHex], ["e", post.id], ["P", payer.publicKeyHex],
                   ["description", description], ["bolt11", invoice(description: description, millisats: 21000)]])
        let archive = YearReviewArchive(owner: recipient.publicKeyHex, fileURL: file)
        _ = try await archive.ingest([post, receipt], source: "test")
        let before = try await archive.zapSigners(period: period)
        XCTAssertEqual(before[recipient.publicKeyHex], [provider.publicKeyHex])
        let first = try await archive.report(owner: recipient.publicKeyHex, period: period, trusted: [], blocked: [],
            zapperKeys: [recipient.publicKeyHex: [provider.publicKeyHex]])
        XCTAssertEqual(first.mostZapped?.zaps, 1)
        let reopened = YearReviewArchive(owner: recipient.publicKeyHex, fileURL: file)
        let remaining = try await reopened.zapSigners(period: period)
        XCTAssertTrue(remaining.isEmpty)
        // No authorization keys supplied: only a persisted, previously validated
        // receipt can produce this result without repeating its validation.
        let cached = try await reopened.report(owner: recipient.publicKeyHex, period: period, trusted: [], blocked: [])
        XCTAssertEqual(cached.mostZapped?.millisats, 21000)
        let changedProvider = try Keys.newKeys()
        let afterAddressChange = try await reopened.report(owner: recipient.publicKeyHex, period: period, trusted: [], blocked: [],
            zapperKeys: [recipient.publicKeyHex: [changedProvider.publicKeyHex]])
        XCTAssertEqual(afterAddressChange.mostZapped?.millisats, 21000)
        // An unreadable derived entry must remain eligible for provider discovery.
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(file.path, &database), SQLITE_OK)
        let cacheDatabase = try XCTUnwrap(database)
        defer { sqlite3_close(cacheDatabase) }
        XCTAssertEqual(sqlite3_exec(cacheDatabase, "UPDATE verified_zaps SET json = 'broken'", nil, nil, nil), SQLITE_OK)
        let corruptSigners = try await reopened.zapSigners(period: period)
        XCTAssertEqual(corruptSigners[recipient.publicKeyHex], [provider.publicKeyHex])
        let recovered = try await reopened.report(owner: recipient.publicKeyHex, period: period, trusted: [], blocked: [],
            zapperKeys: [recipient.publicKeyHex: [provider.publicKeyHex]])
        XCTAssertEqual(recovered.mostZapped?.zaps, 1)
        // A future validator revision must recheck old derived results.
        XCTAssertEqual(sqlite3_exec(cacheDatabase, "UPDATE verified_zaps SET version = 0", nil, nil, nil), SQLITE_OK)
        let oldVersionSigners = try await reopened.zapSigners(period: period)
        XCTAssertEqual(oldVersionSigners[recipient.publicKeyHex], [provider.publicKeyHex])
        let revalidated = try await reopened.report(owner: recipient.publicKeyHex, period: period, trusted: [], blocked: [],
            zapperKeys: [recipient.publicKeyHex: [provider.publicKeyHex]])
        XCTAssertEqual(revalidated.mostZapped?.zaps, 1)
        let blocked = try await reopened.report(owner: recipient.publicKeyHex, period: period, trusted: [], blocked: [payer.publicKeyHex])
        XCTAssertNil(blocked.mostZapped)
        try await reopened.recordLocalDeletions([receipt.id])
        let deleted = try await reopened.report(owner: recipient.publicKeyHex, period: period, trusted: [], blocked: [])
        XCTAssertNil(deleted.mostZapped)
        let newReceipt = try signedEvent(content: "", kind: 9735, keys: provider, tags: receipt.tags, timestamp: period.start + 2)
        _ = try await reopened.ingest([newReceipt], source: "test")
        let newSigners = try await reopened.zapSigners(period: period)
        XCTAssertEqual(newSigners[recipient.publicKeyHex], [provider.publicKeyHex])
    }

    func testProviderCheckCooldownPersistsAndRetriesChangedEndpointOrNewSigner() throws {
        let now = Date.now
        let check = YearReviewZapProviderCheck(checkedAt: now, endpoint: "https://old.example.com", signers: [alice])
        let saved = try JSONDecoder().decode(YearReviewZapProviderCheck.self, from: JSONEncoder().encode(check))
        XCTAssertFalse(saved.shouldRetry(endpoint: saved.endpoint, signers: [alice], now: now.addingTimeInterval(3600)))
        XCTAssertFalse(saved.shouldRetry(endpoint: nil, signers: [alice], now: now.addingTimeInterval(3600)))
        XCTAssertFalse(saved.shouldRetry(endpoint: saved.endpoint, signers: [bob], now: now.addingTimeInterval(60)))
        XCTAssertTrue(saved.shouldRetry(endpoint: saved.endpoint, signers: [bob], now: now.addingTimeInterval(301)))
        XCTAssertTrue(saved.shouldRetry(endpoint: "https://new.example.com", signers: [alice], now: now))
        XCTAssertTrue(saved.shouldRetry(endpoint: saved.endpoint, signers: [alice], now: now.addingTimeInterval(86400)))
    }

    func testProviderMetadataUsesOnlyVerifiedLatestRequestedProfiles() async throws {
        let keys = try Keys.newKeys()
        let old = try signedEvent(content: "{\"lud16\":\"old@example.com\"}", kind: 0, keys: keys)
        let recent = try signedEvent(content: "{\"lud16\":\"new@example.com\"}", kind: 0, keys: keys, timestamp: period.start + 2)
        let forged = YearReviewEvent(id: recent.id, pubkey: recent.pubkey, createdAt: period.start + 3,
            kind: 0, tags: [], content: "{\"lud16\":\"fake@example.com\"}", sig: recent.sig)
        let providers = await YearReviewZapProvider.from(events: [recent, old, forged], authors: [keys.publicKeyHex])
        XCTAssertEqual(providers.count, 1)
        XCTAssertEqual(providers.first?.lud16, "new@example.com")
        let unrelated = await YearReviewZapProvider.from(events: [recent], authors: [owner])
        XCTAssertTrue(unrelated.isEmpty)
    }

    func testLocalReceiptRecoveryPreservesSignedOriginalAndRejectsUnknownTransformation() throws {
        let original = try signedEvent(content: "", kind: 9735, tags: [["p", owner]])
        let display = YearReviewEvent(id: original.id, pubkey: original.pubkey, createdAt: original.createdAt,
            kind: original.kind, tags: original.tags, content: "Payer's message", sig: original.sig)
        XCTAssertFalse(display.verified())
        XCTAssertEqual(YearReviewLocalSeed.restoreReceipt(display), original)
        let nonempty = try signedEvent(content: "original content", kind: 9735, tags: [["p", owner]])
        XCTAssertEqual(YearReviewLocalSeed.restoreReceipt(nonempty), nonempty)
        let unknown = YearReviewEvent(id: nonempty.id, pubkey: nonempty.pubkey, createdAt: nonempty.createdAt,
            kind: nonempty.kind, tags: nonempty.tags, content: "transformed", sig: nonempty.sig)
        XCTAssertFalse(YearReviewLocalSeed.restoreReceipt(unknown).verified())
    }

    func testReceiptOriginalsRemainSignedAndDoNotEnterReplyStatistics() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = YearReviewArchive(owner: owner, fileURL: directory.appendingPathComponent("archive.sqlite"))
        let receipt = try signedEvent(content: "", kind: 9735, tags: [["p", owner]])
        _ = try await archive.ingest([receipt], source: "test")
        let restored = try await archive.events(before: period.end)
        XCTAssertEqual(restored, [receipt])
        XCTAssertTrue(restored[0].verified())
        let report = try await archive.report(owner: owner, period: period, trusted: [], blocked: [])
        XCTAssertEqual(report.ownPostCount, 0)
        XCTAssertNil(report.conversation)
    }

    func testRelayInboxTreatsClosedAndAuthenticationHintsAsIncomplete() async {
        let inbox = YearReviewRelayInbox()
        for (id, response) in [("year-c", "[\"CLOSED\",\"year-c\",\"auth-required: private history\"]"),
                               ("year-d", "[\"EOSE\",\"year-d\",[\"auth\",\"finish\"]]")] {
            let done = expectation(description: id)
            inbox.register(id: id, relay: "wss://relay.example.com") { result in
                if case .failure = result {} else { XCTFail("An incomplete source must not succeed") }
                done.fulfill()
            }
            XCTAssertTrue(inbox.route(text: response, relay: "wss://relay.example.com"))
            await fulfillment(of: [done], timeout: 1)
        }
    }

    func testHistoryAuthRetriesOnlyAfterMatchingRelayAcceptsAndOnlyOnce() async {
        let inbox = YearReviewRelayInbox()
        let retried = expectation(description: "authenticated retry")
        retried.assertForOverFulfill = true
        let rejected = expectation(description: "second auth-required is terminal")
        inbox.register(id: "year-a", relay: "wss://relay.example.com", authenticate: { _, submitted in
            submitted("signed-auth")
        }, retry: { retried.fulfill() }) { result in
            if case .failure(let error) = result {
                XCTAssertTrue(error.localizedDescription.contains("authenticated retry"))
            } else { XCTFail("Repeated auth-required must not loop") }
            rejected.fulfill()
        }
        XCTAssertTrue(inbox.route(text: "[\"AUTH\",\"challenge\"]", relay: "wss://relay.example.com"))
        XCTAssertFalse(inbox.route(text: "[\"OK\",\"signed-auth\",true,\"\"]", relay: "wss://other.example.com"))
        // ACK can precede CLOSED when the original REQ raced with authentication.
        XCTAssertTrue(inbox.route(text: "[\"OK\",\"signed-auth\",true,\"\"]", relay: "wss://relay.example.com"))
        XCTAssertTrue(inbox.route(text: "[\"CLOSED\",\"year-a\",\"auth-required: aggregator\"]", relay: "wss://relay.example.com"))
        await fulfillment(of: [retried], timeout: 1)
        XCTAssertTrue(inbox.route(text: "[\"CLOSED\",\"year-a\",\"auth-required: aggregator\"]", relay: "wss://relay.example.com"))
        await fulfillment(of: [rejected], timeout: 1)
    }

    func testHistoryClosedBeforeChallengeWaitsForAuthThenCompletesPage() async {
        let inbox = YearReviewRelayInbox()
        let waiting = expectation(description: "try stored challenge")
        let retried = expectation(description: "retry after ACK")
        let completed = expectation(description: "EOSE after retry")
        inbox.register(id: "year-b", relay: "wss://relay.example.com", authenticate: { challenge, submitted in
            if challenge.isEmpty { waiting.fulfill() }
            else { submitted("signed-auth") }
        }, retry: { retried.fulfill() }) { result in
            if case .success = result {} else { XCTFail("Authenticated history should finish") }
            completed.fulfill()
        }
        inbox.route(text: "[\"CLOSED\",\"year-b\",\"auth-required: aggregator\"]", relay: "wss://relay.example.com")
        await fulfillment(of: [waiting], timeout: 1)
        XCTAssertNotNil(inbox.receivedCount("year-b"))
        inbox.route(text: "[\"AUTH\",\"challenge\"]", relay: "wss://relay.example.com")
        inbox.route(text: "[\"OK\",\"signed-auth\",true,\"\"]", relay: "wss://relay.example.com")
        await fulfillment(of: [retried], timeout: 1)
        inbox.route(text: "[\"EOSE\",\"year-b\"]", relay: "wss://relay.example.com")
        await fulfillment(of: [completed], timeout: 1)
    }

    func testRejectedHistoryAuthenticationDoesNotRetry() async {
        let inbox = YearReviewRelayInbox()
        let rejected = expectation(description: "auth rejected")
        inbox.register(id: "year-c", relay: "wss://relay.example.com", authenticate: { _, submitted in
            submitted("signed-auth")
        }, retry: { XCTFail("Rejected AUTH must not retry") }) { result in
            if case .failure(let error) = result { XCTAssertTrue(error.localizedDescription.contains("not allowed")) }
            else { XCTFail("Rejected AUTH must fail") }
            rejected.fulfill()
        }
        inbox.route(text: "[\"AUTH\",\"challenge\"]", relay: "wss://relay.example.com")
        inbox.route(text: "[\"OK\",\"signed-auth\",false,\"not allowed\"]", relay: "wss://relay.example.com")
        await fulfillment(of: [rejected], timeout: 1)
    }

    @MainActor
    func testHistoryAuthenticationStaysResponsiveWhileImporterAndDecoderAreHeld() async {
        let entered = expectation(description: "importer held")
        let gate = DispatchSemaphore(value: 0)
        holdImporter(entered: entered, gate: gate)
        defer { gate.signal() }
        await fulfillment(of: [entered], timeout: 1)
        let worker = DispatchQueue(label: "held-history-decoder")
        let decoderEntered = expectation(description: "decoder held")
        let decoderGate = DispatchSemaphore(value: 0)
        worker.async { decoderEntered.fulfill(); _ = decoderGate.wait(timeout: .now() + 5) }
        defer { decoderGate.signal() }
        await fulfillment(of: [decoderEntered], timeout: 1)
        let inbox = YearReviewRelayInbox(worker: worker)
        let signed = expectation(description: "sign promptly")
        let cancelled = expectation(description: "cancel promptly")
        inbox.register(id: "year-d", relay: "wss://relay.example.com", authenticate: { _, submitted in
            submitted("signed-auth"); signed.fulfill()
        }, retry: { XCTFail("Cancelled request must not retry") }) { _ in cancelled.fulfill() }
        let started = Date.now
        XCTAssertTrue(inbox.route(text: "[\"AUTH\",\"challenge\"]", relay: "wss://relay.example.com"))
        await fulfillment(of: [signed], timeout: 0.5)
        XCTAssertTrue(inbox.route(text: "[\"OK\",\"signed-auth\",true,\"\"]", relay: "wss://relay.example.com"))
        inbox.cancel("year-d")
        await fulfillment(of: [cancelled], timeout: 0.5)
        XCTAssertLessThan(Date.now.timeIntervalSince(started), 0.5)
        XCTAssertFalse(inbox.route(text: "[\"OK\",\"signed-auth\",true,\"\"]", relay: "wss://relay.example.com"))
    }

    func testRelayInboxHonorsCompletionHintsAndIgnoresOtherSubscriptions() async throws {
        let inbox = YearReviewRelayInbox()
        let done = expectation(description: "page")
        inbox.register(id: "year-a", relay: "wss://relay.example.com") { result in
            if case .success(let page) = result { XCTAssertTrue(page.isExhaustive); XCTAssertTrue(page.events.isEmpty) }
            else { XCTFail("Unexpected failure") }
            done.fulfill()
        }
        XCTAssertFalse(inbox.route(text: "[\"EOSE\",\"Following-2026\"]", relay: "wss://relay.example.com"))
        XCTAssertTrue(inbox.route(text: "[\"EOSE\",\"year-a\",[\"finish\"]]", relay: "wss://relay.example.com"))
        await fulfillment(of: [done], timeout: 1)
        XCTAssertTrue(inbox.route(text: "[\"EOSE\",\"year-a\"]", relay: "wss://relay.example.com"))
    }

    func testArchivePointLookupAndMediaPreviewKeepOriginalAndStripThumbnailURL() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = YearReviewArchive(owner: owner, fileURL: directory.appendingPathComponent("archive.sqlite"))
        let imageURL = "https://example.com/photo.jpg"
        let event = try signedEvent(content: "My photo \(imageURL)")
        _ = try await archive.ingest([event], source: "test")
        let stored = try await archive.event(id: event.id)
        XCTAssertEqual(stored, event)
        let missing = try await archive.event(id: String(repeating: "f", count: 64))
        XCTAssertNil(missing)
        let context = DataProvider.shared().newTaskContext()
        let preview = try await context.perform {
            defer { context.reset() }
            return try YearReviewPostPreview.build(snapshot: event, context: context)
        }
        XCTAssertEqual(preview.thumbnail?.absoluteString, imageURL)
        XCTAssertFalse(preview.text.contains(imageURL))
        XCTAssertTrue(preview.text.contains("My photo"))
        XCTAssertFalse(preview.isVideo)
        let untouched = try await archive.event(id: event.id)
        XCTAssertEqual(untouched?.content, event.content)
    }

    func testMonthlyReceivedIncludesRepeatsAndLiveTrafficButNotReferenceChecks() throws {
        var job = YearReviewCollection(owner: owner, period: period,
            relays: [.new(url: "wss://relay.example.com", read: true)], trusted: [])
        let work = try XCTUnwrap(job.pending.first)
        job.recordMonthlyReceived(work, count: 500)
        job.recordMonthlyReceived(work, count: 500)
        let live = job.monthProgress(active: [work], received: [(work, 37)])
        XCTAssertEqual(live.reduce(0) { $0 + $1.received }, 1037)
        let reference = YearReviewWork(relay: work.relay, category: .references,
            since: work.since, until: work.until, ids: [])
        job.recordMonthlyReceived(reference, count: 200)
        XCTAssertEqual(job.monthProgress(active: [], received: [(reference, 200)]).reduce(0) { $0 + $1.received }, 1000)
        let restored = try JSONDecoder().decode(YearReviewCollection.self, from: JSONEncoder().encode(job))
        XCTAssertEqual(restored.monthlyReceived, job.monthlyReceived)
    }

    func testReceivedCountIncreasesBeforeDecoderCompletesIncludingDuplicates() async throws {
        let worker = DispatchQueue(label: "year-review-received-test-worker")
        let entered = expectation(description: "decoder blocked")
        let gate = DispatchSemaphore(value: 0)
        worker.async { entered.fulfill(); gate.wait() }
        defer { gate.signal() }
        await fulfillment(of: [entered], timeout: 1)
        let inbox = YearReviewRelayInbox(worker: worker)
        inbox.register(id: "year-d", relay: "wss://relay.example.com") { _ in }
        let event = try signedEvent()
        let payload = "[\"EVENT\",\"year-d\",\(String(decoding: try JSONEncoder().encode(event), as: UTF8.self))]"
        XCTAssertTrue(inbox.route(text: payload, relay: "wss://other.example.com"))
        XCTAssertEqual(inbox.receivedCount("year-d"), 0)
        for count in 1...3 {
            XCTAssertTrue(inbox.route(text: payload, relay: "wss://relay.example.com"))
            XCTAssertEqual(inbox.receivedCount("year-d"), count)
        }
        inbox.cancel("year-d")
        XCTAssertNil(inbox.receivedCount("year-d"))
    }

    func testHistoryTimeoutDoesNotWaitForSaturatedDecoder() async {
        let worker = DispatchQueue(label: "year-review-timeout-test-worker")
        let entered = expectation(description: "decoder blocked")
        let gate = DispatchSemaphore(value: 0)
        worker.async { entered.fulfill(); gate.wait() }
        defer { gate.signal() }
        await fulfillment(of: [entered], timeout: 1)
        let inbox = YearReviewRelayInbox(worker: worker)
        let timedOut = expectation(description: "timeout fires while decoder remains blocked")
        inbox.register(id: "year-c", relay: "wss://relay.example.com", timeout: 0.05) { result in
            if case .failure(let error) = result { XCTAssertFalse(error is CancellationError) }
            else { XCTFail("Expected the network watchdog") }
            timedOut.fulfill()
        }
        XCTAssertTrue(inbox.route(text: "[\"EOSE\",\"year-c\",[\"finish\"]]", relay: "wss://relay.example.com"))
        await fulfillment(of: [timedOut], timeout: 0.5)
    }

    func testSupplementaryBudgetsDoNotStopMonthPassesAndRenewOnResume() {
        let started = Date(timeIntervalSince1970: 100)
        let later = started.addingTimeInterval(61)
        XCTAssertFalse(YearReviewCollection.canContinueSupplementaryWork(phase: .references, startedAt: started, now: later))
        XCTAssertTrue(YearReviewCollection.canContinueSupplementaryWork(phase: .references, startedAt: later, now: later))
        XCTAssertFalse(YearReviewCollection.canContinueSupplementaryWork(phase: .parents, startedAt: started, now: started.addingTimeInterval(30)))
        XCTAssertTrue(YearReviewCollection.canContinueSupplementaryWork(phase: .primary, startedAt: started, now: later))
    }

    func testCancelDoesNotWaitForSaturatedHistoryWorker() async {
        let worker = DispatchQueue(label: "year-review-test-worker")
        let entered = expectation(description: "worker blocked")
        let gate = DispatchSemaphore(value: 0)
        worker.async { entered.fulfill(); gate.wait() }
        defer { gate.signal() }
        await fulfillment(of: [entered], timeout: 1)
        let inbox = YearReviewRelayInbox(worker: worker)
        let cancelled = expectation(description: "cancelled promptly")
        inbox.register(id: "year-b", relay: "wss://relay.example.com") { result in
            if case .failure(let error) = result { XCTAssertTrue(error is CancellationError) }
            else { XCTFail("Cancellation must not succeed") }
            cancelled.fulfill()
        }
        XCTAssertTrue(inbox.route(text: "[\"EOSE\",\"year-b\",[\"finish\"]]", relay: "wss://relay.example.com"))
        inbox.cancel("year-b")
        await fulfillment(of: [cancelled], timeout: 0.5)
    }

    @MainActor
    func testArchiveAndUIOperationCompleteWhileImporterContextIsBlocked() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = YearReviewArchive(owner: owner, fileURL: directory.appendingPathComponent("archive.sqlite"))
        let event = try signedEvent()
        let entered = expectation(description: "importer held")
        let gate = DispatchSemaphore(value: 0)
        holdImporter(entered: entered, gate: gate)
        defer { gate.signal() }
        await fulfillment(of: [entered], timeout: 1)
        let ui = expectation(description: "UI operation")
        Task { @MainActor in ui.fulfill() }
        await fulfillment(of: [ui], timeout: 0.5)
        let started = Date()
        _ = try await archive.ingest([event], source: "test")
        let report = try await archive.report(owner: event.pubkey, period: period, trusted: [], blocked: [])
        XCTAssertEqual(report.ownPostCount, 1)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
    }

    private func holdImporter(entered: XCTestExpectation, gate: DispatchSemaphore) {
        // Synchronous overload schedules work without waiting; the semaphore is
        // held only on the importer's private context, never on the main actor.
        DataProvider.shared().bg.perform { entered.fulfill(); _ = gate.wait(timeout: .now() + 5) }
    }
}

private actor LiveHistoryWriterGate {
    private var blocked = false
    private var released = false
    private var waiting: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func block() async {
        guard !released else { return }
        blocked = true
        started?.resume()
        started = nil
        await withCheckedContinuation { waiting = $0 }
    }

    func waitUntilBlocked() async {
        if blocked { return }
        await withCheckedContinuation { started = $0 }
    }

    func release() {
        released = true
        waiting?.resume()
        waiting = nil
    }
}

private actor LiveHistoryRetryState {
    private var fail = true
    var ids = Set<String>()

    func write(_ entries: [LiveHistoryRecorder.Entry]) throws {
        if fail { fail = false; throw YearReviewError.database("retry-test") }
        for entry in entries {
            if let event = LiveHistoryRecorder.event(from: entry.text) { ids.insert(event.id) }
        }
    }
}
