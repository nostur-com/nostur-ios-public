import Testing
@testable import Nostur

struct NestedReplyParentResolutionTests {
    @Test func unavailable_intermediate_parent_is_reported() {
        let missing = NestedReplyParentResolution.missingParentId(
            preferredParentId: "intermediate",
            detailPostId: "detail",
            knownPostIds: ["detail", "descendant"]
        )

        #expect(missing == "intermediate")
    }

    @Test func direct_reply_has_no_missing_parent() {
        let missing = NestedReplyParentResolution.missingParentId(
            preferredParentId: "detail",
            detailPostId: "detail",
            knownPostIds: ["detail"]
        )

        #expect(missing == nil)
    }

    @Test func available_intermediate_parent_has_no_missing_parent() {
        let missing = NestedReplyParentResolution.missingParentId(
            preferredParentId: "intermediate",
            detailPostId: "detail",
            knownPostIds: ["detail", "intermediate", "descendant"]
        )

        #expect(missing == nil)
    }
}
