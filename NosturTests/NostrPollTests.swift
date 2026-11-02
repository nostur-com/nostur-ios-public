import XCTest
import NostrEssentials
@testable import Nostur

final class NostrPollTests: XCTestCase {
    private let pollID = String(repeating: "ab", count: 32)

    private func poll(type: String? = nil, end: String? = "200") -> NostrPoll {
        var tags = [["option", "uuid-with-hyphens", "First"], ["option", "b", "Second"]]
        if let type { tags.append(["polltype", type]) }
        if let end { tags.append(["endsAt", end]) }
        return NostrPoll(id: pollID, createdAt: 100, tags: tags)
    }

    private func vote(_ id: String, author: String = "voter", at: Int = 150, _ responses: [String]) -> PollVote {
        PollVote(id: id, pubkey: author, createdAt: at, responses: responses)
    }

    func testParsesRealWorldIDsAndMoreThanTenOptionsWithoutTruncatingLabels() {
        let label = String(repeating: "Long option ", count: 10)
        let tags = (0..<11).map { ["option", "uuid-\($0)", label] }
        let value = NostrPoll(id: pollID, createdAt: 100, tags: tags)
        XCTAssertTrue(value.isSupported)
        XCTAssertFalse(value.multipleChoice)
        XCTAssertEqual(value.options.count, 11)
        XCTAssertEqual(value.options[0].label, label)
    }

    func testMalformedAndDuplicateOptionsAreIgnoredAndUnsupportedSettingsCannotVote() {
        let value = NostrPoll(id: pollID, createdAt: 100,
                             tags: [["option"], ["option", "", "Empty ID"], ["option", "a", " "],
                                    ["option", "b", "Original"], ["option", "b", "Duplicate"]])
        XCTAssertEqual(value.options.map(\.label), ["Original"])
        XCTAssertFalse(value.isSupported)
        XCTAssertFalse(poll(type: "rankedchoice").isSupported)
        XCTAssertFalse(poll(end: "invalid").isSupported)
        XCTAssertTrue(poll(end: nil).isSupported)
    }

    func testSingleChoiceOnlyCountsFirstResponseIncludingWhenItIsUnknown() {
        let tally = PollTally(poll: poll(), votes: [vote("a", ["uuid-with-hyphens", "b"]),
                                                   vote("b", author: "other", ["unknown", "b"])], now: 300)
        XCTAssertEqual(tally.totalVoters, 1)
        XCTAssertEqual(tally.votersByOption["uuid-with-hyphens"]?.count, 1)
        XCTAssertNil(tally.votersByOption["b"])
    }

    func testMultipleChoiceDeduplicatesOptionsAndUsesDistinctVoters() {
        let tally = PollTally(poll: poll(type: "multiplechoice"),
                              votes: [vote("a", ["b", "b", "unknown", "uuid-with-hyphens"])], now: 300)
        XCTAssertEqual(tally.totalVoters, 1)
        XCTAssertEqual(tally.votersByOption["b"]?.count, 1)
        XCTAssertEqual(tally.votersByOption["uuid-with-hyphens"]?.count, 1)
        XCTAssertEqual(tally.votes[0].responses.count, 2)
    }

    func testLatestVoteWinsRegardlessOfArrivalOrderAndMovesVoterBetweenOptions() {
        let votes = [vote("old", at: 110, ["b"]), vote("new", at: 160, ["uuid-with-hyphens"])]
        for input in [votes, Array(votes.reversed()), votes + votes] {
            let tally = PollTally(poll: poll(), votes: input, now: 300)
            XCTAssertEqual(tally.totalVoters, 1)
            XCTAssertNil(tally.votersByOption["b"])
            XCTAssertEqual(tally.votersByOption["uuid-with-hyphens"]?.first?.id, "new")
        }
    }

    func testLateAndBackdatedVotesDoNotReplaceValidVoteAndClosedPollStillCountsHistory() {
        let tally = PollTally(poll: poll(), votes: [vote("valid", at: 200, ["b"]),
                                                   vote("late", at: 201, ["uuid-with-hyphens"]),
                                                   vote("early", author: "early", at: 99, ["b"])], now: 500)
        XCTAssertEqual(tally.votes.map(\.id), ["valid"])
    }

    func testFutureVoteDoesNotReplaceCurrentVote() {
        let tally = PollTally(poll: poll(end: nil), votes: [vote("valid", at: 150, ["b"]),
                                                                         vote("future", at: 190, ["uuid-with-hyphens"])], now: 160)
        XCTAssertEqual(tally.votes.map(\.id), ["valid"])
    }

    func testEqualTimestampTieIsDeterministic() {
        let votes = [vote("b", ["b"]), vote("a", ["uuid-with-hyphens"])]
        XCTAssertEqual(PollTally(poll: poll(), votes: votes, now: 300).votes.map(\.id), ["a"])
        XCTAssertEqual(PollTally(poll: poll(), votes: votes.reversed(), now: 300).votes.map(\.id), ["a"])
    }

