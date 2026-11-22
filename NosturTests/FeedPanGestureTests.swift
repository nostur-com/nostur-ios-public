import SwiftUI
import UIKit
import XCTest
@testable import Nostur

@MainActor
final class FeedPanGestureTests: XCTestCase {
    func testHorizontalPanRejectsVerticalScrolling() {
        XCTAssertTrue(FeedPanGesturePolicy.isHorizontal(.init(x: -400, y: 40)))
        XCTAssertTrue(FeedPanGesturePolicy.isHorizontal(.init(x: 400, y: -40)))
        XCTAssertFalse(FeedPanGesturePolicy.isHorizontal(.init(x: 40, y: 400)))
        XCTAssertFalse(FeedPanGesturePolicy.isHorizontal(.init(x: 80, y: 80)))
        XCTAssertFalse(FeedPanGesturePolicy.isHorizontal(.zero))
    }

    func testCompletedDragAndFlickChooseOneAdjacentPage() {
        XCTAssertEqual(FeedPanGesturePolicy.destination(translation: -120, velocity: 0, width: 390, cancelled: false), 1)
        XCTAssertEqual(FeedPanGesturePolicy.destination(translation: 120, velocity: 0, width: 390, cancelled: false), -1)
        XCTAssertEqual(FeedPanGesturePolicy.destination(translation: -30, velocity: -900, width: 390, cancelled: false), 1)
        XCTAssertNil(FeedPanGesturePolicy.destination(translation: -30, velocity: 900, width: 390, cancelled: false))
        XCTAssertNil(FeedPanGesturePolicy.destination(translation: -30, velocity: 0, width: 390, cancelled: false))
        XCTAssertNil(FeedPanGesturePolicy.destination(translation: -120, velocity: -900, width: 390, cancelled: true))
    }

    func testPostTextAndButtonBackedRowsAcceptPagingButSelectionAndSlidersDoNot() {
        let row = UIControl(frame: .init(x: 0, y: 0, width: 390, height: 200))
        let text = UITextView(frame: row.bounds)
        text.isScrollEnabled = false
        text.text = "A post with selectable text"
        text.selectedRange = NSRange(location: 0, length: 0)
        row.addSubview(text)
        XCTAssertTrue(FeedPanGesturePolicy.allowsTouch(in: text, upTo: row))
        text.selectedRange = NSRange(location: 0, length: 6)
        XCTAssertFalse(FeedPanGesturePolicy.allowsTouch(in: text, upTo: row))
        XCTAssertFalse(FeedPanGesturePolicy.allowsTouch(in: UISlider(), upTo: nil))
    }

    func testNestedHorizontalMediaKeepsItsOwnGesture() {
        let scroll = UIScrollView(frame: .init(x: 0, y: 0, width: 390, height: 500))
        let child = UIView(frame: scroll.bounds)
        scroll.addSubview(child)
        scroll.contentSize = .init(width: 391, height: 2000)
        XCTAssertTrue(FeedPanGesturePolicy.allowsTouch(in: child, upTo: scroll))
        scroll.contentSize.width = 780
        XCTAssertFalse(FeedPanGesturePolicy.allowsTouch(in: child, upTo: scroll))
    }

    @available(iOS 18.0, *)
    func testSwiftUIAndTextViewRecognizersCanRecognizeAlongsideFeedPan() {
        let coordinator = FeedPanAttachment.Coordinator()
        let feedPan = UIPanGestureRecognizer()
        let textGesture = UIPanGestureRecognizer()
        let textHost = UIView()
        textHost.addGestureRecognizer(textGesture)
        XCTAssertTrue(coordinator.gestureRecognizer(feedPan, shouldRecognizeSimultaneouslyWith: textGesture))
    }

    @available(iOS 18.0, *)
    func testFeedPanIsAttachedAboveNativeTextInsideTheFeedList() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = .init(x: 0, y: 0, width: 390, height: 844)
        let host = UIHostingController(rootView: FeedPanTestHost())
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 150_000_000)
        host.view.layoutIfNeeded()

        let views = descendants(of: window)
        let text = try XCTUnwrap(views.compactMap { $0 as? UITextView }.first)
        let marker = try XCTUnwrap(views.compactMap { $0 as? FeedPanAttachment.MarkerView }.first)
        XCTAssertNotNil(marker.window)
        XCTAssertGreaterThan(marker.bounds.width, 300)
        let coordinator = try XCTUnwrap(marker.coordinator)
        var ancestor: UIView? = marker
        var chain: [String] = []
        while let view = ancestor {
            chain.append("\(type(of: view)) next=\(String(describing: view.next.map { type(of: $0) }))")
            ancestor = view.superview
        }
        let pans = views.flatMap { $0.gestureRecognizers ?? [] }.filter {
            $0 is UIPanGestureRecognizer && $0.delegate is FeedPanAttachment.Coordinator
        }
        let recognizerSummary = views.flatMap { view in
            (view.gestureRecognizers ?? []).map {
                "\(type(of: $0)) delegate=\(String(describing: $0.delegate)) host=\(type(of: view))"
            }
        }.joined(separator: "\n")
        XCTAssertEqual(pans.count, 1, "Use a single continuous pan for both swipe directions. idiom=\(UIDevice.current.userInterfaceIdiom.rawValue) pan=\(coordinator.pan) chain=\(chain)\n\(recognizerSummary)")
        let pan = try XCTUnwrap(pans.first)
        let gestureHost = try XCTUnwrap(pan.view)
        XCTAssertTrue(text.isDescendant(of: gestureHost), "Post text touches must reach the feed pan")
        XCTAssertTrue(pan.isEnabled)
        XCTAssertGreaterThan(gestureHost.bounds.width, 300)
    }

    private func descendants(of view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }
}

private struct FeedPanTestHost: View {
    @State private var motion = FeedSwipeMotion()

    var body: some View {
        List {
            FeedPanTestText().frame(height: 200)
        }
        .modifier(FeedSwipeModifier(motion: motion, isEnabled: true, canSwipe: { _ in true }, onSwipe: { _ in }))
    }
}

private struct FeedPanTestText: UIViewRepresentable {
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.text = "Selectable post text"
        view.isScrollEnabled = false
        view.isEditable = false
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) { }
}
