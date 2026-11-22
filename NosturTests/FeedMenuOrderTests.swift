import XCTest
@testable import Nostur

final class FeedMenuOrderTests: XCTestCase {
    private let following = FeedSwipeSelection(tab: "Following")
    private let photos = FeedSwipeSelection(tab: "Picture")
    private let explore = FeedSwipeSelection(tab: "Explore")
    private let custom = FeedSwipeSelection(tab: "List", listId: "custom-list")

    func testDefaultOrderPreservesExistingCustomFeedOrder() {
        let available = [following, custom, photos, explore]
        XCTAssertEqual(FeedMenuOrder(rawValue: "[]").ordered(available), available)
    }

    func testSavedOrderMixesBuiltInAndCustomFeedsAndDrivesSwiping() {
        let desired = [custom, explore, following, photos]
        let saved = FeedMenuOrder(rawValue: "[]").reordering(desired).rawValue
        let restored = FeedMenuOrder(rawValue: saved).ordered([following, photos, custom, explore])
        XCTAssertEqual(restored, desired)
        XCTAssertEqual(custom.adjacent(in: restored, offset: 1), explore)
        XCTAssertEqual(following.adjacent(in: restored, offset: -1), explore)
    }

    func testHiddenFeedKeepsItsSlotWhenVisibleFeedsMove() {
        let initial = FeedMenuOrder(rawValue: "[]").reordering([following, photos, custom, explore])
        XCTAssertEqual(initial.ordered([following, custom, explore]), [following, custom, explore])
        let moved = initial.reordering([explore, custom, following])
        let restored = FeedMenuOrder(rawValue: moved.rawValue)
        XCTAssertEqual(restored.ordered([following, photos, custom, explore]), [explore, photos, custom, following])
    }

    func testDeletedFeedsAreSkippedAndNewFeedsAreAppended() {
        let saved = FeedMenuOrder(rawValue: "[]").reordering([custom, explore, following])
        XCTAssertEqual(saved.ordered([following, photos, explore]), [explore, following, photos])
    }

    func testDuplicateOrMalformedPreferencesDoNotDuplicateOrHideFeeds() {
        let available = [following, photos, explore]
        let order = FeedMenuOrder(rawValue: "[\"Explore:\",\"Explore:\",\"deleted\",\"Following:\"]")
        XCTAssertEqual(order.ordered(available), [explore, following, photos])
        XCTAssertEqual(FeedMenuOrder(rawValue: "invalid").ordered(available), available)
    }

    func testListsWithSameTabHaveDistinctOrderIdentities() {
        let other = FeedSwipeSelection(tab: "List", listId: "other-list")
        let saved = FeedMenuOrder(rawValue: "[]").reordering([other, following, custom])
        XCTAssertEqual(saved.ordered([following, custom, other]), [other, following, custom])
    }
}