    func testInvalidLatestResponseDoesNotResurrectOldChoice() {
        let tally = PollTally(poll: poll(), votes: [vote("valid", at: 110, ["b"]),
                                                   vote("invalid", at: 150, ["unknown"])], now: 300)
        XCTAssertEqual(tally.totalVoters, 0)
    }

    func testRelayValidationDeduplicatesRootsButPreservesCaseSensitivePaths() {
        XCTAssertEqual(NostrPoll.relayURLs(["wss://RELAY.test/", "wss://relay.test", "wss://relay.test/AbC",
                                           "wss://relay.test/abc", "https://wrong.test", "wss://bad.test/ ,",
                                           "wss://user:secret@relay.test", "wss://relay.test/#fragment"]),
                       ["wss://relay.test", "wss://relay.test/AbC", "wss://relay.test/abc"])
    }

    private func signedVote(at timestamp: Int, option: String = "b", target: String? = nil) throws -> NEvent {
        let keys = try Keys(privateKeyHex: String(repeating: "0", count: 63) + "1")
        var event = NEvent(publicKey: keys.publicKeyHex, createdAt: NTimestamp(timestamp: timestamp),
                           content: "", kind: .pollResponse,
                           tags: [NostrTag(["e", target ?? pollID]), NostrTag(["response", option])])
        return try event.sign(keys)
    }

    func testRelayQueryPaginatesAndDeduplicatesBoundaryEvents() async throws {
        let a = try signedVote(at: 180)
        let b = try signedVote(at: 170)
        let c = try signedVote(at: 160)
        let transport = PollScriptedTransport(pages: [[a, b], [b, c], [c]])
        let result = await PollRelayClient.query(poll: poll(), transport: transport, author: nil, pageSize: 2)
        XCTAssertTrue(result.complete)
        XCTAssertEqual(Set(result.votes.map(\.id)), Set([a.id, b.id, c.id]))
        XCTAssertTrue(transport.wasClosed)
    }

    func testSaturatedTimestampReportsPartialResultsRatherThanSkippingVotes() async throws {
        let a = try signedVote(at: 180)
        let b = try signedVote(at: 180, option: "uuid-with-hyphens")
        let transport = PollScriptedTransport(pages: [[a, b], [a, b]])
        let result = await PollRelayClient.query(poll: poll(), transport: transport, author: nil, pageSize: 2)
        XCTAssertFalse(result.complete)
        XCTAssertEqual(result.votes.count, 2)
    }

    func testPageLimitReturnsAResumableCursorAndKeepsTimestampBoundary() async throws {
        let a = try signedVote(at: 180)
        let b = try signedVote(at: 170)
        let c = try signedVote(at: 160)
        let first = PollScriptedTransport(pages: [[a, b]])
        let initial = await PollRelayClient.query(poll: poll(), transport: first, author: nil, pageSize: 2, maxPages: 1)
        let cursor = try XCTUnwrap(initial.nextCursor)
        XCTAssertFalse(initial.complete)
        XCTAssertEqual(cursor.until, 170)
        XCTAssertEqual(cursor.boundaryIDs, [b.id])
        let next = PollScriptedTransport(pages: [[b, c], [c]])
        let resumed = await PollRelayClient.query(poll: poll(), transport: next, author: nil, pageSize: 2, cursor: cursor)
        XCTAssertTrue(resumed.complete)
        XCTAssertEqual(resumed.votes.map(\.id), [c.id])
        XCTAssertEqual(next.requestedUntil, [170, 160])
    }

    func testContinuationStopsWhenRelayRepeatsASaturatedBoundary() async throws {
        let a = try signedVote(at: 180)
        let b = try signedVote(at: 180, option: "uuid-with-hyphens")
        let cursor = PollRelayCursor(until: 180, boundaryIDs: [a.id, b.id])
        let transport = PollScriptedTransport(pages: [[a, b]])
        let result = await PollRelayClient.query(poll: poll(), transport: transport, author: nil, pageSize: 2, cursor: cursor)
        XCTAssertFalse(result.complete)
        XCTAssertTrue(result.hitBoundaryLimit)
        XCTAssertNil(result.nextCursor)
        XCTAssertEqual(transport.requestedUntil, [180])
    }

    func testRelaySourcesDistinguishRetryContinuationAndCompletion() {
        let cursor = PollRelayCursor(until: 170, boundaryIDs: ["b"])
        var source = PollResultsSource(id: "wss://relay.example")
        var more = PollRelayResult()
        more.nextCursor = cursor
        source.record(more)
        XCTAssertEqual(source.status, .moreAvailable)
        source.record(PollRelayResult())
        XCTAssertEqual(source.status, .failed)
        XCTAssertEqual(source.cursor, cursor, "Retry must retain continuation progress")
        var limited = PollRelayResult()
        limited.hitBoundaryLimit = true
        source.record(limited)
        XCTAssertEqual(source.status, .limited)
        XCTAssertNil(source.cursor)
        var completed = PollRelayResult()
        completed.complete = true
        source.record(completed)
        XCTAssertEqual(source.status, .checked)
        XCTAssertNotNil(source.lastChecked)
    }

