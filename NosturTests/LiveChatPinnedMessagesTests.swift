import XCTest
@testable import Nostur

final class LiveChatPinnedMessagesTests: XCTestCase {
    func testPinnedMessageIdsPreserveTagOrderAndIgnoreInvalidTags() {
        let tags = [
            NostrTag(["pinned", "first"]),
            NostrTag(["title", "Live"]),
            NostrTag(["pinned", "second"]),
            NostrTag(["pinned", "first"]),
            NostrTag(["pinned", ""])
        ]

        XCTAssertEqual(tags.pinnedMessageIds, ["first", "second"])
    }

    func testPinningIsIdempotentAndPreservesOtherPins() {
        let tags = [
            NostrTag(["d", "room"]),
            NostrTag(["pinned", "first"])
        ]

        let updated = tags
            .updatingPinnedMessage("second", pinned: true)
            .updatingPinnedMessage("second", pinned: true)

        XCTAssertEqual(updated.pinnedMessageIds, ["first", "second"])
        XCTAssertEqual(updated.first?.type, "d")
    }

    func testUnpinningOnlyRemovesTheSelectedMessage() {
        let tags = [
            NostrTag(["pinned", "first"]),
            NostrTag(["pinned", "second"])
        ]

        XCTAssertEqual(
            tags.updatingPinnedMessage("first", pinned: false).pinnedMessageIds,
            ["second"]
        )
    }
}
