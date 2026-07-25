//
//  NestedThreadReplies.swift
//  Nostur
//
//  Nested replies with continuous tree rails.
//
//  Indentation is branch-only:
//  - A linear chain (one reply under another, repeatedly) stays flush with a
//    straight vertical spine — no extra indent per level.
//  - Indent (and an L-rail) is applied only when a parent has multiple children.
//  - After that one step, further linear descendants under each sibling stay flat.
//
//  Collapse is per-node: tapping the tree line under a reply folds that reply
//  plus all of its nested descendants. The collapsed post is replaced by
//  "Show thread from Name (N)" (N includes the folded post). Sibling and
//  ancestor posts stay visible.
//  There is no "collapse entire replies section under the detail post".
//
//  Expanded: tap the tree line to collapse that subtree (no "Hide" chrome).
//  Collapsed: "Show thread from Name (N)" where that subtree was.
//

import SwiftUI

struct NestedThreadReplies: View {
    @Environment(\.theme) private var theme
    @ObservedObject var nrPost: NRPost
    @State private var showNotWoT = false
    
    private var primaryNodes: [NestedReplyNode] {
        if !nrPost.nestedRepliesSorted.isEmpty {
            return nrPost.nestedRepliesSorted
        }
        if !nrPost.nestedRepliesNotWoT.isEmpty {
            return nrPost.nestedRepliesNotWoT
        }
        return nrPost.groupedRepliesSorted.map { NestedReplyNode(nrPost: $0, children: [], depth: 0) }
    }
    
    private var secondaryNodes: [NestedReplyNode] {
        if !nrPost.nestedRepliesSorted.isEmpty {
            return nrPost.nestedRepliesNotWoT
        }
        if !nrPost.nestedRepliesNotWoT.isEmpty {
            return []
        }
        return nrPost.groupedRepliesNotWoT.map { NestedReplyNode(nrPost: $0, children: [], depth: 0) }
    }
    
    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        VStack(alignment: .leading, spacing: 0) {
            if primaryNodes.isEmpty && secondaryNodes.isEmpty {
                Color.clear.frame(height: 30)
            }
            
            ForEach(Array(primaryNodes.enumerated()), id: \.element.id) { index, node in
                NestedReplyRow(node: node, path: "\(index + 1)", visualInset: 0)
            }
            
            if !secondaryNodes.isEmpty {
                Divider().padding(.vertical, 8)
                if WOT_FILTER_ENABLED() && !showNotWoT {
                    Button {
                        showNotWoT = true
                    } label: {
                        Text("Show more")
                            .padding(10)
                            .contentShape(Rectangle())
                    }
                    .padding(.bottom, 10)
                }
                if showNotWoT || !WOT_FILTER_ENABLED() {
                    // Secondary list continues numbering after primary roots.
                    let pathOffset = primaryNodes.count
                    ForEach(Array(secondaryNodes.enumerated()), id: \.element.id) { index, node in
                        NestedReplyRow(node: node, path: "\(pathOffset + index + 1)", visualInset: 0)
                    }
                }
            }
        }
        .background(theme.listBackground)
    }
}

