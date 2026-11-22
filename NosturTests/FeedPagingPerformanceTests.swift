import Combine
import SwiftUI
import UIKit
import XCTest
@testable import Nostur

@MainActor
final class FeedPagingPerformanceTests: XCTestCase {
    func testUnchangedTranslationDoesNotPublishPagingWork() {
        let motion = FeedSwipeMotion()
        var updates = 0
        let subscription = motion.$translation.dropFirst().sink { _ in updates += 1 }
        motion.updateTranslation(0)
        XCTAssertEqual(updates, 0)
        motion.updateTranslation(-25)
        motion.updateTranslation(-25)
        XCTAssertEqual(updates, 1)
        motion.updateTranslation(0)
        motion.updateTranslation(0)
        XCTAssertEqual(updates, 2)
        withExtendedLifetime(subscription) { }
    }

    func testFailedPanDoesNotInvokePagingCallbacks() {
        let coordinator = FeedPanAttachment.Coordinator()
        var changes = 0
        var endings = 0
        coordinator.onChanged = { _ in changes += 1 }
        coordinator.onEnded = { _, _, _, _ in endings += 1 }
        coordinator.handlePan(FailedFeedPan())
        XCTAssertEqual(changes, 0)
        XCTAssertEqual(endings, 0)
    }

    func testDraggingDoesNotRebuildFeedContainerOrPostContent() async throws {
        let motion = FeedSwipeMotion()
        let recorder = FeedPagingRenderRecorder()
        let window = try host(motion: motion, recorder: recorder, loading: false)
        defer { window.isHidden = true }
        try await settle(window)
        let parentBodies = recorder.parentBodies
        let postBodies = recorder.postBodies
        XCTAssertEqual(postBodies.count, 20)
        for sample in 1...120 {
            motion.updateTranslation(-CGFloat(sample))
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        motion.updateTranslation(0)
        try await settle(window)
        XCTAssertEqual(recorder.parentBodies, parentBodies, "Drag samples must stay outside feed-screen state")
        XCTAssertEqual(recorder.postBodies, postBodies, "Only page offsets may update during a drag")
    }

    func testOnlyCurrentAndAdjacentLoadingPreviewsAreBuilt() async throws {
        let motion = FeedSwipeMotion()
        let recorder = FeedPagingRenderRecorder()
        let window = try host(motion: motion, recorder: recorder, loading: true)
        defer { window.isHidden = true }
        try await settle(window)
        XCTAssertEqual(Set(recorder.titleBodies.keys), Set([-1, 0, 1]))
        let initialBodies = recorder.titleBodies
        for sample in 1...60 {
            motion.updateTranslation(-CGFloat(sample))
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        motion.updateTranslation(0)
        try await settle(window)
        XCTAssertEqual(recorder.titleBodies, initialBodies, "Paging must not rebuild the loading rows")
    }

    private func host(motion: FeedSwipeMotion, recorder: FeedPagingRenderRecorder, loading: Bool) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = .init(x: 0, y: 0, width: 390, height: 700)
        window.rootViewController = UIHostingController(rootView:
            FeedPagingPerformanceHost(motion: motion, recorder: recorder, loading: loading))
        window.makeKeyAndVisible()
        return window
    }

    private func settle(_ window: UIWindow) async throws {
        window.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        window.layoutIfNeeded()
    }
}

private final class FailedFeedPan: UIPanGestureRecognizer {
    override var state: UIGestureRecognizer.State {
        get { .failed }
        set { }
    }
}

@MainActor
private final class FeedPagingRenderRecorder {
    var parentBodies = 0
    var postBodies: [Int: Int] = [:]
    var titleBodies: [Int: Int] = [:]
}

private struct FeedPagingPerformanceHost: View {
    let motion: FeedSwipeMotion
    let recorder: FeedPagingRenderRecorder
    let loading: Bool

    var body: some View {
        let _ = recorder.parentBodies += 1
        ZStack {
            ForEach(-10..<10, id: \.self) { page in
                Group {
                    if loading {
                        FeedLoadingPreview {
                            FeedPagingCountedTitle(page: page, recorder: recorder)
                        }
                    } else {
                        FeedPagingCountedPost(page: page, recorder: recorder)
                    }
                }
                .modifier(FeedPagePosition(relativeIndex: page, motion: motion))
            }
        }
        .modifier(FeedSwipeModifier(motion: motion, isEnabled: true,
                                    canSwipeBackward: true, canSwipeForward: true, onSwipe: { _ in }))
    }
}

private struct FeedPagingCountedTitle: View {
    let page: Int
    let recorder: FeedPagingRenderRecorder

    var body: some View {
        let _ = recorder.titleBodies[page, default: 0] += 1
        Text(verbatim: "Feed \(page)")
    }
}

private struct FeedPagingCountedPost: View {
    let page: Int
    let recorder: FeedPagingRenderRecorder

    var body: some View {
        let _ = recorder.postBodies[page, default: 0] += 1
        VStack(alignment: .leading) {
            Text(verbatim: "Author")
            Text(verbatim: "Existing feed content \(page)")
        }
    }
}
