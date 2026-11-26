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

#if DEBUG
    @MainActor
    func testJumpDiagnosticsRecordLargeOffsetAndSizeChanges() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        let window = UIWindow(frame: scrollView.bounds)
        window.addSubview(scrollView)
        scrollView.contentSize = CGSize(width: 320, height: 2000)
        let stabilizer = NXFeedLayoutStabilizer()
        stabilizer.attach(to: scrollView)
        var actions: [String] = []
        stabilizer.onDebugAction = { actions.append($0) }

        scrollView.contentOffset.y = 900
        scrollView.contentSize.height = 6000

        XCTAssertTrue(actions.contains { $0.contains("SCROLL displacement · y 0.0→900.0") })
        XCTAssertTrue(actions.contains { $0.contains("LAYOUT size · 2000.0→6000.0") })
        stabilizer.suspendPositionTracking()
    }
#endif

    @MainActor
    func testUnreadReconciliationDropsAbsentRowsAndPreservesQueuedPrepends() async {
        let posts = await bg().perform {
            (1...3).map { index in
                var event = NEvent(content: "Unread reconciliation \(index)")
                event.id = String(format: "%08x", index) + String(repeating: "0", count: 56)
                let preview = createPreviewEvent(event)
                defer { bg().delete(preview) }
                return NRPost(event: preview, withFooter: false, withParents: false)
            }
        }
        let vm = NXColumnViewModel()
        vm.viewState = .posts([posts[0], posts[1]])
        vm.vmInner.unreadIds = [posts[0].id: 1, posts[1].id: 2, "absent": 958]
        vm.viewState = .posts([posts[0]])
        XCTAssertEqual(vm.vmInner.unreadIds, [posts[0].id: 1])

        // Reproduce the report: every rendered row is read, but absent rows
        // keep the counter nonzero. The no-target recovery must clear it.
        vm.vmInner.unreadIds = [posts[0].id: 0, "absent": 958]
        vm.reconcileUnreadPostIDs()
        XCTAssertEqual(vm.vmInner.unreadCount, 0)
        XCTAssertEqual(vm.vmInner.unreadIds[posts[0].id], 0)

        var queued: (() -> [String])?
        vm.vmInner.performAnchoredFeedUpdate = { _, update in queued = update }
        vm.vmInner.isAtTop = false
        let config = NXColumnConfig(id: "unread-regression", name: "Unread regression")
        vm.putOnScreen([posts[2]], config: config)
        XCTAssertNotNil(queued)
        let queuedCount = vm.vmInner.unreadCount
        XCTAssertGreaterThan(queuedCount, 0)
        // Another snapshot can land while the prepend waits for scroll idle.
        vm.viewState = .posts([posts[0]])
        vm.reconcileUnreadPostIDs()
        XCTAssertEqual(vm.vmInner.unreadCount, queuedCount)
        _ = queued?()
        XCTAssertEqual(vm.currentNRPostsOnScreen.map(\.id), [posts[2].id, posts[0].id])
        XCTAssertEqual(vm.vmInner.unreadCount, queuedCount)

        vm.viewState = .posts([posts[0]])
        XCTAssertEqual(vm.vmInner.unreadCount, 0)
        // A formerly dropped row must be eligible to arrive again.
        vm.vmInner.unreadIds[posts[2].id] = 958
        queued = nil
        vm.putOnScreen([posts[2]], config: config)
        XCTAssertNotNil(queued)
        _ = queued?()
        XCTAssertEqual(vm.currentNRPostsOnScreen.first?.id, posts[2].id)
        XCTAssertEqual(vm.vmInner.unreadCount, queuedCount)
    }

    @MainActor
    func testSyncedReadRemovalWaitsForLayoutAndDefersIncomingPosts() async throws {
        try await assertExternalReadRemoval(useOtherColumn: false)
    }

    @MainActor
    func testCrossColumnReadRemovalWaitsForVisibleFeedAndLayout() async throws {
        try await assertExternalReadRemoval(useOtherColumn: true)
    }

    @MainActor
    private func assertExternalReadRemoval(useOtherColumn: Bool) async throws {
        _ = AppState.shared
        _ = AccountsState.shared
        let wasEnabled = SettingsStore.shared.appWideSeenTracker
        SettingsStore.shared.appWideSeenTracker = true
        defer { SettingsStore.shared.appWideSeenTracker = wasEnabled }
        let posts = await bg().perform {
            (1...13).map { index in
                var event = NEvent(content: "Synced read regression \(index)")
                event.id = String(format: "%08x", 700 + index) + String(repeating: "0", count: 56)
                let preview = createPreviewEvent(event)
                defer { bg().delete(preview) }
                return NRPost(event: preview, withFooter: false, withParents: false)
            }
        }
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 300, height: 300)
        layout.minimumLineSpacing = 0
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 300, height: 600), collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        let source = NXFeedAppendTestSource()
        source.count = 12
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "post")
        collection.dataSource = source
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = collection.bounds
        window.addSubview(collection)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        collection.reloadData()
        collection.layoutIfNeeded()
        collection.contentOffset.y = 900
        collection.layoutIfNeeded()

        let vm = NXColumnViewModel()
        vm.isVisible = true
        vm.collectionView = collection
        vm.viewState = .posts(Array(posts.prefix(12)))
        vm.vmInner.isAtTop = false
        vm.vmInner.unreadIds = Dictionary(uniqueKeysWithValues: posts.prefix(12).map { ($0.id, 1) })
        var layoutBusy = true
        vm.vmInner.isFeedLayoutUpdating = { layoutBusy }
        var anchoredUpdates = 0
        vm.vmInner.performAnchoredFeedUpdate = { _, update in
            anchoredUpdates += 1
            _ = update()
        }
        // Read above, on, and below the viewport. Only the offscreen rows leave.
        let seen = Set([posts[0].shortId, posts[3].shortId, posts[10].shortId])
        if useOtherColumn {
            // Keep the UIKit List attached: visibility and detail navigation must
            // independently prevent a hidden column's rendered snapshot changing.
            vm.isVisible = false
            vm.removeUnreadPostsAlreadyMarkedRead(seen, otherColumnSeenShortIds: seen)
            try? await Task.sleep(nanoseconds: 650_000_000)
            XCTAssertEqual(vm.currentNRPostsOnScreen.count, 12)
            XCTAssertEqual(vm.vmInner.unreadCount, 12)
            vm.isVisible = true
            vm.pauseViewUpdates()
            vm.removeUnreadPostsAlreadyMarkedRead(seen, otherColumnSeenShortIds: seen)
            try? await Task.sleep(nanoseconds: 650_000_000)
            XCTAssertEqual(vm.currentNRPostsOnScreen.count, 12)
            XCTAssertEqual(vm.vmInner.unreadCount, 12)
            // No resend: returning must reconcile the reads received while away.
            vm.resumeViewUpdates()
        } else {
            vm.removeUnreadPostsAlreadyMarkedRead(seen, syncedOrFeedSeenShortIds: seen)
        }
        try? await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertEqual(vm.currentNRPostsOnScreen.count, 12)
        XCTAssertEqual(vm.vmInner.unreadCount, 12)

        if useOtherColumn {
            // Also hide after reconciliation has already been queued.
            vm.isVisible = false
            layoutBusy = false
            try? await Task.sleep(nanoseconds: 500_000_000)
            XCTAssertEqual(vm.currentNRPostsOnScreen.count, 12)
            XCTAssertEqual(vm.vmInner.unreadCount, 12)
            layoutBusy = true
            vm.isVisible = true
            vm.resumeViewUpdates()
        }
        layoutBusy = false
        // Wait until the anchored removal starts so the next batch overlaps it.
        for _ in 0..<100 {
            if vm.isApplyingReadRemoval { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(vm.isApplyingReadRemoval)
        XCTAssertFalse(vm.currentNRPostsOnScreen.contains { $0.id == posts[0].id })
        XCTAssertFalse(vm.currentNRPostsOnScreen.contains { $0.id == posts[10].id })
        XCTAssertTrue(vm.currentNRPostsOnScreen.contains { $0.id == posts[3].id })
        XCTAssertEqual(vm.vmInner.unreadIds[posts[3].id], 0)
        XCTAssertEqual(vm.vmInner.unreadCount, 9)
        XCTAssertEqual(anchoredUpdates, 1)

        let stabilizer = NXFeedLayoutStabilizer()
        stabilizer.attach(to: collection)
        stabilizer.updateItemIDs(vm.currentNRPostsOnScreen.map(\.id))
        stabilizer.shouldDeferAnchoredUpdates = { vm.isApplyingReadRemoval }
        var queuedLayoutApplied = false
        stabilizer.performAnchored(reason: "concurrent layout") { queuedLayoutApplied = true }
        XCTAssertFalse(queuedLayoutApplied)

        let config = NXColumnConfig(id: "synced-read-regression", name: "Synced read regression")
        var completed = false
        vm.putOnScreen([posts[12]], config: config, insertAtEnd: true) { completed = true }
        XCTAssertFalse(completed)
        XCTAssertFalse(vm.currentNRPostsOnScreen.contains { $0.id == posts[12].id })
        try? await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertFalse(vm.isApplyingReadRemoval)
        XCTAssertTrue(completed)
        XCTAssertTrue(queuedLayoutApplied)
        XCTAssertEqual(vm.currentNRPostsOnScreen.last?.id, posts[12].id)
        XCTAssertEqual(anchoredUpdates, 2)
    }

    @MainActor
    func testQueuedExternalReadRemovalRechecksThePostNowVisible() async throws {
        _ = AppState.shared
        _ = AccountsState.shared
        let wasEnabled = SettingsStore.shared.appWideSeenTracker
        SettingsStore.shared.appWideSeenTracker = true
        defer { SettingsStore.shared.appWideSeenTracker = wasEnabled }
        let posts = await bg().perform {
            (0..<3).map { index in
                var event = NEvent(content: "Queued external read \(index)")
                event.id = String(format: "%08x", 8000 + index) + String(repeating: "0", count: 56)
                let preview = createPreviewEvent(event)
                defer { bg().delete(preview) }
                return NRPost(event: preview, withFooter: false, withParents: false)
            }
        }
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 300, height: 100)
        layout.minimumLineSpacing = 0
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 300, height: 100), collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        let source = NXFeedAppendTestSource()
        source.count = posts.count + NXFeedIndexMapping.paginationRowCount
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "post")
        collection.dataSource = source
        let window = UIWindow(frame: collection.bounds)
        window.addSubview(collection)
        collection.reloadData()
        collection.layoutIfNeeded()
        collection.contentOffset.y = 150
        collection.layoutIfNeeded()
        let vm = NXColumnViewModel()
        vm.isVisible = true
        vm.collectionView = collection
        vm.viewState = .posts(posts)
        vm.vmInner.unreadIds = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, 1) })
        var queued: (() -> [String])?
        vm.vmInner.performAnchoredFeedUpdate = { _, update in queued = update }
        vm.removeUnreadPostsAlreadyMarkedRead([posts[0].shortId], otherColumnSeenShortIds: [posts[0].shortId])
        for _ in 0..<200 {
            if queued != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let apply = try XCTUnwrap(queued)
        XCTAssertEqual(vm.currentNRPostsOnScreen.count, 3)
        collection.contentOffset.y = 50
        collection.layoutIfNeeded()
        XCTAssertEqual(apply(), posts.map(\.id))
        XCTAssertEqual(vm.currentNRPostsOnScreen.map(\.id), posts.map(\.id))
        XCTAssertEqual(vm.vmInner.unreadIds[posts[0].id], 0)
        XCTAssertFalse(vm.isApplyingReadRemoval)
    }

    @MainActor
    func testCrossColumnReadRemovalKeepsReadingPostThroughCollapsedEstimates() async throws {
        _ = AppState.shared
        _ = AccountsState.shared
        let wasEnabled = SettingsStore.shared.appWideSeenTracker
        SettingsStore.shared.appWideSeenTracker = true
        defer { SettingsStore.shared.appWideSeenTracker = wasEnabled }
        let posts = await bg().perform {
            (0..<94).map { index in
                var event = NEvent(content: "Cross-column viewport regression \(index)")
                event.id = String(format: "%08x", 9000 + index) + String(repeating: "0", count: 56)
                let preview = createPreviewEvent(event)
                defer { bg().delete(preview) }
                return NRPost(event: preview, withFooter: false, withParents: false)
            }
        }
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 300, height: 205)
        layout.minimumLineSpacing = 0
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 371, height: 1121), collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        collection.contentInset.top = 97
        let source = NXFeedAppendTestSource()
        source.count = 94
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "post")
        collection.dataSource = source
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = collection.bounds
        window.addSubview(collection)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        collection.reloadData()
        collection.layoutIfNeeded()
        collection.contentOffset.y = 39 * 205 - 97
        collection.layoutIfNeeded()

        let vm = NXColumnViewModel()
        vm.isVisible = true
        vm.collectionView = collection
        vm.viewState = .posts(posts)
        vm.vmInner.unreadIds = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, 1) })
        vm.vmInner.readingPostID = posts[39].id
        let stabilizer = NXFeedLayoutStabilizer()
        stabilizer.attach(to: collection)
        stabilizer.updateItemIDs(posts.map(\.id))
        let host = NXFeedSnapshotHostView(frame: collection.convert(collection.bounds, to: window))
        host.stabilizer = stabilizer
        window.addSubview(host)
        vm.vmInner.isFeedLayoutUpdating = { stabilizer.isLayoutUpdating }
        var removalStarted = false
        vm.vmInner.performAnchoredFeedUpdate = { reason, update in
            XCTAssertEqual(reason, NXFeedViewport.unreadRemovalCoverReason)
            stabilizer.performAnchored(reason: reason) {
                let ids = update()
                removalStarted = true
                source.count = ids.count
                layout.itemSize.height = 65
                collection.reloadData()
                collection.layoutIfNeeded()
                collection.contentOffset.y = 2355.5
                stabilizer.updateItemIDs(ids)
            }
        }

        // Reading a different row in another column deletes it here.
        vm.removeUnreadPostsAlreadyMarkedRead([posts[0].shortId], otherColumnSeenShortIds: [posts[0].shortId])
        for _ in 0..<200 {
            if removalStarted { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(removalStarted)
        XCTAssertEqual(vm.currentNRPostsOnScreen.count, 93)
        XCTAssertFalse(vm.currentNRPostsOnScreen.contains { $0.id == posts[0].id })
        XCTAssertTrue(stabilizer.hasActivePrependCover)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(collection.contentOffset.y, 38 * 65 - 97, accuracy: 0.5)

        // Real heights resolve after the first correction, while the cover stays up.
        layout.itemSize.height = 205
        layout.invalidateLayout()
        collection.layoutIfNeeded()
        collection.contentOffset.y = 2355.5
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(collection.contentOffset.y, 38 * 205 - 97, accuracy: 0.5)
        XCTAssertEqual(stabilizer.liveVisiblePostID(), posts[39].id)
        XCTAssertEqual(vm.vmInner.readingPostID, posts[39].id)
        XCTAssertFalse(stabilizer.hasActivePrependCover)
        stabilizer.suspendPositionTracking()
    }

    @MainActor
    func testIdleSeenCleanupKeepsRenderedRowsAndUnreadUntilTop() async throws {
        _ = AppState.shared
        _ = AccountsState.shared
        let wasEnabled = SettingsStore.shared.appWideSeenTracker
        SettingsStore.shared.appWideSeenTracker = true
        defer { SettingsStore.shared.appWideSeenTracker = wasEnabled }
        let posts = await bg().perform {
            (1...12).map { index in
                var event = NEvent(content: "Reading regression \(index)")
                event.id = String(format: "%08x", index) + String(repeating: "0", count: 56)
                let preview = createPreviewEvent(event)
                defer { bg().delete(preview) }
                return NRPost(event: preview, withFooter: false, withParents: false)
            }
        }
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 300, height: 300)
        layout.minimumLineSpacing = 0
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 300, height: 600), collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        let source = NXFeedAppendTestSource()
        source.count = posts.count
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "post")
        collection.dataSource = source
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = collection.bounds
        window.addSubview(collection)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        collection.reloadData()
        collection.layoutIfNeeded()
        collection.contentOffset.y = 900
        collection.layoutIfNeeded()
        let vm = NXColumnViewModel()
        vm.isVisible = true
        vm.collectionView = collection
        vm.viewState = .posts(posts)
        vm.vmInner.unreadIds = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, 1) })
        vm.vmInner.isFeedViewportMovingOrRecently = { false }
        let beforeIDs = posts.map(\.id)
        let beforeUnread = vm.vmInner.unreadIds
        var structuralUpdates = 0
        vm.vmInner.performAnchoredFeedUpdate = { _, update in
            structuralUpdates += 1
            _ = update()
        }
        // Exactly the idle reconciliation in the reports: no finger down, seen
        // rows below the viewport, with the reading post still in the list.
        let seen = Set(posts.suffix(4).map(\.shortId))
        vm.removeUnreadPostsAlreadyMarkedRead(seen)
        XCTAssertEqual(vm.currentNRPostsOnScreen.map(\.id), beforeIDs)
        XCTAssertEqual(vm.vmInner.unreadIds, beforeUnread)
        XCTAssertEqual(structuralUpdates, 0)
        XCTAssertEqual(collection.contentOffset.y, 900, accuracy: 0.5)
        // A cleanup queued at top must recheck when it executes after scrolling.
        var queued: (() -> [String])?
        vm.vmInner.performAnchoredFeedUpdate = { _, update in queued = update }
        collection.contentOffset.y = 0
        collection.layoutIfNeeded()
        vm.removeUnreadPostsAlreadyMarkedRead(seen)
        XCTAssertNotNil(queued)
        collection.contentOffset.y = 900
        collection.layoutIfNeeded()
        _ = queued?()
        XCTAssertEqual(vm.currentNRPostsOnScreen.map(\.id), beforeIDs)
        XCTAssertEqual(vm.vmInner.unreadIds, beforeUnread)
        vm.vmInner.performAnchoredFeedUpdate = { _, update in
            structuralUpdates += 1
            _ = update()
        }
        collection.contentOffset.y = 0
        collection.layoutIfNeeded()
        vm.removeUnreadPostsAlreadyMarkedRead(seen)
        XCTAssertLessThan(vm.currentNRPostsOnScreen.count, posts.count)
        XCTAssertEqual(structuralUpdates, 1)
    }

    @MainActor
    func testNetworkingResumeDoesNotUnpauseDetailSource() {
        _ = AppState.shared
        _ = AccountsState.shared
        let vm = NXColumnViewModel()
        vm.config = NXColumnConfig(id: "detail-resume-regression", name: "Detail resume regression")
        vm.isVisible = true
        vm.viewState = .posts([])
        vm.pauseViewUpdates()
        vm.resume()
        XCTAssertTrue(vm.isViewPaused)
        vm.pause()
    }

    @MainActor
    func testFeedAppearanceClearsViewPauseBeforeTabSelection() {
        let vm = NXColumnViewModel()
        vm.viewState = .posts([])
        vm.pauseViewUpdates()
        XCTAssertTrue(vm.isViewPaused)
        XCTAssertFalse(vm.isVisible)

        vm.resumeViewUpdates()
        vm.isVisible = true

        XCTAssertFalse(vm.isViewPaused)
    }

    @MainActor
    func testDetailNavigationPreservesReadRowsAndThreadContext() async throws {
        _ = AppState.shared
        _ = AccountsState.shared
        let wasEnabled = SettingsStore.shared.appWideSeenTracker
        SettingsStore.shared.appWideSeenTracker = true
        defer { SettingsStore.shared.appWideSeenTracker = wasEnabled }
        let posts = await bg().perform {
            (1...12).map { index in
                var event = NEvent(content: "Detail return regression \(index)")
                event.id = String(format: "%08x", index + 1000) + String(repeating: "0", count: 56)
                let preview = createPreviewEvent(event)
                defer { bg().delete(preview) }
                return NRPost(event: preview, withFooter: false, withParents: false)
            }
        }
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 300, height: 300)
        layout.minimumLineSpacing = 0
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 300, height: 600), collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        let source = NXFeedAppendTestSource()
        source.count = posts.count
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "post")
        collection.dataSource = source
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = collection.bounds
        window.addSubview(collection)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        collection.reloadData()
        collection.layoutIfNeeded()
        collection.contentOffset.y = 950
        collection.layoutIfNeeded()
        let vm = NXColumnViewModel()
        vm.isVisible = true
        vm.collectionView = collection
        vm.viewState = .posts(posts)
        // The visible row contains a read ancestor. Reconciliation must leave
        // that displayed context intact both now and when detail opens.
        let reading = posts[3]
        reading.postOrThreadAttributes.parentPosts = Array(posts.prefix(2))
        vm.vmInner.unreadIds = [reading.id: 3]
        vm.removeUnreadPostsAlreadyMarkedRead([posts[0].shortId])
        let beforeIDs = posts.map(\.id)
        let beforeParents = reading.postOrThreadAttributes.parentPosts.map(\.id)
        let beforeUnread = vm.vmInner.unreadIds
        let stabilizer = NXFeedLayoutStabilizer()
        stabilizer.attach(to: collection)
        stabilizer.updateItemIDs(beforeIDs)
        stabilizer.suspendPositionTracking()
        vm.pauseViewUpdates()
        XCTAssertTrue(vm.isViewPaused)
        XCTAssertEqual(vm.currentNRPostsOnScreen.map(\.id), beforeIDs)
        XCTAssertEqual(reading.postOrThreadAttributes.parentPosts.map(\.id), beforeParents)
        XCTAssertEqual(vm.vmInner.unreadIds, beforeUnread)
        // Even a direct seen update while away must preserve the snapshot.
        vm.removeUnreadPostsAlreadyMarkedRead([reading.shortId])
        stabilizer.updateItemIDs(vm.currentNRPostsOnScreen.map(\.id))
        collection.contentOffset.y = 1250 // UIKit changed its estimate while hidden.
        stabilizer.resumePositionTracking()
        try? await Task.sleep(nanoseconds: 550_000_000)
        XCTAssertEqual(stabilizer.liveVisiblePostID(), reading.id)
        XCTAssertEqual(collection.contentOffset.y, 950, accuracy: 0.5)
        XCTAssertEqual(reading.postOrThreadAttributes.parentPosts.map(\.id), beforeParents)
        stabilizer.suspendPositionTracking()
    }

    @MainActor
    func testFinalUnreadScrollAnimatesToContentEdgeWhileImportQueueIsBlocked() async throws {
        let entered = expectation(description: "import context occupied")
        let gate = DispatchSemaphore(value: 0)
        let importer = Task { await bg().perform { entered.fulfill(); _ = gate.wait(timeout: .now() + 5) } }
        defer { gate.signal(); importer.cancel() }
        await fulfillment(of: [entered], timeout: 1)

        let scrollView = NXFeedAnimatedTopTestScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset.top = 64
        scrollView.contentSize = CGSize(width: 320, height: 3000)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scrollView.bounds
        window.addSubview(scrollView)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        scrollView.contentOffset.y = 180 // Near the first post, with a banner above it.
        let stabilizer = NXFeedLayoutStabilizer()
        stabilizer.attach(to: scrollView)
        var completed = false
        let jump = Task { @MainActor in
            let result = await stabilizer.scrollToContentTop(animated: true)
            completed = true
            return result
        }
        await Task.yield()
        XCTAssertEqual(scrollView.lastAnimatedTarget?.y, -64)
        XCTAssertEqual(scrollView.contentOffset.y, 180, accuracy: 0.5,
            "The final unread must animate instead of immediately setting the final offset")
        XCTAssertFalse(completed, "Do not publish at-top before the native animation lands")

        let started = Date.now
        let uiResponsive = await Task { @MainActor in true }.value
        XCTAssertTrue(uiResponsive)
        XCTAssertLessThan(Date.now.timeIntervalSince(started), 0.5)
        scrollView.completeNativeAnimation()
        let reachedTop = await jump.value
        XCTAssertTrue(reachedTop)
        XCTAssertEqual(scrollView.contentOffset.y, -64, accuracy: 0.5)
        stabilizer.suspendPositionTracking()
    }

    @MainActor
    func testTopAnimationRetargetsAfterSelfSizingLeavesItShort() async throws {
        let scrollView = NXFeedAnimatedTopTestScrollView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset.top = 118
        scrollView.contentSize = CGSize(width: 402, height: 10451)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scrollView.bounds
        window.addSubview(scrollView)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        scrollView.contentOffset.y = 8671
        let stabilizer = NXFeedLayoutStabilizer()
        stabilizer.attach(to: scrollView)
        let jump = Task { @MainActor in await stabilizer.scrollToContentTop(animated: true) }
        await Task.yield()
        XCTAssertEqual(scrollView.animationRequestCount, 1)
        // Match the report: self-sizing expands the list during the native
        // animation and UIKit stops several posts before the requested edge.
        scrollView.contentSize.height = 15538
        scrollView.contentOffset.y = 663
        for _ in 0..<40 {
            if scrollView.animationRequestCount > 1 { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertEqual(scrollView.animationRequestCount, 2, "Continue the native animation after the layout change")
        XCTAssertEqual(scrollView.contentOffset.y, 663, accuracy: 0.5, "Retargeting must not force an unanimated snap")
        scrollView.completeNativeAnimation()
        let reachedTop = await jump.value
        XCTAssertTrue(reachedTop)
        XCTAssertEqual(scrollView.contentOffset.y, -118, accuracy: 0.5)
        stabilizer.suspendPositionTracking()
    }

    @MainActor
    func testCancelledFinalUnreadAnimationDoesNotForceAJumpToTop() async throws {
        let scrollView = NXFeedAnimatedTopTestScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentSize = CGSize(width: 320, height: 3000)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scrollView.bounds
        window.addSubview(scrollView)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        scrollView.contentOffset.y = 160
        let stabilizer = NXFeedLayoutStabilizer()
        stabilizer.attach(to: scrollView)
        let jump = Task { @MainActor in await stabilizer.scrollToContentTop(animated: true) }
        await Task.yield()
        XCTAssertNotNil(scrollView.lastAnimatedTarget)
        jump.cancel()
        let reachedTop = await jump.value
        XCTAssertFalse(reachedTop)
        XCTAssertEqual(scrollView.contentOffset.y, 160, accuracy: 0.5)
        XCTAssertFalse(stabilizer.isProgrammaticScrollPending)
        stabilizer.suspendPositionTracking()
    }

    @MainActor
    func testStalledFinalUnreadAnimationDoesNotForceAnUnanimatedJump() async throws {
        let scrollView = NXFeedAnimatedTopTestScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset.top = 64
        scrollView.contentSize = CGSize(width: 320, height: 3000)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scrollView.bounds
        window.addSubview(scrollView)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        scrollView.contentOffset.y = 180
        let stabilizer = NXFeedLayoutStabilizer()
        stabilizer.attach(to: scrollView)
        let reachedTop = await stabilizer.scrollToContentTop(animated: true)
        XCTAssertFalse(reachedTop)
        XCTAssertEqual(scrollView.contentOffset.y, 180, accuracy: 0.5)
        XCTAssertFalse(stabilizer.isProgrammaticScrollPending)
        stabilizer.suspendPositionTracking()
    }

    @MainActor
    func testLateUnreadLayoutKeepsTheLandedPostVisible() async throws {
        try await assertLateUnreadLayout(userScrolled: false)
    }

    @MainActor
    func testLateUnreadLayoutDoesNotUndoSubsequentUserScrolling() async throws {
        try await assertLateUnreadLayout(userScrolled: true)
    }

    @MainActor
    func testLateUnreadProtectionExpiresInsteadOfPinningAnOldTarget() async throws {
        try await assertLateUnreadLayout(userScrolled: false, protectionExpired: true)
    }

    @MainActor
    func testLateUnreadResizeAndImmediateAppendKeepTheLandedPost() async throws {
        try await assertLateUnreadLayout(userScrolled: false, appendAfterResize: true)
    }

    @MainActor
    private func assertLateUnreadLayout(userScrolled: Bool, protectionExpired: Bool = false, appendAfterResize: Bool = false) async throws {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 0
        let collection = NXFeedUnreadLayoutTestCollection(frame: CGRect(x: 0, y: 0, width: 320, height: 600), collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        let source = NXFeedAppendTestSource()
        source.count = 30
        source.rowHeights = Array(repeating: 200, count: 30)
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "post")
        collection.dataSource = source
        collection.delegate = source
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = collection.bounds
        window.addSubview(collection)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        collection.reloadData()
        collection.layoutIfNeeded()
        collection.contentOffset.y = 2800
        collection.layoutIfNeeded()
        let stabilizer = NXFeedLayoutStabilizer()
        stabilizer.attach(to: collection)
        stabilizer.updateItemIDs((0..<30).map { "post-\($0)" })
        let host = NXFeedSnapshotHostView(frame: collection.convert(collection.bounds, to: window))
        host.stabilizer = stabilizer
        window.addSubview(host)
        await stabilizer.animateItemToVisibleTop(id: "post-10", indexPath: IndexPath(item: 10, section: 0), in: collection)
        XCTAssertTrue(stabilizer.isItemAtVisibleTop(id: "post-10"))
        try await Task.sleep(nanoseconds: protectionExpired ? 2_100_000_000 : 80_000_000)
        if userScrolled {
            collection.userIsDragging = true
            collection.contentOffset.y = 2800
            collection.layoutIfNeeded()
            collection.userIsDragging = false
        }
        // Unreported self-sizing invalidation after a clean unread landing.
        source.rowHeights = Array(repeating: 120, count: 10) + Array(repeating: 200, count: 20)
        layout.invalidateLayout()
        collection.layoutIfNeeded()
        collection.contentOffset.y = userScrolled ? 2800 : 2000
        if appendAfterResize {
            stabilizer.performAnchored(reason: "older posts append") {
                source.count = 32
                source.rowHeights += [200, 200]
                collection.reloadData()
                collection.layoutIfNeeded()
                stabilizer.updateItemIDs((0..<32).map { "post-\($0)" })
            }
        }
        try await Task.sleep(nanoseconds: 250_000_000)
        if userScrolled || protectionExpired {
            XCTAssertEqual(collection.contentOffset.y, userScrolled ? 2800 : 2000, accuracy: 0.5)
        } else {
            XCTAssertEqual(collection.contentOffset.y, 1200, accuracy: 0.5)
            XCTAssertTrue(stabilizer.isItemAtVisibleTop(id: "post-10"))
        }
        XCTAssertFalse(stabilizer.hasActivePrependCover)
        stabilizer.suspendPositionTracking()
    }

    @MainActor
    func testUnreadStartUsesFirstVisiblePostBelowLeadingBanner() {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 300, height: 200)
        layout.minimumLineSpacing = 0
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 406, height: 1275), collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        collection.contentInset.top = 97
        let source = NXFeedAppendTestSource()
        source.count = 29
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "post")
        collection.dataSource = source
        let window = UIWindow(frame: collection.bounds)
        window.addSubview(collection)
        collection.reloadData()
        collection.layoutIfNeeded()
        collection.contentOffset.y = -34
        collection.layoutIfNeeded()
        let stabilizer = NXFeedLayoutStabilizer()
        stabilizer.attach(to: collection)
        let ids = (0..<28).map { "post-\($0)" }
        stabilizer.updateItemIDs(ids, leadingNonPostRowCount: 1)
        stabilizer.rememberAnchor(id: "post-2")
        let live = stabilizer.liveVisiblePostID()
        XCTAssertEqual(live, "post-0")
        let start = NXUnreadNavigation.start(
            liveVisibleIndex: live.flatMap { ids.firstIndex(of: $0) },
            readingIndex: 2, fallbackVisibleIndex: 2,
            isViewportTransitioning: false, postCount: 28
        )
        XCTAssertEqual(start, .init(index: 0, source: "live-visible"))
        XCTAssertNil(NXUnreadNavigation.previousUnreadIndex(from: start.index, postCount: ids.count, isUnread: { $0 == 1 }))
        XCTAssertFalse(stabilizer.isItemAtOrAboveVisibleTop(id: "post-1"))
        stabilizer.suspendPositionTracking()
    }

    func testUnreadSelectionNeverWrapsToAnOlderRowBelowTheStart() {
        XCTAssertNil(NXUnreadNavigation.previousUnreadIndex(from: 2, postCount: 5, isUnread: { $0 == 3 }))
        XCTAssertEqual(NXUnreadNavigation.previousUnreadIndex(from: 2, postCount: 5, isUnread: { [0, 1, 3].contains($0) }), 1)
        XCTAssertNil(NXUnreadNavigation.previousUnreadIndex(from: 0, postCount: 5, isUnread: { $0 == 1 }))
    }

    @MainActor
    func testIdleEstimatedLayoutCollapseRestoresReadingPost() async throws {
        try await assertIdleEstimatedCollapse(userScrolled: false)
    }

    @MainActor
    func testUserScrollingCancelsQueuedIdleCollapseRecovery() async throws {
        try await assertIdleEstimatedCollapse(userScrolled: true)
    }

    @MainActor
    private func assertIdleEstimatedCollapse(userScrolled: Bool) async throws {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 300, height: 200)
        layout.minimumLineSpacing = 0
        let collection = NXFeedUnreadLayoutTestCollection(frame: CGRect(x: 0, y: 0, width: 406, height: 1275), collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        collection.contentInset.top = 97
        let source = NXFeedAppendTestSource()
        source.count = 29
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "post")
        collection.dataSource = source
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = collection.bounds
        window.addSubview(collection)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        collection.reloadData()
        collection.layoutIfNeeded()
        collection.contentOffset.y = 1703
        collection.layoutIfNeeded()
        let stabilizer = NXFeedLayoutStabilizer()
        stabilizer.attach(to: collection)
        var actions: [String] = []
