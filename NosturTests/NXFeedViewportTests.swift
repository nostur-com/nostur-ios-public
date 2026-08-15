//
//  NXFeedViewportTests.swift
//  NosturTests
//

import XCTest
@testable import Nostur

final class NXFeedViewportTests: XCTestCase {
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
