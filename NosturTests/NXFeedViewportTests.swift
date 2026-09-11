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

    func testSeenParentDoesNotConsumeUnreadLeaf() {
        let seenShortIds: Set<String> = ["parent01", "root0001"]

        XCTAssertFalse(
            NXUnreadSeenReconciliation.isLeafSeen("leaf0001", in: seenShortIds)
        )
    }

    func testSeenLeafConsumesUnreadLeaf() {
        let seenShortIds: Set<String> = ["parent01", "leaf0001"]

        XCTAssertTrue(
            NXUnreadSeenReconciliation.isLeafSeen("leaf0001", in: seenShortIds)
        )
    }

    func testSeenOffscreenLeafRowIsRemoved() {
        XCTAssertTrue(
            NXUnreadSeenReconciliation.shouldRemoveSeenLeafRow(
                isVisible: false,
                removeEvenIfVisible: false
            )
        )
    }

    func testSeenVisibleLeafRowIsKeptStable() {
        XCTAssertFalse(
            NXUnreadSeenReconciliation.shouldRemoveSeenLeafRow(
                isVisible: true,
                removeEvenIfVisible: false
            )
        )
    }

    func testSyncedSeenLeafRowCanBeRemovedWhileVisible() {
        XCTAssertTrue(
            NXUnreadSeenReconciliation.shouldRemoveSeenLeafRow(
                isVisible: true,
                removeEvenIfVisible: true
            )
        )
    }

    func testParkedSettlePinsParkedEvenWhenLiveVisibleDiffers() {
        let parked = NXFeedPark.Post(id: "355a0eb9-restored", visibleTopOffset: 0)
        let live = NXFeedPark.Post(id: "c93fb328-neighbor", visibleTopOffset: 0)

        XCTAssertEqual(
            NXFeedPark.settleTarget(
                parked: parked,
                newIDs: ["c93fb328-neighbor", "355a0eb9-restored"],
                live: live
            ),
            .pin(parked)
        )
    }

    func testParkedSettleRetargetsWhenParkedIdWasRemoved() {
        let parked = NXFeedPark.Post(id: "removed", visibleTopOffset: 0)
        let live = NXFeedPark.Post(id: "c93fb328-neighbor", visibleTopOffset: 0)

        XCTAssertEqual(
            NXFeedPark.settleTarget(
                parked: parked,
                newIDs: ["c93fb328-neighbor", "other"],
                live: live
            ),
            .retarget(live)
        )
    }

    func testParkedSettleSkipsWhenParkedUnsetAndNoLiveVisible() {
        XCTAssertEqual(
            NXFeedPark.settleTarget(parked: nil, newIDs: ["a"], live: nil),
            .skip
        )
    }

    func testParkedSettleDoesNotChaseStaleIdWhenParkedWasNeverSet() {
        let live = NXFeedPark.Post(id: "c93fb328-neighbor", visibleTopOffset: 0)
        XCTAssertEqual(
            NXFeedPark.settleTarget(
                parked: nil,
                newIDs: ["c93fb328-neighbor"],
                live: live
            ),
            .retarget(live)
        )
    }

    func testRestoreDoesNotCompleteUntilLiveTopMatchesParked() {
        XCTAssertFalse(
            NXFeedPark.shouldCompleteRestore(parkedID: "saved", liveVisibleID: nil)
        )
        XCTAssertFalse(
            NXFeedPark.shouldCompleteRestore(parkedID: "saved", liveVisibleID: "other")
        )
        XCTAssertTrue(
            NXFeedPark.shouldCompleteRestore(parkedID: "saved", liveVisibleID: "saved")
        )
        XCTAssertFalse(
            NXFeedPark.shouldCompleteRestore(parkedID: nil, liveVisibleID: "saved")
        )
    }

    func testUnreadPostAnimationPinIsCoveredOnlyWhenItWouldSnap() {
        XCTAssertFalse(
            NXUnreadNavigation.shouldCoverPostAnimationCorrection(misalignment: 1.0)
        )
        XCTAssertFalse(
            NXUnreadNavigation.shouldCoverPostAnimationCorrection(misalignment: -1.4)
        )
        XCTAssertTrue(
            NXUnreadNavigation.shouldCoverPostAnimationCorrection(misalignment: 8.0)
        )
        XCTAssertTrue(
            NXUnreadNavigation.shouldCoverPostAnimationCorrection(misalignment: -40)
        )
        XCTAssertTrue(
            NXUnreadNavigation.shouldCoverPostAnimationCorrection(
                misalignment: 0.2,
                rowHeight: 94,
                frozeSelfSizing: true
            )
        )
        XCTAssertFalse(
            NXUnreadNavigation.shouldCoverPostAnimationCorrection(
                misalignment: 0.2,
                rowHeight: 320,
                frozeSelfSizing: true
            )
        )
    }

    func testUnreadNavigationUsesLiveViewportInsteadOfStaleReadingAnchorWhenIdle() {
        let start = NXUnreadNavigation.start(
            liveVisibleIndex: 12,
            readingIndex: 7,
            fallbackVisibleIndex: 12,
            isViewportTransitioning: false,
            postCount: 20
        )

        XCTAssertEqual(start, .init(index: 12, source: "live-visible"))
    }

    func testUnreadNavigationUsesReadingAnchorDuringViewportTransition() {
        let start = NXUnreadNavigation.start(
            liveVisibleIndex: 12,
            readingIndex: 7,
            fallbackVisibleIndex: 12,
            isViewportTransitioning: true,
            postCount: 20
        )

        XCTAssertEqual(start, .init(index: 7, source: "reading"))
    }

    func testReadAncestorTrimsOlderContextButKeepsUnreadParentsNearestLeaf() {
        let result = NXUnreadSeenReconciliation.reconcileParents(
            ["root0001", "parent01", "parent02"],
            seenShortIds: ["root0001"]
        )

        XCTAssertEqual(result.visibleRange, 1..<3)
        XCTAssertEqual(result.unreadCount, 3)
    }

    func testReadDirectParentIsStillKeptForContext() {
        let result = NXUnreadSeenReconciliation.reconcileParents(
            ["root0001", "parent01", "parent02"],
            seenShortIds: ["parent02"]
        )

        XCTAssertEqual(result.visibleRange, 2..<3)
        XCTAssertEqual(result.unreadCount, 1)
    }

    func testParentlessUnreadLeafStillCountsAsOne() {
        let result = NXUnreadSeenReconciliation.reconcileParents(
            [],
            seenShortIds: ["root0001"]
        )

        XCTAssertEqual(result.visibleRange, 0..<0)
        XCTAssertEqual(result.unreadCount, 1)
    }

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
                userHasScrolledTowardOlder: false,
                visiblePostCount: 24
            )
        )
        XCTAssertTrue(
            NXFeedViewport.shouldAllowRememberOnOlderFetch(
                continueEnabled: true,
                userHasScrolledTowardOlder: true,
                visiblePostCount: 24
            )
        )
        XCTAssertTrue(
            NXFeedViewport.shouldAllowRememberOnOlderFetch(
                continueEnabled: false,
                userHasScrolledTowardOlder: false,
                visiblePostCount: 24
            )
        )
    }

    func testSparseRememberOnFeedCanRecoverWithoutAUserScroll() {
        XCTAssertTrue(
            NXFeedViewport.shouldAllowRememberOnOlderFetch(
                continueEnabled: true,
                userHasScrolledTowardOlder: false,
                visiblePostCount: 1
            )
        )
        XCTAssertFalse(
            NXFeedViewport.shouldAllowRememberOnOlderFetch(
                continueEnabled: true,
                userHasScrolledTowardOlder: false,
                visiblePostCount: 6
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

    func testUnfinishedRestoreIsNeverTreatedAsAtTop() {
        XCTAssertFalse(
            NXFeedViewport.isActuallyAtTop(
                hasLiveScrollView: true,
                contentOffsetY: -47,
                insetTop: 47,
                isPreparingRestore: true,
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
                fallbackIsAtTop: false
            )
        )
        XCTAssertFalse(
            NXFeedViewport.isActuallyAtTop(
                hasLiveScrollView: true,
                contentOffsetY: 420,
                insetTop: 47,
                isPreparingRestore: false,
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
                fallbackIsAtTop: false
            )
        )
    }

    func testUnreadRegionRemovesOffscreenReadRowsAboveReadingPost() {
        XCTAssertEqual(
            NXUnreadRegion.postIDsToRemove(
                postIDs: ["new", "read-a", "read-b", "reading", "older"],
                unreadCount: { id in
                    ["new": 1, "read-a": 0, "read-b": 0, "reading": 0, "older": 0][id, default: 0]
                },
                readingPostID: "reading",
                visiblePostIDs: ["reading"]
            ),
            ["read-a", "read-b"]
        )
    }

    func testUnreadRegionKeepsVisibleAndUnreadRows() {
        XCTAssertEqual(
            NXUnreadRegion.postIDsToRemove(
                postIDs: ["unread", "peeking", "reading"],
                unreadCount: { id in
                    ["unread": 1, "peeking": 0, "reading": 0][id, default: 0]
                },
                readingPostID: "reading",
                visiblePostIDs: ["peeking", "reading"]
            ),
            []
        )
    }

    func testUnreadRegionDoesNotCompactWithoutAReadingPost() {
        XCTAssertTrue(
            NXUnreadRegion.postIDsToRemove(
                postIDs: ["a", "b"],
                unreadCount: { _ in 0 },
                readingPostID: nil,
                visiblePostIDs: []
            ).isEmpty
        )
    }

    func testAppearOnceIgnoresRowsAboveTheTopEdge() {
        XCTAssertFalse(
            NXUnreadAppearance.shouldConsumeAppearance(
                appearedID: "above",
                postIDs: ["above", "top", "below"],
                topEdgeID: "top",
                readingID: "top",
                holdUnreadAboveReadingPost: false,
                visibleIDs: ["above", "top"],
                isPreparingRestore: false,
                isPerformingScroll: false,
                isPerformingUnreadScroll: false
            )
        )
        XCTAssertTrue(
            NXUnreadAppearance.shouldConsumeAppearance(
                appearedID: "top",
                postIDs: ["above", "top", "below"],
                topEdgeID: "top",
                readingID: "top",
                holdUnreadAboveReadingPost: false,
                visibleIDs: ["top"],
                isPreparingRestore: false,
                isPerformingScroll: false,
                isPerformingUnreadScroll: false
            )
        )
    }

    func testAppearOnceIgnoresRestorePaint() {
        XCTAssertFalse(
            NXUnreadAppearance.shouldConsumeAppearance(
                appearedID: "newest",
                postIDs: ["newest", "saved"],
                topEdgeID: "newest",
                readingID: nil,
                holdUnreadAboveReadingPost: true,
                visibleIDs: ["newest"],
                isPreparingRestore: true,
                isPerformingScroll: false,
                isPerformingUnreadScroll: false
            )
        )
    }

    func testViewportCoverIncludesUnreadRemovals() {
        XCTAssertTrue(
            NXFeedViewport.shouldCoverViewport(
                updateReasons: [NXFeedViewport.unreadRemovalCoverReason]
            )
        )
        XCTAssertTrue(
            NXFeedViewport.shouldCoverViewport(
                updateReasons: [NXFeedViewport.prependCoverReason]
            )
        )
        XCTAssertFalse(
            NXFeedViewport.shouldCoverViewport(updateReasons: ["older posts append"])
        )
    }

    func testPureOffscreenRemovalUsesListAnimationWithoutViewportSettle() {
        XCTAssertTrue(
            NXFeedViewport.shouldAnimateOffscreenRemoval(
                removedPostIDs: ["read-above"],
                visiblePostIDs: ["reading", "below"],
                hasParentUpdates: false
            )
        )
    }

    func testVisibleRemovalOrRowResizeStillUsesAnchoredUpdate() {
        XCTAssertFalse(
            NXFeedViewport.shouldAnimateOffscreenRemoval(
                removedPostIDs: ["reading"],
                visiblePostIDs: ["reading", "below"],
                hasParentUpdates: false
            )
        )
        XCTAssertFalse(
            NXFeedViewport.shouldAnimateOffscreenRemoval(
                removedPostIDs: ["read-above"],
                visiblePostIDs: ["reading", "below"],
                hasParentUpdates: true
            )
        )
    }

    func testPureOffscreenInsertionUsesListAnimationWithoutViewportSettle() {
        XCTAssertTrue(
            NXFeedViewport.shouldAnimateOffscreenInsertion(
                insertedPostIDs: ["new-above"],
                removedPostIDs: [],
                visiblePostIDs: ["reading", "below"],
                isPreparingRestore: false
            )
        )
    }

    func testMixedInsertionOrRestoreStillUsesAnchoredUpdate() {
        XCTAssertFalse(
            NXFeedViewport.shouldAnimateOffscreenInsertion(
                insertedPostIDs: ["new-above"],
                removedPostIDs: ["old-tail"],
                visiblePostIDs: ["reading", "below"],
                isPreparingRestore: false
            )
        )
        XCTAssertFalse(
            NXFeedViewport.shouldAnimateOffscreenInsertion(
                insertedPostIDs: ["new-above"],
                removedPostIDs: [],
                visiblePostIDs: ["reading", "below"],
                isPreparingRestore: true
            )
        )
    }
}
