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
    ///
    /// Extra List rows are skipped rather than counted as posts:
    /// a Mac header section, an already-seen banner (`leadingNonPostRows`),
    /// and trailing pagination / spinner rows.
    static func itemIndex(
        for indexPath: IndexPath,
        sectionCounts: [Int],
        itemCount: Int,
        leadingNonPostRows: Int = 0
    ) -> Int? {
        guard itemCount > 0, sectionCounts.indices.contains(indexPath.section) else { return nil }
        guard indexPath.item >= 0, indexPath.item < sectionCounts[indexPath.section] else { return nil }

        let cells = flattenedCells(sectionCounts)
        guard let flatIndex = cells.firstIndex(where: {
            $0.section == indexPath.section && $0.item == indexPath.item
        }) else { return nil }
        let postIndex = flatIndex - postStart(
            sectionCounts: sectionCounts,
            itemCount: itemCount,
            leadingNonPostRows: leadingNonPostRows
        )
        return (0..<itemCount).contains(postIndex) ? postIndex : nil
    }

    /// Inverse of `itemIndex(for:sectionCounts:itemCount:leadingNonPostRows:)`.
    static func indexPath(
        forItemIndex itemIndex: Int,
        sectionCounts: [Int],
        itemCount: Int,
        leadingNonPostRows: Int = 0
    ) -> IndexPath? {
        guard (0..<itemCount).contains(itemIndex), !sectionCounts.isEmpty else { return nil }
        let cells = flattenedCells(sectionCounts)
        let flatIndex = postStart(
            sectionCounts: sectionCounts,
            itemCount: itemCount,
            leadingNonPostRows: leadingNonPostRows
        ) + itemIndex
        guard cells.indices.contains(flatIndex) else { return nil }
        let cell = cells[flatIndex]
        return IndexPath(item: cell.item, section: cell.section)
    }

    static func leadingNonPostRowCount(alreadySeenNewerBannerVisible: Bool) -> Int {
        alreadySeenNewerBannerVisible ? 1 : 0
    }

    private static func flattenedCells(_ sectionCounts: [Int]) -> [(section: Int, item: Int)] {
        var cells: [(section: Int, item: Int)] = []
        for section in sectionCounts.indices where sectionCounts[section] > 0 {
            for item in 0..<sectionCounts[section] {
                cells.append((section, item))
            }
        }
        return cells
    }

    /// Cells before the first post: an inferred Mac header section (not used
    /// when every section is a singleton) plus the already-seen banner.
    private static func postStart(
        sectionCounts: [Int],
        itemCount: Int,
        leadingNonPostRows: Int
    ) -> Int {
        var headerCells = 0
        if !isOneItemPerSection(sectionCounts),
           let first = sectionCounts.firstIndex(where: { $0 > 0 }),
           sectionCounts[first] == 1 {
            let remainingAfterHeader = flattenedCells(sectionCounts).count - 1
            if remainingAfterHeader - leadingNonPostRows >= itemCount {
                headerCells = 1
            }
        }
        return headerCells + leadingNonPostRows
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

    /// True when the reading post moved because rows were inserted or removed above it.
    static func anchorIndexShifted(oldIDs: [String], newIDs: [String], anchorID: String) -> Bool {
        guard let oldIndex = oldIDs.firstIndex(of: anchorID),
              let newIndex = newIDs.firstIndex(of: anchorID) else { return false }
        return newIndex != oldIndex
    }
}

/// The only post the feed is allowed to settle to.
enum NXFeedPark {
    struct Post: Equatable {
        var id: String
        var visibleTopOffset: CGFloat
    }

    enum SettleTarget: Equatable {
        case pin(Post)
        case retarget(Post)
        case skip
    }

    /// Mutations pin `parked` when it is still in the feed. If that id was
    /// removed, retarget once to the live top-edge. Never chase a stale id.
    static func settleTarget(
        parked: Post?,
        newIDs: [String],
        live: Post?
    ) -> SettleTarget {
        if let parked, newIDs.contains(parked.id) {
            return .pin(parked)
        }
        if let live {
            return .retarget(live)
        }
        return .skip
    }

