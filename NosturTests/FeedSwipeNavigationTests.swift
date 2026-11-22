import XCTest
@testable import Nostur

final class FeedSwipeNavigationTests: XCTestCase {
    func testSwipesFollowAvailableFeedOrderInBothDirections() {
        let feeds: [FeedSwipeSelection] = [.init(tab: "Following"), .init(tab: "Explore"), .init(tab: "Articles")]
        XCTAssertEqual(feeds[0].adjacent(in: feeds, offset: 1), feeds[1])
        XCTAssertEqual(feeds[2].adjacent(in: feeds, offset: -1), feeds[1])
    }

    func testPinnedListsAreSeparateSwipeDestinations() {
        let feeds: [FeedSwipeSelection] = [.init(tab: "Following"), .init(tab: "List", listId: "first"),
                                          .init(tab: "List", listId: "second"), .init(tab: "Explore")]
        XCTAssertEqual(feeds[1].adjacent(in: feeds, offset: 1), feeds[2])
        XCTAssertEqual(feeds[2].adjacent(in: feeds, offset: -1), feeds[1])
        XCTAssertEqual(feeds[2].adjacent(in: feeds, offset: 1), feeds[3])
    }

    func testBoundariesAndRemovedSelectionsDoNotJumpToAnotherFeed() {
        let feeds: [FeedSwipeSelection] = [.init(tab: "Following"), .init(tab: "Explore")]
        XCTAssertNil(feeds[0].adjacent(in: feeds, offset: -1))
        XCTAssertNil(feeds[1].adjacent(in: feeds, offset: 1))
        XCTAssertNil(FeedSwipeSelection(tab: "Hot").adjacent(in: feeds, offset: 1))
        XCTAssertNil(feeds[0].adjacent(in: feeds, offset: 2))
    }
}