    func testMoreRelaysProgressesInBatchesWithoutChangingTheBasePlan() {
        let foreign = (0..<12).map { "wss://relay\($0).example" }
        let plan = PollRelayPlan.Query(relays: ["wss://mine.example"], more: foreign)
        var approved = Set<String>()
        let base = PollResultsSource(id: "wss://mine.example", status: .checked)
        let first = PollResultsRequest.moreRelays.selection(from: plan, previous: [base], approved: &approved)
        XCTAssertEqual(first.relays, Array(foreign.prefix(8)))
        let completed = first.sources.map { PollResultsSource(id: $0.id, status: first.relays.contains($0.id) ? .checked : $0.status) }
        let second = PollResultsRequest.moreRelays.selection(from: plan, previous: completed, approved: &approved)
        XCTAssertEqual(second.relays, Array(foreign.suffix(4)))
        XCTAssertEqual(approved.count, 12)
        XCTAssertEqual(plan.more, foreign)
        let refresh = PollResultsRequest.refresh.selection(from: plan, previous: completed, approved: &approved)
        XCTAssertEqual(refresh.relays.count, 13)
        let restricted = PollRelayPlan.Query(relays: plan.relays, more: [])
        let disabled = PollResultsRequest.refresh.selection(from: restricted, previous: completed, approved: &approved)
        XCTAssertEqual(disabled.relays, plan.relays, "Previously approved relays must still respect the current relay policy")
    }

    func testRelayRecoveryActionsOnlySelectAffectedSources() {
        let sources = [PollResultsSource(id: "checked", status: .checked),
                       PollResultsSource(id: "failed", status: .failed),
                       PollResultsSource(id: "more", status: .moreAvailable),
                       PollResultsSource(id: "limited", status: .limited)]
        let plan = PollRelayPlan.Query(relays: sources.map(\.id), more: [])
        var approved = Set<String>()
        XCTAssertEqual(PollResultsRequest.retryFailed.selection(from: plan, previous: sources, approved: &approved).relays, ["failed"])
        XCTAssertEqual(PollResultsRequest.moreResponses.selection(from: plan, previous: sources, approved: &approved).relays, ["more"])
    }

    private func testAuthenticator() throws -> PollRelayAuthentication {
        let privateKey = String(repeating: "0", count: 63) + "1"
        let publicKey = try Keys(privateKeyHex: privateKey).publicKeyHex
        return PollRelayAuthentication(publicKey: publicKey) { event in
            var unsigned = event
            return try unsigned.sign(Keys(privateKeyHex: privateKey))
        }
    }

