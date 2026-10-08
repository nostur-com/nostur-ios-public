import XCTest
import SwiftUI
@testable import Nostur

final class MediaFrameLayoutTests: XCTestCase {
    func testCrossingHeightLimitDoesNotCollapseToPlaceholderHeight() {
        let before = layout(aspect: 1000.0 / 2999.0)
        let after = layout(aspect: 433.0 / 1300.0)
        XCTAssertEqual(before.height, 1199.6, accuracy: 0.001)
        XCTAssertEqual(after.height, 1200)
        XCTAssertEqual(after.contentMode, .fill)
        XCTAssertLessThan(abs(before.height - after.height), 1)
    }

    func testTallMediaReservesCappedHeightBeforeLoading() {
        let frame = layout(aspect: 1 / 4)
        XCTAssertEqual(frame.height, 1200)
        XCTAssertEqual(frame.contentMode, .fill)
    }

    func testExplicitFillKeepsFixedGridHeight() {
        let frame = MediaFrameLayout(availableWidth: 200, aspect: 1 / 4, placeholderAspect: 1, maxHeight: 1200, contentMode: .fill)
        XCTAssertEqual(frame.height, 200)
        XCTAssertEqual(frame.contentMode, .fill)
    }

    func testFullscreenDoesNotForceCropping() {
        let frame = MediaFrameLayout(availableWidth: 400, aspect: 1 / 4, placeholderAspect: 4 / 3, maxHeight: 1200, contentMode: .fit, fullScreen: true)
        XCTAssertEqual(frame.height, 1200)
        XCTAssertEqual(frame.contentMode, .fit)
    }

    func testInvalidMetadataFallsBackToFiniteLayout() {
        for size in [CGSize.zero, CGSize(width: -1, height: 20), CGSize(width: CGFloat.infinity, height: 20)] {
            XCTAssertNil(MediaFrameLayout.aspect(for: size))
        }
        XCTAssertEqual(layout(aspect: .nan).height, 300)
    }

    private func layout(aspect: CGFloat) -> MediaFrameLayout {
        MediaFrameLayout(availableWidth: 400, aspect: aspect, placeholderAspect: 4 / 3, maxHeight: 1200, contentMode: .fit)
    }
}
