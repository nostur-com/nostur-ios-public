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
    /// Prefers a section whose size matches the feed so a Mac List header row is not counted as a post.
    static func itemIndex(for indexPath: IndexPath, sectionCounts: [Int], itemCount: Int) -> Int? {
        guard itemCount > 0, sectionCounts.indices.contains(indexPath.section) else { return nil }
        guard indexPath.item >= 0, indexPath.item < sectionCounts[indexPath.section] else { return nil }

        if let contentSection = contentSection(sectionCounts: sectionCounts, itemCount: itemCount) {
            guard indexPath.section == contentSection else { return nil }
            return (0..<itemCount).contains(indexPath.item) ? indexPath.item : nil
        }

        if isOneItemPerSection(sectionCounts) {
            var seen = 0
            for section in 0...indexPath.section where sectionCounts[section] > 0 {
                if section == indexPath.section {
                    return (0..<itemCount).contains(seen) ? seen : nil
                }
                seen += 1
            }
            return nil
        }

        var index = 0
        for section in 0..<indexPath.section {
            index += sectionCounts[section]
        }
        index += indexPath.item
        return (0..<itemCount).contains(index) ? index : nil
    }

    /// Inverse of `itemIndex(for:sectionCounts:itemCount:)`.
    static func indexPath(forItemIndex itemIndex: Int, sectionCounts: [Int], itemCount: Int) -> IndexPath? {
        guard (0..<itemCount).contains(itemIndex), !sectionCounts.isEmpty else { return nil }

        if let contentSection = contentSection(sectionCounts: sectionCounts, itemCount: itemCount),
           sectionCounts[contentSection] > itemIndex {
            return IndexPath(item: itemIndex, section: contentSection)
        }

        if isOneItemPerSection(sectionCounts) {
            var seen = 0
            for section in sectionCounts.indices where sectionCounts[section] > 0 {
                if seen == itemIndex {
                    return IndexPath(item: 0, section: section)
                }
                seen += 1
            }
            return nil
        }

        var remaining = itemIndex
        for section in sectionCounts.indices {
            let count = sectionCounts[section]
            if remaining < count {
                return IndexPath(item: remaining, section: section)
            }
            remaining -= count
        }
        return nil
    }

    /// A section that holds the feed rows (or feed rows + the pagination sentinel).
    /// A leading singleton section is treated as a header, not as a post.
    private static func contentSection(sectionCounts: [Int], itemCount: Int) -> Int? {
        sectionCounts.firstIndex(where: { $0 == itemCount || $0 == itemCount + 1 })
    }

    private static func isOneItemPerSection(_ sectionCounts: [Int]) -> Bool {
        let nonEmpty = sectionCounts.filter { $0 > 0 }
        return nonEmpty.count > 1 && nonEmpty.allSatisfy { $0 == 1 }
    }

    static func itemsInsertedAbove(oldIDs: [String], newIDs: [String], anchorID: String) -> Bool {
        guard let oldIndex = oldIDs.firstIndex(of: anchorID),
              let newIndex = newIDs.firstIndex(of: anchorID) else { return false }
        return newIndex > oldIndex
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