    func testPaidRelayAuthenticatesAndRetriesTheSameSubscription() async throws {
        let transport = PollAuthenticationTransport(vote: try signedVote(at: 150))
        let result = await PollRelayClient.query(poll: poll(), transport: transport, author: nil,
                                                relayURL: "wss://filter.nostr.wine", authentication: try testAuthenticator())
        XCTAssertTrue(result.complete)
        XCTAssertNil(result.failure)
        XCTAssertEqual(result.votes.count, 1)
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests.first, transport.requests.last)
        let signed = try XCTUnwrap(transport.authEvents.first)
        XCTAssertEqual(transport.authEvents.count, 1)
        XCTAssertEqual(signed.kind.id, 22242)
        XCTAssertTrue(signed.tags.contains { $0.type == "relay" && $0.value == "wss://filter.nostr.wine" })
        XCTAssertTrue(signed.tags.contains { $0.type == "challenge" && $0.value == "test-challenge" })
        XCTAssertTrue(try signed.verified(logInvalidID: false))
    }

    func testAuthRequiredWithoutPermissionReturnsTheRelayReasonAndDoesNotSign() async throws {
        let transport = PollAuthenticationTransport(vote: try signedVote(at: 150))
        let result = await PollRelayClient.query(poll: poll(), transport: transport, author: nil)
        XCTAssertFalse(result.complete)
        XCTAssertEqual(result.failure?.kind, .authenticationRequired)
        XCTAssertTrue(result.failure?.detail?.contains("auth-required:") == true)
        XCTAssertTrue(transport.authEvents.isEmpty)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testRejectedAuthDoesNotRetryOrLoopAndPreservesTheReason() async throws {
        let transport = PollAuthenticationTransport(vote: try signedVote(at: 150), accepted: false)
        let result = await PollRelayClient.query(poll: poll(), transport: transport, author: nil,
                                                relayURL: "wss://filter.nostr.wine", authentication: try testAuthenticator())
        XCTAssertFalse(result.complete)
        XCTAssertEqual(result.failure?.kind, .authenticationRejected)
        XCTAssertEqual(result.failure?.detail, "restricted: account has no access")
        XCTAssertEqual(transport.authEvents.count, 1)
        XCTAssertEqual(transport.requests.count, 1)
        var source = PollResultsSource(id: "wss://filter.nostr.wine")
        source.record(result)
        XCTAssertEqual(source.failure, result.failure)
    }

    func testOptionalChallengeDoesNotSignWhenTheQueryWorksAnonymously() async throws {
        let transport = PollAuthenticationTransport(vote: try signedVote(at: 150), requiresAuth: false)
        let result = await PollRelayClient.query(poll: poll(), transport: transport, author: nil,
                                                relayURL: "wss://public.example", authentication: try testAuthenticator())
        XCTAssertTrue(result.complete)
        XCTAssertTrue(transport.authEvents.isEmpty)
    }

    func testEOSEAuthHintAuthenticatesAndKeepsPublicResponsesDeduplicated() async throws {
        let transport = PollAuthenticationTransport(vote: try signedVote(at: 150), authHint: true)
        let result = await PollRelayClient.query(poll: poll(), transport: transport, author: nil,
                                                relayURL: "wss://filter.nostr.wine", authentication: try testAuthenticator())
        XCTAssertTrue(result.complete)
        XCTAssertEqual(result.votes.count, 1)
        XCTAssertEqual(transport.authEvents.count, 1)
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testAnEOSECompletedQueryDoesNotFailBecauseClosingTheSubscriptionFails() async throws {
        let transport = PollScriptedTransport(pages: [[try signedVote(at: 150)]], failClose: true)
        let result = await PollRelayClient.query(poll: poll(), transport: transport, author: nil)
        XCTAssertTrue(result.complete)
        XCTAssertNil(result.failure)
        XCTAssertEqual(result.votes.count, 1)
    }

    func testPollTimeoutHasAnExplicitReason() async {
        let transport = PollScriptedTransport(pages: [], stalled: true)
        let result = await PollRelayClient.query(poll: poll(), transport: transport, author: nil,
                                                timeoutNanoseconds: 20_000_000)
        XCTAssertFalse(result.complete)
        XCTAssertEqual(result.failure?.kind, .timedOut)
        XCTAssertTrue(transport.wasClosed)
    }

    func testRelayRejectsTamperedWrongPollAndOutOfWindowVotes() async throws {
        var tampered = try signedVote(at: 150)
        tampered.content = "tampered"
        let wrongPoll = try signedVote(at: 150, target: String(repeating: "cd", count: 32))
        let late = try signedVote(at: 201)
        let early = try signedVote(at: 99)
        let good = try signedVote(at: 200)
        let transport = PollScriptedTransport(pages: [[tampered, wrongPoll, late, early, good]])
        let result = await PollRelayClient.query(poll: poll(), transport: transport, author: nil)
        XCTAssertTrue(result.complete)
        XCTAssertEqual(result.votes.map(\.id), [good.id])
    }

    func testPublishingRequiresMatchingPositiveAcknowledgement() async throws {
        let event = try signedVote(at: 150)
        for accepted in [true, false] {
            let transport = PollScriptedTransport(pages: [], accepted: accepted)
            let success = await PollRelayClient.publish(json: event.eventJson(), eventID: event.id, transport: transport)
            XCTAssertEqual(success, accepted)
            XCTAssertTrue(transport.wasClosed)
        }
    }

    func testCancellationClosesStalledRelay() async throws {
        let transport = PollScriptedTransport(pages: [], stalled: true)
        let value = poll()
        let task = Task { await PollRelayClient.query(poll: value, transport: transport, author: nil) }
        try await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()
        let result = await task.value
        XCTAssertFalse(result.complete)
        XCTAssertTrue(transport.wasClosed)
    }

    @MainActor
    func testSigningTimeoutReturnsPromptlyAndIgnoresLateCallback() async throws {
        let event = try signedVote(at: 150)
        let started = Date()
        do {
            _ = try await PollSigningRequest.wait(timeoutNanoseconds: 20_000_000) {
                try await Task.sleep(nanoseconds: 60_000_000)
                return event
            }
            XCTFail("A stalled signer must time out")
        } catch { }
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
        // Let the signer finish after timeout; it must not resume the continuation twice.
        try await Task.sleep(nanoseconds: 80_000_000)
    }

    @MainActor
    func testSigningCancellationReturnsPromptly() async throws {
        let event = try signedVote(at: 150)
        let task = Task {
            try await PollSigningRequest.wait {
                try await Task.sleep(nanoseconds: 80_000_000)
                return event
            }
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled signing should fail") }
        catch { XCTAssertTrue(error is CancellationError) }
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    @MainActor
    func testHeldImporterDoesNotBlockPollQueryOrMainActor() async throws {
        let release = DispatchSemaphore(value: 0)
        let held = expectation(description: "Importer held")
        let context = bg()
        let holding = Task { await context.perform { held.fulfill(); release.wait() } }
        defer { release.signal(); holding.cancel() }
        await fulfillment(of: [held], timeout: 2)
        let loaded = expectation(description: "Poll loads independently")
        let responsive = expectation(description: "Main actor responds")
        let value = poll()
        let transport = PollScriptedTransport(pages: [[]])
        let loading = Task {
            _ = await PollRelayClient.query(poll: value, transport: transport, author: nil)
            loaded.fulfill()
        }
        Task { @MainActor in responsive.fulfill() }
        await fulfillment(of: [loaded, responsive], timeout: 1)
        await loading.value
    }

    func testDraftBuildsASupportedPollAndKeepsOptionIDs() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var draft = PollDraft(answers: [
            .init(id: "abcdefgh", label: "  Yes \n"),
            .init(id: "ijklmnop", label: "No"),
            .init(id: "qrstuvwx", label: "   ")
        ], multipleChoice: false, duration: .day)
        XCTAssertTrue(draft.isReady(question: " Pineapple? "))
        XCTAssertFalse(draft.isReady(question: "   "))
        let built = draft.builtEvent(question: " Pineapple? ", relays: ["wss://RELAY.test/", "https://nope"], now: now)
        let poll = NostrPoll(id: pollID, createdAt: 1_000_000, tags: built?.tags ?? [])
        XCTAssertEqual(built?.content, "Pineapple?")
        XCTAssertTrue(poll.isSupported)
        XCTAssertFalse(poll.multipleChoice)
        XCTAssertEqual(poll.options.map(\.id), ["abcdefgh", "ijklmnop"])
        XCTAssertEqual(poll.options.map(\.label), ["Yes", "No"])
        XCTAssertEqual(poll.relays, ["wss://relay.test"])
        XCTAssertEqual(poll.endsAt, 1_000_000 + 86_400)

        draft.multipleChoice = true
        draft.duration = .open
        let open = draft.builtEvent(question: "Pineapple?", relays: ["wss://relay.test"], now: now)
        XCTAssertEqual(open?.tags.first { $0.first == "polltype" }, ["polltype", "multiplechoice"])
        XCTAssertNil(open?.tags.first { $0.first == "endsAt" })
    }

    func testDraftRejectsDuplicateAnswersAndBlankQuestionsWithoutRequiringRelays() {
        let draft = PollDraft(answers: [
            .init(id: "abcdefgh", label: "Same"),
            .init(id: "ijklmnop", label: " same ")
        ], multipleChoice: false, duration: .hour)
        XCTAssertTrue(draft.hasDuplicateAnswers)
        XCTAssertFalse(draft.isReady(question: "Question"))
        XCTAssertNil(draft.builtEvent(question: "Question", relays: ["wss://relay.test"], now: Date(timeIntervalSince1970: 10)))
        let ready = PollDraft(answers: [
            .init(id: "abcdefgh", label: "One"),
            .init(id: "ijklmnop", label: "Two")
        ], multipleChoice: false, duration: .hour)
        let withoutRelay = ready.builtEvent(question: "Question", relays: ["https://not-a-relay"], now: Date())
        XCTAssertNotNil(withoutRelay)
        XCTAssertNil(withoutRelay?.tags.first { $0.first == "relay" })
        let empty = ready.builtEvent(question: "Question", relays: [], now: Date())
        XCTAssertEqual(empty?.content, "Question")
        XCTAssertNil(empty?.tags.first { $0.first == "relay" })
    }

    func testRelayQueryKeepsTheSignedEventJSON() async throws {
        let vote = try signedVote(at: 150)
        let transport = PollScriptedTransport(pages: [[vote]])
        let result = await PollRelayClient.query(poll: poll(), transport: transport, author: nil)
        XCTAssertEqual(result.eventJSON.count, 1)
        let decoded = try JSONDecoder().decode(NEvent.self, from: Data(result.eventJSON[0].utf8))
        XCTAssertEqual(decoded.id, vote.id)
    }

    func testDraftTruncatesLongLabelsAndIssuesAlphanumericIDs() {
        let long = String(repeating: "a", count: 90)
        let draft = PollDraft(answers: [
            .init(id: "abcdefgh", label: long),
            .init(id: "ijklmnop", label: "Second")
        ], multipleChoice: false, duration: .week)
        let built = draft.builtEvent(question: "Q", relays: ["wss://relay.test"], now: Date(timeIntervalSince1970: 50))
        XCTAssertEqual(built?.tags[0][2].count, PollDraft.maximumLabelLength)
        var seen = Set<String>()
        for _ in 0..<20 {
            let id = PollDraft.optionID(existing: seen)
            XCTAssertTrue(PollDraft.isOptionID(id))
            XCTAssertTrue(seen.insert(id).inserted)
        }
        var draftWithRoom = PollDraft.new()
        XCTAssertEqual(draftWithRoom.answers.count, 2)
        draftWithRoom = draftWithRoom.addingAnswer()
        XCTAssertEqual(Set(draftWithRoom.answers.map(\.id)).count, 3)
    }

    func testAdvertisedRelaysPreferAnnouncedReadsWeAlsoRead() {
        let input = PollRelayPlan.Input(
            announcedRead: ["wss://announced.example", "wss://both.example", "wss://auth.example"],
            configuredRead: ["wss://both.example", "wss://mine.example", "wss://auth.example"],
            authRelays: ["wss://auth.example"]
        )
        XCTAssertEqual(PollRelayPlan.advertised(input), ["wss://both.example"])
    }

    func testAdvertisedRelaysFallBackAndSkipPrivateOrAuthRelays() {
        let announcedOnly = PollRelayPlan.Input(
            announcedRead: ["wss://announced.example", "ws://plain.example", "wss://localhost", "wss://127.0.0.1"],
            configuredRead: ["wss://somewhere-else.example"]
        )
        XCTAssertEqual(PollRelayPlan.advertised(announcedOnly), ["wss://announced.example"])

        let configuredOnly = PollRelayPlan.Input(
            configuredRead: ["wss://RELAY.test/", "ws://plain.example", "wss://box.local", "https://nope"]
        )
        XCTAssertEqual(PollRelayPlan.advertised(configuredOnly), ["wss://relay.test"])

        let locked = PollRelayPlan.Input(lockRelay: "ws://only.example/")
        XCTAssertEqual(PollRelayPlan.advertised(locked), ["ws://only.example"])

        let disabled = PollRelayPlan.Input(
            configuredRead: ["wss://mine.example", "wss://off.example"],
            disabled: ["wss://off.example/"]
        )
        XCTAssertEqual(PollRelayPlan.advertised(disabled), ["wss://mine.example"])

        var many = PollRelayPlan.Input()
        many.announcedRead = (1...10).map { "wss://r\($0).example" }
        many.configuredRead = many.announcedRead
        XCTAssertEqual(PollRelayPlan.advertised(many).count, PollRelayPlan.maximumAdvertised)
    }

    func testQueryHoldsBackEventRelaysUntilTheViewerFollowsOrAsks() {
        let input = PollRelayPlan.Input(
            announcedWrite: ["wss://author-write.example"],
            configuredRead: ["wss://mine.example"],
            configuredWrite: ["wss://my-write.example"],
            eventRelays: ["wss://mine.example", "wss://poll.example", "wss://my-write.example"],
            outboxEnabled: true,
            followsAuthor: false
        )
        let hidden = PollRelayPlan.query(input)
        XCTAssertEqual(hidden.relays, ["wss://mine.example", "wss://my-write.example"])
        XCTAssertEqual(hidden.more, ["wss://poll.example"])

        let asked = PollRelayPlan.query(input, includeMore: true)
        XCTAssertEqual(asked.relays, ["wss://mine.example", "wss://my-write.example", "wss://poll.example"])
        XCTAssertTrue(asked.more.isEmpty)
    }

    func testQueryIncludesEventAndOutboxRelaysForFollowedAuthors() {
        let input = PollRelayPlan.Input(
            announcedWrite: ["wss://author-write.example", "ws://private.example"],
            configuredRead: ["wss://mine.example"],
            eventRelays: ["wss://poll.example", "wss://localhost/poll"],
            outboxEnabled: true,
            followsAuthor: true
        )
        XCTAssertEqual(PollRelayPlan.query(input).relays,
                       ["wss://mine.example", "wss://author-write.example", "wss://poll.example"])

        var disabledOutbox = input
        disabledOutbox.outboxEnabled = false
        XCTAssertEqual(PollRelayPlan.query(disabledOutbox).relays, ["wss://mine.example", "wss://poll.example"])
        XCTAssertTrue(PollRelayPlan.query(disabledOutbox).more.isEmpty)
    }

    func testOwnPollQueriesItsEventRelaysWithoutFollowing() {
        let input = PollRelayPlan.Input(
            configuredRead: ["wss://mine.example"],
            eventRelays: ["wss://poll.example"],
            followsAuthor: false,
            isOwnPoll: true
        )
        let plan = PollRelayPlan.query(input)
        XCTAssertEqual(plan.relays, ["wss://mine.example", "wss://poll.example"])
        XCTAssertTrue(plan.more.isEmpty)
    }

    func testForeignRelayCapLeavesTheRestForAnExplicitCheck() {
        let foreign = (1...10).map { "wss://poll\($0).example" }
        let input = PollRelayPlan.Input(
            configuredRead: ["wss://mine.example"],
            eventRelays: foreign,
            followsAuthor: true
        )
        let plan = PollRelayPlan.query(input)
        XCTAssertEqual(plan.relays.count, 1 + PollRelayPlan.maximumForeign)
        XCTAssertEqual(plan.relays.first, "wss://mine.example")
        XCTAssertEqual(plan.more, Array(foreign.dropFirst(PollRelayPlan.maximumForeign)))

        let more = PollRelayPlan.query(input, includeMore: true)
        XCTAssertEqual(more.relays.count, 1 + foreign.count)
        XCTAssertTrue(more.more.isEmpty)
    }

    func testArchiveRoundTripKeepsOwnPollsAndResults() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let keys = try Keys(privateKeyHex: String(repeating: "0", count: 63) + "1")
        var pollEvent = NEvent(publicKey: keys.publicKeyHex, createdAt: NTimestamp(timestamp: 100),
                               content: "Question", kind: .poll,
                               tags: [NostrTag(["option", "abcdefgh", "Yes"]), NostrTag(["option", "ijklmnop", "No"]),
                                      NostrTag(["relay", "wss://relay.example"])])
        pollEvent = try pollEvent.sign(keys)
        let vote = try signedVote(at: 150)
        var other = NEvent(publicKey: keys.publicKeyHex, createdAt: NTimestamp(timestamp: 160),
                           content: "nope", kind: .textNote, tags: [])
        other = try other.sign(keys)

        let archive = PollArchive(root: directory)
        let savedPoll = await archive.save(owner: keys.publicKeyHex, json: pollEvent.eventJson())
        let savedVote = await archive.save(owner: keys.publicKeyHex, json: vote.eventJson())
        let savedNote = await archive.save(owner: keys.publicKeyHex, json: other.eventJson())
        var tampered = vote
        tampered.content = "tampered"
        let savedTampered = await archive.save(owner: keys.publicKeyHex, json: tampered.eventJson())
        XCTAssertTrue(savedPoll)
        XCTAssertTrue(savedVote)
        XCTAssertFalse(savedNote)
        XCTAssertFalse(savedTampered)

        let voterKeys = try Keys(privateKeyHex: String(repeating: "0", count: 62) + "11")
        var foreign = NEvent(publicKey: voterKeys.publicKeyHex, createdAt: NTimestamp(timestamp: 170),
                             content: "", kind: .pollResponse,
                             tags: [NostrTag(["e", pollID]), NostrTag(["response", "b"])])
        foreign = try foreign.sign(voterKeys)
        let savedForeign = await archive.save(owner: keys.publicKeyHex, json: foreign.eventJson())
        let savedResults = await archive.saveResults(owner: keys.publicKeyHex, pollID: pollID, jsons: [foreign.eventJson(), foreign.eventJson()])
        XCTAssertFalse(savedForeign)
        XCTAssertEqual(savedResults, 1)

        let restored = PollArchive(root: directory)
        let votes = await restored.votes(owner: keys.publicKeyHex, pollID: pollID)
        XCTAssertEqual(Set(votes.map(\.id)), Set([vote.id, foreign.id]))
        XCTAssertEqual(votes.first { $0.id == foreign.id }?.responses, ["b"])
    }

    func testArchiveKeepsOurVotesWhenOtherResultsHitTheCap() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let keys = try Keys(privateKeyHex: String(repeating: "0", count: 63) + "1")
        let archive = PollArchive(root: directory, maximumEvents: 1)
        var pollEvent = NEvent(publicKey: keys.publicKeyHex, createdAt: NTimestamp(timestamp: 100),
                               content: "Question", kind: .poll, tags: [])
        pollEvent = try pollEvent.sign(keys)
        let savedPoll = await archive.save(owner: keys.publicKeyHex, json: pollEvent.eventJson())
        XCTAssertTrue(savedPoll)

        let voterKeys = try Keys(privateKeyHex: String(repeating: "0", count: 62) + "11")
        var foreign = NEvent(publicKey: voterKeys.publicKeyHex, createdAt: NTimestamp(timestamp: 170),
                             content: "", kind: .pollResponse,
                             tags: [NostrTag(["e", pollID]), NostrTag(["response", "b"])])
        foreign = try foreign.sign(voterKeys)
        let savedResults = await archive.saveResults(owner: keys.publicKeyHex, pollID: pollID, jsons: [foreign.eventJson()])
        XCTAssertEqual(savedResults, 0)

        let vote = try signedVote(at: 150)
        let savedVote = await archive.save(owner: keys.publicKeyHex, json: vote.eventJson())
        XCTAssertTrue(savedVote)
        let votes = await archive.votes(owner: keys.publicKeyHex, pollID: pollID)
        XCTAssertEqual(votes.map(\.id), [vote.id])
    }
}