/// One node in a reply tree.
///
/// Each row that has children owns its own collapse state:
/// - Tap the spine under this post, or the L-rail into a direct child → fold
///   this post + all descendants (not the whole d0 thread unless this is d0).
/// - "Show thread from Name (N)" stands in for the folded subtree.
struct NestedReplyRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.availableWidth) private var availableWidth
    
    let node: NestedReplyNode
    /// Hierarchical index for debug (e.g. `"1.3.2"`).
    let path: String
    /// Cumulative branch indent applied to this row (not logical depth).
    let visualInset: CGFloat
    
    @State private var isCollapsed = false
    
    private var hasChildren: Bool { !node.children.isEmpty }
    
    private var parentHasMultipleChildren: Bool { node.children.count > 1 }
    
    private var lineColor: Color { theme.lineColor.opacity(0.65) }
    
    private var nestedAvailableWidth: CGFloat {
        max(120, availableWidth - visualInset)
    }
    
    private var descendantCount: Int {
        node.children.reduce(0) { $0 + 1 + descendantCount(of: $1) }
    }
    
    private func descendantCount(of n: NestedReplyNode) -> Int {
        n.children.reduce(0) { $0 + 1 + descendantCount(of: $1) }
    }
    
    /// Posts in this subtree including this node (for "Show N replies").
    private var threadPostCount: Int {
        1 + descendantCount
    }
    
    /// Collapse this node and its descendants only.
    private func collapseSelf() {
        guard hasChildren else { return }
        isCollapsed = true
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Folded subtree: hide this post + nested; only a show control remains.
            if isCollapsed && hasChildren {
                showThreadRepliesButton
            }
            else {
                postBlock
                
                if hasChildren {
                    let step = NestedThreadMetrics.stepInset(
                        parentHasMultipleChildren: parentHasMultipleChildren,
                        currentVisualInset: visualInset
                    )
                    let railStyle = NestedThreadMetrics.railStyle(
                        parentHasMultipleChildren: parentHasMultipleChildren,
                        stepInset: step
                    )
                    let childVisualInset = visualInset + step
                    
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(node.children.enumerated()), id: \.element.id) { index, child in
                            NestedChildBranch(
                                node: child,
                                path: "\(path).\(index + 1)",
                                visualInset: childVisualInset,
                                isLastSibling: index == node.children.count - 1,
                                lineColor: lineColor,
                                stepInset: step,
                                railStyle: railStyle,
                                onRailTap: collapseSelf
                            )
                        }
                    }
                }
            }
        }
        .background(theme.listBackground)
        .animation(.easeInOut(duration: 0.15), value: isCollapsed)
    }
    
    private var postBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Box(nrPost: node.nrPost, showGutter: false) {
                PostRowDeletable(
                    nrPost: node.nrPost,
                    missingReplyTo: false,
                    connect: nil,
                    fullWidth: false,
                    isDetail: false,
                    theme: theme
                )
            }
            .id(node.id)
            .environment(\.availableWidth, nestedAvailableWidth)
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .topLeading) {
                // Spine under this post when it has children.
                // Tap collapses this subtree only.
                if hasChildren {
                    bodySpine(onTap: collapseSelf)
                }
            }
            .overlay(alignment: .topLeading) {
                if NestedThreadMetrics.showPathLabels {
                    pathBadge
                        // Center on the post PFP column.
                        .frame(
                            width: DIMENSIONS.POST_ROW_PFP_DIAMETER,
                            height: DIMENSIONS.POST_ROW_PFP_DIAMETER
                        )
                        .padding(.leading, DIMENSIONS.BOX_PADDING)
                        .padding(.top, DIMENSIONS.BOX_PADDING)
                        .allowsHitTesting(false)
                }
            }
            
            if NestedThreadMetrics.showDebugLabels {
                Text(node.debugLine)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.orange)
                    .textSelection(.enabled)
                    .padding(.leading, 8)
                    .padding(.bottom, 2)
            }
        }
    }
    
    /// Orange path chip for nest-layout debugging (e.g. `1.3.2`).
    private var pathBadge: some View {
        Text(path)
            .font(.system(size: path.count > 6 ? 8 : 10, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func bodySpine(onTap: @escaping () -> Void) -> some View {
        let hit = NestedThreadMetrics.railHitWidth
        let x = NestedThreadMetrics.spineX
        // Start below the PFP so the spine does not draw over the avatar.
        let y0 = NestedThreadMetrics.spineBelowPfpY
        let lineW = NestedThreadMetrics.lineWidth
        
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Path { path in
                    guard geo.size.height > y0 else { return }
                    path.move(to: CGPoint(x: x, y: y0))
                    path.addLine(to: CGPoint(x: x, y: geo.size.height))
                }
                .stroke(lineColor, style: StrokeStyle(lineWidth: lineW, lineCap: .square))
                .allowsHitTesting(false)
                
                Color.clear
                    .frame(width: hit, height: max(0, geo.size.height - y0))
                    .padding(.leading, x - hit / 2)
                    .padding(.top, y0)
                    .contentShape(Rectangle())
                    .highPriorityGesture(TapGesture().onEnded(onTap))
                    .accessibilityLabel(String(localized: "Collapse thread", comment: "A11y: collapse reply thread"))
            }
        }
    }
    
    private var showThreadRepliesButton: some View {
        let count = threadPostCount
        let name = node.nrPost.anyName
        let pfpSize = NestedThreadMetrics.collapsedPfpSize
        // Left-align with the PFP column so the parent L-rail meets the avatar.
        // Entire row (PFP + label) expands; no chevron — parent rail hits used to
        // steal chevron taps and collapse the parent instead.
        return Button {
            isCollapsed = false
        } label: {
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    PFP(
                        pubkey: node.nrPost.pubkey,
                        nrContact: node.nrPost.contact,
                        size: pfpSize
                    )
                    .frame(width: pfpSize, height: pfpSize)
                    
                    if NestedThreadMetrics.showPathLabels {
                        pathBadge
                            .scaleEffect(0.85)
                    }
                }
                .frame(width: pfpSize, height: pfpSize)
                .allowsHitTesting(false)
                
                Text(String(localized: "Show thread from \(name) (\(count))", comment: "Expand collapsed reply thread; name and post count"))
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(theme.accent)
                Spacer(minLength: 0)
            }
            .padding(.leading, DIMENSIONS.BOX_PADDING)
            .padding(.trailing, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Show collapsed reply thread", comment: "A11y"))
    }
}

