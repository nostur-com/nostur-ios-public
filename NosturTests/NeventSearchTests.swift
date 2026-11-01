import XCTest
import NostrEssentials
@testable import Nostur

@MainActor
final class NeventSearchTests: XCTestCase {
    private let suppliedLink = "nevent1qqst4qy87zgqpk34v3qnxyu9fvd9jgrfuuk29yly8r4nq0htd60fccgzyruwd3jrgtc7q5jgqccwylsszmwwxh7r5c2wvpp5lm625fgrx2x2jqcyqqqqgtqpr9mhxue69uhhq7tjv9kkjepwve5kzar2v9nzucm0d5q3vamnwvaz7tmjv4kxz7fwwpexjmtpdshxuet5qyxhwumn8ghj7mn0wvhxcmmvqythwumn8ghj7un9d3shjtnwdaehgu3wvf6kjmryqyvhwumn8ghj7um9dejxjapwdehhxenvv9ex2tnrdakszxrhwden5te0wpex2mtfw4kjuurjd9kkzmpwdejhgqgkwaehxw309aek2ctjvd5zumn0wvh8gmmyv9usz9rhwden5te0wfjkccte9ejxzmt4wvhxjmcpzfmhxue69uhhqatjwpkx2urpvuhx2uclpyw0k"

    func testSuppliedPollLinkDecodesAndUsesMoreThanTheFirstHint() throws {
        let target = try XCTUnwrap(NeventSearchTarget(suppliedLink))
        XCTAssertEqual(target.eventID, "ba8087f09000da3564413313854b1a592069e72ca293e438eb303eeb6e9e9c61")
        XCTAssertEqual(target.relays, ["wss://pyramid.fiatjaf.com", "wss://relay.primal.net", "wss://nos.lol"])
        XCTAssertTrue(target.hasRelayHints)
        XCTAssertEqual(try ShareableIdentifier(suppliedLink).kind, 1068)
    }

    func testRelayHintsAreValidatedDeduplicatedAndBounded() throws {
        let link = try ShareableIdentifier(prefix: "nevent", kind: 1068,
                                          pubkey: String(repeating: "ab", count: 32),
                                          eventId: String(repeating: "cd", count: 32),
                                          relays: ["https://invalid.test", "wss://one.test/", "wss://one.test",
                                                   "wss://user:secret@invalid.test", "wss://two.test", "wss://three.test", "wss://four.test"])
        let target = try XCTUnwrap(NeventSearchTarget(link.bech32string))
        XCTAssertEqual(target.relays, ["wss://one.test/", "wss://two.test", "wss://three.test"])
    }

    func testLinkWithoutHintsStillHasADeadline() async {
        let expired = expectation(description: "No-hint lookup expires")
        let session = NeventSearchSession()
        session.start(timeoutNanoseconds: 20_000_000) { expired.fulfill() }
        await fulfillment(of: [expired], timeout: 0.5)
        XCTAssertEqual(session.state, .timedOut)
        XCTAssertFalse(session.found())
    }

    func testCachedResultCancelsDeadline() async throws {
        let expired = expectation(description: "Found lookup must not time out")
        expired.isInverted = true
        let session = NeventSearchSession()
        session.start(timeoutNanoseconds: 20_000_000) { expired.fulfill() }
        XCTAssertTrue(session.found())
        XCTAssertFalse(session.found())
        await fulfillment(of: [expired], timeout: 0.06)
        XCTAssertEqual(session.state, .found)
    }

    func testNewSearchCancelsOldDeadlineAndRejectsLateResult() async {
        let stale = expectation(description: "Old query cannot update new search")
        stale.isInverted = true
        let session = NeventSearchSession()
        session.start(timeoutNanoseconds: 20_000_000) { stale.fulfill() }
        session.cancel()
        XCTAssertFalse(session.found())
        await fulfillment(of: [stale], timeout: 0.06)
        XCTAssertEqual(session.state, .cancelled)
    }

    func testDeadlineEndsSpinnerWithImporterHeldAndBacklogTimerReset() async {
        let release = DispatchSemaphore(value: 0)
        let held = expectation(description: "Importer context held")
        let context = bg()
        let holding = Task { await context.perform { held.fulfill(); release.wait() } }
        defer { release.signal(); holding.cancel() }
        await fulfillment(of: [held], timeout: 1)

        let backlog = Backlog(timeout: 12, auto: false, backlogDebugName: "NeventSearchRegression")
        let first = ReqTask(reqCommand: { _ in }, processResponseCommand: { _, _, _ in })
        backlog.add(first)
        backlog.clear()
        // This is the same clear/add ordering used when the search field changes.
        let queued = expectation(description: "Response callback queued behind importer")
        let next = ReqTask(debounceTime: 0.001, reqCommand: { _ in }, processResponseCommand: { _, _, _ in
            context.perform { }
            queued.fulfill()
        })
        backlog.add(next)
        next.process()

        var searching = true
        let expired = expectation(description: "UI exits loading independently")
        let responsive = expectation(description: "Main actor responds")
        let session = NeventSearchSession()
        session.start(timeoutNanoseconds: 50_000_000) {
            searching = false
            expired.fulfill()
        }
        Task { @MainActor in responsive.fulfill() }
        await fulfillment(of: [queued, expired, responsive], timeout: 0.75)
        XCTAssertFalse(searching)
        XCTAssertEqual(session.state, .timedOut)
        backlog.clear()
    }
}
