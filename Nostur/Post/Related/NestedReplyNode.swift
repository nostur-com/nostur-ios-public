//
//  NestedReplyNode.swift
//  Nostur
//
//  Tree node for nested reply rendering under a detail post.
//

import Foundation
import CoreGraphics

/// One reply in a nested tree. Built on a background context, published to main for `NestedThreadReplies`.
final class NestedReplyNode: Identifiable {
    let id: String
    let nrPost: NRPost
    let children: [NestedReplyNode]
    let depth: Int
    /// Parent id used when building the tree (for debug).
    let resolvedParentId: String?
    /// How this node was placed: "root-direct", "child", "root-orphan", etc.
    let placement: String
    
    init(
        nrPost: NRPost,
        children: [NestedReplyNode] = [],
        depth: Int = 0,
        resolvedParentId: String? = nil,
        placement: String = ""
    ) {
        self.id = nrPost.id
        self.nrPost = nrPost
        self.children = children
        self.depth = depth
        self.resolvedParentId = resolvedParentId
        self.placement = placement
    }
    
    /// Rebuild tree with corrected depths (e.g. after WoT promotion).
    func withDepth(_ depth: Int) -> NestedReplyNode {
        NestedReplyNode(
            nrPost: nrPost,
            children: children.map { $0.withDepth(depth + 1) },
            depth: depth,
            resolvedParentId: resolvedParentId,
            placement: placement
        )
    }
    
    /// One-line debug summary for UI / logs.
    var debugLine: String {
        let short: (String?) -> String = { id in
            guard let id, id.count >= 8 else { return id ?? "nil" }
            return String(id.prefix(8))
        }
        return "d\(depth) id=\(short(id)) replyTo=\(short(nrPost.replyToId)) root=\(short(nrPost.replyToRootId)) parent=\(short(resolvedParentId)) [\(placement)]"
    }
}

enum NestedThreadMetrics {
    /// Flip to `true` to show orange per-row nest debug labels in the UI.
    static let showDebugLabels = false
    
    static let lineWidth: CGFloat = 2.0
    /// Hit-test width for tap-to-collapse on the tree rail (kept outside Box navigation).
    static let railHitWidth: CGFloat = 32.0
    /// Corner radius for the L-branch into a child.
    static let cornerRadius: CGFloat = 8.0
    /// Chevron in collapsed "Show thread…" rows (left-aligned with the PFP column).
    static let collapsedChevronSize: CGFloat = 16.0
    
    /// Same X as `PostLayout` thread connect lines: Box pad + THREAD_LINE_OFFSET.
    static var spineX: CGFloat {
        DIMENSIONS.BOX_PADDING + THREAD_LINE_OFFSET
    }
    
    /// Mid-PFP Y from top of a post Box (for horizontal L into a child).
    static var branchY: CGFloat {
        DIMENSIONS.BOX_PADDING + DIMENSIONS.POST_ROW_PFP_DIAMETER / 2.0
    }
    
    /// Y just below the PFP so a vertical spine does not paint over the avatar.
    static var spineBelowPfpY: CGFloat {
        DIMENSIONS.BOX_PADDING + DIMENSIONS.POST_ROW_PFP_DIAMETER
    }
    
    /// Left edge of the child post Box / PFP column in parent coordinates.
    /// L-arms stop here so rails meet avatars instead of drawing on top of them.
    static func branchEndX(stepInset: CGFloat) -> CGFloat {
        stepInset + DIMENSIONS.BOX_PADDING
    }
    
    // MARK: - Tapered indentation
    //
    // Level 1 (under a top-level reply) uses firstLevelInset.
    // Level 2+ uses deepLevelInset (slightly tighter).
    // Cumulative indent is capped so deep threads do not run off-screen.
    
    /// First nesting step (parent depth 0 → child depth 1).
    static let firstLevelInset: CGFloat = 32.0
    
    /// Deeper nesting steps (parent depth ≥ 1).
    static let deepLevelInset: CGFloat = 30.0
    
    /// Stop growing indent after first + two deep steps.
    static var maxCumulativeInset: CGFloat {
        firstLevelInset + deepLevelInset * 2
    }
    
    /// Leading padding applied when nesting a child under a parent of `parentDepth`.
    static func stepInset(fromParentDepth parentDepth: Int) -> CGFloat {
        let childDepth = parentDepth + 1
        return cumulativeInset(depth: childDepth) - cumulativeInset(depth: parentDepth)
    }
    
    /// Total leading inset for a node at `depth` (0 = top-level reply under the detail post).
    static func cumulativeInset(depth: Int) -> CGFloat {
        guard depth > 0 else { return 0 }
        let raw = firstLevelInset + CGFloat(depth - 1) * deepLevelInset
        return min(raw, maxCumulativeInset)
    }
    
    /// Horizontal run from parent spine to child spine for a given step inset.
    static func branchWidth(stepInset: CGFloat) -> CGFloat {
        max(lineWidth, branchEndX(stepInset: stepInset) - spineX)
    }
    
    static let maxVisualDepth: Int = 8
    static let maxNodes: Int = 200
}