#if DEBUG
        stabilizer.onDebugAction = { actions.append($0) }
#endif
        stabilizer.updateItemIDs((0..<28).map { "post-\($0)" }, leadingNonPostRowCount: 1)
        stabilizer.rememberAnchor(id: "post-8")
        XCTAssertEqual(stabilizer.liveVisiblePostID(), "post-8")
        let host = NXFeedSnapshotHostView(frame: collection.convert(collection.bounds, to: window))
        host.stabilizer = stabilizer
        window.addSubview(host)
        // Every row temporarily becomes an estimate; no post IDs changed.
        layout.itemSize.height = 43
        layout.invalidateLayout()
        collection.layoutIfNeeded()
        collection.contentOffset.y = -34
        if userScrolled {
            collection.userIsDragging = true
            collection.contentOffset.y = -30
            collection.userIsDragging = false
        }
        try await Task.sleep(nanoseconds: 160_000_000)
        XCTAssertEqual(stabilizer.hasActivePrependCover, !userScrolled,
            "A clamped estimate cannot count as a successful pin, and a new user scroll must win")
        layout.itemSize.height = 200
        layout.invalidateLayout()
        collection.layoutIfNeeded()
        if userScrolled {
            // Exercise an in-content destination after the short estimated
            // layout ends, rather than UIKit's automatic top-edge bounce.
            collection.userIsDragging = true
            collection.contentOffset.y = 400
            collection.layoutIfNeeded()
            collection.userIsDragging = false
        } else {
            collection.contentOffset.y = -34
        }
        try await Task.sleep(nanoseconds: 220_000_000)
        if userScrolled {
            // A synthetic drag does not drive UIKit's pan recognizer. UIKit may
            // finish its own clamp animation, so assert our recovery stayed canceled.
            XCTAssertFalse(actions.contains { $0.hasPrefix("LAYOUT collapse recovery") || $0.hasPrefix("SETTLE ") },
                actions.joined(separator: " | "))
        } else {
            XCTAssertEqual(collection.contentOffset.y, 1703, accuracy: 0.5,
                "Size \(collection.contentSize), trace: \(actions.joined(separator: " | "))")
            XCTAssertEqual(stabilizer.liveVisiblePostID(), "post-8")
        }
        XCTAssertFalse(stabilizer.hasActivePrependCover)
        stabilizer.suspendPositionTracking()
    }

    @MainActor
    func testHomeRemainsAtContentTopWhenBannerIsInsertedAndRemoved() async throws {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 300, height: 200)
        layout.minimumLineSpacing = 0
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 300, height: 600), collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        collection.contentInset.top = 64
        let source = NXFeedAppendTestSource()
        source.sections = [15, 2]
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "post")
        collection.dataSource = source
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = collection.bounds
        window.addSubview(collection)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        collection.reloadData()
        collection.layoutIfNeeded()
        let stabilizer = NXFeedLayoutStabilizer()
        stabilizer.attach(to: collection)
        let ids = (0..<15).map { "post-\($0)" }
        stabilizer.updateItemIDs(ids, leadingNonPostRowCount: 0, trailingNonPostRowCount: 2)
        let reachedTop = await stabilizer.scrollToContentTop()
        XCTAssertTrue(reachedTop)
        for visible in [true, false] {
            stabilizer.performAnchored(reason: NXFeedViewport.bannerUpdateCoverReason) {
                stabilizer.updateItemIDs(ids, leadingNonPostRowCount: visible ? 1 : 0, trailingNonPostRowCount: 2)
            }
            source.sections = visible ? [1, 15, 2] : [15, 2]
            collection.reloadData()
            collection.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 350_000_000)
            XCTAssertEqual(collection.contentOffset.y, -64, accuracy: 0.5, "Banner visible: \(visible)")
            XCTAssertEqual(stabilizer.liveVisiblePostID(), "post-0")
            XCTAssertFalse(stabilizer.hasActivePrependCover)
        }
        stabilizer.suspendPositionTracking()
    }

    @MainActor
    func testHomeReachesContentTopWithLeadingBannerAndStaysThereAfterPromptLayout() async throws {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 300, height: 200)
        layout.minimumLineSpacing = 0
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 300, height: 600), collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        collection.contentInset.top = 64
        let source = NXFeedAppendTestSource()
        source.count = 16 // One already-seen banner followed by fifteen posts.
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "post")
        collection.dataSource = source
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = collection.bounds
        window.addSubview(collection)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        collection.reloadData()
        collection.layoutIfNeeded()
        let stabilizer = NXFeedLayoutStabilizer()
        stabilizer.attach(to: collection)
        stabilizer.updateItemIDs((0..<15).map { "post-\($0)" }, leadingNonPostRowCount: 1)
        collection.contentOffset.y = 700
        stabilizer.rememberAnchor(id: "post-3")

        // The old first-post target leaves the banner above the viewport, so
        // the very next sample hides the report prompt after Home announces top.
        collection.scrollToItem(at: IndexPath(item: 1, section: 0), at: .top, animated: false)
        XCTAssertFalse(NXFeedViewport.isOffsetAtTop(contentOffsetY: collection.contentOffset.y,
            insetTop: collection.adjustedContentInset.top))

        let reachedTop = await stabilizer.scrollToContentTop()
        XCTAssertTrue(reachedTop)
        XCTAssertEqual(collection.contentOffset.y, -64, accuracy: 0.5)
        XCTAssertTrue(collection.indexPathsForVisibleItems.contains(IndexPath(item: 0, section: 0)))
        stabilizer.rememberContentTop() // The normal viewport callback after Home.

        // Showing the prompt resizes the feed. A later top check and another
        // Home tap must keep it eligible, without pinning the first post again.
        collection.frame.size.height -= 100
        collection.contentInset.top += 30
        collection.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertTrue(YearReviewDiscovery.canPresent(isVisible: true,
            isAtTop: NXFeedViewport.isOffsetAtTop(contentOffsetY: collection.contentOffset.y,
                insetTop: collection.adjustedContentInset.top), unreadCount: 0, isRestoring: false),
            "After prompt layout: offset \(collection.contentOffset.y), inset \(collection.adjustedContentInset.top)")
        let reachedTopAgain = await stabilizer.scrollToContentTop()
        XCTAssertTrue(reachedTopAgain)
        XCTAssertEqual(collection.contentOffset.y, -94, accuracy: 0.5)
        // Choosing a post leaves the top target; a later inset change must not
        // unexpectedly bring the user back to the report prompt.
        stabilizer.rememberAnchor(id: "post-3")
        collection.contentOffset.y = 600
        collection.contentInset.top += 20
        collection.layoutIfNeeded()
        XCTAssertGreaterThan(collection.contentOffset.y, 400)
        stabilizer.suspendPositionTracking()
    }

    @MainActor
    func testDelayedBannerInsertionPinsReadingRowWithoutChangingPostIDs() async throws {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 300, height: 200)
        layout.minimumLineSpacing = 0
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 300, height: 600), collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        let source = NXFeedAppendTestSource()
        source.count = 15
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "post")
        collection.dataSource = source
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = collection.bounds
        window.addSubview(collection)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        collection.reloadData()
        collection.layoutIfNeeded()
        collection.contentOffset.y = 650
        collection.layoutIfNeeded()
        let ids = (0..<15).map { "post-\($0)" }
        let stabilizer = NXFeedLayoutStabilizer()
        stabilizer.attach(to: collection)
        stabilizer.updateItemIDs(ids)
        XCTAssertEqual(stabilizer.liveVisiblePostID(), "post-3")
        stabilizer.performAnchored(reason: NXFeedViewport.bannerUpdateCoverReason) {
            stabilizer.updateItemIDs(ids, leadingNonPostRowCount: 1)
        }
        // SwiftUI has not inserted the banner cell yet. The old layout must
        // not be used with the new leading-row mapping or finish the settle.
        try? await Task.sleep(nanoseconds: 160_000_000)
        XCTAssertTrue(stabilizer.hasActivePrependCover)
        XCTAssertEqual(collection.contentOffset.y, 650, accuracy: 0.5)
        source.count += 1
        collection.reloadData()
        collection.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(stabilizer.liveVisiblePostID(), "post-3")
        XCTAssertEqual(collection.contentOffset.y, 850, accuracy: 0.5)
        stabilizer.performAnchored(reason: NXFeedViewport.bannerUpdateCoverReason) {
            stabilizer.updateItemIDs(ids, leadingNonPostRowCount: 0)
        }
        try? await Task.sleep(nanoseconds: 160_000_000)
        XCTAssertTrue(stabilizer.hasActivePrependCover)
        XCTAssertEqual(collection.contentOffset.y, 850, accuracy: 0.5)
        source.count -= 1
        collection.reloadData()
        collection.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(stabilizer.liveVisiblePostID(), "post-3")
        XCTAssertEqual(collection.contentOffset.y, 650, accuracy: 0.5)
        stabilizer.suspendPositionTracking()
    }

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

    func testMidFeedSeenReconciliationKeepsUnreadOnRowsThatStay() {
        // The Following trace skipped aba490e2 because it was app-wide seen
        // while structural cleanup left the row on screen.
        let kept = NXUnreadSeenReconciliation.unreadBookkeeping(
            markedReadIDs: ["aba490e2"],
            unreadCountUpdates: ["thread": 0],
            allowsRowMutation: false
        )
        XCTAssertTrue(kept.markedReadIDs.isEmpty)
        XCTAssertTrue(kept.unreadCountUpdates.isEmpty)

        let applied = NXUnreadSeenReconciliation.unreadBookkeeping(
            markedReadIDs: ["aba490e2"],
            unreadCountUpdates: ["thread": 2],
            allowsRowMutation: true
        )
        XCTAssertEqual(applied.markedReadIDs, ["aba490e2"])
        XCTAssertEqual(applied.unreadCountUpdates, ["thread": 2])

        // Cross-column seen state must not remove below-viewport rows or consume
        // their unread counts merely because the scrolling cooldown expired.
        let deferred = NXUnreadSeenReconciliation.unreadBookkeeping(
            markedReadIDs: ["above", "visible", "below"],
            unreadCountUpdates: ["thread": 0],
            allowsRowMutation: NXFeedStructuralUpdate.shouldMutateRows(isVisuallyAtTop: false)
        )
        XCTAssertTrue(deferred.markedReadIDs.isEmpty)
        XCTAssertTrue(deferred.unreadCountUpdates.isEmpty)
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
        XCTAssertTrue(
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
            XCTAssertFalse(NXFeedViewport.shouldPinTailAppend(
                updateReasons: reasons,
                oldIDs: ["old-first", "visible"],
                newIDs: ["revealed", "old-first", "visible", "older"],
                anchorID: "old-first"
            ))
        }
        XCTAssertTrue(NXFeedViewport.shouldPinTailAppend(
            updateReasons: ["older posts append"],
            oldIDs: ["newer", "visible", "tail"],
            newIDs: ["newer", "visible", "tail", "older-1", "older-2"],
            anchorID: "visible"
        ))
        XCTAssertFalse(NXFeedViewport.shouldPinTailAppend(
            updateReasons: ["older posts append"],
            oldIDs: ["newer", "tail"],
            newIDs: ["newer", "visible", "tail", "older"],
            anchorID: "visible"
        ))
        XCTAssertTrue(NXFeedViewport.shouldSettleAnchoredUpdate(
            updateReasons: ["older posts append", NXFeedViewport.unreadRemovalCoverReason],
            pinByIdentity: false,
            anchorIndexShifted: true
        ))
    }

    func testPrependSettleDoesNotFlingPastTheHeightActuallyAdded() {
        // The nos.lol trace scrolled from 2269 to 3933 while the list had not
        // grown, then a collapsed height of 1872 looked like the end of the feed.
        XCTAssertFalse(
            NXFeedViewport.shouldApplyPrependOffset(
                offsetAtStart: 782,
                currentOffset: 2269,
                correction: 1664,
                contentHeight: 4715,
                contentHeightAtStart: 4715
            )
        )
        XCTAssertTrue(
            NXFeedViewport.shouldApplyPrependOffset(
                offsetAtStart: 782,
                currentOffset: 3933,
                correction: -2882,
                contentHeight: 1872,
                contentHeightAtStart: 4715
            )
        )
        // Three new posts grew the list by 1181 and the anchor moved by the same amount.
        XCTAssertTrue(
            NXFeedViewport.shouldApplyPrependOffset(
                offsetAtStart: 1045.3,
                currentOffset: 1045.3,
                correction: 1181.3,
                contentHeight: 6528,
                contentHeightAtStart: 5347
            )
        )
        // UIKit already flung during the first yield. Step back to the start
        // plus slack while the list has not grown. A recovery and a matched
        // pin are not clamped.
        XCTAssertEqual(
            NXFeedViewport.prependOffsetClamp(
                offsetAtStart: 782,
                currentOffset: 2269,
                correction: 1664,
                contentHeight: 4715,
                contentHeightAtStart: 4715
            ),
            CGFloat?(862)
        )
        XCTAssertNil(
            NXFeedViewport.prependOffsetClamp(
                offsetAtStart: 782,
                currentOffset: 3933,
                correction: -2882,
                contentHeight: 1872,
                contentHeightAtStart: 4715
            )
        )
        XCTAssertNil(
            NXFeedViewport.prependOffsetClamp(
                offsetAtStart: 1045.3,
                currentOffset: 1045.3,
                correction: 1181.3,
                contentHeight: 6528,
                contentHeightAtStart: 5347
            )
        )
        // At the top the list shrank (6688→6090) while two new posts needed a
        // pin larger than the 80pt slack. That pin stays near the start.
        XCTAssertTrue(
            NXFeedViewport.shouldApplyPrependOffset(
                offsetAtStart: -118,
                currentOffset: -118,
                correction: 420,
                contentHeight: 6090,
                contentHeightAtStart: 6688,
                viewportHeight: 956
            )
        )
        XCTAssertNil(
            NXFeedViewport.prependOffsetClamp(
                offsetAtStart: -118,
                currentOffset: -118,
                correction: 420,
                contentHeight: 6090,
                contentHeightAtStart: 6688,
                viewportHeight: 956
            )
        )
        // Following trace: one new post moved the reading row by 2051 while the
        // estimated list was already taller than the real one. The pin lands
        // past the slack limit. The next sample is on that row and must stay
        // there. Pulling back to start+80 makes the following sample reapply
        // the same pin, 503↔2474, for the whole extended settle.
        XCTAssertTrue(
            NXFeedViewport.shouldApplyPrependOffset(
                offsetAtStart: 423.5,
                currentOffset: 423.5,
                correction: 2051,
                contentHeight: 10506,
                contentHeightAtStart: 10506,
                viewportHeight: 1280
            )
        )
        XCTAssertNil(
            NXFeedViewport.prependOffsetClamp(
                offsetAtStart: 423.5,
                currentOffset: 2474.5,
                correction: 0,
                contentHeight: 10506,
                contentHeightAtStart: 10506,
                viewportHeight: 1280
            )
        )
        XCTAssertTrue(
            NXFeedViewport.shouldApplyPrependOffset(
                offsetAtStart: 423.5,
                currentOffset: 2474.5,
                correction: 12,
                contentHeight: 5870,
                contentHeightAtStart: 10506,
                viewportHeight: 1280
            )
        )
        XCTAssertNil(
            NXFeedViewport.prependOffsetClamp(
                offsetAtStart: 423.5,
                currentOffset: 2474.5,
                correction: 12,
                contentHeight: 5870,
                contentHeightAtStart: 10506,
                viewportHeight: 1280
            )
        )
        // Already on the pin, another full screen of travel is a stale frame.
        XCTAssertFalse(
            NXFeedViewport.shouldApplyPrependOffset(
                offsetAtStart: 423.5,
                currentOffset: 2474.5,
                correction: 1971,
                contentHeight: 10506,
                contentHeightAtStart: 10506,
                viewportHeight: 1280
            )
        )
        XCTAssertEqual(
            NXFeedViewport.prependOffsetClamp(
                offsetAtStart: 423.5,
                currentOffset: 2474.5,
                correction: 1971,
                contentHeight: 10506,
                contentHeightAtStart: 10506,
                viewportHeight: 1280
            ),
            CGFloat?(503.5)
        )
    }

    func testPrependSettleWaitsUntilTheNewCellsExist() {
        XCTAssertNil(NXFeedViewport.prependMinimumCellCount(cellsBefore: 21, insertedCount: 0))
        XCTAssertNil(NXFeedViewport.prependMinimumCellCount(cellsBefore: 0, insertedCount: 1))
        XCTAssertEqual(NXFeedViewport.prependMinimumCellCount(cellsBefore: 21, insertedCount: 1), 22)
        // At-top truncation dropped 43 posts while inserting 1. Waiting for
        // the old cell total (64) never returns, so the pin never runs.
        XCTAssertEqual(
            NXFeedViewport.prependMinimumCellCount(cellsBefore: 63, insertedCount: 1, removedCount: 43),
            21
        )
        // Following trace: 91 posts, the collection view already had 93 cells,
        // 6 posts were added, and it settled at 98. Waiting for 99 never
        // restored the anchor, and the cover lifted on the jumped offset.
        XCTAssertEqual(
            NXFeedViewport.prependMinimumCellCount(
                cellsBefore: 93,
                insertedCount: 6,
                itemCount: 97
            ),
            97
        )

        // Right after an unread landing the old list is already aligned. Finishing
        // there lifts the cover before the new row exists, and it pushes the feed down.
        XCTAssertFalse(
            NXFeedViewport.shouldFinishAnchoredSettle(
                stableSamples: 3,
                step: 7,
                extended: true,
                renderedCellCount: 21,
                prependMinimumCellCount: 22
            )
        )
        XCTAssertTrue(
            NXFeedViewport.shouldFinishAnchoredSettle(
                stableSamples: 3,
                step: 7,
                extended: true,
                renderedCellCount: 22,
                prependMinimumCellCount: 22
            )
        )
        // Estimated heights still need the extended settle's minimum frames.
        XCTAssertFalse(
            NXFeedViewport.shouldFinishAnchoredSettle(
                stableSamples: 3,
                step: 6,
                extended: true,
                renderedCellCount: 22,
                prependMinimumCellCount: 22
            )
        )
        XCTAssertTrue(
            NXFeedViewport.shouldFinishAnchoredSettle(
                stableSamples: 3,
                step: 2,
                extended: false,
                renderedCellCount: 21,
                prependMinimumCellCount: nil
            )
        )
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
    func testOlderAppendWaitsForRowsAndPreservesOffsetThroughHeightCollapse() async throws {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 300, height: 500)
        layout.minimumLineSpacing = 0
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 700), collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        let source = NXFeedAppendTestSource()
        source.count = 20
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "post")
        collection.dataSource = source
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = collection.bounds
        window.addSubview(collection)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        collection.reloadData()
        collection.layoutIfNeeded()
        collection.contentOffset.y = 4350
        collection.layoutIfNeeded()
        // snapshotView(afterScreenUpdates: false) needs a painted viewport.
        try? await Task.sleep(nanoseconds: 50_000_000)
        let ids = (0..<34).map { "post-\($0)" }
        let stabilizer = NXFeedLayoutStabilizer()
        stabilizer.attach(to: collection)
        stabilizer.updateItemIDs(Array(ids.prefix(20)))
        let host = NXFeedSnapshotHostView(frame: collection.convert(collection.bounds, to: window))
        host.stabilizer = stabilizer
        window.addSubview(host)
        XCTAssertEqual(stabilizer.liveVisiblePostID(), "post-8")
        stabilizer.performAnchored(reason: "older posts append") {
            stabilizer.updateItemIDs(ids)
        }
        // The old short settle ended before this delayed List commit.
        try? await Task.sleep(nanoseconds: 180_000_000)
        XCTAssertTrue(stabilizer.hasActivePrependCover)
        XCTAssertFalse(host.subviews.isEmpty)
        XCTAssertEqual(collection.contentOffset.y, 4350, accuracy: 0.5)
        source.count = 34
        layout.itemSize.height = 150
        collection.reloadData()
        collection.layoutIfNeeded()
        collection.contentOffset.y = 2625
        try? await Task.sleep(nanoseconds: 32_000_000)
        // Real self-sized heights arrive after the appended cells.
        layout.itemSize.height = 500
        layout.invalidateLayout()
        collection.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(stabilizer.liveVisiblePostID(), "post-8")
        XCTAssertEqual(collection.contentOffset.y, 4350, accuracy: 0.5)
        XCTAssertFalse(stabilizer.hasActivePrependCover)
        XCTAssertTrue(host.subviews.isEmpty)
        stabilizer.suspendPositionTracking()
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

    func testUnreadCorrectionRejectsNonFiniteEstimatedGeometry() {
        XCTAssertTrue(NXUnreadNavigation.shouldCoverPostAnimationCorrection(misalignment: .nan))
        XCTAssertTrue(NXUnreadNavigation.shouldCoverPostAnimationCorrection(misalignment: .infinity))
        XCTAssertFalse(NXFeedViewport.isUsableRowFrame(CGRect(x: 0, y: CGFloat.nan, width: 406, height: 200)))
        XCTAssertFalse(NXFeedViewport.isUsableRowFrame(.null))
        XCTAssertFalse(NXFeedViewport.isUsableRowFrame(.zero))
        XCTAssertTrue(NXFeedViewport.isUsableRowFrame(CGRect(x: 0, y: 97, width: 406, height: 200)))
    }

    @MainActor
    func testUnreadLandingRequiresRealTargetFrameAndRefreshedBannerLookup() {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 300, height: 200)
        layout.minimumLineSpacing = 0
        let collection = NXFeedMissingGeometryCollection(frame: CGRect(x: 0, y: 0, width: 320, height: 600), collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        collection.contentInset.top = 97
        let source = NXFeedAppendTestSource()
        source.count = 16 // banner + 15 posts
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "post")
        collection.dataSource = source
        let window = UIWindow(frame: collection.bounds)
        window.addSubview(collection)
        collection.reloadData()
        collection.layoutIfNeeded()
        collection.contentOffset.y = 4 * 200 - 97
        collection.layoutIfNeeded()
        let ids = (0..<15).map { "post-\($0)" }
        let stabilizer = NXFeedLayoutStabilizer()
        stabilizer.attach(to: collection)
        // Reproduce the report's 12-ID lookup against a 15-post snapshot and banner.
        stabilizer.updateItemIDs(Array(ids.dropFirst(3)), leadingNonPostRowCount: 1)
        XCTAssertFalse(stabilizer.isItemAtVisibleTop(id: "post-3"))
        stabilizer.updateItemIDs(ids, leadingNonPostRowCount: 1)
        XCTAssertTrue(stabilizer.isItemAtVisibleTop(id: "post-3"))
        collection.invalidItem = 4
        XCTAssertFalse(stabilizer.isItemAtVisibleTop(id: "post-3"))
        stabilizer.pinItemToVisibleTop(id: "post-3")
        XCTAssertTrue(collection.contentOffset.y.isFinite)
        collection.invalidItem = nil
        XCTAssertTrue(stabilizer.isItemAtVisibleTop(id: "post-3"))
        stabilizer.suspendPositionTracking()
    }

    func testRetainedPrependRecoveryRequiresMatchingRowsAndStaysClearOfTail() {
        XCTAssertTrue(NXFeedViewport.isPrependKeepingRows(
            oldIDs: ["reading", "older"], newIDs: ["new", "reading", "older"], anchorID: "reading"
        ))
        XCTAssertFalse(NXFeedViewport.isPrependKeepingRows(
            oldIDs: ["reading", "older"], newIDs: ["new", "reading", "replacement"], anchorID: "reading"
        ))
        XCTAssertFalse(NXFeedViewport.isPrependKeepingRows(
            oldIDs: ["reading", "older"], newIDs: ["new", "reading", "older"], anchorID: "older"
        ))
        XCTAssertFalse(NXFeedViewport.shouldApplyPrependOffset(
            offsetAtStart: -118, currentOffset: 4422.7, correction: 1606.7,
            contentHeight: 10006, contentHeightAtStart: 4507, viewportHeight: 956
        ))
        XCTAssertTrue(NXFeedViewport.shouldApplyPrependOffset(
            offsetAtStart: -118, currentOffset: 4422.7, correction: 1606.7,
            contentHeight: 10006, contentHeightAtStart: 4507, viewportHeight: 956,
            hasStableRetainedPrependGeometry: true
        ))
        XCTAssertFalse(NXFeedViewport.shouldApplyPrependOffset(
            offsetAtStart: -118, currentOffset: 4422.7, correction: 5000,
            contentHeight: 10006, contentHeightAtStart: 4507, viewportHeight: 956,
            hasStableRetainedPrependGeometry: true
        ))
    }

    @MainActor
    func testMorningCatchUpKeepsFirstOldPostAfterLargePrependResizes() async throws {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 0
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 460, height: 956), collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        collection.contentInset = UIEdgeInsets(top: 118, left: 0, bottom: 83, right: 0)
        let source = NXFeedAppendTestSource()
        source.count = 28
        source.rowHeights = Array(repeating: 161, count: 28)
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "post")
        collection.dataSource = source
        collection.delegate = source
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = collection.bounds
        window.addSubview(collection)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        collection.reloadData()
        collection.layoutIfNeeded()
        collection.contentOffset.y = -118
        collection.layoutIfNeeded()
        let oldIDs = (0..<28).map { "old-\($0)" }
        let stabilizer = NXFeedLayoutStabilizer()
        stabilizer.attach(to: collection)
        stabilizer.updateItemIDs(oldIDs)
        XCTAssertEqual(stabilizer.liveVisiblePostID(), "old-0")
        stabilizer.performAnchored(reason: NXFeedViewport.prependCoverReason) {
            source.count = 72
            source.rowHeights = Array(repeating: CGFloat(4540.6666667 / 44), count: 44)
                + Array(repeating: 161, count: 28)
            collection.reloadData()
            collection.layoutIfNeeded()
            stabilizer.updateItemIDs((0..<44).map { "new-\($0)" } + oldIDs)
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(collection.contentOffset.y, 4422.6666667, accuracy: 1)
        source.rowHeights = Array(repeating: CGFloat(6147.3333333 / 44), count: 44)
            + Array(repeating: CGFloat(3858.6666667 / 28), count: 28)
        layout.invalidateLayout()
        collection.layoutIfNeeded()
        collection.contentOffset.y = 4422.6666667
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(collection.contentOffset.y, 6029.3333333, accuracy: 1)
        XCTAssertEqual(stabilizer.liveVisiblePostID(), "old-0")
        XCTAssertFalse(stabilizer.hasActivePrependCover)
        stabilizer.suspendPositionTracking()
    }

    @MainActor
    func testTailTrimmingPrependFinishesPinAfterInsertedRowsGrow() async throws {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 0
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 1282), collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        collection.contentInset.top = 97
        let source = NXFeedAppendTestSource()
        source.count = 36
        source.rowHeights = Array(repeating: 210, count: 36)
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "post")
        collection.dataSource = source
        collection.delegate = source
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = collection.bounds
        window.addSubview(collection)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        collection.reloadData()
        collection.layoutIfNeeded()
        collection.contentOffset.y = -97
        collection.layoutIfNeeded()
        let oldIDs = (0..<36).map { "old-\($0)" }
        let newIDs = (0..<8).map { "new-\($0)" } + Array(oldIDs.prefix(12))
        let stabilizer = NXFeedLayoutStabilizer()
        stabilizer.attach(to: collection)
        stabilizer.updateItemIDs(oldIDs)
        XCTAssertEqual(stabilizer.liveVisiblePostID(), oldIDs.first)

        stabilizer.performAnchored(reason: NXFeedViewport.prependCoverReason) {
            source.count = 20
            source.rowHeights = Array(repeating: 215, count: 8) + Array(repeating: 165, count: 12)
            collection.reloadData()
            collection.layoutIfNeeded()
            stabilizer.updateItemIDs(newIDs)
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(collection.contentOffset.y, 1623, accuracy: 0.5)

        // The eight inserted rows grow by 920 points after the first pin.
        // The trimmed snapshot is still shorter than before the prepend.
        source.rowHeights = Array(repeating: 330, count: 8) + Array(repeating: 142, count: 12)
        layout.invalidateLayout()
        collection.layoutIfNeeded()
        collection.contentOffset.y = 1623
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(collection.contentOffset.y, 2543, accuracy: 0.5)
        XCTAssertEqual(stabilizer.liveVisiblePostID(), oldIDs.first)
        XCTAssertFalse(stabilizer.hasActivePrependCover)
        stabilizer.suspendPositionTracking()
    }

    @MainActor
    func testPrependPreservesLiveAnchorAcrossCollapsedHeightEstimates() async throws {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 300, height: 338)
        layout.minimumLineSpacing = 0
        let collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 1282), collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        collection.contentInset.top = 97
        let source = NXFeedAppendTestSource()
        source.count = 37
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "post")
        collection.dataSource = source
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = collection.bounds
        window.addSubview(collection)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        collection.reloadData()
        collection.layoutIfNeeded()
        collection.contentOffset.y = 7 * 338 - 97
        collection.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: 50_000_000)
        let oldIDs = (0..<37).map { "post-\($0)" }
        let stabilizer = NXFeedLayoutStabilizer()
        stabilizer.attach(to: collection)
        stabilizer.updateItemIDs(oldIDs)
        // The live row must win over an older remembered unread landing.
        let unreadControl = UIView(frame: CGRect(x: 240, y: 130, width: 61, height: 36))
        window.addSubview(unreadControl)
        // A scroll view's bounds origin is its content offset. The overlay is
        // a window sibling, so it needs the viewport rect in window coordinates.
        let snapshotHost = NXFeedSnapshotHostView(frame: collection.convert(collection.bounds, to: window))
        snapshotHost.stabilizer = stabilizer
        window.insertSubview(snapshotHost, belowSubview: unreadControl)
        // Native navigation chrome and a dragged unread control stay above
        // the frozen feed, with no uncovered holes in their glass backdrops.
        unreadControl.frame.origin = CGPoint(x: 170, y: 500)
        stabilizer.rememberAnchor(id: "post-6")
        XCTAssertEqual(stabilizer.liveVisiblePostID(), "post-7")
        stabilizer.performAnchored(reason: NXFeedViewport.prependCoverReason) {
            source.count = 38
            layout.itemSize.height = 75
            collection.reloadData()
            collection.layoutIfNeeded()
            collection.contentOffset.y = 183.5
            stabilizer.updateItemIDs(["new"] + oldIDs)
        }
        XCTAssertTrue(stabilizer.hasActivePrependCover)
        let cover = try XCTUnwrap(snapshotHost.subviews.first)
        XCTAssertEqual(cover.frame, snapshotHost.bounds)
        XCTAssertNil(cover.layer.mask)
        XCTAssertEqual(window.subviews.last, unreadControl)
        // Simulate the overlay being recreated while the List is settling.
        let replacementHost = NXFeedSnapshotHostView(frame: snapshotHost.frame)
        replacementHost.stabilizer = stabilizer
        window.insertSubview(replacementHost, belowSubview: unreadControl)
        snapshotHost.removeFromSuperview()
        XCTAssertTrue(cover.superview === replacementHost)
        XCTAssertEqual(cover.frame, replacementHost.bounds)
        XCTAssertEqual(window.subviews.last, unreadControl)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(collection.contentOffset.y, 8 * 75 - 97, accuracy: 0.5)
        // The real heights resolve while the covered correction is still active.
        layout.itemSize.height = 338
        layout.invalidateLayout()
        collection.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(collection.contentOffset.y, 8 * 338 - 97, accuracy: 0.5)
        XCTAssertEqual(stabilizer.liveVisiblePostID(), "post-7")
        XCTAssertFalse(stabilizer.hasActivePrependCover)
        stabilizer.suspendPositionTracking()
    }

    func testHeldPostsMergeAheadOfIncomingWithoutDuplicatingTheScreen() {
        XCTAssertEqual(
            NXIncomingFeedPosts.mergedIDs(
                held: ["new-2", "new-1"],
                incoming: ["new-1", "new-0"],
                onScreen: ["visible"]
            ),
            ["new-2", "new-1", "new-0"]
        )
        XCTAssertEqual(
            NXIncomingFeedPosts.mergedIDs(
                held: ["visible"],
                incoming: ["fresh"],
                onScreen: ["visible"]
            ),
            ["fresh"]
        )
    }

    func testScrollingToTopClearsAStaleUnreadHold() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        XCTAssertTrue(
            NXUnreadAtTop.shouldClearAllUnread(
                isAtTop: true,
                isPreparingRestore: false,
                holdUnreadAboveReadingPost: true,
                holdStartedAt: now.addingTimeInterval(-30),
                now: now
            )
        )
        XCTAssertTrue(
            NXUnreadAtTop.shouldClearAllUnread(
                isAtTop: true,
                isPreparingRestore: false,
                holdUnreadAboveReadingPost: false,
                holdStartedAt: nil,
                now: now
            )
        )
        XCTAssertTrue(
            NXUnreadAtTop.shouldClearAllUnread(
                isAtTop: true,
                isPreparingRestore: false,
                holdUnreadAboveReadingPost: true,
                holdStartedAt: nil,
                now: now
            )
        )
    }

    func testFreshHoldAtTopDoesNotClearUnreadBeforeThePinLands() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        XCTAssertFalse(
            NXUnreadAtTop.shouldClearAllUnread(
                isAtTop: true,
                isPreparingRestore: false,
                holdUnreadAboveReadingPost: true,
                holdStartedAt: now.addingTimeInterval(-0.1),
                now: now
            )
        )
        XCTAssertFalse(
            NXUnreadAtTop.shouldClearAllUnread(
                isAtTop: true,
                isPreparingRestore: true,
                holdUnreadAboveReadingPost: true,
                holdStartedAt: now.addingTimeInterval(-30),
                now: now
            )
        )
        XCTAssertFalse(
            NXUnreadAtTop.shouldClearAllUnread(
                isAtTop: false,
                isPreparingRestore: false,
                holdUnreadAboveReadingPost: true,
                holdStartedAt: now.addingTimeInterval(-30),
                now: now
            )
        )
    }

    func testReachingTheTopKeepsHeldPostsUnread() {
        let remaining = NXIncomingFeedPosts.unreadIDsAfterReachingTop(
            unreadIDs: ["held-1": 1, "held-2": 2, "already-on-screen": 1, "read": 0],
            preservedIDs: ["held-1", "held-2"]
        )
        XCTAssertEqual(remaining, ["held-1": 1, "held-2": 2])
        XCTAssertEqual(
            NXIncomingFeedPosts.unreadIDsAfterReachingTop(
                unreadIDs: ["old": 1],
                preservedIDs: []
            ),
            [:]
        )
    }

    func testDetailReturnDoesNotReplayAnOffsetPastTheRow() {
        // Explore trace: the saved row was 1404pt above the viewport. After a
        // hidden parent trim that row can be shorter. Replaying -1404 scrolls
        // onto the next post.
        XCTAssertEqual(
            NXFeedViewport.visibleTopOffsetInsideRow(saved: -1404, rowHeight: 2200),
            -1404
        )
        XCTAssertEqual(
            NXFeedViewport.visibleTopOffsetInsideRow(saved: -1404, rowHeight: 400),
            -399
        )
        XCTAssertEqual(
            NXFeedViewport.visibleTopOffsetInsideRow(saved: -43.5, rowHeight: 180),
            -43.5
        )
        XCTAssertEqual(
            NXFeedViewport.visibleTopOffsetInsideRow(saved: 12, rowHeight: 180),
            12
        )
        XCTAssertFalse(
            NXFeedViewport.shouldTreatOffsetAsUserAtTop(
                hasWindow: false,
                contentOffsetY: 0,
                insetTop: 0,
                isPreparingRestore: false
            )
        )
        XCTAssertTrue(
            NXFeedViewport.shouldTreatOffsetAsUserAtTop(
                hasWindow: true,
                contentOffsetY: -97,
                insetTop: 97,
                isPreparingRestore: false
            )
        )
    }

    func testReadRowRemovalWaitsUntilTheFeedIsAtTop() {
        XCTAssertFalse(NXFeedStructuralUpdate.shouldMutateRows(isVisuallyAtTop: false))
        XCTAssertTrue(NXFeedStructuralUpdate.shouldMutateRows(isVisuallyAtTop: true))
    }
}

