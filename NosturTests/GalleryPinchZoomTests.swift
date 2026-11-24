import XCTest
@testable import Nostur

final class GalleryPinchZoomTests: XCTestCase {
    private let viewport = CGSize(width: 400, height: 800)

    func testOffCenterPinchKeepsSourcePointUnderFingers() {
        verifyAnchor(scale: 1, position: .zero, anchor: CGPoint(x: 320, y: 230), newScale: 3)
    }

    func testSecondPinchAfterPanKeepsSourcePointUnderFingers() {
        verifyAnchor(scale: 2, position: CGSize(width: -140, height: 220), anchor: CGPoint(x: 90, y: 610), newScale: 3.5)
    }

    func testZoomingOutKeepsSourcePointUnderFingers() {
        verifyAnchor(scale: 3.5, position: CGSize(width: 180, height: -260), anchor: CGPoint(x: 310, y: 120), newScale: 1.5)
    }

    func testReturningToOriginalScaleRestoresPosition() {
        let initial = GalleryPinchZoom(scale: 2, position: CGSize(width: 70, height: -120), anchor: CGPoint(x: 80, y: 600))
        let zoomed = initial.position(at: 4, viewport: viewport)
        let restored = GalleryPinchZoom(scale: 4, position: zoomed, anchor: initial.anchor).position(at: 2, viewport: viewport)
        XCTAssertEqual(restored.width, initial.position.width, accuracy: 0.001)
        XCTAssertEqual(restored.height, initial.position.height, accuracy: 0.001)
    }

    private func verifyAnchor(scale: CGFloat, position: CGSize, anchor: CGPoint, newScale: CGFloat) {
        let start = GalleryPinchZoom(scale: scale, position: position, anchor: anchor)
        let result = start.position(at: newScale, viewport: viewport)
        let sourceX = (anchor.x - viewport.width / 2 - position.width) / scale
        let sourceY = (anchor.y - viewport.height / 2 - position.height) / scale
        XCTAssertEqual(sourceX * newScale + result.width + viewport.width / 2, anchor.x, accuracy: 0.001)
        XCTAssertEqual(sourceY * newScale + result.height + viewport.height / 2, anchor.y, accuracy: 0.001)
    }
}
