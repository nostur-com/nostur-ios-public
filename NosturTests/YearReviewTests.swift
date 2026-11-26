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

    func testYearToDateLabelEndsDecember15InReportTimeZone() {
        let zone = TimeZone(identifier: "Europe/Amsterdam")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let boundary = calendar.date(from: DateComponents(year: 2026, month: 12, day: 15))!
        let before = YearReviewPeriod(year: 2026, now: boundary.addingTimeInterval(-1), timeZone: zone)
        let after = YearReviewPeriod(year: 2026, now: boundary, timeZone: zone)
        XCTAssertTrue(before.showsYearToDateLabel)
        XCTAssertFalse(after.showsYearToDateLabel)
        XCTAssertTrue(after.isYearToDate)
        XCTAssertFalse(after.contains(Int64(boundary.timeIntervalSince1970)))
        let testPeriod = YearReviewPeriod(year: 2026, now: boundary, timeZone: zone, monthLimit: 2, monthStart: 11)
        XCTAssertTrue(testPeriod.showsYearToDateLabel)
    }

    private func note(_ id: String, by pubkey: String, parent: String? = nil, content: String = "",
                      tags: [[String]] = [], timestamp: Int64? = nil, kind: Int = 1) -> YearReviewEvent {
        let replyTags = parent.map { [["e", $0, "", "reply"]] } ?? []
        return YearReviewEvent(id: id, pubkey: pubkey, createdAt: timestamp ?? period.start + 1,
                               kind: kind, tags: tags + replyTags, content: content, sig: "")
    }

    private func analyze(_ events: [YearReviewEvent], trusted: Set<String> = [], blocked: Set<String> = [],
                         includeRestricted: Bool = false) -> YearReviewReport {
        YearReviewAnalyzer.analyze(events: events, owner: owner, period: period, trusted: trusted, blocked: blocked,
                                  includeRestricted: includeRestricted)
    }

    func testConversationStoriesUseSavedHistoryAndDistinctReplyDays() {
        let day = period.start
        let events = [
            note("old-post", by: owner, timestamp: day - 100),
            note("old-reply", by: bob, parent: "old-post", timestamp: day - 90),
            note("thread", by: owner, timestamp: day + 1),
            note("first", by: alice, parent: "thread", timestamp: day + 2),
            note("owner-reply", by: owner, parent: "first", timestamp: day + 86_401),
            note("back", by: alice, parent: "owner-reply", timestamp: day + 86_402),
            note("again", by: alice, parent: "owner-reply", timestamp: day + 86_403),
            note("return", by: bob, parent: "thread", timestamp: day + 5 * 86_400),
            note("owner-self", by: owner, parent: "thread", timestamp: day + 6 * 86_400)
        ]
        let report = analyze(events + [events[3]], trusted: [alice, bob])
        XCTAssertNil(report.returningThread)
        XCTAssertNil(report.newConversations)
        let recurring = (7...8).map { note("later-\($0)", by: bob, parent: "thread", timestamp: day + Int64($0) * 86_400) }
        let longer = analyze(events + recurring, trusted: [alice, bob])
        XCTAssertEqual(longer.returningThread?.post.id, "thread")
        XCTAssertEqual(longer.returningThread?.activeDays.count, 5)
        XCTAssertNil(longer.newConversations)
        let blocked = analyze(events, trusted: [alice, bob], blocked: [alice])
        XCTAssertNil(blocked.newConversations)
        XCTAssertNil(blocked.returningThread)
    }

    func testConversationStoriesIgnoreDeletedPriorExchangeAndRankFirstExchangesByThread() {
        let day = period.start
        let events = [
            note("old-post", by: owner, timestamp: day - 100),
            note("old-reply", by: bob, parent: "old-post", timestamp: day - 90),
            note("deletion", by: bob, tags: [["e", "old-reply"]], timestamp: day - 80, kind: 5),
            note("first-thread", by: owner, timestamp: day + 1),
            note("second-thread", by: owner, timestamp: day + 2),
            note("alice-first", by: alice, parent: "second-thread", timestamp: day + 3),
            note("bob-first", by: bob, parent: "second-thread", timestamp: day + 4),
            note("alice-later", by: alice, parent: "first-thread", timestamp: day + 5),
            note("bob-later", by: bob, parent: "first-thread", timestamp: day + 6)
        ]
        let charlie = String(repeating: "d", count: 64)
        let dana = String(repeating: "e", count: 64)
        let third = note("charlie-first", by: charlie, parent: "second-thread", timestamp: day + 7)
        let fourth = note("dana-first", by: dana, parent: "second-thread", timestamp: day + 8)
        XCTAssertNil(analyze(events + [third], trusted: [alice, bob, charlie]).newConversations)
        let report = analyze(Array(events.reversed()) + [third, fourth], trusted: [alice, bob, charlie, dana])
        XCTAssertEqual(report.newConversations?.post.id, "second-thread")
        XCTAssertEqual(report.newConversations?.newConversations, 4)
        XCTAssertNil(report.returningThread)
    }

    func testPostingStreakAndBreakOnlyUseSelectedLocalDays() {
        let zone = TimeZone(identifier: "Europe/Amsterdam")!
        var selected = YearReviewPeriod(year: 2026, now: Date(timeIntervalSince1970: 1_800_000_000),
            timeZone: zone, monthLimit: 2, monthStart: 3)
        selected.includeMonth(7, now: Date(timeIntervalSince1970: 1_800_000_000))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let dates = [(3, 28), (3, 29), (3, 29), (3, 30), (4, 10), (7, 1)]
        let events = dates.enumerated().map { i, date in
            let local = calendar.date(from: DateComponents(year: 2026, month: date.0, day: date.1, hour: 12))!
            return note("post-\(i)", by: owner, timestamp: Int64(local.timeIntervalSince1970))
        }
        let report = YearReviewAnalyzer.analyze(events: events, owner: owner, period: selected, trusted: [], blocked: [])
        XCTAssertEqual(report.longestPostingStreak, 3) // Includes the spring DST change.
        XCTAssertEqual(report.longestPostingBreak, 10) // March 31 through April 9.
    }

    func testAddingMonthToTwoMonthSelectionKeepsGapsUnselected() throws {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let selected = YearReviewPeriod(year: 2026, now: Date(timeIntervalSince1970: 1_800_000_000), timeZone: timeZone, monthLimit: 2, monthStart: 6)
        var job = YearReviewCollection(owner: owner, period: selected, relays: [.new(url: "wss://relay.example", read: true)], trusted: [])
        let existing = job.pending
        job.prepareMonth(1)
        XCTAssertTrue(existing.allSatisfy { job.pending.contains($0) })
        XCTAssertEqual(job.period.includedMonths, [1, 6, 7])
        XCTAssertEqual(job.period.monthLimit, 2) // Keep the existing checkpoint key.
        XCTAssertEqual(job.period.monthStart, 6)
        XCTAssertEqual(job.period.calendarDays, 92)
        let months = YearReviewCollection.monthWindows(period: job.period).map { window in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            return calendar.component(.month, from: Date(timeIntervalSince1970: Double(window.since)))
        }
        XCTAssertEqual(months, [1, 6, 7])
        let restored = try JSONDecoder().decode(YearReviewCollection.self, from: JSONEncoder().encode(job))
        XCTAssertEqual(restored.period, job.period)
        let untouched = try XCTUnwrap(job.monthProgress(active: []).first { $0.month == 2 })
        XCTAssertTrue(untouched.available)
        XCTAssertFalse(untouched.own.finished)
        XCTAssertEqual(untouched.own.completed, 0)
    }

    func testExpandedTestReportExcludesUnselectedMonths() {
        let zone = TimeZone(secondsFromGMT: 0)!
        var selected = YearReviewPeriod(year: 2026, now: Date(timeIntervalSince1970: 1_800_000_000), timeZone: zone, monthLimit: 2, monthStart: 6)
        selected.includeMonth(1)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let events = [1, 2, 6, 7].map { month in
            note("post-\(month)", by: owner,
                timestamp: Int64(calendar.date(from: DateComponents(year: 2026, month: month, day: 2))!.timeIntervalSince1970))
        }
        let report = YearReviewAnalyzer.analyze(events: events, owner: owner, period: selected, trusted: [], blocked: [])
        XCTAssertEqual(report.ownPostCount, 3)
        XCTAssertEqual(report.averagePostsPerDay, 3.0 / 92.0, accuracy: 0.00001)
    }

    func testMonthUpdateChecksNewRelayWithoutRepeatingCompletedSources() {
        let kept = RelayData.new(url: "wss://kept.example", read: true)
        let removed = RelayData.new(url: "wss://removed.example", read: true)
        let added = RelayData.new(url: "wss://added.example", read: true, auth: true)
        var job = YearReviewCollection(owner: owner, period: period, relays: [kept, removed], trusted: [])
        let removedWork = job.pending.filter { $0.relay == removed.url }
        job.pending = []
        job.failed = removedWork
        job.phase = .finished
        job.monthlyQueries = ["1-own": 1]
        job.monthlyReceived = ["1": 42]

        var authenticated = kept
        authenticated.auth = true
        job.reconcileRelays([authenticated, added])
        let scheduled = job.pending
        job.reconcileRelays([authenticated, added])
        XCTAssertEqual(job.pending, scheduled)
        job.prepareMonth(1)

        XCTAssertTrue(job.failed.isEmpty)
        XCTAssertEqual(job.relays.map(\.url), [kept.url, added.url])
        XCTAssertTrue(job.relays.allSatisfy(\.auth))
        XCTAssertEqual(Set(job.pending.map(\.relay)), [added.url])
        XCTAssertEqual(job.nextBatch(excluding: []).map(\.relay), [added.url])
        XCTAssertTrue(job.nextBatch(excluding: []).allSatisfy { job.belongsToMonth($0, month: 1) })
        XCTAssertEqual(job.monthlyQueries?["1-own"], 1)
        XCTAssertEqual(job.monthlyReceived?["1"], 42)
    }

    func testNewRelayForSingleMonthPreservesOtherMonthsAndSurvivesRestart() throws {
        let kept = RelayData.new(url: "wss://kept.example", read: true)
        let added = RelayData.new(url: "wss://added.example", read: true)
        var job = YearReviewCollection(owner: owner, period: period, relays: [kept], trusted: [])
        job.pending = []
        job.phase = .finished
        job.monthlyReceived = ["1": 12, "2": 24]
        let before = job.monthProgress(active: [])

        job.reconcileRelays([kept, added], month: 1)
        job.prepareMonth(1)
        XCTAssertEqual(job.monthProgress(active: []).filter { $0.month != 1 }, before.filter { $0.month != 1 })
        XCTAssertTrue(job.pending.allSatisfy { $0.relay == added.url && job.belongsToMonth($0, month: 1) })
        let scheduled = job.pending
        job.reconcileRelays([kept, added], month: 1)
        XCTAssertEqual(job.pending, scheduled)
        XCTAssertFalse(job.hasNewRelaySources([kept.url, added.url], month: 1))
        XCTAssertTrue(job.hasNewRelaySources([kept.url, added.url], month: 2))

        job.pending = []
        job.monthScope = nil
        var restored = try JSONDecoder().decode(YearReviewCollection.self, from: JSONEncoder().encode(job))
        XCTAssertTrue(restored.hasNewRelaySources([kept.url, added.url]))
        restored.reconcileRelays([kept, added], month: 2)
        XCTAssertTrue(restored.pending.allSatisfy { $0.relay == added.url && restored.belongsToMonth($0, month: 2) })
        XCTAssertFalse(restored.pending.isEmpty)
        restored.reconcileRelays([kept, added])
        XCTAssertFalse(restored.hasNewRelaySources([kept.url, added.url]))
        XCTAssertFalse(restored.pending.contains { restored.belongsToMonth($0, month: 1) })
    }

    func testSingleMonthRelayRemovalPreservesOtherMonthFailuresAndPendingWork() throws {
        let kept = RelayData.new(url: "wss://kept.example", read: true)
        let removed = RelayData.new(url: "wss://removed.example", read: true)
        var job = YearReviewCollection(owner: owner, period: period, relays: [kept, removed], trusted: [])
        let failed = try XCTUnwrap(job.pending.first { job.belongsToMonth($0, month: 2) && $0.relay == removed.url })
        job.pending.removeAll { $0 == failed }
        job.failed = [failed]
        let before = job.monthProgress(active: [])
        job.reconcileRelays([kept], month: 1)
        XCTAssertEqual(job.monthProgress(active: []).filter { $0.month != 1 }, before.filter { $0.month != 1 })
        job.reconcileRelays([kept])
        XCTAssertFalse(job.pending.contains { $0.relay == removed.url })
        XCTAssertTrue(job.failed.isEmpty)
    }

    func testMonthRetryPreservesSuccessfulRequestsAndOtherMonths() throws {
        var job = YearReviewCollection(owner: owner, period: period,
            relays: [.new(url: "wss://relay.example", read: true)], trusted: [])
        let completed = try XCTUnwrap(job.pending.first { job.belongsToMonth($0, month: 1) && $0.category == .authored })
        let failed = try XCTUnwrap(job.pending.first { job.belongsToMonth($0, month: 1) && $0.category == .incoming })
        job.pending.removeAll { $0 == completed || $0 == failed }
        job.failed = [failed]
        let others = job.pending.filter { !job.belongsToMonth($0, month: 1) }
        job.prepareMonth(1)
        XCTAssertFalse(job.pending.contains(completed))
        XCTAssertTrue(job.pending.contains(failed))
        XCTAssertTrue(job.failed.isEmpty)
        XCTAssertEqual(job.pending.filter { !job.belongsToMonth($0, month: 1) }, others)
        XCTAssertEqual(job.monthScope, 1)
        let restored = try JSONDecoder().decode(YearReviewCollection.self, from: JSONEncoder().encode(job))
        XCTAssertEqual(restored.monthScope, 1)
    }

    func testMonthRetryShowsActivePassDespiteEarlierCompletedQueries() throws {
        var job = YearReviewCollection(owner: owner, period: period,
            relays: [.new(url: "wss://relay.example", read: true)], trusted: [])
        let retry = try XCTUnwrap(job.pending.first { job.belongsToMonth($0, month: 1) && $0.category == .authored })
        job.pending = []
        job.failed = [retry]
        job.monthlyQueries = ["1-own": 1000, "1-others": 400]
        job.phase = .finished
        job.prepareMonth(1)
        let active = job.calendarActivity(active: [retry], scanningMonths: true)
        let progress = try XCTUnwrap(job.monthProgress(active: active, received: [(retry, 17)]).first { $0.month == 1 })
        XCTAssertTrue(progress.currentPass.active)
        XCTAssertFalse(progress.interactionPass)
        XCTAssertFalse(progress.own.finished)
        XCTAssertEqual(progress.received, 17)
        // Saving/checkpoint handoffs must prioritize a live pass even after its
        // pending request was removed from the checkpoint snapshot.
        job.pending = []
        let saving = try XCTUnwrap(job.monthProgress(active: active).first { $0.month == 1 })
        XCTAssertTrue(saving.currentPass.active)
        XCTAssertFalse(saving.interactionPass)
        XCTAssertFalse(saving.own.finished)
        XCTAssertTrue(job.monthProgress(active: active).filter { $0.month != 1 }.allSatisfy { !$0.own.active && !$0.others.active })
    }

    func testMonthlyReceivedFeedbackRemainsVisibleWhileSavingRetryResponse() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("Year in Review requires iOS 17") }
        let job = YearReviewCollection(owner: owner, period: period,
            relays: [.new(url: "wss://relay.example", read: true)], trusted: [])
        let work = try XCTUnwrap(job.pending.first)
        var activity = YearReviewActivity(work: work, timeZoneIdentifier: period.timeZoneIdentifier, step: .fetching)
        XCTAssertFalse(activity.isReceivingMonth)
        activity.received = 17
        XCTAssertTrue(activity.isReceivingMonth)
        activity.step = .saving
        XCTAssertTrue(activity.isReceivingMonth)
        activity.step = .pacing
        XCTAssertFalse(activity.isReceivingMonth)
        let references = YearReviewWork(relay: work.relay, category: .references, since: work.since, until: work.until)
        var supplementary = YearReviewActivity(work: references, timeZoneIdentifier: period.timeZoneIdentifier, step: .saving)
        supplementary.received = 17
        XCTAssertFalse(supplementary.isReceivingMonth)
    }

    func testMonthRefreshRechecksSuccessfulSourcesAlongsideFailures() throws {
        var job = YearReviewCollection(owner: owner, period: period,
            relays: [.new(url: "wss://one.example", read: true), .new(url: "wss://two.example", read: true)], trusted: [])
        let initial = job
        let monthWork = job.pending.filter { initial.belongsToMonth($0, month: 1) }
        let completed = try XCTUnwrap(monthWork.first)
        let failed = try XCTUnwrap(monthWork.last)
        job.pending.removeAll { $0 == completed || $0 == failed }
        job.failed = [failed]
        job.recordMonthlyQuery(completed)
        job.monthlyReceived = ["1": 42]
        let before = job.monthProgress(active: [])

        job.prepareMonth(1, refresh: true)

        XCTAssertEqual(job.pending.filter { job.belongsToMonth($0, month: 1) }, monthWork)
        XCTAssertTrue(job.failed.isEmpty)
        XCTAssertEqual(job.monthProgress(active: []).filter { $0.month != 1 }, before.filter { $0.month != 1 })
        XCTAssertEqual(job.monthlyReceived?["1"], 42)
        XCTAssertEqual(job.monthlyQueries?["1-own"], 1)
        XCTAssertEqual(job.monthScope, 1)
    }

    func testMonthRefreshFailureDoesNotFailOtherMonths() throws {
        var job = YearReviewCollection(owner: owner, period: period,
            relays: [.new(url: "wss://relay.example", read: true)], trusted: [])
        let snapshot = job
        job.pending.removeAll { snapshot.belongsToMonth($0, month: 1) }
        let others = job.pending
        job.phase = .finished
        job.prepareMonth(1)
        XCTAssertTrue(job.nextBatch(excluding: []).allSatisfy { job.belongsToMonth($0, month: 1) })
        let authored = job.pending.filter { job.belongsToMonth($0, month: 1) && $0.category == .authored }
        job.pending.removeAll { authored.contains($0) }
        XCTAssertTrue(job.nextBatch(excluding: []).allSatisfy { job.belongsToMonth($0, month: 1) && $0.category != .authored })
        job.markRelayUnavailable("wss://relay.example", reason: "timeout")
        XCTAssertEqual(job.pending, others)
        XCTAssertTrue(job.nextBatch(excluding: []).isEmpty)
        XCTAssertTrue(job.failed.allSatisfy { job.belongsToMonth($0, month: 1) })
        XCTAssertFalse(job.failed.isEmpty)
    }

    private var pollTags: [[String]] { [["option", "a", "Yes"], ["option", "b", "No"], ["polltype", "singlechoice"]] }

    func testPollsEnterRegularHighlightsAndPostingRhythmButVotesDoNot() {
        let poll = note("poll", by: owner, content: "Tea or coffee?", tags: pollTags, kind: 1068)
        let vote = note("vote", by: alice, tags: [["e", "poll"], ["response", "a"]], kind: 1018)
        let report = analyze([poll, vote,
            note("reply", by: alice, parent: "poll"),
            note("reaction", by: alice, content: "+", tags: [["e", "poll"]], kind: 7)], trusted: [alice])
        XCTAssertEqual(report.ownPostCount, 1)
        XCTAssertEqual(report.mostActiveDay?.posts, 1)
        XCTAssertEqual(report.conversation?.id, "poll")
        XCTAssertEqual(report.conversation?.replies, 1)
        XCTAssertEqual(report.mostReacted?.id, "poll")
        XCTAssertEqual(report.mostReacted?.reactions, 1)
        XCTAssertEqual(report.supporters.first?.supportCount, 1)
        XCTAssertEqual(report.polls?.mostVotedCount, 1)
        XCTAssertEqual(report.polls?.mostVoted?.kind, 1068)
    }

    func testPollVotersAreUniqueAcrossPollsAndParticipationCountsPollsNotVotes() {
        let events = [note("first", by: owner, tags: pollTags, kind: 1068),
            note("second", by: owner, tags: pollTags, kind: 1068),
            note("other", by: alice, tags: pollTags, timestamp: period.start - 10, kind: 1068),
            note("one", by: bob, tags: [["e", "first"], ["response", "a"]], kind: 1018),
            note("two", by: bob, tags: [["e", "second"], ["response", "b"]], kind: 1018),
            note("my-old", by: owner, tags: [["e", "other"], ["response", "a"]], timestamp: period.start + 2, kind: 1018),
            note("my-new", by: owner, tags: [["e", "other"], ["response", "b"]], timestamp: period.start + 3, kind: 1018)]
        let report = analyze(events + events)
        XCTAssertEqual(report.polls?.created, 2)
        XCTAssertEqual(report.polls?.voters, 1) // All valid voters, even outside WoT.
        XCTAssertEqual(report.polls?.votedIn, 1)
        XCTAssertEqual(report.polls?.mostVoted?.id, "first")
        XCTAssertTrue(report.supporters.isEmpty)
        XCTAssertTrue(report.mostInteracted.isEmpty)
    }

    func testPollTallyHonorsClosingTimeOptionsChangedVotesAndReportCutoff() {
        let end = period.start + 20
        let poll = note("poll", by: owner, tags: pollTags + [["endsAt", String(end)]], kind: 1068)
        let votes = [note("before", by: alice, tags: [["e", "poll"], ["response", "a"]], timestamp: period.start + 2, kind: 1018),
            note("invalid-latest", by: alice, tags: [["e", "poll"], ["response", "invalid"], ["response", "b"]], timestamp: period.start + 3, kind: 1018),
            note("valid", by: bob, tags: [["e", "poll"], ["response", "b"]], timestamp: end, kind: 1018),
            note("after-close", by: bob, tags: [["e", "poll"], ["response", "invalid"]], timestamp: end + 1, kind: 1018),
            note("before-poll", by: owner, tags: [["e", "poll"], ["response", "a"]], timestamp: period.start, kind: 1018),
            note("after-year", by: owner, tags: [["e", "poll"], ["response", "a"]], timestamp: period.end, kind: 1018)]
        let report = analyze([poll] + votes)
        XCTAssertEqual(report.polls?.voters, 1)
        XCTAssertEqual(report.polls?.mostVotedCount, 1)
        XCTAssertEqual(report.polls?.votedIn, 0)
    }

    func testMultipleChoiceStillCountsOneVoterAndUsesFirstETag() {
        let tags = pollTags.filter { $0.first != "polltype" } + [["polltype", "multiplechoice"]]
        let report = analyze([note("poll", by: owner, tags: tags, kind: 1068),
            note("vote", by: alice, tags: [["e", "poll"], ["e", "wrong"], ["response", "a"], ["response", "b"], ["response", "a"]], kind: 1018)])
        XCTAssertEqual(report.polls?.voters, 1)
        XCTAssertEqual(report.polls?.mostVotedCount, 1)
    }

    func testPollBlocksDeletionsAndParticipationOnlyCard() {
        let poll = note("poll", by: alice, tags: pollTags, kind: 1068)
        let vote = note("vote", by: owner, tags: [["e", "poll"], ["response", "a"]], kind: 1018)
        let report = analyze([poll, vote])
        XCTAssertEqual(report.polls?.created, 0)
        XCTAssertEqual(report.polls?.votedIn, 1)
        XCTAssertTrue(YearReviewCard.polls.hasHighlight(in: report))
        XCTAssertNil(report.polls?.mostVoted)
        XCTAssertNil(analyze([poll, vote], blocked: [alice]).polls)
        XCTAssertNil(analyze([poll, vote, note("delete", by: owner, tags: [["e", "vote"]], kind: 5)]).polls)
        XCTAssertNil(analyze([poll, vote, note("delete", by: alice, tags: [["e", "poll"]], kind: 5)]).polls)
        XCTAssertNil(analyze([]).polls)
    }

    func testPollCollectionFetchesVotesWithoutAuthorPTagAndResolvesVotedPolls() async throws {
        let poll = try signedEvent(kind: 1068, tags: pollTags)
        let vote = try signedEvent(kind: 1018, tags: [["e", poll.id], ["response", "a"]])
        let work = YearReviewWork(relay: "wss://relay.example", category: .references, since: period.start, until: period.end - 1, ids: [poll.id])
        XCTAssertTrue((work.filter(owner: poll.pubkey)["kinds"] as? [Int])?.contains(1018) == true)
        XCTAssertTrue(work.accepts(vote, owner: poll.pubkey))
        XCTAssertTrue(YearReviewKinds.content.contains(1068))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = YearReviewArchive(owner: vote.pubkey, fileURL: directory.appendingPathComponent("archive.sqlite"))
        _ = try await archive.ingest([vote], source: "test")
        let inventory = try await archive.inventory(owner: vote.pubkey, period: period)
        XCTAssertTrue(inventory.missingParentIds.contains(poll.id))
    }

    func testRetiredHighlightDoesNotResetSavedPreferences() throws {
        let data = Data("""
        {"cardSelectionVersion":4,"cards":["replyRegular","returningThread"],"hiddenPeople":["hidden"],"shareFormat":"report","selectedRelays":["wss://relay.example"],"relays":[]}
        """.utf8)
        let preferences = try JSONDecoder().decode(YearReviewPreferences.self, from: data)
        XCTAssertEqual(preferences.selectedCards, [.returningThread])
        XCTAssertEqual(preferences.hiddenPeople, ["hidden"])
        XCTAssertEqual(preferences.selectedRelays, ["wss://relay.example"])
    }

    func testNewPollCardDefaultsPreserveExistingHiddenCards() {
        var preferences = YearReviewPreferences(cards: [.activeDay], hiddenPeople: [], shareFormat: .report, selectedRelays: [], relays: [])
        preferences.cardSelectionVersion = 2
        XCTAssertEqual(preferences.selectedCards, [.activeDay, .polls, .returningThread, .newConversations])
        preferences.cardSelectionVersion = 3
        XCTAssertEqual(preferences.selectedCards, [.activeDay, .returningThread, .newConversations])
        preferences.cardSelectionVersion = 4
        XCTAssertEqual(preferences.selectedCards, [.activeDay])
    }

    func testPollArchiveAndHighlightedDetailRestoreVotesWithMatchingTally() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let poll = try signedEvent(content: "A question?", kind: 1068, tags: pollTags)
        let vote = try signedEvent(kind: 1018, tags: [["e", poll.id], ["response", "a"]])
        let pollArchive = PollArchive(root: directory.appendingPathComponent("polls"))
        let pollJSON = String(decoding: try JSONEncoder().encode(poll), as: UTF8.self)
        let voteJSON = String(decoding: try JSONEncoder().encode(vote), as: UTF8.self)
        let saved = await pollArchive.save(owner: poll.pubkey, json: pollJSON)
        XCTAssertTrue(saved)
        _ = await pollArchive.saveResults(owner: poll.pubkey, pollID: poll.id, jsons: [voteJSON])
        let reopened = PollArchive(root: directory.appendingPathComponent("polls"))
        let page = await reopened.historyPage(owner: poll.pubkey, after: "")
        XCTAssertEqual(Set(page.map(\.id)), [poll.id, vote.id])
        let archive = YearReviewArchive(owner: poll.pubkey, fileURL: directory.appendingPathComponent("archive.sqlite"))
        _ = try await archive.ingest(page + [vote], source: "poll-archive")
        let report = try await archive.report(owner: poll.pubkey, period: period, trusted: [], blocked: [])
        let highlight = try XCTUnwrap(report.polls?.mostVoted)
        XCTAssertEqual(report.polls?.mostVotedCount, 1)
        let detail = try await archive.detailPage(to: poll.id)
        XCTAssertEqual(detail.events.map(\.id), [vote.id])
        XCTAssertTrue(detail.replyIds.isEmpty)
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: DataProvider.shared().container.managedObjectModel)
        _ = try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        try await YearReviewDetailHydrator.restore(post: highlight, archive: archive, blocked: [], context: context)
        let definition = NostrPoll(id: poll.id, createdAt: Int(poll.createdAt), tags: poll.tags)
        let cached = await PollRelayClient.shared.cachedVotes(poll: definition, context: context)
        let tally = PollTally(poll: definition, votes: cached, now: Int(period.end))
        XCTAssertEqual(tally.totalVoters, report.polls?.mostVotedCount)
        let empty = await reopened.historyPage(owner: poll.pubkey, after: page.last!.id)
        XCTAssertTrue(empty.isEmpty)
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
        XCTAssertEqual(job.calendarActivity(active: [], scanningMonths: true), [first])
        var pacing = YearReviewRelayPacing()
        pacing.started(first.relay)
        job.pacing = pacing
        XCTAssertEqual(job.calendarActivity(active: [], scanningMonths: true), [first])
        job.pending.removeFirst()
        job.recordMonthlyQuery(first)
        let next = job.pending.first!
        let handoff = job.calendarActivity(active: [], scanningMonths: true)
        XCTAssertEqual(handoff, [next])
        XCTAssertEqual(job.monthProgress(active: handoff).filter { $0.own.active }.count, 1)
        XCTAssertTrue(job.calendarActivity(active: [next], scanningMonths: false).isEmpty)
        job.pending.removeAll { $0.category == .authored }
        let interactions = job.pending.first!
        XCTAssertEqual(job.calendarActivity(active: [], scanningMonths: true), [interactions])
        XCTAssertEqual(job.monthProgress(active: job.calendarActivity(active: [], scanningMonths: true)).filter { $0.others.active }.count, 1)
    }

    @MainActor
    func testSingleMonthCalendarStopsWhileBuildingReportWithOtherMonthsPending() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("Year in Review requires iOS 17") }
        var job = YearReviewCollection(owner: owner, period: period,
            relays: [.new(url: "wss://relay.example.com", read: true)], trusted: [])
        job.prepareMonth(1)
        let model = YearReviewModel.shared
        let (previousCollection, previousStage, wasRunning) = (model.collection, model.stage, model.isRunning)
        defer {
            model.collection = previousCollection
            model.stage = previousStage
            model.isRunning = wasRunning
        }
        model.isRunning = true
        model.stage = .posts
        model.collection = job
        let active = try XCTUnwrap(model.calendarActivity.first)
        XCTAssertTrue(job.belongsToMonth(active, month: 1))

        let snapshot = job
        job.pending.removeAll { snapshot.belongsToMonth($0, month: 1) }
        let otherMonth = try XCTUnwrap(job.pending.first)
        model.collection = job
        XCTAssertTrue(model.calendarActivity.isEmpty)
        XCTAssertTrue(job.calendarActivity(active: [otherMonth], scanningMonths: true).isEmpty)

        model.stage = .parents
        job.monthScope = nil
        model.collection = job
        XCTAssertEqual(job.nextBatch(excluding: []).first, otherMonth)
        XCTAssertTrue(model.calendarActivity.isEmpty)
    }

    func testFinalCollectionStagesUseBusyHeaderInsteadOfRestartingCalendar() {
        var job = YearReviewCollection(owner: owner, period: period,
            relays: [.new(url: "wss://relay.example.com", read: true)], trusted: [])
        job.pending = []
        for phase in [YearReviewCollection.Phase.references, .parents, .finished] {
            job.phase = phase
            let references = YearReviewWork(relay: "wss://relay.example.com", category: .references,
                since: period.start, until: period.end - 1)
            XCTAssertTrue(job.calendarActivity(active: [references], scanningMonths: true).isEmpty)
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
        let tappable = (1...12).filter { month in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            return calendar.date(from: DateComponents(year: 2026, month: month, day: 1))! < Date.now
        }
        XCTAssertEqual(job.monthProgress(active: []).filter(\.available).map(\.month), tappable)
        let data = try JSONEncoder().encode(limited)
        XCTAssertEqual(try JSONDecoder().decode(YearReviewPeriod.self, from: data), limited)
        let legacy = try JSONEncoder().encode(period)
        XCTAssertNil(try JSONDecoder().decode(YearReviewPeriod.self, from: legacy).monthLimit)
    }


    func testLegacyLimitedPeriodScopesRequestsAndKeepsOtherMonthsTappable() {
        let zone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3))!
        let limited = YearReviewPeriod(year: 2026, now: now, timeZone: zone, monthLimit: 2, monthStart: 9)
        let september = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        XCTAssertEqual(limited.start, Int64(september.timeIntervalSince1970))
        XCTAssertEqual(limited.end, Int64(now.timeIntervalSince1970))
        let job = YearReviewCollection(owner: owner, period: limited, relays: [.new(url: "wss://relay.example.com", read: true)], trusted: [])
        let tappable = (1...12).filter { month in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            return calendar.date(from: DateComponents(year: 2026, month: month, day: 1))! < Date.now
        }
        XCTAssertEqual(job.monthProgress(active: []).filter(\.available).map(\.month), tappable)
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

    func testSuccessfulRelayResponseResetsCooldownAcrossOutOfOrderSaves() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = YearReviewArchive(owner: owner, fileURL: directory.appendingPathComponent("archive.sqlite"))
        let now = Date(timeIntervalSince1970: 1_000)
        var pacing = YearReviewRelayPacing()
        pacing.failed("relay", now: now)
        pacing.failed("relay", now: now.addingTimeInterval(60))
        let failed = pacing
        try await archive.savePacing(failed)
        let recoveredAt = now.addingTimeInterval(200)
        pacing.started("relay", now: recoveredAt, jitter: 0)
        pacing.succeeded("relay", now: recoveredAt.addingTimeInterval(1))
        try await archive.savePacing(pacing)
        try await archive.savePacing(failed)
        var restored = try await archive.load(YearReviewRelayPacing.self, key: "relay-pacing")!
        XCTAssertEqual(restored.delay(for: "relay", now: recoveredAt), 2)
        XCTAssertEqual(restored.failures["relay", default: 0], 0)
        restored.failed("relay", now: recoveredAt.addingTimeInterval(10))
        XCTAssertEqual(restored.delay(for: "relay", now: recoveredAt.addingTimeInterval(10)), 60)
    }

    @MainActor
    func testHealthyAppSocketRecoversConnectionCooldownButPreservesQueryBackoff() async throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("Year in Review requires iOS 17") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = YearReviewArchive(owner: owner, fileURL: directory.appendingPathComponent("archive.sqlite"))
        let pool = ConnectionPool()
        pool.queue = DispatchQueue(label: "history-cooldown-recovery")
        let relays = ["healthy", "limited", "offline"].map { RelayData.new(url: "wss://\($0).example", read: true) }
        let connections = relays.map { Nostur.RelayConnection($0, queue: pool.queue) }
        await withCheckedContinuation { continuation in
            pool.queue.async(flags: .barrier) {
                for (relay, connection) in zip(relays, connections) { pool.connections[relay.id] = connection }
                connections[0].isSocketConnected = true
                connections[1].isSocketConnected = true
                continuation.resume()
            }
        }
        var pacing = YearReviewRelayPacing()
        pacing.failed(relays[0].url, scope: .connection)
        pacing.failed(relays[1].url, scope: .request)
        pacing.failed(relays[2].url, scope: .connection)
        try await archive.savePacing(pacing)
        var job = YearReviewCollection(owner: owner, period: period, relays: relays, trusted: [])
        job.pacing = pacing
        let pending = job.pending
        try await YearReviewModel.shared.recoverConnectedHistoryRelays(&job, archive: archive, pool: pool)
        XCTAssertEqual(job.pacing?.delay(for: relays[0].url), 0)
        XCTAssertGreaterThan(job.pacing?.delay(for: relays[1].url) ?? 0, 3)
        XCTAssertGreaterThan(job.pacing?.delay(for: relays[2].url) ?? 0, 3)
        XCTAssertEqual(job.pending, pending)
        try await archive.savePacing(pacing) // A delayed older write must not restore the recovered cooldown.
        let persisted = try await archive.load(YearReviewRelayPacing.self, key: "relay-pacing")
        XCTAssertEqual(persisted?.delay(for: relays[0].url), 0)
        XCTAssertFalse(persisted?.canRecoverConnection(relays[0].url, legacyFailures: []) ?? true)
    }

    func testLegacyCooldownAllowsOneHealthySocketRecoveryExceptKnownRateLimits() throws {
        var old = YearReviewRelayPacing()
        old.nextRequest["relay"] = Date.now.addingTimeInterval(120)
        old.failures["relay"] = 3
        var restored = try JSONDecoder().decode(YearReviewRelayPacing.self, from: JSONEncoder().encode(old))
        XCTAssertNil(restored.failureScopes)
        XCTAssertTrue(restored.canRecoverConnection("relay", legacyFailures: []))
        let work = YearReviewWork(relay: "relay", category: .incoming, since: 1, until: 2)
        for reason in ["rate-limited: slow down", "auth-required: sign in", "blocked: access denied", "Connection failed (HTTP 429)"] {
            let failure = YearReviewSourceFailure(work: work, status: .failed, reason: reason,
                trigger: work, received: 0, date: .now)
            XCTAssertFalse(restored.canRecoverConnection("relay", legacyFailures: [failure]))
        }
        restored.recoveredConnection("relay")
        XCTAssertEqual(restored.delay(for: "relay"), 0)
        XCTAssertFalse(restored.canRecoverConnection("relay", legacyFailures: []))
        restored.failed("relay", scope: .request)
        XCTAssertFalse(restored.canRecoverConnection("relay", legacyFailures: []))
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
        let event = try signedEvent(tags: [["p", owner]])
        let january = try signedEvent(tags: [["p", owner]], timestamp: period.start + 1)
        let march = try signedEvent(tags: [["p", owner]], timestamp: period.start + 70 * 86400)
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
        let other = try signedEvent(content: "second device", tags: [["p", owner]])
        _ = try await archiveB.ingest([other, event], source: "relay")
        try await b.sync()
        try await a.sync()
        let merged = try await archiveA.events(before: period.end)
        XCTAssertEqual(merged.count, 4)
        let monthlyA = try await archiveA.monthlyArchivedCounts(year: period.year,
            timeZone: TimeZone(secondsFromGMT: 0)!)
        let monthlyB = try await archiveB.monthlyArchivedCounts(year: period.year,
            timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(monthlyA, monthlyB)
        XCTAssertEqual(monthlyA.values.reduce(0, +), 4)
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

    func testReleaseAvailabilityStartsAfterDecember10InLocalTime() {
        let zone = TimeZone(identifier: "Europe/Amsterdam")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let launch = calendar.date(from: DateComponents(year: 2026, month: 12, day: 11))!
        XCTAssertFalse(YearReviewFeature.isReleased(now: launch.addingTimeInterval(-1), timeZone: zone))
        XCTAssertTrue(YearReviewFeature.isReleased(now: launch, timeZone: zone))
        XCTAssertFalse(YearReviewFeature.isReleased(now: launch, timeZone: TimeZone(secondsFromGMT: 0)!))
        XCTAssertTrue(YearReviewFeature.isReleased(now: launch.addingTimeInterval(365 * 86_400), timeZone: zone))
        #if DEBUG
        XCTAssertTrue(YearReviewFeature.isEnabled)
        #endif
    }

    @MainActor
    func testNineVersionTapsUnlockReleaseAccessAndPersistAcrossLaunches() {
        let suite = "YearReviewEarlyAccessTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = YearReviewEarlyAccess(defaults: defaults)
        let beforeRelease = Date(timeIntervalSince1970: 1_790_000_000)
        for _ in 0..<8 { state.tapVersion() }
        XCTAssertFalse(state.isUnlocked)
        XCTAssertFalse(YearReviewFeature.isAvailableInRelease(now: beforeRelease, defaults: defaults))
        state.tapVersion()
        XCTAssertTrue(state.isUnlocked)
        XCTAssertTrue(YearReviewFeature.isAvailableInRelease(now: beforeRelease, defaults: defaults))
        XCTAssertTrue(YearReviewEarlyAccess(defaults: defaults).isUnlocked)
        state.tapVersion()
        XCTAssertTrue(state.isUnlocked)
    }

    @MainActor
    func testDiscoveryLaterPersistsForThreeDaysAndOpeningSuppressesReminder() {
        let suite = "YearReviewDiscoveryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = YearReviewDiscoveryState(defaults: defaults, resetsOnLaunch: false)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertTrue(state.shouldPrompt(owner: owner, year: 2026, now: now))
        state.remindLater(owner: owner, year: 2026, now: now, calendar: calendar)
        let relaunched = YearReviewDiscoveryState(defaults: defaults, resetsOnLaunch: false)
        XCTAssertFalse(relaunched.shouldPrompt(owner: owner, year: 2026, now: now.addingTimeInterval(3 * 86_400 - 1)))
        XCTAssertTrue(relaunched.shouldPrompt(owner: owner, year: 2026, now: now.addingTimeInterval(3 * 86_400)))
        XCTAssertTrue(relaunched.shouldPrompt(owner: alice, year: 2026, now: now))
        relaunched.markOpened(owner: owner, year: 2026)
        let opened = YearReviewDiscoveryState(defaults: defaults, resetsOnLaunch: false)
        XCTAssertFalse(opened.shouldPrompt(owner: owner, year: 2026, now: now.addingTimeInterval(30 * 86_400)))
        XCTAssertTrue(opened.hasOpened(owner: owner, year: 2026))
        XCTAssertTrue(opened.hasOpened(owner: owner, year: 2027))
        XCTAssertFalse(opened.shouldPrompt(owner: owner, year: 2027, now: now))
        XCTAssertFalse(opened.hasOpened(owner: alice, year: 2026))
    }

    @MainActor
    func testDebugDiscoveryResetsEachLaunchWithoutChangingReleasePreferences() {
        let suite = "YearReviewDiscoveryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let release = YearReviewDiscoveryState(defaults: defaults, resetsOnLaunch: false)
        release.markOpened(owner: owner, year: 2026)
        let firstLaunch = YearReviewDiscoveryState(defaults: defaults, resetsOnLaunch: true)
        XCTAssertTrue(firstLaunch.shouldPrompt(owner: owner, year: 2026))
        firstLaunch.markOpened(owner: owner, year: 2026)
        firstLaunch.remindLater(owner: alice, year: 2026)
        XCTAssertFalse(firstLaunch.shouldPrompt(owner: owner, year: 2026))
        XCTAssertFalse(firstLaunch.shouldPrompt(owner: alice, year: 2026))
        let nextLaunch = YearReviewDiscoveryState(defaults: defaults, resetsOnLaunch: true)
        XCTAssertTrue(nextLaunch.shouldPrompt(owner: owner, year: 2026))
        XCTAssertTrue(nextLaunch.shouldPrompt(owner: alice, year: 2026))
        XCTAssertTrue(release.hasOpened(owner: owner, year: 2026))
        XCTAssertFalse(release.hasOpened(owner: alice, year: 2026))
    }

    func testDiscoveryOnlyAppearsOnVisibleCaughtUpFeedAtTop() {
        XCTAssertTrue(YearReviewDiscovery.canPresent(isVisible: true, isAtTop: true, unreadCount: 0, isRestoring: false))
        XCTAssertFalse(YearReviewDiscovery.canPresent(isVisible: false, isAtTop: true, unreadCount: 0, isRestoring: false))
        XCTAssertFalse(YearReviewDiscovery.canPresent(isVisible: true, isAtTop: false, unreadCount: 0, isRestoring: false))
        XCTAssertFalse(YearReviewDiscovery.canPresent(isVisible: true, isAtTop: true, unreadCount: 1, isRestoring: false))
        XCTAssertFalse(YearReviewDiscovery.canPresent(isVisible: true, isAtTop: true, unreadCount: 0, isRestoring: true))
        #if DEBUG
        XCTAssertNotNil(YearReviewDiscovery.promptYear())
        #endif
    }

    func testSeasonalDiscoveryWindowAndTargetYearRespectLocalDates() {
        var calendar = Calendar(identifier: .gregorian)
        let zone = TimeZone(secondsFromGMT: 7200)!
        calendar.timeZone = zone
        func year(_ y: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Int? {
            let date = calendar.date(from: DateComponents(year: y, month: month, day: day, hour: hour))!
            return YearReviewDiscovery.seasonalYear(now: date, timeZone: zone)
        }
        XCTAssertNil(year(2026, 12, 10))
        XCTAssertEqual(year(2026, 12, 11, hour: 0), 2026)
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

    private func storeReportSnapshot(archive: YearReviewArchive, pubkey: String,
                                     period requestedPeriod: YearReviewPeriod? = nil, includeRestricted: Bool = false) async throws -> YearReviewSavedReport {
        let period = requestedPeriod ?? self.period
        let revision = try await archive.reportRevision()
        let report = try await archive.report(owner: pubkey, period: period, trusted: [], blocked: [], includeRestricted: includeRestricted)
        let saved = YearReviewSavedReport(version: YearReviewSavedReport.currentVersion, owner: pubkey,
            revision: revision, report: report,
            previews: ["post": .init(text: "A preview", thumbnail: URL(string: "https://example.com/photo.jpg"), extraCount: 0, isVideo: false)],
            names: [alice: "Alice"], pictures: [:], collection: nil,
            counts: try await archive.archivedCounts(), lastFetchedDate: nil, trusted: [], blocked: [], zapperKeys: [:],
            includeRestrictedContent: includeRestricted)
        try await archive.save(saved, key: "cached-report-test")
        return saved
    }

    func testReportCoverageMigratesLegacyCheckpointWithoutRetainingRequests() throws {
        var collection = YearReviewCollection(owner: owner, period: period,
            relays: [.new(url: "wss://relay.example", read: true)], trusted: [alice])
        collection.failed = [collection.pending[0]]
        collection.estimatedResponses = 4
        collection.parentsLimited = true
        let legacy = try JSONEncoder().encode(collection)
        let coverage = try JSONDecoder().decode(YearReviewReportCoverage.self, from: legacy)
        XCTAssertEqual(coverage, YearReviewReportCoverage(collection))
        let compact = try JSONEncoder().encode(coverage)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: compact) as? [String: Any])
        XCTAssertEqual(Set(fields.keys), ["phase", "hasIncompleteSources", "estimatedResponses", "parentsLimited"])
        XCTAssertLessThan(compact.count, 200)
        XCTAssertEqual(try JSONDecoder().decode(YearReviewReportCoverage.self, from: compact), coverage)
    }

    func testSavedReportRestoresExpandedTestMonthsBeforeLoadingFullCheckpoint() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let event = try signedEvent()
        let archive = YearReviewArchive(owner: event.pubkey, fileURL: directory.appendingPathComponent("archive.sqlite"))
        let selection = YearReviewPeriod(year: 2026, now: Date(timeIntervalSince1970: 1_800_000_000),
            timeZone: TimeZone(secondsFromGMT: 0)!, monthLimit: 2, monthStart: 8)
        var expanded = selection
        expanded.includeMonth(1)
        var collection = YearReviewCollection(owner: event.pubkey, period: expanded,
            relays: [.new(url: "wss://relay.example", read: true)], trusted: [])
        collection.pending.append(.init(relay: "wss://relay.example", category: .references,
            since: expanded.start, until: expanded.end - 1, ids: [alice, bob]))
        try await archive.save(collection, key: "collection-2026")
        _ = try await storeReportSnapshot(archive: archive, pubkey: event.pubkey, period: expanded)
        let cached = try await archive.savedReport(key: "cached-report-test", period: selection,
            trusted: [], blocked: [], restoringSavedSelection: true)
        XCTAssertEqual(cached?.snapshot.report.period, expanded)
        XCTAssertEqual(cached?.isCurrent, true)
        let strict = try await archive.savedReport(key: "cached-report-test", period: selection, trusted: [], blocked: [])
        XCTAssertNil(strict)
        let restored = try await archive.load(YearReviewCollection.self, key: "collection-2026")
        XCTAssertEqual(restored, collection)
    }

    func testSavedReportSurvivesRestartAndDistinguishesDuplicatesFromNewHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let event = try signedEvent()
        let file = directory.appendingPathComponent("archive.sqlite")
        let archive = YearReviewArchive(owner: event.pubkey, fileURL: file)
        _ = try await archive.ingest([event], source: "relay")
        let saved = try await storeReportSnapshot(archive: archive, pubkey: event.pubkey)

        let reopened = YearReviewArchive(owner: event.pubkey, fileURL: file)
        let cached = try await reopened.savedReport(key: "cached-report-test", period: period, trusted: [], blocked: [])
        XCTAssertEqual(cached?.snapshot.report, saved.report)
        XCTAssertEqual(cached?.snapshot.previews, saved.previews)
        XCTAssertEqual(cached?.snapshot.names, saved.names)
        XCTAssertEqual(cached?.snapshot.counts, saved.counts)
        XCTAssertEqual(cached?.isCurrent, true)

        _ = try await reopened.ingest([event], source: "another-relay")
        let duplicate = try await reopened.savedReport(key: "cached-report-test", period: period, trusted: [], blocked: [])
        XCTAssertEqual(duplicate?.isCurrent, true)

        let another = try signedEvent(content: "New history")
        _ = try await reopened.ingest([another], source: "relay")
        let updating = try await reopened.savedReport(key: "cached-report-test", period: period, trusted: [], blocked: [])
        XCTAssertEqual(updating?.isCurrent, false)
        XCTAssertEqual(updating?.snapshot.report, saved.report)
    }

    @MainActor
    func testSavedReportLoadsPromptlyWhileImporterIsBlocked() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let event = try signedEvent()
        let archive = YearReviewArchive(owner: event.pubkey, fileURL: directory.appendingPathComponent("archive.sqlite"))
        _ = try await archive.ingest([event], source: "relay")
        _ = try await storeReportSnapshot(archive: archive, pubkey: event.pubkey)
        let entered = expectation(description: "importer blocked")
        let gate = DispatchSemaphore(value: 0)
        holdImporter(entered: entered, gate: gate)
        defer { gate.signal() }
        await fulfillment(of: [entered], timeout: 1)
        let started = Date.now
        let cached = try await archive.savedReport(key: "cached-report-test", period: period, trusted: [], blocked: [])
        XCTAssertEqual(cached?.isCurrent, true)
        XCTAssertLessThan(Date.now.timeIntervalSince(started), 0.5)
    }

    func testSavedReportRejectsChangedFiltersPeriodAndCorruptCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let event = try signedEvent()
        let archive = YearReviewArchive(owner: event.pubkey, fileURL: directory.appendingPathComponent("archive.sqlite"))
        _ = try await archive.ingest([event], source: "relay")
        _ = try await storeReportSnapshot(archive: archive, pubkey: event.pubkey)
        let blocked = try await archive.savedReport(key: "cached-report-test", period: period, trusted: [], blocked: [alice])
        let trust = try await archive.savedReport(key: "cached-report-test", period: period, trusted: [alice], blocked: [])
        let otherPeriod = YearReviewPeriod(year: 2026, timeZone: TimeZone(secondsFromGMT: 0)!, monthLimit: 2, monthStart: 9)
        let selection = try await archive.savedReport(key: "cached-report-test", period: otherPeriod, trusted: [], blocked: [])
        XCTAssertNil(blocked)
        XCTAssertNil(trust)
        XCTAssertNil(selection)
        let newZapKeys = try await archive.savedReport(key: "cached-report-test", period: period, trusted: [],
            blocked: [], zapperKeys: [alice: [bob]])
        XCTAssertEqual(newZapKeys?.isCurrent, false)
        try await archive.save("Unrecognized cache format", key: "cached-report-test")
        let corrupt = try await archive.savedReport(key: "cached-report-test", period: period, trusted: [], blocked: [])
        XCTAssertNil(corrupt)
    }

    func testSavedReportInvalidatesForDeletedHistoryAndZapProviderUpdates() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let keys = try Keys.newKeys()
        let event = try signedEvent(keys: keys)
        let file = directory.appendingPathComponent("archive.sqlite")
        let archive = YearReviewArchive(owner: event.pubkey, fileURL: file)
        _ = try await archive.ingest([event], source: "relay")
        _ = try await storeReportSnapshot(archive: archive, pubkey: event.pubkey)
        try await archive.save([alice: Set([bob])], key: "zap-providers")
        let providers = try await archive.savedReport(key: "cached-report-test", period: period, trusted: [], blocked: [])
        XCTAssertEqual(providers?.isCurrent, false)

        try await archive.recordLocalDeletions([event.id])
        let localDeletion = try await archive.savedReport(key: "cached-report-test", period: period, trusted: [], blocked: [])
        XCTAssertNil(localDeletion)
        _ = try await storeReportSnapshot(archive: archive, pubkey: event.pubkey)
        let before = try await archive.reportRevision()
        try await archive.recordLocalDeletions([event.id])
        let after = try await archive.reportRevision()
        XCTAssertEqual(before, after)

        let deletion = try signedEvent(content: "", kind: 5, keys: keys, tags: [["e", event.id]])
        _ = try await archive.ingest([deletion], source: "relay")
        let remoteDeletion = try await archive.savedReport(key: "cached-report-test", period: period, trusted: [], blocked: [])
        XCTAssertNil(remoteDeletion)

        _ = try await storeReportSnapshot(archive: archive, pubkey: event.pubkey)
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(file.path, &database), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, "DELETE FROM events", nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)
        let manualDeletion = try await archive.savedReport(key: "cached-report-test", period: period, trusted: [], blocked: [])
        XCTAssertNil(manualDeletion)
    }

    @MainActor
    func testMonthlySavedCountsOnlyIncludeAccountAndPostReferencesIncludingLegacyArchives() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("archive.sqlite")
        let keys = try Keys.newKeys()
        let archive = YearReviewArchive(owner: keys.publicKeyHex, fileURL: file)
        let oldPost = try signedEvent(keys: keys, timestamp: period.start - 1)
        let article = try signedEvent(kind: 30023, keys: keys, tags: [["d", "article"]])
        let unrelated = try signedEvent()
        let context = try signedEvent(content: "parent of my reply")
        let ownReply = try signedEvent(keys: keys, tags: [["e", context.id]])
        let mention = try signedEvent(tags: [["p", keys.publicKeyHex]])
        let reaction = try signedEvent(kind: 7, tags: [["e", article.id], ["p", keys.publicKeyHex]])
        let quote = try signedEvent(tags: [["q", article.coordinate!]])
        let comment = try signedEvent(kind: 1111, tags: [["E", article.id]])
        let zap = try signedEvent(kind: 9735, tags: [["P", keys.publicKeyHex]])
        let oldReference = try signedEvent(tags: [["e", oldPost.id]])
        let unrelatedReaction = try signedEvent(kind: 7, tags: [["e", unrelated.id]])
        _ = try await archive.ingest([oldPost, article, unrelated, context, ownReply, mention,
            reaction, quote, comment, zap, oldReference, unrelatedReaction, reaction], source: "local-cache")
        let otherKeys = try Keys.newKeys()
        let unrelatedFeed = try (0..<510).map { try signedEvent(content: "Feed post \($0)", keys: otherKeys) }
        _ = try await archive.ingest(unrelatedFeed, source: "local-cache")
        let counts = try await archive.monthlyArchivedCounts(year: period.year, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(counts.values.reduce(0, +), 8)
        // Simulate an archive written before the relationship index existed.
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(file.path, &database), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, "DROP TABLE account_refs; DROP TABLE account_posts; DELETE FROM metadata WHERE key LIKE 'account-index-%'", nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)
        let reopened = YearReviewArchive(owner: keys.publicKeyHex, fileURL: file)
        var progress: [Double] = []
        let zone = TimeZone(secondsFromGMT: 0)!
        let migrated = try await reopened.monthlyArchivedCounts(year: period.year, timeZone: zone) {
            progress.append($0)
        }
        XCTAssertEqual(migrated, counts)
        XCTAssertEqual(progress.first, 0)
        XCTAssertTrue(progress.contains { $0 > 0 && $0 < 0.99 })
        XCTAssertEqual(progress, progress.sorted())
        progress.removeAll()
        _ = try await reopened.monthlyArchivedCounts(year: period.year, timeZone: zone) {
            progress.append($0)
        }
        XCTAssertTrue(progress.isEmpty)
        let retained = try await reopened.event(id: unrelated.id)
        XCTAssertEqual(retained, unrelated) // Counting does not delete archive context.
    }

    func testMonthlySavedCountsRecognizePostReferencesWhenOwnPostArrivesLater() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let keys = try Keys.newKeys()
        let archive = YearReviewArchive(owner: keys.publicKeyHex, fileURL: directory.appendingPathComponent("archive.sqlite"))
        let post = try signedEvent(keys: keys)
        let reference = try signedEvent(tags: [["e", post.id]])
        _ = try await archive.ingest([reference], source: "relay")
        let before = try await archive.monthlyArchivedCounts(year: period.year, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(before.values.reduce(0, +), 0)
        _ = try await archive.ingest([post, reference], source: "icloud:other-device")
        let after = try await archive.monthlyArchivedCounts(year: period.year, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(after.values.reduce(0, +), 2)
    }

    func testMonthlySavedCountsDeduplicateRelaysCloudCopiesAndSurviveReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("archive.sqlite")
        let keys = try Keys.newKeys()
        let archive = YearReviewArchive(owner: keys.publicKeyHex, fileURL: file)
        var calendar = Calendar(identifier: .gregorian)
        let zone = TimeZone(secondsFromGMT: 0)!
        calendar.timeZone = zone
        func timestamp(_ month: Int) -> Int64 {
            Int64(calendar.date(from: DateComponents(year: 2026, month: month, day: 10))!.timeIntervalSince1970)
        }
        let january = try signedEvent(keys: keys, timestamp: timestamp(1))
        let reaction = try signedEvent(kind: 7, tags: [["e", january.id]], timestamp: timestamp(1))
        let march = try signedEvent(kind: 9802, keys: keys, timestamp: timestamp(3))
        _ = try await archive.ingest([january, reaction, january], source: "wss://first.example")
        _ = try await archive.ingest([reaction, january], source: "wss://second.example")
        let before = try await archive.monthlyArchivedCounts(year: 2026, timeZone: zone)
        XCTAssertEqual(before[1], 2)
        XCTAssertEqual(before[3], 0)
        _ = try await archive.ingest([march, january], source: "icloud:other-device.json")
        let reopened = YearReviewArchive(owner: keys.publicKeyHex, fileURL: file)
        let counts = try await reopened.monthlyArchivedCounts(year: 2026, timeZone: zone)
        XCTAssertEqual(counts.count, 12)
        XCTAssertEqual(counts[1], 2)
        XCTAssertEqual(counts[3], 1)
        XCTAssertEqual(counts.values.reduce(0, +), 3)
        try await reopened.delete()
        let empty = try await reopened.monthlyArchivedCounts(year: 2026, timeZone: zone)
        XCTAssertEqual(empty.values.reduce(0, +), 0)
    }

    func testMonthlySavedCountsRespectLocalMonthAndYearBoundaries() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let keys = try Keys.newKeys()
        let archive = YearReviewArchive(owner: keys.publicKeyHex, fileURL: directory.appendingPathComponent("archive.sqlite"))
        let zone = TimeZone(identifier: "Europe/Amsterdam")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day))!
        }
        let first = Int64(date(2026, 1, 1).timeIntervalSince1970)
        let april = Int64(date(2026, 4, 1).timeIntervalSince1970)
        let nextDay = date(2026, 4, 2)
        let events = try [first - 1, first, april - 1, april, Int64(nextDay.timeIntervalSince1970),
                          Int64(date(2027, 1, 1).timeIntervalSince1970)].map { try signedEvent(keys: keys, timestamp: $0) }
        _ = try await archive.ingest(events, source: "relay")
        let counts = try await archive.monthlyArchivedCounts(year: 2026, timeZone: zone)
        XCTAssertEqual(counts[1], 1)
        XCTAssertEqual(counts[3], 1)
        XCTAssertEqual(counts[4], 2)
        XCTAssertEqual(counts.values.reduce(0, +), 4)
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

    func testEverydayCaptureRetainsRestrictedButExcludesPrivateAndTamperedEvents() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archives = YearReviewArchives(directory: directory)
        let recorder = LiveHistoryRecorder(archives: archives)
        let events = [try signedEvent(kind: 4), try signedEvent(kind: 1059),
            try signedEvent(tags: [["-"]]), try signedEvent(kind: 7, tags: [["-"]]),
            try signedEvent(kind: 7, tags: [["k", "14"], ["e", String(repeating: "e", count: 64)]])]
        for event in events { recorder.receive(text: try liveMessage(event), source: "test", owner: owner) }
        let signed = try signedEvent()
        let tampered = YearReviewEvent(id: signed.id, pubkey: signed.pubkey, createdAt: signed.createdAt,
            kind: signed.kind, tags: signed.tags, content: "tampered", sig: signed.sig)
        recorder.receive(text: try liveMessage(tampered), source: "test", owner: owner)
        try await recorder.flush()
        let archive = await archives.archive(owner: owner)
        let counts = try await archive.archivedCounts()
        XCTAssertEqual(counts, YearReviewArchivedCounts(fromYou: 0, fromOthers: 2))
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

    func testReportExcludesRestrictedPostsRepliesReactionsAndPrivateKinds() {
        let publicPost = note("public", by: owner)
        let publicHyphen = note("public-hyphen", by: owner, content: "-")
        let protected = YearReviewKinds.content.map { kind in
            note("restricted-\(kind)", by: owner, tags: [["-"]], kind: kind)
        }
        let events = [publicPost, publicHyphen]
            + protected
            + [note("restricted-reply", by: alice, parent: publicPost.id, tags: [["-"]]),
               note("restricted-like", by: alice, content: "+", tags: [["e", publicPost.id], ["-"]], kind: 7),
               note("dm-like", by: alice, content: "+", tags: [["e", publicPost.id], ["k", "14"]], kind: 7),
               note("dm", by: owner, kind: 4), note("rumor", by: owner, kind: 14),
               note("wrap", by: owner, kind: 1059),
               note("like-protected", by: alice, content: "+", tags: [["e", "restricted-1"]], kind: 7)]
        let report = analyze(events, trusted: [alice])
        XCTAssertEqual(report.ownPostCount, 2)
        XCTAssertEqual(report.mostActiveDay?.posts, 2)
        XCTAssertNil(report.mostReacted)
        XCTAssertNil(report.conversation)
        XCTAssertTrue(report.people.isEmpty)
        XCTAssertEqual(report.polls?.created ?? 0, 0)
        XCTAssertFalse(publicHyphen.isRestricted, "A hyphen in content is not the restriction tag")
    }

    func testArchiveRetainsRestrictedButRejectsPrivateMessageReactions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = YearReviewArchive(owner: owner, fileURL: directory.appendingPathComponent("archive.sqlite"))
        let restricted = try signedEvent(tags: [["-"]])
        let restrictedReaction = try signedEvent(content: "+", kind: 7, tags: [["-", "restricted"]])
        let dmReaction = try signedEvent(content: "+", kind: 7, tags: [["k", "14"]])
        let publicPost = try signedEvent(content: "-")
        let result = try await archive.ingest([restricted, restrictedReaction, dmReaction, publicPost], source: "relay")
        XCTAssertEqual(result.invalid, 1)
        XCTAssertEqual(result.added, 3)
        let stored = try await archive.events(before: period.end)
        XCTAssertEqual(Set(stored.map(\.id)), Set([restricted.id, restrictedReaction.id, publicPost.id]))
    }

    func testRestrictedContentOptInIncludesPostsAndTheirInteractionsButNeverDMs() {
        let events = [note("public", by: owner), note("restricted", by: owner, tags: [["-"]]),
            note("restricted-reply", by: alice, parent: "restricted", tags: [["-"]]),
            note("public-reply", by: bob, parent: "restricted"),
            note("restricted-reaction", by: bob, content: "+", tags: [["e", "public"], ["-"]], kind: 7),
            note("public-reaction", by: alice, content: "+", tags: [["e", "restricted"]], kind: 7),
            note("quote", by: bob, tags: [["q", "restricted"]]),
            note("dm-reaction", by: alice, content: "+", tags: [["e", "public"], ["k", "14"]], kind: 7),
            note("dm", by: owner, kind: 4), note("rumor", by: owner, kind: 14), note("wrap", by: owner, kind: 1059)]
        let publicReport = analyze(events, trusted: [alice, bob])
        XCTAssertEqual(publicReport.ownPostCount, 1)
        XCTAssertTrue(publicReport.people.isEmpty)
        XCTAssertNil(publicReport.conversation)
        let full = analyze(events, trusted: [alice, bob], includeRestricted: true)
        XCTAssertEqual(full.ownPostCount, 2)
        XCTAssertEqual(full.conversation?.id, "restricted")
        XCTAssertEqual(full.conversation?.replies, 2)
        XCTAssertEqual(full.mostReacted?.reactions, 1)
        XCTAssertEqual(full.amplifiedBy.first?.quotes, 1)
        XCTAssertEqual(full.people, Set([alice, bob]))
    }

    func testRestrictedPreferenceDefaultsOffAndPersistsPerProfile() throws {
        let suite = "year-review-restricted-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var preferences = YearReviewPreferences(cards: [], hiddenPeople: [], shareFormat: .report,
            selectedRelays: [], relays: [])
        let legacy = try JSONDecoder().decode(YearReviewPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertFalse(legacy.includeRestrictedContent ?? false)
        preferences.includeRestrictedContent = true
        preferences.save(owner: owner, defaults: defaults)
        XCTAssertEqual(YearReviewPreferences.load(owner: owner, defaults: defaults)?.includeRestrictedContent, true)
        XCTAssertFalse(YearReviewPreferences.load(owner: alice, defaults: defaults)?.includeRestrictedContent ?? false)
        preferences.includeRestrictedContent = false
        preferences.save(owner: owner, defaults: defaults)
        XCTAssertEqual(YearReviewPreferences.load(owner: owner, defaults: defaults)?.includeRestrictedContent, false)
    }

    func testRestrictedReportCachesCannotBeReusedForTheOtherScope() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let keys = try Keys.newKeys()
        let archive = YearReviewArchive(owner: keys.publicKeyHex, fileURL: directory.appendingPathComponent("archive.sqlite"))
        let publicPost = try signedEvent(keys: keys)
        let restricted = try signedEvent(keys: keys, tags: [["-"]])
        _ = try await archive.ingest([publicPost, restricted], source: "relay")
        _ = try await storeReportSnapshot(archive: archive, pubkey: keys.publicKeyHex, includeRestricted: true)
        let full = try await archive.savedReport(key: "cached-report-test", period: period, trusted: [], blocked: [], includeRestricted: true)
        XCTAssertEqual(full?.snapshot.report.ownPostCount, 2)
        let blocked = try await archive.savedReport(key: "cached-report-test", period: period, trusted: [], blocked: [])
        XCTAssertNil(blocked)
        _ = try await storeReportSnapshot(archive: archive, pubkey: keys.publicKeyHex)
        let publicOnly = try await archive.savedReport(key: "cached-report-test", period: period, trusted: [], blocked: [])
        XCTAssertEqual(publicOnly?.snapshot.report.ownPostCount, 1)
        let needsRebuild = try await archive.savedReport(key: "cached-report-test", period: period, trusted: [], blocked: [], includeRestricted: true)
        XCTAssertNil(needsRebuild)
    }

    func testRestrictedDetailPagesAndReactionCountsFollowReportScope() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = YearReviewArchive(owner: owner, fileURL: directory.appendingPathComponent("archive.sqlite"))
        let post = try signedEvent()
        let reply = try signedEvent(tags: [["e", post.id, "", "reply"], ["-"]])
        let reaction = try signedEvent(content: "+", kind: 7, tags: [["e", post.id], ["-"]])
        _ = try await archive.ingest([post, reply, reaction], source: "relay")
        let publicPage = try await archive.detailPage(to: post.id)
        let fullPage = try await archive.detailPage(to: post.id, includeRestricted: true)
        XCTAssertTrue(publicPage.events.isEmpty)
        XCTAssertEqual(Set(fullPage.events.map(\.id)), Set([reply.id, reaction.id]))
        let publicCount = try await archive.reactionCount(to: post.id, blocked: [])
        let fullCount = try await archive.reactionCount(to: post.id, blocked: [], includeRestricted: true)
        XCTAssertEqual(publicCount, 0)
        XCTAssertEqual(fullCount, 1)
    }

    func testPublicHistoryExportOmitsRetainedRestrictedEvents() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = YearReviewArchive(owner: owner, fileURL: directory.appendingPathComponent("archive.sqlite"))
        let publicPost = try signedEvent()
        let restricted = try signedEvent(tags: [["-"]])
        _ = try await archive.ingest([publicPost, restricted], source: "relay")
        let url = try await archive.export()
        defer { try? FileManager.default.removeItem(at: url) }
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        let exported = try lines.map { try JSONDecoder().decode(YearReviewEvent.self, from: Data($0.utf8)) }
        XCTAssertEqual(exported.map(\.id), [publicPost.id])
    }

    func testLegacyReportCacheBeforeRestrictedFilteringIsRejected() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let event = try signedEvent()
        let archive = YearReviewArchive(owner: event.pubkey, fileURL: directory.appendingPathComponent("archive.sqlite"))
        _ = try await archive.ingest([event], source: "relay")
        let current = try await storeReportSnapshot(archive: archive, pubkey: event.pubkey)
        let legacy = YearReviewSavedReport(version: 1, owner: current.owner, revision: current.revision,
            report: current.report, previews: current.previews, names: current.names, pictures: current.pictures,
            collection: current.collection, counts: current.counts, lastFetchedDate: current.lastFetchedDate,
            trusted: current.trusted, blocked: current.blocked, zapperKeys: current.zapperKeys)
        try await archive.save(legacy, key: "cached-report-test")
        let restored = try await archive.savedReport(key: "cached-report-test", period: period, trusted: [], blocked: [])
        XCTAssertNil(restored, "An older report must be rebuilt using the public-only policy")
    }

    func testCloudMixedBatchRetainsRestrictedHistoryButReportDefaultsPublic() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let keys = try Keys.newKeys()
        let owner = keys.publicKeyHex
        let cloud = root.appendingPathComponent("cloud")
        let directory = cloud.appendingPathComponent(owner + "/initial/2026-01")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let restricted = try signedEvent(keys: keys, tags: [["-"]])
        let publicPost = try signedEvent(keys: keys)
        let batch = HistoryArchiveBatch(version: 1, owner: owner, generation: "initial", events: [restricted, publicPost], deletions: [])
        try JSONEncoder().encode(batch).write(to: directory.appendingPathComponent("legacy.json"))
        let archives = YearReviewArchives(directory: root.appendingPathComponent("local"))
        let sync = HistoryArchiveSyncEngine(archives: archives, localRoot: root.appendingPathComponent("state"), cloudRoot: cloud)
        try await sync.sync()
        let archive = await archives.archive(owner: owner)
        let events = try await archive.events(before: period.end)
        XCTAssertEqual(Set(events.map(\.id)), Set([publicPost.id, restricted.id]))
        let publicReport = try await archive.report(owner: owner, period: period, trusted: [], blocked: [])
        let fullReport = try await archive.report(owner: owner, period: period, trusted: [], blocked: [], includeRestricted: true)
        XCTAssertEqual(publicReport.ownPostCount, 1)
        XCTAssertEqual(fullReport.ownPostCount, 2)
        let outbox = try await archive.syncPage(after: 0)
        XCTAssertTrue(outbox.events.isEmpty)
    }

    func testDatabaseSeedExcludesPrivateAndGroupContexts() async throws {
        let context = DataProvider.shared().newTaskContext()
        let author = try Keys.newKeys().publicKeyHex
        let start = period.start
        let ids = (0..<3).map { _ in UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() }
        for parentsOnly in [false, true] {
            await context.perform {
                for index in ids.indices {
                    let event = Event(context: context)
                    event.id = ids[index]
                    event.pubkey = author
                    event.created_at = start + 1
                    event.kind = 1
                    event.sig = "fixture"
                    event.content = "seed privacy"
                    if index == 1 { event.otherId = "private-message" }
                    if index == 2 { event.groupId = "private-group" }
                }
            }
            let batch: YearReviewLocalSeed.Batch
            if parentsOnly { batch = try await YearReviewLocalSeed.parents(ids: ids, context: context) }
            else { batch = try await YearReviewLocalSeed.batch(owner: author, period: period, offset: 0, context: context) }
            XCTAssertEqual(batch.events.map(\.id), [ids[0]])
        }
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

    func testZapProviderDiscoveryOnlyIncludesRelevantValidReceipts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let account = try Keys.newKeys()
        let other = try Keys.newKeys()
        let stranger = try Keys.newKeys()
        let provider = try Keys.newKeys()
        func receipt(to recipient: Keys, from payer: Keys, payment: UInt8) throws -> YearReviewEvent {
            let request = try signedEvent(content: "", kind: 9734, keys: payer,
                tags: [["p", recipient.publicKeyHex], ["amount", "21000"]])
            let description = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
            return try signedEvent(content: "", kind: 9735, keys: provider,
                tags: [["p", recipient.publicKeyHex], ["description", description],
                       ["bolt11", invoice(description: description, millisats: 21000, payment: payment)]])
        }
        let incoming = try receipt(to: account, from: stranger, payment: 1)
        let outgoing = try receipt(to: other, from: account, payment: 2)
        let unrelated = try receipt(to: stranger, from: other, payment: 3)
        let invalid = try signedEvent(content: "", kind: 9735, keys: provider, tags: [["p", account.publicKeyHex]])
        let archive = YearReviewArchive(owner: account.publicKeyHex, fileURL: directory.appendingPathComponent("archive.sqlite"))
        _ = try await archive.ingest([incoming, outgoing, unrelated, invalid], source: "test")
        let signers = try await archive.zapSigners(period: period, relevantTo: account.publicKeyHex)
        XCTAssertEqual(Set(signers.keys), [account.publicKeyHex, other.publicKeyHex])
        let blocked = try await archive.zapSigners(period: period, relevantTo: account.publicKeyHex, blocked: [stranger.publicKeyHex])
        XCTAssertEqual(Set(blocked.keys), [other.publicKeyHex])
        let report = try await archive.report(owner: account.publicKeyHex, period: period, trusted: [], blocked: [],
            zapperKeys: [account.publicKeyHex: [provider.publicKeyHex], other.publicKeyHex: [provider.publicKeyHex]])
        XCTAssertEqual(report.zappedBy.first?.zaps, 1)
        XCTAssertEqual(report.zapped.first?.zaps, 1)
    }

    func testSharedZapProviderCachePersistsHistoricalKeysAndRetryChecks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("providers.json")
        let cache = YearReviewZapProviderCache(fileURL: file)
        let old = YearReviewZapProviderCheck(checkedAt: Date(timeIntervalSince1970: 100), endpoint: "https://example.com/old", signers: [alice])
        let new = YearReviewZapProviderCheck(checkedAt: Date(timeIntervalSince1970: 200), endpoint: "https://example.com/new", signers: [bob])
        let profile = YearReviewZapProvider(pubkey: owner, keys: [], lud16: "user@example.com", lud06: nil)
        try await cache.remember(keys: [owner: [alice]], profiles: [owner: profile], checks: [owner: old])
        try await cache.remember(keys: [owner: [bob]], profiles: [:], checks: [owner: new])
        try await cache.remember(keys: [:], profiles: [:], checks: [owner: old])
        let reopened = YearReviewZapProviderCache(fileURL: file)
        let saved = await reopened.snapshot()
        XCTAssertEqual(saved.keys[owner], [alice, bob])
        XCTAssertEqual(saved.profiles[owner]?.lud16, "user@example.com")
        XCTAssertEqual(saved.checks[owner]?.checkedAt, new.checkedAt)
        XCTAssertFalse(saved.checks[owner]!.shouldRetry(endpoint: new.endpoint, signers: [bob], now: Date(timeIntervalSince1970: 201)))
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
        await fulfillment(of: [timedOut], timeout: 0.5)
    }

    func testTimelyEOSEDoesNotBecomeRelayTimeoutWhileDecoderIsBlocked() async throws {
        let worker = DispatchQueue(label: "year-review-eose-backpressure")
        let entered = expectation(description: "decoder blocked")
        let gate = DispatchSemaphore(value: 0)
        worker.async { entered.fulfill(); _ = gate.wait(timeout: .now() + 5) }
        defer { gate.signal() }
        await fulfillment(of: [entered], timeout: 1)
        let inbox = YearReviewRelayInbox(worker: worker)
        let complete = expectation(description: "page after decoding")
        let event = try signedEvent()
        inbox.register(id: "year-e", relay: "wss://relay.example.com", timeout: 0.03) { result in
            if case .success(let page) = result { XCTAssertEqual(page.events.count, 1) }
            else { XCTFail("Timely EOSE must survive delayed decoding") }
            complete.fulfill()
        }
        let payload = "[\"EVENT\",\"year-e\",\(String(decoding: try JSONEncoder().encode(event), as: UTF8.self))]"
        XCTAssertTrue(inbox.route(text: payload, relay: "wss://relay.example.com"))
        XCTAssertTrue(inbox.route(text: "[\"EOSE\",\"year-e\"]", relay: "wss://relay.example.com"))
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(inbox.receivedCount("year-e"), 1)
        gate.signal()
        await fulfillment(of: [complete], timeout: 1)
    }

    func testBlockedHistoryProcessingHasSeparateLocalFailure() async {
        let worker = DispatchQueue(label: "year-review-processing-timeout")
        let gate = DispatchSemaphore(value: 0)
        worker.async { _ = gate.wait(timeout: .now() + 5) }
        defer { gate.signal() }
        let inbox = YearReviewRelayInbox(worker: worker)
        let complete = expectation(description: "local processing timeout")
        inbox.register(id: "year-e", relay: "wss://relay.example.com", timeout: 0.03, processingTimeout: 0.08) { result in
            if case .failure(YearReviewError.processingTimeout) = result { }
            else { XCTFail("Local decoding delays must not be reported as relay failures") }
            complete.fulfill()
        }
        XCTAssertTrue(inbox.route(text: "[\"EOSE\",\"year-e\"]", relay: "wss://relay.example.com"))
        await fulfillment(of: [complete], timeout: 0.5)
    }

    func testConnectionFailureDistinguishesUnavailableServerFromRateLimiting() async {
        let inbox = YearReviewRelayInbox()
        let complete = expectation(description: "classified failures")
        complete.expectedFulfillmentCount = 2
        for status in [503, 429] {
            let id = "year-\(status)"
            inbox.register(id: id, relay: "wss://relay.example.com") { result in
                if case .failure(let error) = result {
                    if status == 503 {
                        if case YearReviewError.relayConnection = error { }
                        else { XCTFail("HTTP 503 must be a connection failure") }
                    } else {
                        if case YearReviewError.relay = error { }
                        else { XCTFail("HTTP 429 must retain relay backoff") }
                    }
                } else { XCTFail("Expected connection failure") }
                complete.fulfill()
            }
            inbox.connectionFailed(ids: [id], relay: "wss://relay.example.com",
                error: URLError(.badServerResponse), httpStatus: status)
        }
        await fulfillment(of: [complete], timeout: 1)
    }

    func testConnectionFailureReportsHTTPStatusOnlyForItsRequests() async {
        let inbox = YearReviewRelayInbox()
        let failed = expectation(description: "connection error")
        let complete = expectation(description: "other request finishes")
        inbox.register(id: "year-a", relay: "wss://relay.example.com") { result in
            if case .failure(let error) = result { XCTAssertTrue(error.localizedDescription.contains("503")) }
            else { XCTFail("Expected a connection failure") }
            failed.fulfill()
        }
        inbox.register(id: "year-b", relay: "wss://relay.example.com") { result in
            if case .success = result { }
            else { XCTFail("Another connection must remain independent") }
            complete.fulfill()
        }
        inbox.connectionFailed(ids: ["year-a"], relay: "wss://relay.example.com",
            error: URLError(.badServerResponse), httpStatus: 503)
        await fulfillment(of: [failed], timeout: 0.5)
        XCTAssertNotNil(inbox.receivedCount("year-b"))
        XCTAssertTrue(inbox.route(text: "[\"EOSE\",\"year-b\"]", relay: "wss://relay.example.com"))
        await fulfillment(of: [complete], timeout: 0.5)
    }

    @MainActor
    func testHistoryReusesAppConnectionAndPreservesFeedSubscription() async throws {
        let pool = ConnectionPool()
        pool.queue = DispatchQueue(label: "year-review-app-connection")
        let relay = RelayData.new(url: "wss://history.example.invalid", read: true)
        let appConnection = Nostur.RelayConnection(relay, queue: pool.queue)
        _ = pool.retainEphemeralConnection(relay)
        defer { pool.releaseEphemeralConnection(relay) }
        await withCheckedContinuation { continuation in
            pool.queue.async(flags: .barrier) {
                pool.connections[relay.id] = appConnection
                appConnection.isSocketConnected = true
                appConnection.nreqSubscriptions = ["Following-test", "year-test"]
                continuation.resume()
            }
        }
        let selected = try await pool.historyConnection(for: relay)
        XCTAssertTrue(selected.connection === appConnection)
        XCTAssertFalse(selected.retainedEphemeral)
        selected.connection.closeAndDropSubscription("year-test")
        let remaining = await withCheckedContinuation { continuation in
            pool.queue.async {
                continuation.resume(returning: (appConnection.nreqSubscriptions, appConnection.isSocketConnected))
            }
        }
        XCTAssertEqual(remaining.0, ["Following-test"])
        XCTAssertTrue(remaining.1)
        // Another caller's temporary connection still owns its original retain.
        XCTAssertFalse(pool.removeIdleEphemeralConnection(relay.id))
    }

    @MainActor
    func testHistoryPrefersConnectedOutboxOverDisconnectedAppConnection() async throws {
        let pool = ConnectionPool()
        pool.queue = DispatchQueue(label: "year-review-outbox-connection")
        let relay = RelayData.new(url: "wss://history.example.invalid", read: true)
        let appConnection = Nostur.RelayConnection(relay, queue: pool.queue)
        await withCheckedContinuation { continuation in
            pool.queue.async(flags: .barrier) {
                pool.connections[relay.id] = appConnection
                continuation.resume()
            }
        }
        let outbox: Nostur.RelayConnection = await withCheckedContinuation { continuation in
            pool.addOutboxConnection(relay) { connection in
                connection.isSocketConnected = true
                continuation.resume(returning: connection)
            }
        }
        let selected = try await pool.historyConnection(for: relay)
        XCTAssertTrue(selected.connection === outbox)
        XCTAssertFalse(selected.retainedEphemeral)
    }

    @MainActor
    func testHistoryReusesAvailableAppConnectionAndAvoidsWalletSockets() async throws {
        let pool = ConnectionPool()
        pool.queue = DispatchQueue(label: "year-review-available-connection")
        let relay = RelayData.new(url: "wss://history.example.invalid", read: true)
        let appConnection = Nostur.RelayConnection(relay, queue: pool.queue)
        await withCheckedContinuation { continuation in
            pool.queue.async(flags: .barrier) {
                pool.connections[relay.id] = appConnection
                continuation.resume()
            }
        }
        let existing = try await pool.historyConnection(for: relay)
        XCTAssertTrue(existing.connection === appConnection)
        XCTAssertFalse(existing.retainedEphemeral)
        let wallet = Nostur.RelayConnection(relay, isNWC: true, queue: pool.queue)
        await withCheckedContinuation { continuation in
            pool.queue.async(flags: .barrier) {
                pool.connections[relay.id] = wallet
                wallet.isSocketConnected = true
                continuation.resume()
            }
        }
        let fallback = try await pool.historyConnection(for: relay)
        XCTAssertFalse(fallback.connection === wallet)
        XCTAssertTrue(fallback.retainedEphemeral)
        XCTAssertFalse(pool.removeIdleEphemeralConnection(relay.id))
        pool.releaseEphemeralConnection(relay)
        XCTAssertTrue(pool.removeIdleEphemeralConnection(relay.id))
    }

    @MainActor
    func testHistoryConnectionLookupCancelsAndTimesOutWhilePoolQueueIsBlocked() async {
        let pool = ConnectionPool()
        pool.queue = DispatchQueue(label: "year-review-held-lookup")
        let relay = RelayData.new(url: "wss://history.example.invalid", read: true)
        let entered = expectation(description: "pool queue blocked")
        let gate = DispatchSemaphore(value: 0)
        pool.queue.async { entered.fulfill(); _ = gate.wait(timeout: .now() + 5) }
        defer { gate.signal() }
        await fulfillment(of: [entered], timeout: 1)
        let lookup = Task { @MainActor in try await pool.historyConnection(for: relay) }
        await Task.yield()
        let started = Date.now
        lookup.cancel()
        do {
            _ = try await lookup.value
            XCTFail("Cancelled lookup must not retain a socket")
        } catch is CancellationError { }
        catch { XCTFail("Unexpected cancellation error: \(error)") }
        do {
            _ = try await pool.historyConnection(for: relay, lookupTimeout: 0.03)
            XCTFail("Blocked lookup must remain bounded")
        } catch YearReviewError.connectionBusy { }
        catch { XCTFail("Unexpected timeout error: \(error)") }
        XCTAssertLessThan(Date.now.timeIntervalSince(started), 0.5)
    }

    @MainActor
    func testHistoryConnectionStaysRetainedAndResponsiveWithBlockedPoolQueue() async {
        let pool = ConnectionPool()
        pool.queue = DispatchQueue(label: "year-review-blocked-connection-pool")
        let relay = RelayData.new(url: "wss://history.example.invalid", read: true)
        let entered = expectation(description: "pool queue blocked")
        let gate = DispatchSemaphore(value: 0)
        pool.queue.async { entered.fulfill(); _ = gate.wait(timeout: .now() + 5) }
        defer { gate.signal() }
        await fulfillment(of: [entered], timeout: 1)
        let started = Date.now
        let connection = pool.retainEphemeralConnection(relay)
        XCTAssertFalse(pool.removeIdleEphemeralConnection(relay.id))
        XCTAssertTrue(pool.retainEphemeralConnection(relay) === connection)
        pool.releaseEphemeralConnection(relay)
        XCTAssertFalse(pool.removeIdleEphemeralConnection(relay.id))
        pool.releaseEphemeralConnection(relay)
        XCTAssertTrue(pool.removeIdleEphemeralConnection(relay.id))
        XCTAssertLessThan(Date.now.timeIntervalSince(started), 0.5)
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
