import XCTest
@testable import Nostur

final class NXAlreadySeenNewerPostsTests: XCTestCase {
    @MainActor
    func testExplicitRevealInsertsUnreadPostWhileLatestPrependIsSuppressed() async {
        _ = AppState.shared
        _ = AccountsState.shared
        let posts = await bg().perform {
            ["a", "b"].map { character in
                var event = NEvent(content: "Show again regression \(character)")
                event.id = String(repeating: character, count: 64)
                let preview = createPreviewEvent(event)
                defer { bg().delete(preview) }
                return NRPost(event: preview, withFooter: false)
            }
        }
        let config = NXColumnConfig(id: "show-again-test", name: "Show again test")

        // Exercise each independent gate, as well as both together.
        for (hasUnreadEntry, suppressPrepend) in [(true, false), (false, true), (true, true)] {
            let vm = NXColumnViewModel()
            vm.viewState = .posts([posts[0]])
            vm.latestSuppressPrepend = suppressPrepend
            if hasUnreadEntry {
                vm.vmInner.unreadIds = [posts[1].id: 1]
            }
            var completed = false
            vm.putOnScreen([posts[1]], config: config, revealAtTop: true) {
                completed = true
            }

            guard case .posts(let revealed) = vm.viewState else {
                XCTFail("Reveal must keep the feed visible")
                continue
            }
            XCTAssertEqual(revealed.map(\.id), [posts[1].id, posts[0].id])
            XCTAssertEqual(vm.vmInner.scrollToIndexSubject.value, 0)
            XCTAssertTrue(vm.vmInner.unreadIds.isEmpty)
            XCTAssertTrue(completed)
        }
    }

    @MainActor
    func testShowAgainKeepsRepliesWithMissingParentsWithoutStartingParentFetches() async {
        // Match app startup: these singletons initialize main-context state.
        _ = AppState.shared
        _ = AccountsState.shared
        await bg().perform {
            var event = NEvent(content: "Already seen reply")
            event.id = String(repeating: "d", count: 64)
            let preview = createPreviewEvent(event)
            defer { bg().delete(preview) }
            preview.replyToId = String(repeating: "e", count: 64)
            preview.replyToRootId = String(repeating: "f", count: 64)

            // Exercise both feed settings: neither may strand the reveal waiting
            // for a parent that this relay does not have.
            for repliesEnabled in [false, true] {
                let post = NRPost(event: preview, withFooter: false, withParents: repliesEnabled)
                XCTAssertTrue(post.parentPosts.isEmpty)
                let normal = extractDanglingReplies([post])
                XCTAssertEqual(normal.danglers.map(\.id), [post.id])
                XCTAssertTrue(normal.threads.isEmpty)

                let revealed = extractDanglingReplies([post], revealAtTop: true)
                XCTAssertTrue(revealed.danglers.isEmpty)
                XCTAssertEqual(revealed.threads.map(\.id), [post.id])
            }
        }
    }

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

    func testExcludesRepostWhenItsTargetIsAlreadyInTheFeed() {
        XCTAssertEqual(
            NXAlreadySeenNewerPosts.candidateIDs(
                from: [
                    NXAlreadySeenNewerPostCandidate(id: "repost", createdAt: 9_900, repostedID: "visible"),
                    NXAlreadySeenNewerPostCandidate(id: "hidden", createdAt: 9_800, repostedID: "unseen-target"),
                ],
                visibleCreatedAt: [7_000],
                excludingIDs: ["visible"],
                now: Date(timeIntervalSince1970: 10_000)
            ),
            ["hidden"]
        )
    }
}