private final class PollScriptedTransport: ProfileRelayTransport, @unchecked Sendable {
    private let stream: AsyncThrowingStream<String, Error>
    private let continuation: AsyncThrowingStream<String, Error>.Continuation
    private let lock = NSLock()
    private var pages: [[NEvent]]
    private var untils: [Int] = []
    var requestedUntil: [Int] { lock.withLock { untils } }
    private let accepted: Bool
    private let stalled: Bool
    private let failClose: Bool
    private var closed = false
    var wasClosed: Bool { lock.withLock { closed } }

    init(pages: [[NEvent]], accepted: Bool = true, stalled: Bool = false, failClose: Bool = false) {
        var captured: AsyncThrowingStream<String, Error>.Continuation!
        stream = AsyncThrowingStream { captured = $0 }
        continuation = captured
        self.pages = pages
        self.accepted = accepted
        self.stalled = stalled
        self.failClose = failClose
    }

    func send(_ message: String) async throws {
        guard !stalled else { return }
        let array = try JSONSerialization.jsonObject(with: Data(message.utf8)) as! [Any]
        if array[0] as? String == "CLOSE", failClose { throw URLError(.networkConnectionLost) }
        if array[0] as? String == "REQ" {
            if let filter = array[2] as? [String: Any], let until = filter["until"] as? Int {
                lock.withLock { untils.append(until) }
            }
            let page = lock.withLock { pages.isEmpty ? [] : pages.removeFirst() }
            let subscription = array[1] as! String
            for event in page {
                let object = try JSONSerialization.jsonObject(with: Data(event.eventJson().utf8))
                try yield(["EVENT", subscription, object])
            }
            try yield(["EOSE", subscription])
        } else if array[0] as? String == "EVENT", let event = array[1] as? [String: Any] {
            try yield(["OK", "unrelated-id", true, ""])
            try yield(["OK", event["id"] as! String, accepted, ""])
        }
    }

