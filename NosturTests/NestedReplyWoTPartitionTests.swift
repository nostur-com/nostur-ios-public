import Foundation
import Testing
@testable import Nostur

struct NestedReplyWoTPartitionTests {
    private struct Node: Equatable {
        let id: String
        let inWoT: Bool
        var children: [Node] = []
    }
    
    private func partition(_ nodes: [Node]) -> (main: [Node], more: [Node]) {
        NestedReplyWoTPartition.partition(
            nodes,
            isInWoT: { $0.inWoT },
            children: { $0.children },
            replacingChildren: {
                var copy = $0
                copy.children = $1
                return copy
            }
        )
    }
    
    @Test func hidesNotInWoTDirectReplyToTrustedRoot() {
        let tree = [
            Node(id: "trusted-root-reply", inWoT: true),
            Node(id: "spam-direct-reply", inWoT: false)
        ]
        
        let result = partition(tree)
        
        #expect(result.main.map(\.id) == ["trusted-root-reply"])
        #expect(result.more.map(\.id) == ["spam-direct-reply"])
    }
    
    @Test func hidesNotInWoTChildUnderTrustedParent() {
        let tree = [
            Node(id: "trusted", inWoT: true, children: [
                Node(id: "spam-child", inWoT: false),
                Node(id: "trusted-child", inWoT: true)
            ])
        ]
        
        let result = partition(tree)
        
        #expect(result.main.map(\.id) == ["trusted"])
        #expect(result.main[0].children.map(\.id) == ["trusted-child"])
        #expect(result.more.map(\.id) == ["spam-child"])
    }
    
    @Test func keepsOutOfWoTParentWhenSomeoneInWoTReplies() {
        let tree = [
            Node(id: "outside-wot", inWoT: false, children: [
                Node(id: "trusted-reply", inWoT: true)
            ])
        ]
        
        let result = partition(tree)
        
        #expect(result.main.map(\.id) == ["outside-wot"])
        #expect(result.main[0].children.map(\.id) == ["trusted-reply"])
        #expect(result.more.isEmpty)
    }
    
    @Test func prunesOutOfWoTSiblingsFromGlueParent() {
        let tree = [
            Node(id: "outside-wot", inWoT: false, children: [
                Node(id: "trusted-reply", inWoT: true),
                Node(id: "spam-sibling", inWoT: false)
            ])
        ]
        
        let result = partition(tree)
        
        #expect(result.main.map(\.id) == ["outside-wot"])
        #expect(result.main[0].children.map(\.id) == ["trusted-reply"])
        #expect(result.more.map(\.id) == ["spam-sibling"])
    }
    
    @Test func neverPromotesNotWoTIntoPrimaryWhenInWoTListIsEmpty() {
        let lists = NestedReplyWoTPartition.displayLists(
            nestedSorted: [String](),
            nestedNotWoT: ["spam-direct-reply"],
            groupedSorted: ["should-not-use-grouped-in-wot"],
            groupedNotWoT: ["should-not-use-grouped-not-wot"]
        )
        
        #expect(lists.primary.isEmpty)
        #expect(lists.secondary == ["spam-direct-reply"])
    }
    
    @Test func fallsBackToGroupedListsOnlyBeforeNestedDataExists() {
        let lists = NestedReplyWoTPartition.displayLists(
            nestedSorted: [String](),
            nestedNotWoT: [String](),
            groupedSorted: ["grouped-in-wot"],
            groupedNotWoT: ["grouped-not-wot"]
        )
        
        #expect(lists.primary == ["grouped-in-wot"])
        #expect(lists.secondary == ["grouped-not-wot"])
    }
}
