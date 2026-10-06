//
//  NXFeedViewportTests.swift
//  NosturTests
//

import XCTest
import UIKit
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

    func testLastUnreadLeafBehindToolbarIsRemovedWhenReadElsewhere() {
        let isVisible = NXFeedViewport.isPostVisible(
            frame: CGRect(x: 0, y: 100, width: 300, height: 60),
            contentOffsetY: 100,
            viewportHeight: 600,
            insetTop: 60,
            insetBottom: 0
        )
        XCTAssertFalse(isVisible)
        XCTAssertTrue(NXUnreadSeenReconciliation.shouldRemoveSeenLeafRow(
            isVisible: isVisible,
            removeEvenIfVisible: false
        ))
    }

    func testPartiallyReadableLeafBelowToolbarStaysStable() {
        XCTAssertTrue(NXFeedViewport.isPostVisible(
            frame: CGRect(x: 0, y: 100, width: 300, height: 61),
            contentOffsetY: 100,
            viewportHeight: 600,
            insetTop: 60,
            insetBottom: 0
        ))
    }

    func testLeafBehindBottomBarIsNotReadable() {
        XCTAssertFalse(NXFeedViewport.isPostVisible(
            frame: CGRect(x: 0, y: 650, width: 300, height: 60),
            contentOffsetY: 100,
            viewportHeight: 600,
            insetTop: 60,
            insetBottom: 50
        ))
    }

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

    @MainActor
    func testSeenReconciliationCancellationDropsPendingMutation() async {
        let scheduler = NXSeenReconciliationScheduler()
        var applyCount = 0

        scheduler.schedule(
            isBusy: { false },
            apply: { applyCount += 1 }
        )

        // Detail navigation pauses the feed during this idle grace period.
        try? await Task.sleep(nanoseconds: 100_000_000)
        scheduler.cancel()
        try? await Task.sleep(nanoseconds: 350_000_000)

        XCTAssertEqual(applyCount, 0)
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

    func testCoveredUnreadRemovalSettlesEvenWhenAnchorIndexDoesNotChange() {
        XCTAssertTrue(
            NXFeedViewport.shouldSettleAnchoredUpdate(
                updateReasons: [NXFeedViewport.unreadRemovalCoverReason],
                pinByIdentity: false,
                anchorIndexShifted: false
            )
        )
        XCTAssertFalse(
            NXFeedViewport.shouldSettleAnchoredUpdate(
                updateReasons: ["media row resized"],
                pinByIdentity: false,
                anchorIndexShifted: false
            )
        )
    }

    func testOlderAppendDoesNotSettleStaleAnchorAfterTopReveal() {
        for reasons in [["older posts append"], ["older posts append", "older posts append"]] {
            XCTAssertFalse(NXFeedViewport.shouldSettleAnchoredUpdate(
                updateReasons: reasons,
                pinByIdentity: false,
                anchorIndexShifted: true
            ))
        }
        XCTAssertTrue(NXFeedViewport.shouldSettleAnchoredUpdate(
            updateReasons: ["older posts append", NXFeedViewport.unreadRemovalCoverReason],
            pinByIdentity: false,
            anchorIndexShifted: true
        ))
    }

    func testSettleDoesNotCountMissingFramesOrChangingEstimatesAsStable() {
        var progress = NXFeedSettleProgress()
        for _ in 0..<5 { progress.observe(geometry: nil, corrected: false) }
        XCTAssertEqual(progress.stableSamples, 0)
        let frame = CGRect(x: 0, y: 300, width: 440, height: 200)
        let estimated = NXFeedSettleProgress.Geometry(contentHeight: 4680, offsetY: 1282, insetTop: 118, anchorFrame: frame)
        let resolved = NXFeedSettleProgress.Geometry(contentHeight: 7544, offsetY: 1282, insetTop: 118, anchorFrame: frame)
        progress.observe(geometry: estimated, corrected: false)
        progress.observe(geometry: estimated, corrected: false)
        XCTAssertEqual(progress.stableSamples, 1)
        progress.observe(geometry: resolved, corrected: false)
        XCTAssertEqual(progress.stableSamples, 0)
        for _ in 0..<3 { progress.observe(geometry: resolved, corrected: false) }
        XCTAssertEqual(progress.stableSamples, 3)
        progress.observe(geometry: resolved, corrected: true)
        XCTAssertEqual(progress.stableSamples, 0)
    }

    @MainActor
    func testActualAppendAfterTopRevealDoesNotScrollToStaleFirstPost() async {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 300, height: 100)
        layout.minimumLineSpacing = 0
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 300), collectionViewLayout: layout)
        let source = NXFeedAppendTestSource()
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "post")
        collection.dataSource = source
        let window = UIWindow(frame: collection.bounds)
        window.addSubview(collection)
        collection.reloadData()
        collection.layoutIfNeeded()
        let stabilizer = NXFeedLayoutStabilizer()
        stabilizer.attach(to: collection)
        // UIKit has already painted the explicitly revealed snapshot, while the
        // List onChange callback has not yet replaced the old lookup IDs.
        stabilizer.updateItemIDs(["old-first", "a", "b", "c", "d", "e"])
        stabilizer.rememberAnchor(id: "old-first")
        stabilizer.performAnchored(reason: "older posts append") {
            source.count = 5
            collection.reloadData()
            collection.layoutIfNeeded()
            stabilizer.updateItemIDs(["revealed", "old-first", "a", "b", "older"])
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(collection.contentOffset.y, 0, accuracy: 0.5)
        stabilizer.suspendPositionTracking()
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

    func testOffscreenRemovalDuringPostScrollCooldownUsesAnchoredQueue() {
        XCTAssertFalse(
            NXFeedViewport.shouldAnimateOffscreenRemoval(
                removedPostIDs: ["read-above"],
                visiblePostIDs: ["reading", "below"],
                hasParentUpdates: false,
                isViewportMovingOrRecently: true
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
                isPreparingRestore: false,
                isAtTop: false
            )
        )
    }

    func testMixedInsertionOrRestoreStillUsesAnchoredUpdate() {
        XCTAssertFalse(
            NXFeedViewport.shouldAnimateOffscreenInsertion(
                insertedPostIDs: ["new-above"],
                removedPostIDs: ["old-tail"],
                visiblePostIDs: ["reading", "below"],
                isPreparingRestore: false,
                isAtTop: false
            )
        )
        XCTAssertFalse(
            NXFeedViewport.shouldAnimateOffscreenInsertion(
                insertedPostIDs: ["new-above"],
                removedPostIDs: [],
                visiblePostIDs: ["reading", "below"],
                isPreparingRestore: true,
                isAtTop: false
            )
        )
        XCTAssertFalse(
            NXFeedViewport.shouldAnimateOffscreenInsertion(
                insertedPostIDs: ["new-above"],
                removedPostIDs: [],
                visiblePostIDs: ["reading", "below"],
                isPreparingRestore: false,
                isAtTop: true
            )
        )
    }
}

@MainActor
private final class NXFeedAppendTestSource: NSObject, UICollectionViewDataSource {
    var count = 4

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        collectionView.dequeueReusableCell(withReuseIdentifier: "post", for: indexPath)
    }
}
