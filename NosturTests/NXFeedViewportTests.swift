//
//  NXFeedViewportTests.swift
//  NosturTests
//

import XCTest
@testable import Nostur

private actor NXFeedTestGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

final class NXFeedViewportTests: XCTestCase {

    @MainActor
    func testCloudSeenRefreshCoalescesNotificationBurst() async {
        let scheduler = NXCloudSeenRefreshScheduler()
        var loadCount = 0
        var appliedIds = Set<String>()

        for index in 0..<5 {
            scheduler.schedule(
                debounceNanoseconds: 50_000_000,
                load: {
                    loadCount += 1
                    return ["id-\(index)"]
                },
                apply: { appliedIds = $0 }
            )
        }

        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(loadCount, 1)
        XCTAssertEqual(appliedIds, ["id-4"])
    }

    @MainActor
    func testCloudSeenRefreshDoesNotBlockUIWhileBackgroundLoadIsHeld() async {
        let scheduler = NXCloudSeenRefreshScheduler()
        let loadGate = NXFeedTestGate()
        var didApply = false
        var uiOperationCompleted = false

        scheduler.schedule(
            debounceNanoseconds: 0,
            load: {
                await loadGate.wait()
                return ["synced-id"]
            },
            apply: { _ in didApply = true }
        )

        try? await Task.sleep(nanoseconds: 50_000_000)
        Task { @MainActor in
            uiOperationCompleted = true
        }
        await Task.yield()

        XCTAssertTrue(uiOperationCompleted)
        XCTAssertFalse(didApply)

        await loadGate.open()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(didApply)
    }

    @MainActor
    func testSeenReconciliationWaitsUntilScrollingIsIdle() async {
        let scheduler = NXSeenReconciliationScheduler()
        var isScrolling = true
        var applyCount = 0

        scheduler.schedule(
            isBusy: { isScrolling },
            apply: { applyCount += 1 }
        )

        try? await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertEqual(applyCount, 0)

        isScrolling = false
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(applyCount, 1)
    }

    @MainActor
    func testSeenReconciliationReschedulesWhenScrollingRestartsDuringIdleGrace() async {
        let scheduler = NXSeenReconciliationScheduler()
        var isScrolling = false
        var applyCount = 0

        scheduler.schedule(
            isBusy: { isScrolling },
            apply: { applyCount += 1 }
        )

        try? await Task.sleep(nanoseconds: 150_000_000)
        isScrolling = true
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(applyCount, 0)

        isScrolling = false
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(applyCount, 1)
    }
    private struct Item: Equatable {
        let id: String
    }

    func testPrependCoverIsOnlyForNewerPostInserts() {
        XCTAssertTrue(
            NXFeedViewport.shouldCoverPrepend(updateReasons: [NXFeedViewport.prependCoverReason])
        )
        XCTAssertTrue(
            NXFeedViewport.shouldCoverPrepend(
                updateReasons: ["media row resized", NXFeedViewport.prependCoverReason]
            )
        )
        XCTAssertFalse(
            NXFeedViewport.shouldCoverPrepend(updateReasons: ["older posts append"])
        )
        XCTAssertFalse(
            NXFeedViewport.shouldCoverPrepend(updateReasons: ["media row resized", "repost row resolved"])
        )
        XCTAssertFalse(NXFeedViewport.shouldCoverPrepend(updateReasons: []))
    }

    func testRememberOnOlderFetchWaitsForDownwardUserScroll() {
        XCTAssertFalse(
            NXFeedViewport.shouldAllowRememberOnOlderFetch(
                continueEnabled: true,
                userHasScrolledTowardOlder: false
            )
        )
        XCTAssertTrue(
            NXFeedViewport.shouldAllowRememberOnOlderFetch(
                continueEnabled: true,
                userHasScrolledTowardOlder: true
            )
        )
        XCTAssertTrue(
            NXFeedViewport.shouldAllowRememberOnOlderFetch(
                continueEnabled: false,
                userHasScrolledTowardOlder: false
            )
        )
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