    func receive() async throws -> String {
        var iterator = stream.makeAsyncIterator()
        guard let value = try await iterator.next() else { throw CancellationError() }
        return value
    }

    func close() {
        lock.withLock { closed = true }
        continuation.finish(throwing: CancellationError())
    }

    private func yield(_ object: [Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        continuation.yield(String(decoding: data, as: UTF8.self))
    }
}

private final class PollAuthenticationTransport: ProfileRelayTransport, @unchecked Sendable {
    private let stream: AsyncThrowingStream<String, Error>
    private let continuation: AsyncThrowingStream<String, Error>.Continuation
    private let lock = NSLock()
    private let vote: NEvent
    private let accepted: Bool
    private let requiresAuth: Bool
    private let authHint: Bool
    private var authenticated = false
    private var storedRequests: [String] = []
    private var storedAuth: [NEvent] = []
    var requests: [String] { lock.withLock { storedRequests } }
    var authEvents: [NEvent] { lock.withLock { storedAuth } }

    init(vote: NEvent, accepted: Bool = true, requiresAuth: Bool = true, authHint: Bool = false) {
        var captured: AsyncThrowingStream<String, Error>.Continuation!
        stream = AsyncThrowingStream { captured = $0 }
        continuation = captured
        self.vote = vote
        self.accepted = accepted
        self.requiresAuth = requiresAuth
        self.authHint = authHint
    }

