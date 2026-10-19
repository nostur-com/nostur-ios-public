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

/// A missing frame is not a stable layout sample. Require unchanged geometry
/// across frames before lifting a viewport cover after List invalidates estimates.
struct NXFeedSettleProgress {
    struct Geometry: Equatable {
        let contentHeight: CGFloat
        let offsetY: CGFloat
        let insetTop: CGFloat
        let anchorFrame: CGRect
    }

    private var previous: Geometry?
    private(set) var stableSamples = 0

    mutating func observe(geometry: Geometry?, corrected: Bool) {
        if let geometry, !corrected, geometry == previous {
            stableSamples += 1
        } else {
            stableSamples = 0
        }
        previous = geometry
    }
}

/// Visible-top relative feed coordinates. Safe-area / live-banner inset changes
/// must not be baked into the stored reading position.
enum NXFeedViewport {
    /// UIKit's visible-item APIs also include rows underneath translucent bars.
    /// Only protect rows that intersect the readable area inside the insets.
    static func isPostVisible(
        frame: CGRect,
        contentOffsetY: CGFloat,
        viewportHeight: CGFloat,
        insetTop: CGFloat,
        insetBottom: CGFloat
    ) -> Bool {
        let top = contentOffsetY + insetTop
        let bottom = contentOffsetY + viewportHeight - insetBottom
        return bottom > top && frame.maxY > top && frame.minY < bottom
    }

    /// SwiftUI can expose non-finite estimated frames during List reconciliation.
    /// Those cannot identify a visible row or drive an offset correction.
    static func isUsableRowFrame(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.width.isFinite && frame.height.isFinite
            && frame.width > 0 && frame.height > 0
    }

    /// `performAnchored` reason for a mid-feed newer-post insert. Used to cover
    /// the viewport before the unanimated prepend paints.
    static let prependCoverReason = "newer posts"
    /// `performAnchored` reason for removing already-read rows above the reading post.
    static let unreadRemovalCoverReason = "read leaf rows removed"
    static let bannerUpdateCoverReason = "already seen banner changed"

    static func shouldCoverPrepend(updateReasons: [String]) -> Bool {
        updateReasons.contains(prependCoverReason)
    }

    static func shouldCoverViewport(updateReasons: [String]) -> Bool {
        shouldCoverPrepend(updateReasons: updateReasons)
            || updateReasons.contains(unreadRemovalCoverReason)
            || updateReasons.contains(bannerUpdateCoverReason)
            || updateReasons.contains("older posts append")
    }

    /// A covered mutation must keep its pre-mutation post pinned until List finishes
    /// reconciling self-sized geometry. Row removal can invalidate estimated heights
    /// even when the anchor's array index is unchanged.
    static func shouldSettleAnchoredUpdate(
        updateReasons: [String],
        pinByIdentity: Bool,
        anchorIndexShifted: Bool
    ) -> Bool {
        // Appends can encounter an older ID snapshot after an explicit reveal.
        // That apparent index shift must never restore a pre-reveal post.
        if !updateReasons.isEmpty, updateReasons.allSatisfy({ $0 == "older posts append" }) { return false }
        return pinByIdentity
            || anchorIndexShifted
            || shouldCoverViewport(updateReasons: updateReasons)
    }

    /// A tail append does not move the visible row. List still rewrites
    /// `contentOffset` from the new estimated heights and the feed jumps toward
    /// newer posts. Pin that row. A shifted index is a stale reveal snapshot.
    static func shouldPinTailAppend(
        updateReasons: [String],
        oldIDs: [String],
        newIDs: [String],
        anchorID: String?
    ) -> Bool {
        guard !updateReasons.isEmpty,
              updateReasons.allSatisfy({ $0 == "older posts append" }),
              let anchorID,
              let oldIndex = oldIDs.firstIndex(of: anchorID),
              let newIndex = newIDs.firstIndex(of: anchorID) else { return false }
        return oldIndex == newIndex
    }

    /// Cell count that includes every post inserted above the parked row.
    /// `nil` when this update did not add rows, so settle must not wait.
    /// Removals count too: an at-top truncation can drop more rows than the
    /// prepend adds, and the collection view never grows to the old total.
    static func prependMinimumCellCount(
        cellsBefore: Int,
        insertedCount: Int,
        removedCount: Int = 0,
        itemCount: Int? = nil
    ) -> Int? {
        // A zero count means the scroll view has not reported its rows yet.
        // Treating that as "one more cell" would finish before the real insert.
        guard cellsBefore > 0, insertedCount > 0 else { return nil }
        var expected = cellsBefore + insertedCount - max(0, removedCount)
        // The collection view can already contain a cell the post list does not.
        // Waiting for that stale extra cell keeps the cover up, then the settle
        // gives up and the jumped offset is what the user sees.
        if let itemCount, itemCount > 0 {
            expected = min(expected, itemCount)
        }
        guard expected > 0 else { return nil }
        return expected
    }

