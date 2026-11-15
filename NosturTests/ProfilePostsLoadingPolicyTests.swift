import CoreData
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

    @Test("Cold profile relays get a full connection window")
    func coldRelayDeadline() {
        #expect(ProfilePostsLoadingPolicy.connectedRelayDeadline >= 9.0)
        #expect(
            ProfilePostsLoadingPolicy.connectingRelayDeadline
                > ProfilePostsLoadingPolicy.connectedRelayDeadline
        )
    }

    @Test("Relay completion distinguishes an empty response from a timeout")
    func noImportTerminalDecision() {
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

    @Test("Completed profile requests can show newer standalone posts found by Search")
    func completedRequestIncludesCachedStandalonePosts() async throws {
        let context = bg()
        try await context.perform {
            let pubkey = UUID().uuidString
            let olderPost = Event(context: context)
            let newerPost = Event(context: context)
            let reply = Event(context: context)
            let events = [olderPost, newerPost, reply]
            defer { events.forEach(context.delete) }

            for (index, event) in events.enumerated() {
                event.id = UUID().uuidString
                event.pubkey = pubkey
                event.kind = 1
                event.created_at = Int64(index + 1)
            }
            reply.replyToRootId = olderPost.id

            let request = Event.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
            let returnedIds: Set<String> = [olderPost.id, reply.id]

            request.predicate = ProfilePostsLoadingPolicy.standalonePostsPredicate(
                pubkey: pubkey, validatedEventIds: returnedIds, requestCompleted: false
            )
            let initialIds = try context.fetch(request).map(\.id)
            #expect(initialIds == [olderPost.id])

            for validatedIds in [returnedIds, []] {
                request.predicate = ProfilePostsLoadingPolicy.standalonePostsPredicate(
                    pubkey: pubkey, validatedEventIds: validatedIds, requestCompleted: true
                )
                let completedIds = try context.fetch(request).map(\.id)
                #expect(completedIds == [newerPost.id, olderPost.id])
            }
        }
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
