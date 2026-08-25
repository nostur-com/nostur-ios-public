//
//  NestedReplyWoTPartition.swift
//  Nostur
//
//  Nested reply trees keep parent/child structure, but WoT still applies per post:
//  a reply from someone outside WoT is hidden even when it is a direct child of a
//  trusted root. Out-of-WoT parents of in-WoT replies stay as glue so a trusted
//  reply-to-reply is not promoted out of its thread.
//

import Foundation

enum NestedReplyWoTPartition {
    /// Recursively keep in-WoT nodes, plus out-of-WoT glue that still has in-WoT descendants.
    /// Out-of-WoT-only subtrees (including a not-in-WoT direct reply to a trusted root)
    /// are collected into `more`.
    static func partition<Node>(
        _ nodes: [Node],
        isInWoT: (Node) -> Bool,
        children: (Node) -> [Node],
        replacingChildren: (Node, [Node]) -> Node
    ) -> (main: [Node], more: [Node]) {
        var main: [Node] = []
        var more: [Node] = []
        for node in nodes {
            if containsInWoT(node, isInWoT: isInWoT, children: children) {
                let (kept, pruned) = partition(
                    children(node),
                    isInWoT: isInWoT,
                    children: children,
                    replacingChildren: replacingChildren
                )
                main.append(replacingChildren(node, kept))
                more.append(contentsOf: pruned)
            }
            else {
                more.append(node)
            }
        }
        return (main, more)
    }
    
    /// Nested view lists: never promote the not-WoT bucket into the main list just
    /// because the in-WoT list is empty. Fall back to the classic grouped lists only
    /// when nested data has not been built yet.
    static func displayLists<Node>(
        nestedSorted: [Node],
        nestedNotWoT: [Node],
        groupedSorted: [Node],
        groupedNotWoT: [Node]
    ) -> (primary: [Node], secondary: [Node]) {
        if !nestedSorted.isEmpty || !nestedNotWoT.isEmpty {
            return (nestedSorted, nestedNotWoT)
        }
        return (groupedSorted, groupedNotWoT)
    }
    
    private static func containsInWoT<Node>(
        _ node: Node,
        isInWoT: (Node) -> Bool,
        children: (Node) -> [Node]
    ) -> Bool {
        if isInWoT(node) { return true }
        return children(node).contains {
            containsInWoT($0, isInWoT: isInWoT, children: children)
        }
    }
}
