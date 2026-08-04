import XCTest
@testable import Nostur

final class RoomPresenceTests: XCTestCase {
    func testFreshPresenceIsShownOnceWhileRefreshesRemainActive() {
        var tracker = RoomPresenceTracker(freshnessWindow: 120)

        XCTAssertTrue(tracker.shouldShowPresence(pubkey: "john", timestamp: 950, now: 1_000))
        XCTAssertFalse(tracker.shouldShowPresence(pubkey: "john", timestamp: 980, now: 1_000))
        XCTAssertFalse(tracker.shouldShowPresence(pubkey: "john", timestamp: 980, now: 1_010))
    }

    func testStalePresenceIsIgnored() {
        var tracker = RoomPresenceTracker(freshnessWindow: 120)

        XCTAssertFalse(tracker.shouldShowPresence(pubkey: "john", timestamp: 880, now: 1_000))
    }

    func testPresenceIsShownAgainAfterAListenerReturns() {
        var tracker = RoomPresenceTracker(freshnessWindow: 120)

        XCTAssertTrue(tracker.shouldShowPresence(pubkey: "john", timestamp: 950, now: 1_000))
        XCTAssertTrue(tracker.shouldShowPresence(pubkey: "john", timestamp: 1_101, now: 1_101))
    }
}
