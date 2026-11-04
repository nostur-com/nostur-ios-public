import SwiftUI

/// Stack each category beneath the shortest column instead of reserving the
/// height of the tallest category for every item in a grid row.
@available(iOS 16.0, *)
struct BrowserDirectoryLayout: Layout {
    var minimumColumnWidth: CGFloat = 250
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(0, proposal.width ?? minimumColumnWidth)
        let frames = categoryFrames(width: width, subviews: subviews)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = categoryFrames(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func categoryFrames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let count = max(1, min(subviews.count, Int((width + spacing) / (minimumColumnWidth + spacing))))
        let columnWidth = max(0, (width - CGFloat(count - 1) * spacing) / CGFloat(count))
        var bottoms = Array(repeating: CGFloat.zero, count: count)
        return subviews.map { subview in
            let column = bottoms.indices.min(by: { bottoms[$0] < bottoms[$1] }) ?? 0
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            let frame = CGRect(x: CGFloat(column) * (columnWidth + spacing), y: bottoms[column],
                               width: columnWidth, height: size.height)
            bottoms[column] = frame.maxY + spacing
            return frame
        }
    }
}