/// Child under parent: optional indent + connector rail.
/// Rail tap collapses the *parent* (the post this branch hangs from).
///
/// Rail styles:
/// - `.linear` — single child: vertical spine only, no indent
/// - `.branch` — multi-child with room to indent: classic L into PFP
/// - `.flatBranch` — multi-child at indent cap: no L (avoids overlapping arms)
private struct NestedChildBranch: View {
    let node: NestedReplyNode
    let path: String
    let visualInset: CGFloat
    let isLastSibling: Bool
    let lineColor: Color
    let stepInset: CGFloat
    let railStyle: NestedThreadMetrics.RailStyle
    let onRailTap: () -> Void
    
    private var yBranch: CGFloat { NestedThreadMetrics.branchY }
    private var lineW: CGFloat { NestedThreadMetrics.lineWidth }
    private var spineX: CGFloat { NestedThreadMetrics.spineX }
    private var hit: CGFloat { NestedThreadMetrics.railHitWidth }
    private var cornerR: CGFloat { NestedThreadMetrics.cornerRadius }
    
    /// L arm ends at the left edge of the child PFP column.
    private var branchEndX: CGFloat {
        NestedThreadMetrics.branchEndX(stepInset: stepInset)
    }
    
    var body: some View {
        NestedReplyRow(node: node, path: path, visualInset: visualInset)
            .padding(.leading, stepInset)
            .fixedSize(horizontal: false, vertical: true)
            // Overlay so the rail is visible in the gutter; geometry is clipped
            // to end at the PFP column so it does not paint over avatars.
            .overlay {
                if railStyle != .flatBranch {
                    connectingRail
                }
            }
    }
    
    private var connectingRail: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let x = spineX
            // Short collapsed rows: branch mid-row so the L hits the small PFP.
            // Tall expanded posts: branch at mid-PFP.
            let y: CGFloat = {
                if h < yBranch + 12 {
                    return max(cornerR + 1, h / 2)
                }
                return min(yBranch, max(cornerR + 1, h))
            }()
            
            ZStack(alignment: .topLeading) {
                switch railStyle {
                case .linear:
                    linearRail(height: h, spineX: x, midY: y)
                case .branch:
                    branchRail(height: h, spineX: x, midY: y)
                case .flatBranch:
                    EmptyView()
                }
            }
        }
    }
    
    /// Straight vertical connector into a single-child chain (no indent, no L).
    /// Into mid-PFP only; the child's bodySpine continues below when it has kids.
    @ViewBuilder
    private func linearRail(height h: CGFloat, spineX x: CGFloat, midY y: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: y))
        }
        .stroke(lineColor, style: StrokeStyle(lineWidth: lineW, lineCap: .square))
        .allowsHitTesting(false)
        
        Color.clear
            .frame(width: hit, height: max(y, hit))
            .padding(.leading, x - hit / 2)
            .contentShape(Rectangle())
            .highPriorityGesture(TapGesture().onEnded(onRailTap))
            .accessibilityLabel(String(localized: "Collapse thread", comment: "A11y: tap tree line"))
    }
    
    /// Classic L-rail into an indented multi-child sibling.
    @ViewBuilder
    private func branchRail(height h: CGFloat, spineX x: CGFloat, midY y: CGFloat) -> some View {
        let endX = max(x + lineW + 4, branchEndX)
        let r = min(cornerR, y - 2, max(0, endX - x - 2))
        // Hit only where ink is drawn. Do not extend past endX into the PFP column.
        let verticalHitHeight = isLastSibling ? max(y, hit) : h
        let horizontalHitWidth = max(0, endX - x)
        
        Path { path in
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: max(0, y - r)))
            
            if r > 0 {
                path.addQuadCurve(
                    to: CGPoint(x: x + r, y: y),
                    control: CGPoint(x: x, y: y)
                )
            }
            
            path.addLine(to: CGPoint(x: endX, y: y))
            
            if !isLastSibling && h > y {
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x, y: h))
            }
        }
        .stroke(lineColor, style: StrokeStyle(lineWidth: lineW, lineCap: .round, lineJoin: .round))
        .allowsHitTesting(false)
        
        // Vertical segment of the L (and continuing spine for non-last siblings).
        Color.clear
            .frame(width: hit, height: verticalHitHeight)
            .padding(.leading, x - hit / 2)
            .contentShape(Rectangle())
            .highPriorityGesture(TapGesture().onEnded(onRailTap))
            .accessibilityLabel(String(localized: "Collapse thread", comment: "A11y: tap tree line"))
        
        // Horizontal arm of the L into this child.
        Color.clear
            .frame(width: horizontalHitWidth, height: hit)
            .padding(.leading, x)
            .padding(.top, max(0, y - hit / 2))
            .contentShape(Rectangle())
            .highPriorityGesture(TapGesture().onEnded(onRailTap))
            .accessibilityHidden(true)
    }
}
