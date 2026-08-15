//
//  NXFeedIndexMappingTests.swift
//  NosturTests
//

import XCTest
@testable import Nostur

final class NXFeedIndexMappingTests: XCTestCase {
    func testSingleSectionMapsRowToItemIndex() {
        let sectionCounts = [20]
        let itemCount = 20

        XCTAssertEqual(
            NXFeedIndexMapping.itemIndex(
                for: IndexPath(item: 7, section: 0),
                sectionCounts: sectionCounts,
                itemCount: itemCount
            ),
            7
        )
        XCTAssertEqual(
            NXFeedIndexMapping.indexPath(
                forItemIndex: 7,
                sectionCounts: sectionCounts,
                itemCount: itemCount
            ),
            IndexPath(item: 7, section: 0)
        )
    }

    func testSingleSectionIgnoresPaginationRow() {
        let sectionCounts = [21]
        let itemCount = 20

        XCTAssertEqual(
            NXFeedIndexMapping.itemIndex(
                for: IndexPath(item: 4, section: 0),
                sectionCounts: sectionCounts,
                itemCount: itemCount
            ),
            4
        )
        XCTAssertNil(
            NXFeedIndexMapping.itemIndex(
                for: IndexPath(item: 20, section: 0),
                sectionCounts: sectionCounts,
                itemCount: itemCount
            )
        )
    }

    func testOneItemPerSectionUsesSectionAsItemIndex() {
        let sectionCounts = Array(repeating: 1, count: 12)
        let itemCount = 12

        XCTAssertEqual(
            NXFeedIndexMapping.itemIndex(
                for: IndexPath(item: 0, section: 5),
                sectionCounts: sectionCounts,
                itemCount: itemCount
            ),
            5
        )
        XCTAssertEqual(
            NXFeedIndexMapping.indexPath(
                forItemIndex: 5,
                sectionCounts: sectionCounts,
                itemCount: itemCount
            ),
            IndexPath(item: 0, section: 5)
        )
    }

    func testContentSectionCanFollowAHeaderSection() {
        let sectionCounts = [0, 15]
        let itemCount = 15

        XCTAssertEqual(
            NXFeedIndexMapping.itemIndex(
                for: IndexPath(item: 3, section: 1),
                sectionCounts: sectionCounts,
                itemCount: itemCount
            ),
            3
        )
        XCTAssertEqual(
            NXFeedIndexMapping.indexPath(
                forItemIndex: 3,
                sectionCounts: sectionCounts,
                itemCount: itemCount
            ),
            IndexPath(item: 3, section: 1)
        )
    }

    func testWalksSectionsWithALeadingEmptySectionAndPagination() {
        let sectionCounts = [0, 16]
        let itemCount = 15

        XCTAssertEqual(
            NXFeedIndexMapping.indexPath(
                forItemIndex: 14,
                sectionCounts: sectionCounts,
                itemCount: itemCount
            ),
            IndexPath(item: 14, section: 1)
        )
        XCTAssertNil(
            NXFeedIndexMapping.itemIndex(
                for: IndexPath(item: 15, section: 1),
                sectionCounts: sectionCounts,
                itemCount: itemCount
            )
        )
    }

    func testLeadingSingletonSectionIsAHeaderNotAPost() {
        let sectionCounts = [1, 20]
        let itemCount = 20

        XCTAssertEqual(
            NXFeedIndexMapping.indexPath(
                forItemIndex: 0,
                sectionCounts: sectionCounts,
                itemCount: itemCount
            ),
            IndexPath(item: 0, section: 1)
        )
        XCTAssertEqual(
            NXFeedIndexMapping.itemIndex(
                for: IndexPath(item: 0, section: 1),
                sectionCounts: sectionCounts,
                itemCount: itemCount
            ),
            0
        )
        XCTAssertNil(
            NXFeedIndexMapping.itemIndex(
                for: IndexPath(item: 0, section: 0),
                sectionCounts: sectionCounts,
                itemCount: itemCount
            )
        )
    }

    func testItemsInsertedAboveDetectsPrepend() {
        let oldIDs = ["a", "b", "c"]
        let newIDs = ["n1", "n2", "a", "b", "c"]

        XCTAssertTrue(
            NXFeedIndexMapping.itemsInsertedAbove(oldIDs: oldIDs, newIDs: newIDs, anchorID: "b")
        )
        XCTAssertFalse(
            NXFeedIndexMapping.itemsInsertedAbove(oldIDs: oldIDs, newIDs: newIDs, anchorID: "missing")
        )
        XCTAssertFalse(
            NXFeedIndexMapping.itemsInsertedAbove(oldIDs: oldIDs, newIDs: oldIDs, anchorID: "b")
        )
    }

    func testOffsetFromVisibleTopIsIndependentOfTopInset() {
        let atTopWithoutBanner = NXFeedViewport.offsetFromVisibleTop(
            itemMinY: 0,
            contentOffsetY: -59,
            insetTop: 59
        )
        let atTopWithBanner = NXFeedViewport.offsetFromVisibleTop(
            itemMinY: 0,
            contentOffsetY: -109,
            insetTop: 109
        )

        XCTAssertEqual(atTopWithoutBanner, 0)
        XCTAssertEqual(atTopWithBanner, 0)
    }

    func testPreservingVisibleContentWhenLiveBannerAppears() {
        // At top: offset == -inset. Banner adds 50pt. Stay at the new top.
        XCTAssertEqual(
            NXFeedViewport.contentOffset(
                preservingVisibleContent: -59,
                oldInsetTop: 59,
                newInsetTop: 109
            ),
            -109
        )

        // Mid-feed: keep the same content under the visible top.
        XCTAssertEqual(
            NXFeedViewport.contentOffset(
                preservingVisibleContent: 500,
                oldInsetTop: 59,
                newInsetTop: 109
            ),
            450
        )
    }
}
