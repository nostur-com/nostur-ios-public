//
//  NXFeedViewportTests.swift
//  NosturTests
//

import XCTest
@testable import Nostur

final class NXFeedViewportTests: XCTestCase {
    private struct Item: Equatable {
        let id: String
    }

    func testTopEdgeAnchorUsesPartiallyVisibleTallRow() {
        let frames = [
            CGRect(x: 0, y: 100, width: 390, height: 700),
            CGRect(x: 0, y: 800, width: 390, height: 120)
        ]

        XCTAssertEqual(
            NXFeedViewport.topEdgeAnchorIndex(itemFrames: frames, visibleTopY: 650),
            0
        )
    }

    func testTopEdgeAnchorFallsBackToFirstRowBelowViewportTop() {
        let frames = [
            CGRect(x: 0, y: 710, width: 390, height: 100),
            CGRect(x: 0, y: 900, width: 390, height: 100)
        ]

        XCTAssertEqual(
            NXFeedViewport.topEdgeAnchorIndex(itemFrames: frames, visibleTopY: 650),
            0
        )
    }

    func testQueuedPrependKeepsPageAppendedWhileScrolling() {
        let old = [Item(id: "3"), Item(id: "2")]
        let desired = [Item(id: "4"), Item(id: "3"), Item(id: "2")]
        let current = [Item(id: "3"), Item(id: "2"), Item(id: "1")]

        let result = NXFeedUpdateRebaser.rebase(
            old: old,
            desired: desired,
            current: current,
            id: \.id
        )

        XCTAssertEqual(result.map(\.id), ["4", "3", "2", "1"])
    }

    func testMultipleQueuedPrependsCanRebaseInOrder() {
        let old = [Item(id: "3"), Item(id: "2")]
        let afterFirst = NXFeedUpdateRebaser.rebase(
            old: old,
            desired: [Item(id: "4")] + old,
            current: old + [Item(id: "1")],
            id: \.id
        )
        let afterSecond = NXFeedUpdateRebaser.rebase(
            old: old,
            desired: [Item(id: "5")] + old,
            current: afterFirst,
            id: \.id
        )

        XCTAssertEqual(afterSecond.map(\.id), ["5", "4", "3", "2", "1"])
    }

    func testQueuedUpdateStillAppliesIntentionalTailRemoval() {
        let old = [Item(id: "3"), Item(id: "2"), Item(id: "old-tail")]
        let desired = [Item(id: "4"), Item(id: "3"), Item(id: "2")]
        let current = old + [Item(id: "new-page")]

        let result = NXFeedUpdateRebaser.rebase(
            old: old,
            desired: desired,
            current: current,
            id: \.id
        )

        XCTAssertEqual(result.map(\.id), ["4", "3", "2", "new-page"])
    }

    func testLiveScrollViewAtTopIgnoresUnfinishedRestoreAfterExpiry() {
        XCTAssertTrue(
            NXFeedViewport.isActuallyAtTop(
                hasLiveScrollView: true,
                contentOffsetY: -47,
                insetTop: 47,
                isPreparingRestore: true,
                restoreExpired: true,
                fallbackIsAtTop: false
            )
        )
    }

    func testInProgressRestoreIsNotTreatedAsAtTop() {
        XCTAssertFalse(
            NXFeedViewport.isActuallyAtTop(
                hasLiveScrollView: true,
                contentOffsetY: -47,
                insetTop: 47,
                isPreparingRestore: true,
                restoreExpired: false,
                fallbackIsAtTop: true
            )
        )
    }

    func testLiveOffsetWinsOverStaleFallback() {
        XCTAssertTrue(
            NXFeedViewport.isActuallyAtTop(
                hasLiveScrollView: true,
                contentOffsetY: -47,
                insetTop: 47,
                isPreparingRestore: false,
                restoreExpired: false,
                fallbackIsAtTop: false
            )
        )
        XCTAssertFalse(
            NXFeedViewport.isActuallyAtTop(
                hasLiveScrollView: true,
                contentOffsetY: 420,
                insetTop: 47,
                isPreparingRestore: false,
                restoreExpired: false,
                fallbackIsAtTop: true
            )
        )
    }

    func testMissingScrollViewUsesFallback() {
        XCTAssertFalse(
            NXFeedViewport.isActuallyAtTop(
                hasLiveScrollView: false,
                contentOffsetY: 0,
                insetTop: 0,
                isPreparingRestore: false,
                restoreExpired: false,
                fallbackIsAtTop: false
            )
        )
    }
}
