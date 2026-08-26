import Foundation
import Testing
@testable import Nostur

@Suite("Profile posts loading policy")
struct ProfilePostsLoadingPolicyTests {
    @MainActor
    @Test("Opening a profile does not wait for the importer context")
    func openingDoesNotWaitForImporter() {
        let backgroundWorkStarted = DispatchSemaphore(value: 0)
        let releaseBackgroundWork = DispatchSemaphore(value: 0)

        bg().perform {
            backgroundWorkStarted.signal()
            _ = releaseBackgroundWork.wait(timeout: .now() + 2)
        }
        #expect(backgroundWorkStarted.wait(timeout: .now() + 1) == .success)

        let viewModel = ProfilePostsViewModel(String(repeating: "a", count: 64), type: .articles)
        let startedAt = Date()
        viewModel.load()
        let elapsed = Date().timeIntervalSince(startedAt)

        viewModel.cancel()
        releaseBackgroundWork.signal()
        #expect(elapsed < 0.1)
    }

    @Test("First paint waits for a small validated batch")
    func firstPaintThreshold() {
        #expect(!ProfilePostsLoadingPolicy.shouldReveal(postCount: 0, force: false))
        #expect(!ProfilePostsLoadingPolicy.shouldReveal(postCount: 2, force: false))
        #expect(ProfilePostsLoadingPolicy.shouldReveal(postCount: 3, force: false))
    }

    @Test("Relay completion reveals a sparse profile")
    func forceRevealSparseProfile() {
        #expect(ProfilePostsLoadingPolicy.shouldReveal(postCount: 1, force: true))
    }

    @Test("Cached posts are not revealed without a matching import")
    func noUnvalidatedCacheReveal() {
        #expect(
            ProfilePostsLoadingPolicy.terminalDecision(
                timedOut: false,
                receivedImport: false
            ) == .readyEmpty
        )
        #expect(
            ProfilePostsLoadingPolicy.terminalDecision(
                timedOut: true,
                receivedImport: false
            ) == .timeout
        )
        #expect(
            ProfilePostsLoadingPolicy.terminalDecision(
                timedOut: true,
                receivedImport: true
            ) == .revealImportedPosts
        )
    }

    @Test("Profile requests use bounded preferred-relay fan-out")
    func profileFanOutIsBounded() {
        #expect(usesBoundedPreferredRelayFanOut("prio-PROFILEPOSTS-test"))
        #expect(!usesBoundedPreferredRelayFanOut("PROFILE-test"))
    }

    @Test("Pagination waits for its relay page before supplementing from cache")
    func paginationSequencesCacheAfterRelay() {
        let candidates = ProfilePostsLoadingPolicy.paginationCandidateIds(
            validatedEventIds: ["visible", "relay-page"],
            visibleEventIds: ["visible", "old-bookmark"]
        )

        #expect(candidates == ["relay-page"])
        #expect(!candidates.contains("old-bookmark"))
        #expect(!ProfilePostsLoadingPolicy.shouldIncludeLocalCache(pageCompleted: false))
        #expect(ProfilePostsLoadingPolicy.shouldIncludeLocalCache(pageCompleted: true))
    }
}
