//
//  NestedReplyWoTPartition.swift
//  Nostur
//
//  Nested reply trees keep parent/child structure while applying WoT to whole
//  conversation paths. Out-of-WoT parents of trusted replies stay as glue. Once
//  a trusted participant replies to an out-of-WoT author, that author's replies
//  further down the same branch remain visible as part of that conversation.
//

import Foundation

enum NestedReplyWoTPartition {
    /// Recursively keep in-WoT nodes, plus out-of-WoT glue that still has in-WoT descendants.
    /// Out-of-WoT-only subtrees (including a not-in-WoT direct reply to a trusted root)
    /// are collected into `more`.
    static func partition<Node>(
        _ nodes: [Node],
        isInWoT: (Node) -> Bool,
        author: (Node) -> String,
        children: (Node) -> [Node],
        replacingChildren: (Node, [Node]) -> Node
    ) -> (main: [Node], more: [Node]) {
        partition(
            nodes,
            engagedAuthors: [],
            parentAuthor: nil,
            isInWoT: isInWoT,
            author: author,
            children: children,
            replacingChildren: replacingChildren
        )
    }

    /// Whether the final node in a root-to-leaf path belongs in the main list.
    /// This is also used by the classic flat thread presentation.
    static func isVisibleLeaf<Node>(
        path: [Node],
        isInWoT: (Node) -> Bool,
        author: (Node) -> String
    ) -> Bool {
        guard let leaf = path.last else { return false }
        var engagedAuthors = Set<String>()
        var previousAuthor: String?

        for node in path {
            if isInWoT(node), let previousAuthor {
                engagedAuthors.insert(previousAuthor)
            }
            previousAuthor = author(node)
        }

        return isInWoT(leaf) || engagedAuthors.contains(author(leaf))
    }

    private static func partition<Node>(
        _ nodes: [Node],
        engagedAuthors: Set<String>,
        parentAuthor: String?,
        isInWoT: (Node) -> Bool,
        author: (Node) -> String,
        children: (Node) -> [Node],
        replacingChildren: (Node, [Node]) -> Node
    ) -> (main: [Node], more: [Node]) {
        var main: [Node] = []
        var more: [Node] = []
        for node in nodes {
            let trusted = isInWoT(node)
            var childEngagedAuthors = engagedAuthors
            if trusted, let parentAuthor {
                childEngagedAuthors.insert(parentAuthor)
            }
            let (kept, pruned) = partition(
                children(node),
                engagedAuthors: childEngagedAuthors,
                parentAuthor: author(node),
                isInWoT: isInWoT,
                author: author,
                children: children,
                replacingChildren: replacingChildren
            )

            if trusted || engagedAuthors.contains(author(node)) || !kept.isEmpty {
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
    
}
