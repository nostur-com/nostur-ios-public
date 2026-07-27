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
import UIKit

private struct VerticalCollapseModifier: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: 1, y: progress, anchor: .top)
            .opacity(progress)
            .clipped()
    }
}

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
    @Environment(\.colorScheme) private var colorScheme
    
    let node: NestedReplyNode
    /// Hierarchical index for debug (e.g. `"1.3.2"`).
    let path: String
    /// Cumulative branch indent applied to this row (not logical depth).
    let visualInset: CGFloat
    /// Connector style entering this row; roots have no incoming connector.
    var incomingRailStyle: NestedThreadMetrics.RailStyle? = nil
    
    @State private var isCollapsed = false
    @State private var isAnimatingPFP = false
    @State private var animatedPFPIsCollapsed = false
    
    private var hasChildren: Bool { !node.children.isEmpty }

    /// Collapse the surrounding content vertically. The PFP hero is rendered
    /// by the row overlay, outside this transformed subtree.
    private var collapseAnimation: Animation {
        .easeInOut(duration: 0.28)
    }

    private var collapseTransition: AnyTransition {
        .modifier(
            active: VerticalCollapseModifier(progress: 0),
            identity: VerticalCollapseModifier(progress: 1)
        )
    }
    
    private var parentHasMultipleChildren: Bool { node.children.count > 1 }
    
    /// Pre-blend with the known background instead of applying opacity.
    /// This lets adjoining rail segments overlap slightly without producing
    /// a darker/thicker-looking seam where their alpha would accumulate.
    private var lineColor: Color {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let traits = UITraitCollection(userInterfaceStyle: style)
        let foreground = UIColor(theme.lineColor).resolvedColor(with: traits)
        let background = UIColor(theme.listBackground).resolvedColor(with: traits)
        
        var foregroundRed: CGFloat = 0
        var foregroundGreen: CGFloat = 0
        var foregroundBlue: CGFloat = 0
        var foregroundAlpha: CGFloat = 0
        var backgroundRed: CGFloat = 0
        var backgroundGreen: CGFloat = 0
        var backgroundBlue: CGFloat = 0
        var backgroundAlpha: CGFloat = 0
        
        guard foreground.getRed(
            &foregroundRed,
            green: &foregroundGreen,
            blue: &foregroundBlue,
            alpha: &foregroundAlpha
        ), background.getRed(
            &backgroundRed,
            green: &backgroundGreen,
            blue: &backgroundBlue,
            alpha: &backgroundAlpha
        ) else {
            return theme.lineColor
        }
        
        let alpha = foregroundAlpha * 0.65
        return Color(
            red: foregroundRed * alpha + backgroundRed * (1 - alpha),
            green: foregroundGreen * alpha + backgroundGreen * (1 - alpha),
            blue: foregroundBlue * alpha + backgroundBlue * (1 - alpha),
            opacity: 1
        )
    }
    
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
        setCollapsed(true)
    }

    /// Animate one temporary PFP in this row's coordinate space, following the
    /// same explicit scale/position approach used by the fullscreen image hero.
    private func setCollapsed(_ collapsed: Bool) {
        guard collapsed != isCollapsed, !isAnimatingPFP else { return }

        animatedPFPIsCollapsed = isCollapsed
        isAnimatingPFP = true

        // Give SwiftUI one render pass to place the hero at the source frame
        // before changing both the layout and its destination.
        DispatchQueue.main.async {
            withAnimation(collapseAnimation) {
                isCollapsed = collapsed
                animatedPFPIsCollapsed = collapsed
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                isAnimatingPFP = false
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Folded subtree: hide this post + nested; only a show control remains.
            if isCollapsed && hasChildren {
                showThreadRepliesButton
                    .transition(collapseTransition)
            }
            else {
                VStack(alignment: .leading, spacing: 0) {
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
                .transition(collapseTransition)
            }
        }
        .background(theme.listBackground)
        .overlay(alignment: .topLeading) {
            if isAnimatingPFP {
                if case .branch? = incomingRailStyle {
                    animatedBranchConnectorExtension
                }
                animatedPFP
            }
        }
    }
    
    private var postBlock: some View {
        // Keep the Box flush with the children container below it. A VStack
        // spacing here creates a real gap between bodySpine (on the Box) and
        // the incoming rail (on the first child).
        VStack(alignment: .leading, spacing: 0) {
            Box(nrPost: node.nrPost, showGutter: false) {
            PostRowDeletable(
                nrPost: node.nrPost,
                    missingReplyTo: false,
                    connect: nil,
                    fullWidth: false,
                    isDetail: false,
                theme: theme
            )
            .environment(\.nestedReplyPFPHidden, isAnimatingPFP)
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
                    .padding(.top, 2)
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
                    path.move(to: CGPoint(x: x, y: y0+1))
                    path.addLine(to: CGPoint(x: x, y: geo.size.height ))
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
        let pfpColumnWidth = DIMENSIONS.POST_ROW_PFP_DIAMETER
        let collapsedTopPadding = NestedThreadMetrics.branchY - pfpSize / 2
        // Center the smaller PFP in the same column used by regular post PFPs,
        // keeping both the avatar center and the following text aligned.
        // Entire row (PFP + label) expands; no chevron — parent rail hits used to
        // steal chevron taps and collapse the parent instead.
        return Button {
            setCollapsed(false)
        } label: {
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    PFP(
                        pubkey: node.nrPost.pubkey,
                        nrContact: node.nrPost.contact,
                        size: pfpSize
                    )
                    .frame(width: pfpSize, height: pfpSize)
                    .opacity(isAnimatingPFP ? 0 : 1)
                    
                    if NestedThreadMetrics.showPathLabels {
                        pathBadge
                            .scaleEffect(0.85)
                    }
                }
                .frame(width: pfpSize, height: pfpSize)
                .frame(width: pfpColumnWidth, alignment: .center)
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
            .padding(.top, collapsedTopPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Show collapsed reply thread", comment: "A11y"))
        .overlay(alignment: .topLeading) {
            collapsedConnectorExtension
        }
    }

    @ViewBuilder
    private var collapsedConnectorExtension: some View {
        let normalRadius = DIMENSIONS.POST_ROW_PFP_DIAMETER / 2
        let collapsedRadius = NestedThreadMetrics.collapsedPfpSize / 2
        let extensionLength = normalRadius - collapsedRadius
        let centerY = NestedThreadMetrics.branchY

        switch incomingRailStyle {
        case .linear:
            Path { path in
                path.move(to: CGPoint(x: NestedThreadMetrics.spineX, y: centerY - normalRadius))
                path.addLine(to: CGPoint(x: NestedThreadMetrics.spineX, y: centerY - collapsedRadius))
            }
            .stroke(lineColor, style: StrokeStyle(lineWidth: NestedThreadMetrics.lineWidth, lineCap: .butt))
            .allowsHitTesting(false)
        case .branch:
            if !isAnimatingPFP {
                Path { path in
                    path.move(to: CGPoint(x: DIMENSIONS.BOX_PADDING, y: centerY))
                    path.addLine(to: CGPoint(x: DIMENSIONS.BOX_PADDING + extensionLength, y: centerY))
                }
                .stroke(lineColor, style: StrokeStyle(lineWidth: NestedThreadMetrics.lineWidth, lineCap: .square))
                .allowsHitTesting(false)
            }
        case .flatBranch, .none:
            EmptyView()
        }
    }

    private var animatedBranchConnectorExtension: some View {
        let extensionLength = (
            DIMENSIONS.POST_ROW_PFP_DIAMETER - NestedThreadMetrics.collapsedPfpSize
        ) / 2

        return Path { path in
            path.move(to: CGPoint(x: DIMENSIONS.BOX_PADDING, y: NestedThreadMetrics.branchY))
            path.addLine(
                to: CGPoint(
                    x: DIMENSIONS.BOX_PADDING + extensionLength,
                    y: NestedThreadMetrics.branchY
                )
            )
        }
        .trim(from: 0, to: animatedPFPIsCollapsed ? 1 : 0)
        .stroke(
            lineColor,
            style: StrokeStyle(lineWidth: NestedThreadMetrics.lineWidth, lineCap: .square)
        )
        .allowsHitTesting(false)
        .zIndex(9)
    }

    private var animatedPFP: some View {
        let expandedSize = DIMENSIONS.POST_ROW_PFP_DIAMETER
        let collapsedSize = NestedThreadMetrics.collapsedPfpSize
        let centerX = DIMENSIONS.BOX_PADDING + expandedSize / 2
        let centerY = animatedPFPIsCollapsed
            ? NestedThreadMetrics.branchY
            : DIMENSIONS.BOX_PADDING + expandedSize / 2

        return PFP(
            pubkey: node.nrPost.pubkey,
            nrContact: node.nrPost.contact,
            size: expandedSize
        )
        .frame(width: expandedSize, height: expandedSize)
        .scaleEffect(animatedPFPIsCollapsed ? collapsedSize / expandedSize : 1)
        .position(x: centerX, y: centerY)
        .allowsHitTesting(false)
        .zIndex(10)
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
        NestedReplyRow(
            node: node,
            path: path,
            visualInset: visualInset,
            incomingRailStyle: railStyle
        )
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
            // Keep the endpoint fixed at the normal PFP center. The collapsed
            // control uses this same center, so the rail never jumps.
            let y = yBranch
            
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
    /// Stop at the top of the PFP; the child's bodySpine continues below it.
    /// Keep the hit target off the PFP so a collapsed row always receives taps.
    @ViewBuilder
    private func linearRail(height h: CGFloat, spineX x: CGFloat, midY y: CGFloat) -> some View {
        let pfpTopY = max(1, y - DIMENSIONS.POST_ROW_PFP_DIAMETER / 2.0)
        
        Path { path in
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: pfpTopY))
        }
        .stroke(lineColor, style: StrokeStyle(lineWidth: lineW, lineCap: .butt))
        .allowsHitTesting(false)
        
        Color.clear
            .frame(width: hit, height: pfpTopY)
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
        let incomingHeight = max(0, y - r)
        // Hit only where ink is drawn. Do not extend past endX into the PFP column.
        let verticalHitHeight = isLastSibling ? max(y, hit) : h
        let horizontalHitWidth = max(0, endX - x)
        
        Path { path in
            path.move(to: CGPoint(x: x, y: -5))
            path.addLine(to: CGPoint(x: x, y: incomingHeight))
            
            if r > 0 {
                path.addQuadCurve(
                    to: CGPoint(x: x + r, y: y),
                    control: CGPoint(x: x, y: y)
                )
            }
            
            path.addLine(to: CGPoint(x: endX - 1, y: y))
            
            if !isLastSibling && h > y {
                path.move(to: CGPoint(x: x, y: y - 5))
                path.addLine(to: CGPoint(x: x, y: h + 5))
            }
        }
        .stroke(lineColor, style: StrokeStyle(lineWidth: lineW, lineCap: .square, lineJoin: .round))
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
