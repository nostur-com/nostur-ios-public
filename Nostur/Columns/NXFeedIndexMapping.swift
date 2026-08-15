//
//  NXFeedIndexMapping.swift
//  Nostur
//
//  Maps SwiftUI List index paths to ForEach item indices. iOS List is backed
//  by either one content section or one section per row.
//

import Foundation

enum NXFeedIndexMapping {
    /// Maps a UIKit index path to a `ForEach` item index.
    static func itemIndex(for indexPath: IndexPath, sectionCounts: [Int], itemCount: Int) -> Int? {
        guard itemCount > 0, !sectionCounts.isEmpty else { return nil }

        if isOneItemPerSection(sectionCounts) {
            let index = indexPath.section
            return (0..<itemCount).contains(index) ? index : nil
        }

        if let section = contentSection(sectionCounts: sectionCounts, itemCount: itemCount),
           indexPath.section == section {
            return (0..<itemCount).contains(indexPath.item) ? indexPath.item : nil
        }

        return (0..<itemCount).contains(indexPath.item) ? indexPath.item : nil
    }

    /// Inverse of `itemIndex(for:sectionCounts:itemCount:)`.
    static func indexPath(forItemIndex itemIndex: Int, sectionCounts: [Int], itemCount: Int) -> IndexPath? {
        guard (0..<itemCount).contains(itemIndex), !sectionCounts.isEmpty else { return nil }

        if isOneItemPerSection(sectionCounts) {
            guard sectionCounts.indices.contains(itemIndex), sectionCounts[itemIndex] > 0 else { return nil }
            return IndexPath(item: 0, section: itemIndex)
        }

        let section = contentSection(sectionCounts: sectionCounts, itemCount: itemCount) ?? 0
        guard sectionCounts.indices.contains(section), sectionCounts[section] > itemIndex else { return nil }
        return IndexPath(item: itemIndex, section: section)
    }

    static func itemsInsertedAbove(oldIDs: [String], newIDs: [String], anchorID: String) -> Bool {
        guard let oldIndex = oldIDs.firstIndex(of: anchorID),
              let newIndex = newIDs.firstIndex(of: anchorID) else { return false }
        return newIndex > oldIndex
    }

    private static func isOneItemPerSection(_ sectionCounts: [Int]) -> Bool {
        sectionCounts.count > 1 && sectionCounts.allSatisfy { $0 <= 1 }
    }

    private static func contentSection(sectionCounts: [Int], itemCount: Int) -> Int? {
        if let match = sectionCounts.firstIndex(where: { $0 == itemCount || $0 == itemCount + 1 }) {
            return match
        }
        return sectionCounts.firstIndex(where: { $0 > 0 })
    }
}

/// Visible-top relative feed coordinates. Safe-area / live-banner inset changes
/// must not be baked into the stored reading position.
enum NXFeedViewport {
    /// Distance from the visible content top (below the current top inset) to the row.
    /// Zero means the row is flush with whatever is currently inset at the top.
    static func offsetFromVisibleTop(itemMinY: CGFloat, contentOffsetY: CGFloat, insetTop: CGFloat) -> CGFloat {
        itemMinY - (contentOffsetY + insetTop)
    }

    /// Content offset that keeps the same content under the visible top after an inset change.
    static func contentOffset(
        preservingVisibleContent oldOffset: CGFloat,
        oldInsetTop: CGFloat,
        newInsetTop: CGFloat
    ) -> CGFloat {
        oldOffset + oldInsetTop - newInsetTop
    }
}
