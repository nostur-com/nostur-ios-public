import XCTest
import CoreData
import NostrEssentials
@testable import Nostur

final class PostReactionsTests: XCTestCase {
    func testPartialOrEmptyLocalRowsDoNotEraseKnownCount() {
        XCTAssertEqual(PostReactionsModel.reconciledCount(cached: 35, available: 0), 35)
        XCTAssertEqual(PostReactionsModel.reconciledCount(cached: 35, available: 10), 35)
        XCTAssertEqual(PostReactionsModel.reconciledCount(cached: 35, available: 36), 36)
    }

    func testCompletedFetchRepairsInflatedCountButEmptyOrCappedFetchDoesNot() {
        XCTAssertEqual(PostReactionsModel.reconciledCount(cached: 95, available: 17, finishesFetch: true), 17)
        XCTAssertEqual(PostReactionsModel.reconciledCount(cached: 95, available: 0, finishesFetch: true), 95)
        XCTAssertEqual(PostReactionsModel.reconciledCount(cached: 950, available: 500, finishesFetch: true, capped: true), 950)
        XCTAssertEqual(PostReactionsModel.reconciledCount(cached: 95, available: 17), 95)
    }

    func testOpeningListRequestsOlderHistoryEvenWithRecentLocalRows() throws {
        let request = PostReactionsModel.historyRequest(eventId: "post", subscriptionId: "reactions-test")
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(request.utf8)) as? [Any])
        let filter = try XCTUnwrap(envelope[2] as? [String: Any])
        XCTAssertEqual(filter["#e"] as? [String], ["post"])
        XCTAssertEqual(filter["kinds"] as? [Int], [7])
        XCTAssertEqual(filter["limit"] as? Int, 500)
        XCTAssertNil(filter["since"])
    }

    func testPrunedReactionIsDecodedAgainButExistingRowRemainsDeduplicated() async throws {
        await MainActor.run { _ = AppState.shared; _ = AccountsState.shared }
        let reaction = try signedEvent(kind: 7)
        let eventJSON = String(decoding: try JSONEncoder().encode(reaction), as: UTF8.self)
        let payload = "[\"EVENT\",\"reactions-test\",\(eventJSON)]"
        let context = bg()
        try await context.perform {
            Importer.shared.existingIds[reaction.id] = EventState(status: .SAVED)
            defer {
                Importer.shared.existingIds[reaction.id] = nil
                EventCache.shared.removeValue(forKey: reaction.id)
            }
            let restored = try nxParseRelayMessage(text: payload, relay: "wss://relay.example.com")
            XCTAssertEqual(restored.event?.id, reaction.id)
            XCTAssertTrue(restored.restoredAfterPruning)
            let row = Event.fromNEvent(nEvent: reaction, context: context)
            defer { context.delete(row) }
            Importer.shared.existingIds[reaction.id] = EventState(status: .SAVED)
            XCTAssertThrowsError(try nxParseRelayMessage(text: payload, relay: "wss://relay.example.com")) { error in
                guard case NXRelayMessageError.DUPLICATE_ALREADY_SAVED = error else {
                    XCTFail("Existing reaction should still be deduplicated"); return
                }
            }
        }
    }

    func testRestoredReactionRebuildsRelationWithoutCountingItAgain() async throws {
        let post = try signedEvent(kind: 1)
        let reaction = try signedEvent(kind: 7, tags: [["e", post.id]])
        let context = bg()
        await context.perform {
            let target = Event.fromNEvent(nEvent: post, context: context)
            target.likesCount = 35
            Importer.shared.existingIds[post.id] = EventState(status: .SAVED)
            let row = Event.fromNEvent(nEvent: reaction, context: context)
            defer {
                Importer.shared.existingIds[post.id] = nil
                EventCache.shared.removeValue(forKey: post.id)
                context.delete(row); context.delete(target)
            }
            handleReaction(nEvent: reaction, savedEvent: row, context: context, countReaction: false)
            XCTAssertEqual(row.reactionToId, post.id)
            XCTAssertEqual(target.likesCount, 35)
            handleReaction(nEvent: reaction, savedEvent: row, context: context)
            XCTAssertEqual(target.likesCount, 36)
        }
    }

    @MainActor
    func testOpeningReactionListReturnsPromptlyWhileImporterIsBlocked() async {
        let entered = expectation(description: "importer blocked")
        let gate = DispatchSemaphore(value: 0)
        holdImporter(entered, gate: gate)
        defer { gate.signal() }
        await fulfillment(of: [entered], timeout: 1)
        let model = PostReactionsModel()
        let start = Date()
        model.setup(eventId: UUID().uuidString)
        model.beginFetch()
        model.load(limit: 500)
        XCTAssertTrue(model.isLoading)
        model.markFetchTimedOut()
        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(model.fetchTimedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.1)
        let ui = expectation(description: "UI remains available")
        Task { @MainActor in ui.fulfill() }
        await fulfillment(of: [ui], timeout: 0.5)
    }

    @MainActor
    func testCachedRepostsLoadWhileSharedImporterIsBlocked() async throws {
        _ = AppState.shared
        let target = UUID().uuidString
        let repost = try signedEvent(kind: 6)
        let context = DataProvider.shared().newTaskContext()
        try await context.perform {
            let row = Event.fromNEvent(nEvent: repost, context: context)
            row.firstQuoteId = target
            try context.save()
        }
        let entered = expectation(description: "importer blocked for repost lookup")
        let gate = DispatchSemaphore(value: 0)
        holdImporter(entered, gate: gate)
        await fulfillment(of: [entered], timeout: 1)
        let start = Date()
        let contacts = await PostRepostsLoader.load(id: target, blocked: [repost.publicKey], context: context)
        let elapsed = Date().timeIntervalSince(start)
        gate.signal()
        XCTAssertLessThan(elapsed, 0.5)
        XCTAssertEqual(contacts.blocked.map(\.pubkey), [repost.publicKey])
        XCTAssertTrue(contacts.inWoT.isEmpty)
        try await context.perform {
            let rows = Event.fetchReposts(id: target, context: context)
            rows.forEach { context.delete($0) }
            try context.save()
        }
        NRContactCache.shared.removeValue(forKey: repost.publicKey)
    }

    private func holdImporter(_ entered: XCTestExpectation, gate: DispatchSemaphore) {
        bg().perform { entered.fulfill(); gate.wait() }
    }

    private func signedEvent(kind: Int, tags: [[String]] = []) throws -> NEvent {
        let keys = try Keys.newKeys()
        var event = NEvent(publicKey: keys.publicKeyHex, createdAt: NTimestamp(timestamp: 1_790_000_000),
            content: kind == 7 ? "+" : "post", kind: NEventKind(id: kind), tags: tags.map { Nostur.NostrTag($0) })
        return try event.sign(keys)
    }
}