@MainActor
private final class NXFeedAppendTestSource: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var count = 4
    var sections: [Int]?
    var rowHeights: [CGFloat] = []

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        CGSize(width: 300, height: rowHeights[indexPath.item])
    }


    func numberOfSections(in collectionView: UICollectionView) -> Int { sections?.count ?? 1 }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { sections?[section] ?? count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        collectionView.dequeueReusableCell(withReuseIdentifier: "post", for: indexPath)
    }
}

@MainActor
private final class NXFeedMissingGeometryCollection: UICollectionView {
    var invalidItem: Int?

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.item != invalidItem else { return nil }
        return super.layoutAttributesForItem(at: indexPath)
    }
}

/// Hold UIKit's animation open so tests can check the pending and cancelled
/// states without relying on display-frame timing.
@MainActor
private final class NXFeedAnimatedTopTestScrollView: UIScrollView {
    private(set) var lastAnimatedTarget: CGPoint?
    private(set) var animationRequestCount = 0

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        if animated {
            lastAnimatedTarget = contentOffset
            animationRequestCount += 1
        }
        else { super.setContentOffset(contentOffset, animated: false) }
    }

    func completeNativeAnimation() {
        if let target = lastAnimatedTarget { super.setContentOffset(target, animated: false) }
    }
}


@MainActor
private final class NXFeedUnreadLayoutTestCollection: UICollectionView {
    var userIsDragging = false
    override var isDragging: Bool { userIsDragging || super.isDragging }
}