    func send(_ message: String) async throws {
        let envelope = try JSONSerialization.jsonObject(with: Data(message.utf8)) as! [Any]
        if envelope[0] as? String == "REQ", let id = envelope[1] as? String {
            let state = lock.withLock { () -> (Bool, Bool) in
                storedRequests.append(id)
                return (storedRequests.count == 1, authenticated)
            }
            if state.0 { try yield(["AUTH", "test-challenge"]) }
            if requiresAuth && !state.1 {
                if authHint {
                    try yield(["EVENT", id, JSONSerialization.jsonObject(with: Data(vote.eventJson().utf8))])
                    try yield(["EOSE", id, ["auth"]])
                } else {
                    try yield(["CLOSED", id, "auth-required: please authenticate before sending REQs"])
                }
            } else {
                try yield(["EVENT", id, JSONSerialization.jsonObject(with: Data(vote.eventJson().utf8))])
                try yield(["EOSE", id])
            }
        } else if envelope[0] as? String == "AUTH" {
            let data = try JSONSerialization.data(withJSONObject: envelope[1])
            let event = try JSONDecoder().decode(NEvent.self, from: data)
            lock.withLock {
                storedAuth.append(event)
                authenticated = accepted
            }
            try yield(["OK", "unrelated-id", true, ""])
            try yield(["OK", event.id, accepted, accepted ? "" : "restricted: account has no access"])
        }
    }

    func receive() async throws -> String {
        var iterator = stream.makeAsyncIterator()
        guard let message = try await iterator.next() else { throw CancellationError() }
        return message
    }

    func close() { continuation.finish(throwing: CancellationError()) }

    private func yield(_ envelope: [Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: envelope)
        continuation.yield(String(decoding: data, as: UTF8.self))
    }
}