    static func shouldCompleteRestore(parkedID: String?, liveVisibleID: String?) -> Bool {
        guard let parkedID else { return false }
        return parkedID == liveVisibleID
    }
}

/// Visible-top relative feed coordinates. Safe-area / live-banner inset changes
/// must not be baked into the stored reading position.
enum NXFeedViewport {
    /// `performAnchored` reason for a mid-feed newer-post insert. Used to cover
    /// the viewport before the unanimated prepend paints.
    static let prependCoverReason = "newer posts"
    /// `performAnchored` reason for removing already-read rows above the reading post.
    static let unreadRemovalCoverReason = "read leaf rows removed"

    static func shouldCoverPrepend(updateReasons: [String]) -> Bool {
        updateReasons.contains(prependCoverReason)
    }

    static func shouldCoverViewport(updateReasons: [String]) -> Bool {
        shouldCoverPrepend(updateReasons: updateReasons) || updateReasons.contains(unreadRemovalCoverReason)
    }

    /// Let SwiftUI/List animate a pure offscreen deletion. List already keeps the
    /// visible rows stable for this case, while an identity settle can fight its
    /// transient self-sizing layout and visibly correct a viewport that never moved.
    static func shouldAnimateOffscreenRemoval(
        removedPostIDs: Set<String>,
        visiblePostIDs: Set<String>,
        hasParentUpdates: Bool
    ) -> Bool {
        !removedPostIDs.isEmpty
            && removedPostIDs.isDisjoint(with: visiblePostIDs)
            && !hasParentUpdates
    }

    /// Remember-on restores already-seen posts. Older pages are for scrolling
    /// down that snapshot, not for restore, prepend, or estimated near-tail.
    static func shouldAllowRememberOnOlderFetch(
        continueEnabled: Bool,
        userHasScrolledTowardOlder: Bool,
        visiblePostCount: Int = .max,
        sparseFeedMinimum: Int = 6
    ) -> Bool {
        !continueEnabled
            || userHasScrolledTowardOlder
            || visiblePostCount < sparseFeedMinimum
    }

    /// Select the visible row that actually crosses the viewport's top edge. Falling back to
    /// the first row below the edge avoids anchoring a later row hundreds of points down when
    /// the partially visible top post is tall.
    static func topEdgeAnchorIndex(
        itemFrames: [CGRect],
        visibleTopY: CGFloat,
        tolerance: CGFloat = 0.5
    ) -> Int? {
        guard !itemFrames.isEmpty else { return nil }

        let crossing = itemFrames.indices.filter { index in
            let frame = itemFrames[index]
            return frame.minY <= visibleTopY + tolerance && frame.maxY > visibleTopY + tolerance
        }
        if let index = crossing.max(by: { itemFrames[$0].minY < itemFrames[$1].minY }) {
            return index
        }

        return itemFrames.indices
            .filter { itemFrames[$0].minY > visibleTopY - tolerance }
            .min(by: { itemFrames[$0].minY < itemFrames[$1].minY })
    }

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

    static func isOffsetAtTop(contentOffsetY: CGFloat, insetTop: CGFloat, threshold: CGFloat = 5) -> Bool {
        contentOffsetY <= -insetTop + threshold
    }

    /// Live scroll offset wins. An unfinished restore paints from offset 0, so
    /// that offset must not be treated as "the user is at the top".
    static func isActuallyAtTop(
        hasLiveScrollView: Bool,
        contentOffsetY: CGFloat,
        insetTop: CGFloat,
        isPreparingRestore: Bool,
        fallbackIsAtTop: Bool
    ) -> Bool {
        if isPreparingRestore {
            return false
        }
        if hasLiveScrollView {
            return isOffsetAtTop(contentOffsetY: contentOffsetY, insetTop: insetTop)
        }
        return fallbackIsAtTop
    }
}
