//
//  NestedThreadReplies.swift
//  Nostur
//
//  Nested replies with continuous tree rails.
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
            
            ForEach(primaryNodes) { node in
                NestedReplyRow(node: node)
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
                    ForEach(secondaryNodes) { node in
                        NestedReplyRow(node: node)
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
    
    @State private var isCollapsed = false
    
    private var hasChildren: Bool { !node.children.isEmpty }
    
    private var lineColor: Color { theme.lineColor.opacity(0.65) }
    
    private var nestedAvailableWidth: CGFloat {
        max(120, availableWidth - NestedThreadMetrics.cumulativeInset(depth: node.depth))
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
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(node.children.enumerated()), id: \.element.id) { index, child in
                            NestedChildBranch(
                                node: child,
                                isLastSibling: index == node.children.count - 1,
                                lineColor: lineColor,
                                stepInset: NestedThreadMetrics.stepInset(fromParentDepth: node.depth),
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
    
    private func bodySpine(onTap: @escaping () -> Void) -> some View {
        let hit = NestedThreadMetrics.railHitWidth
        let x = NestedThreadMetrics.spineX
        let y0 = NestedThreadMetrics.branchY
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
        let chevron = NestedThreadMetrics.collapsedChevronSize
        // Chevron center sits on spineX so the parent L-rail meets it.
        let leading = NestedThreadMetrics.spineX - chevron / 2
        return Button {
            isCollapsed = false
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: chevron, weight: .semibold))
                    .frame(width: chevron, height: chevron)
                Text(String(localized: "Show thread from \(name) (\(count))", comment: "Expand collapsed reply thread; name and post count"))
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundColor(theme.accent)
            .padding(.leading, leading)
            .padding(.trailing, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Show collapsed reply thread", comment: "A11y"))
    }
}

/// Child under parent: content indented; L-rail in parent coordinates (aligned spine).
/// Rail tap collapses the *parent* (the post this branch hangs from).
///
/// The L-rail is an *overlay* (on top of content). Drawing it in `.background`
/// hides it under `NestedReplyRow`'s opaque `listBackground`. Using
/// `.background(alignment:)` / a leading `GeometryReader` in a sized `ZStack`
/// can also give the rail zero height so nothing is painted.
private struct NestedChildBranch: View {
    let node: NestedReplyNode
    let isLastSibling: Bool
    let lineColor: Color
    let stepInset: CGFloat
    let onRailTap: () -> Void
    
    private var yBranch: CGFloat { NestedThreadMetrics.branchY }
    private var lineW: CGFloat { NestedThreadMetrics.lineWidth }
    private var spineX: CGFloat { NestedThreadMetrics.spineX }
    private var hit: CGFloat { NestedThreadMetrics.railHitWidth }
    private var cornerR: CGFloat { NestedThreadMetrics.cornerRadius }
    
    /// L arm ends at the leading edge of the child spine control
    /// (collapsed chevron / near expanded PFP center).
    private var branchEndX: CGFloat {
        NestedThreadMetrics.branchEndX(stepInset: stepInset)
            - NestedThreadMetrics.collapsedChevronSize / 2
    }
    
    var body: some View {
        NestedReplyRow(node: node)
            .padding(.leading, stepInset)
            .fixedSize(horizontal: false, vertical: true)
            // Plain overlay (no alignment) proposes the full content size to
            // GeometryReader and paints the L *above* the opaque list background.
            .overlay {
                connectingRail
            }
    }
    
    private var connectingRail: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let x = spineX
            // Short collapsed rows: branch mid-row so the L hits the chevron.
            // Tall expanded posts: branch at mid-PFP.
            let y: CGFloat = {
                if h < yBranch + 12 {
                    return max(cornerR + 1, h / 2)
                }
                return min(yBranch, max(cornerR + 1, h))
            }()
            let endX = max(x + lineW + 4, branchEndX)
            let r = min(cornerR, y - 2, max(0, endX - x - 2))
            // Hit only where ink is drawn. A full-height column would steal taps
            // meant for deeper rails that sit further to the right.
            let verticalHitHeight = isLastSibling ? max(y, hit) : h
            let horizontalHitWidth = max(0, endX - x + hit / 2)
            
            ZStack(alignment: .topLeading) {
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
    }
}
