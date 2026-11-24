import SwiftUI
import UIKit
import XCTest
@testable import Nostur

@MainActor
final class FeedNativePagerTests: XCTestCase {
    func testSelectionWaitsForCompletedNativeScrolling() {
        let session = FeedNativePagingSession()
        session.begin(at: 3)
        XCTAssertEqual(session.origin, 3)
        // No selection callback is available during tracking or deceleration.
        XCTAssertEqual(session.finish(at: 4), 1)
        XCTAssertNil(session.origin)
        XCTAssertNil(session.finish(at: 4), "A second idle notification must not reload a feed")
        session.begin(at: 4)
        XCTAssertNil(session.finish(at: 4), "An incomplete swipe must not resume another feed")
        session.begin(at: 4)
        session.cancel()
        XCTAssertNil(session.finish(at: 5))
    }

    func testFlingTargetsStayWithinOneAdjacentFeedAndBounds() {
        XCTAssertEqual(FeedNativePagingSession.boundedTarget(start: 3, proposed: 9, pageCount: 10), 4)
        XCTAssertEqual(FeedNativePagingSession.boundedTarget(start: 3, proposed: 0, pageCount: 10), 2)
        XCTAssertEqual(FeedNativePagingSession.boundedTarget(start: 0, proposed: -2, pageCount: 10), 0)
        XCTAssertEqual(FeedNativePagingSession.boundedTarget(start: 9, proposed: 12, pageCount: 10), 9)
        XCTAssertEqual(FeedNativePagingSession.boundedTarget(start: 0, proposed: 3, pageCount: 1), 0)
    }

    @available(iOS 18.0, *)
    func testPagePositionsStayFixedWhenSelectionIsCommitted() async throws {
        let state = NativePagerTestState()
        let window = try host(state: state, pageCount: 3)
        defer { window.isHidden = true }
        try await settle(window)
        let pager = try horizontalPager(in: window)
        XCTAssertEqual(pager.contentOffset.x, pager.bounds.width * CGFloat(state.selected), accuracy: 1,
                       "Initial positioning must respect the saved selection")
        let markers = descendants(window).filter { $0.accessibilityIdentifier?.hasPrefix("native-page-") == true }
        XCTAssertEqual(markers.count, 3)
        let positions = markers.map { $0.convert(.zero, to: pager).x }
        pager.setContentOffset(.init(x: pager.bounds.width * 2, y: 0), animated: false)
        state.selected = 2
        try await settle(window)
        for (marker, x) in zip(markers, positions) {
            XCTAssertEqual(marker.convert(.zero, to: pager).x, x, accuracy: 1,
                           "Selection must not recenter or displace the mounted pages")
        }
        XCTAssertEqual(pager.contentOffset.x, pager.bounds.width * 2, accuracy: 1)
    }

    @available(iOS 18.0, *)
    func testSingleFeedKeepsItsVerticalListEnabled() async throws {
        let state = NativePagerTestState()
        state.selected = 0
        let window = try host(state: state, pageCount: 1)
        defer { window.isHidden = true }
        try await settle(window)
        let lists = descendants(window).compactMap { $0 as? UICollectionView }
        XCTAssertFalse(lists.isEmpty)
        XCTAssertTrue(lists.allSatisfy(\.isScrollEnabled), "Disabling horizontal paging must not disable the feed")
    }

    @available(iOS 18.0, *)
    private func host(state: NativePagerTestState, pageCount: Int) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = .init(x: 0, y: 0, width: 390, height: 700)
        window.rootViewController = UIHostingController(rootView: NativePagerTestHost(state: state, pageCount: pageCount))
        window.makeKeyAndVisible()
        return window
    }

    private func settle(_ window: UIWindow) async throws {
        window.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 150_000_000)
        window.layoutIfNeeded()
    }

    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }

    private func horizontalPager(in view: UIView) throws -> UIScrollView {
        try XCTUnwrap(descendants(view).compactMap { $0 as? UIScrollView }.first {
            $0.bounds.width > 0 && $0.contentSize.width > $0.bounds.width * 1.5
        })
    }
}

@MainActor
private final class NativePagerTestState: ObservableObject {
    @Published var selected = 1
}

@available(iOS 18.0, *)
private struct NativePagerTestHost: View {
    @ObservedObject var state: NativePagerTestState
    let pageCount: Int
    @State private var motion = FeedSwipeMotion()

    var body: some View {
        ZStack {
            ForEach(0..<pageCount, id: \.self) { page in
                List {
                    Text(verbatim: "Feed \(page)")
                }
                .background(NativePageMarker(page: page))
                .modifier(FeedPagePosition(relativeIndex: page - state.selected, motion: motion))
            }
        }
        .modifier(FeedSwipeModifier(motion: motion, isEnabled: true,
                                   canSwipeBackward: state.selected > 0,
                                   canSwipeForward: state.selected + 1 < pageCount,
                                   onSwipe: { state.selected += $0 }, pageCount: pageCount,
                                   selectedIndex: state.selected, selectionID: String(state.selected)))
    }
}

private struct NativePageMarker: UIViewRepresentable {
    let page: Int
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.accessibilityIdentifier = "native-page-\(page)"
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { }
}
