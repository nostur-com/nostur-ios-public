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
    
    func withChildren(_ children: [NestedReplyNode]) -> NestedReplyNode {
        NestedReplyNode(
            nrPost: nrPost,
            children: children,
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
    
    /// Hierarchical path badge on each reply PFP (e.g. `1.3.2`) for discussing nest layout.
    /// Flip to `true` to show orange path chips while debugging nest layout.
    static let showPathLabels = false
    
    static let lineWidth: CGFloat = 2.0
    /// Hit-test width for tap-to-collapse on the tree rail (kept outside Box navigation).
    static let railHitWidth: CGFloat = 32.0
    /// Corner radius for the L-branch into a child.
    static let cornerRadius: CGFloat = 8.0
    /// Small PFP in collapsed "Show thread…" rows (left-aligned with the PFP column).
    static let collapsedPfpSize: CGFloat = 20.0
    
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
    
    // MARK: - Branch-only indentation
    //
    // Indent only when a parent has *multiple* children (a real branch).
    // Linear chains (single reply → single reply → …) stay flush and share one
    // straight spine — they do not consume indent budget.
    // After a branch step, further linear descendants stay at that inset.
    // Cumulative branch indent is capped so deep multi-branch trees do not run off-screen.
    
    /// Horizontal step applied at each multi-child branch.
    static let branchInset: CGFloat = 32.0
    
    /// Minimum step worth drawing as an L-branch (below this, treat as no indent).
    static let minUsefulStep: CGFloat = 12.0
    
    /// Cap total indent from successive branches (≈ 3 branch steps).
    static var maxCumulativeInset: CGFloat {
        branchInset * 3
    }
    
    /// Leading padding for a child given whether its parent branched and the
    /// parent's current visual inset.
    /// - Linear (parent has 1 child): `0` — straight spine, no indent.
    /// - Branch (parent has 2+ children): `branchInset`, clamped to the remaining cap.
    static func stepInset(
        parentHasMultipleChildren: Bool,
        currentVisualInset: CGFloat
    ) -> CGFloat {
        guard parentHasMultipleChildren else { return 0 }
        let remaining = maxCumulativeInset - currentVisualInset
        guard remaining >= minUsefulStep else { return 0 }
        return min(branchInset, remaining)
    }
    
    /// How to draw the connector into a child.
    enum RailStyle {
        /// Parent has one child: vertical spine only, no indent.
        case linear
        /// Parent has multiple children and we have room to indent: classic L-rail.
        case branch
        /// Parent has multiple children but indent is capped: no L (avoids overlapping arms).
        case flatBranch
    }
    
    static func railStyle(
        parentHasMultipleChildren: Bool,
        stepInset: CGFloat
    ) -> RailStyle {
        if !parentHasMultipleChildren { return .linear }
        if stepInset >= minUsefulStep { return .branch }
        return .flatBranch
    }
    
    static let maxNodes: Int = 300
}
