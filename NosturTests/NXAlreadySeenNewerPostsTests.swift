import XCTest
@testable import Nostur

final class NXAlreadySeenNewerPostsTests: XCTestCase {
    func testReturnsOnlyCandidatesNewerThanStaleVisiblePost() {
        let now = Date(timeIntervalSince1970: 10_000)
        let candidates = [
            NXAlreadySeenNewerPostCandidate(id: "newest", createdAt: 9_900),
            NXAlreadySeenNewerPostCandidate(id: "middle", createdAt: 9_800),
            NXAlreadySeenNewerPostCandidate(id: "older", createdAt: 6_000),
        ]

        XCTAssertEqual(
            NXAlreadySeenNewerPosts.candidateIDs(
                from: candidates,
                visibleCreatedAt: [7_000, 6_500],
                now: now
            ),
            ["newest", "middle"]
        )
    }

    func testReturnsNothingWhenNewestVisiblePostIsLessThanThirtyMinutesOld() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertTrue(
            NXAlreadySeenNewerPosts.candidateIDs(
                from: [NXAlreadySeenNewerPostCandidate(id: "new", createdAt: 9_950)],
                visibleCreatedAt: [8_201],
                now: now
            ).isEmpty
        )
    }

    func testReturnsNothingWithoutVisiblePosts() {
        XCTAssertTrue(
            NXAlreadySeenNewerPosts.candidateIDs(
                from: [NXAlreadySeenNewerPostCandidate(id: "new", createdAt: 9_950)],
                visibleCreatedAt: [],
                now: Date(timeIntervalSince1970: 10_000)
            ).isEmpty
        )
    }

    func testExcludesCandidateAlreadyRenderedAsThreadContext() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertEqual(
            NXAlreadySeenNewerPosts.candidateIDs(
                from: [
                    NXAlreadySeenNewerPostCandidate(id: "thread-parent", createdAt: 9_900),
                    NXAlreadySeenNewerPostCandidate(id: "actually-hidden", createdAt: 9_800),
                ],
                visibleCreatedAt: [7_000],
                excludingIDs: ["thread-parent"],
                now: now
            ),
            ["actually-hidden"]
        )
    }
}