    /// Furthest `contentOffset.y` a prepend may use: where it started, plus the
    /// height the list has actually gained, plus a small estimate slack.
    static func prependOffsetLimit(
        offsetAtStart: CGFloat,
        contentHeight: CGFloat,
        contentHeightAtStart: CGFloat,
        slack: CGFloat = 80
    ) -> CGFloat {
        let heightAdded = contentHeight - contentHeightAtStart
        return offsetAtStart + max(0, heightAdded) + slack
    }

    /// A prepend may scroll down by the height the list gained, or by a pin that
    /// is still near the start and clear of the tail. After that pin lands, a
    /// short correction may keep tracking the anchor.
    /// Content height often lags the new rows, and an at-top truncation shrinks
    /// it. Refusing every correction then leaves the offset at the top, so the
    /// new posts push the feed when the cover lifts.
    /// A stale frame that flings toward the end is still refused. That collapsed
    /// height looks like the end of the feed and requests another page.
    static func shouldApplyPrependOffset(
        offsetAtStart: CGFloat,
        currentOffset: CGFloat,
        correction: CGFloat,
        contentHeight: CGFloat,
        contentHeightAtStart: CGFloat,
        slack: CGFloat = 80,
        viewportHeight: CGFloat = 956
    ) -> Bool {
        let allowedOffset = prependOffsetLimit(
            offsetAtStart: offsetAtStart,
            contentHeight: contentHeight,
            contentHeightAtStart: contentHeightAtStart,
            slack: slack
        )
        let projected = currentOffset + correction
        if projected <= allowedOffset + 0.5 { return true }
        // Already past the inserted height. Allow a correction that comes back.
        if projected < currentOffset - 0.5 { return true }
        let viewport = max(viewportHeight, 1)
        let clearOfTail = projected <= contentHeight - viewport * 1.5
        guard clearOfTail else { return false }
        // The first sample is still at the pre-insert offset, so a pin taller
        // than the screen is allowed. Once that pin has moved us, only a short
        // correction may continue. Another full screen is a stale frame.
        let stillNearStart = currentOffset <= offsetAtStart + viewport + slack
        if stillNearStart { return true }
        return correction <= viewport + slack
    }

    /// UIKit can move past the inserted height before the first settle sample,
    /// while the anchor frame still points further down. Step back to the limit.
    /// A correction that is already coming back is left to `shouldApplyPrependOffset`.
    static func prependOffsetClamp(
        offsetAtStart: CGFloat,
        currentOffset: CGFloat,
        correction: CGFloat,
        contentHeight: CGFloat,
        contentHeightAtStart: CGFloat,
        slack: CGFloat = 80,
        viewportHeight: CGFloat = 956
    ) -> CGFloat? {
        guard !shouldApplyPrependOffset(
            offsetAtStart: offsetAtStart,
            currentOffset: currentOffset,
            correction: correction,
            contentHeight: contentHeight,
            contentHeightAtStart: contentHeightAtStart,
            slack: slack,
            viewportHeight: viewportHeight
        ) else { return nil }
        let viewport = max(viewportHeight, 1)
        // The anchor is already here, or only a short self-size away. Pulling
        // back to the slack limit undoes a pin taller than the viewport, and
        // the next sample applies that same pin again.
        guard correction > viewport + slack else { return nil }
        let allowedOffset = prependOffsetLimit(
            offsetAtStart: offsetAtStart,
            contentHeight: contentHeight,
            contentHeightAtStart: contentHeightAtStart,
            slack: slack
        )
        guard currentOffset > allowedOffset + 0.5 else { return nil }
        return allowedOffset
    }

    /// The pre-insert list looks aligned for several frames after an unread landing,
    /// while SwiftUI is still applying the new row. Finishing then lifts the cover
    /// and the row paints at the top, pushing the feed down.
    static func shouldFinishAnchoredSettle(
        stableSamples: Int,
        step: Int,
        extended: Bool,
        renderedCellCount: Int,
        prependMinimumCellCount: Int?
    ) -> Bool {
        guard stableSamples >= 3 else { return false }
        if let prependMinimumCellCount, renderedCellCount < prependMinimumCellCount {
            return false
        }
        return !extended || step >= 7
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

    /// Keep a saved in-row offset inside the row's current height. A parent trim
    /// while detail is open can shrink the row. Replaying the old offset then
    /// scrolls past it onto the next post.
    static func visibleTopOffsetInsideRow(saved: CGFloat, rowHeight: CGFloat) -> CGFloat {
        guard saved < 0, rowHeight > 1, saved.isFinite, rowHeight.isFinite else { return saved }
        return max(saved, 1 - rowHeight)
    }

    /// A list that has left the window reports offset 0 and a zero inset. That
    /// is not the user reaching the top.
    static func shouldTreatOffsetAsUserAtTop(
        hasWindow: Bool,
        contentOffsetY: CGFloat,
        insetTop: CGFloat,
        isPreparingRestore: Bool
    ) -> Bool {
        guard hasWindow, !isPreparingRestore else { return false }
        return isOffsetAtTop(contentOffsetY: contentOffsetY, insetTop: insetTop)
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
