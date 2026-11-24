import CoreGraphics

/// Snapshot at pinch start, in the untransformed Gallery viewport coordinates.
struct GalleryPinchZoom {
    let scale: CGFloat
    let position: CGSize
    let anchor: CGPoint

    func position(at newScale: CGFloat, viewport: CGSize) -> CGSize {
        let ratio = newScale / scale
        let x = anchor.x - viewport.width / 2
        let y = anchor.y - viewport.height / 2
        // Keep the same source pixel under the pinch midpoint, including prior pan.
        return CGSize(
            width: x - (x - position.width) * ratio,
            height: y - (y - position.height) * ratio
        )
    }
}
