import XCTest
import CoreData
import NostrEssentials
@testable import Nostur

final class GenericRepostTests: XCTestCase {
    func testIncomingKindSurvivesJSONRoundTrip() throws {
        let repost = try signedEvent(kind: 16)
        let decoded = try JSONDecoder().decode(NEvent.self, from: JSONEncoder().encode(repost))
        XCTAssertEqual(decoded.kind, .genericRepost)
        XCTAssertEqual(decoded.kind.id, 16)
        XCTAssertTrue(decoded.kind.isRepost)
        XCTAssertEqual(NEventKind.repost.id, 6)
    }

    func testFeedAndReferenceRequestsIncludeBothRepostKinds() throws {
        for kinds in [FETCH_GLOBAL_KINDS, FETCH_GLOBAL_KINDS_WITH_REPLIES,
                      FETCH_FOLLOWING_FEED_KINDS, FETCH_FOLLOWING_FEED_KINDS_WITH_REPLIES,
                      QUERY_FOLLOWING_KINDS, QUERY_FOLLOWING_KINDS_WITH_REPLIES, PROFILE_KINDS] {
            XCTAssertTrue(kinds.isSuperset(of: [6, 16]))
        }
        let message = RM.getEventReferences(ids: [String(repeating: "a", count: 64)])
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(message.utf8)) as? [Any])
        let filter = try XCTUnwrap(request[2] as? [String: Any])
        let kinds = try XCTUnwrap(filter["kinds"] as? [Int])
        XCTAssertTrue(kinds.contains(6))
        XCTAssertTrue(kinds.contains(16))
    }

    func testGenericRepostLinksAndCountsNonTextPostAndOutgoingStaysKind6() async throws {
        await MainActor.run { _ = AppState.shared; _ = AccountsState.shared }
        for kind in [20, 30023, 34235] {
            let original = try signedEvent(kind: kind)
            let repost = try signedEvent(kind: 16, tags: [["e", original.id], ["p", original.publicKey], ["k", String(kind)]])
            let context = bg()
            try await context.perform {
                let target = Event.fromNEvent(nEvent: original, context: context)
                target.relays = ""
                Importer.shared.existingIds[original.id] = EventState(status: .SAVED)
                let row = Event.fromNEvent(nEvent: repost, context: context)
                defer {
                    Importer.shared.existingIds[original.id] = nil
                    EventCache.shared.removeValue(forKey: original.id)
                    context.delete(row); context.delete(target)
                }
                let embedded = try handleRepost(repost, relays: "wss://relay.example.com", bgContext: context)
                handleRepost(nEvent: repost, savedEvent: row, kind6firstQuote: embedded, context: context)
                XCTAssertEqual(row.kind, 16)
                XCTAssertEqual(row.firstQuoteId, target.id)
                XCTAssertEqual(row.otherPubkey, target.pubkey)
                XCTAssertEqual(target.repostsCount, 1)
                XCTAssertEqual(Event.fetchReposts(id: target.id, context: context).map(\.id), [row.id])
                for embed in [false, true] {
                    let outgoing = EventMessageBuilder.makeRepost(original: target, embedOriginal: embed)
                    XCTAssertEqual(outgoing.kind, .repost)
                    XCTAssertEqual(outgoing.kind.id, 6)
                    XCTAssertEqual(outgoing.firstE(), target.id)
                }
            }
        }
    }

    func testEmbeddedGenericRepostResolvesWithoutETag() async throws {
        await MainActor.run { _ = AppState.shared; _ = AccountsState.shared }
        let original = try signedEvent(kind: 20)
        let repost = try signedEvent(kind: 16, content: original.eventJson(), tags: [["p", original.publicKey], ["k", "20"]])
        let context = DataProvider.shared().newTaskContext()
        try await context.perform {
            let target = try XCTUnwrap(handleRepost(repost, relays: "wss://relay.example.com", bgContext: context))
            let row = Event.fromNEvent(nEvent: repost, context: context)
            defer { context.delete(row); context.delete(target); EventCache.shared.removeValue(forKey: original.id) }
            handleRepost(nEvent: repost, savedEvent: row, kind6firstQuote: target, context: context)
            XCTAssertEqual(row.firstQuoteId, original.id)
            XCTAssertEqual(target.repostsCount, 1)
        }
    }

    func testGenericRepostRejectsInvalidEmbeddedSignature() async throws {
        await MainActor.run { _ = AppState.shared; _ = AccountsState.shared }
        var original = try signedEvent(kind: 20)
        original.content = "tampered"
        let repost = try signedEvent(kind: 16, content: original.eventJson(), tags: [["e", original.id]])
        let context = DataProvider.shared().newTaskContext()
        try await context.perform {
            XCTAssertThrowsError(try handleRepost(repost, relays: "wss://relay.example.com", bgContext: context))
            XCTAssertNil(Event.fetchEvent(id: original.id, context: context))
        }
    }

    func testPreviouslyStoredRepostTargetSurvivesReopeningWithoutRecounting() async throws {
        let original = try signedEvent(kind: 20)
        for tags in [[["e", original.id], ["p", original.publicKey]], [["p", original.publicKey]]] {
            let repost = try signedEvent(kind: 16, content: original.eventJson(), tags: tags)
            let context = DataProvider.shared().newTaskContext()
            let objectID = try await context.perform {
                let row = Event.fromNEvent(nEvent: repost, context: context)
                let target = Event.fromNEvent(nEvent: original, context: context)
                target.repostsCount = 12
                row.relays = ""
                target.relays = ""
                try context.save()
                XCTAssertNil(row.firstQuoteId) // Stored before kind 16 was understood.
                XCTAssertTrue(restoreRepostTarget(row, context: context))
                XCTAssertEqual(row.firstQuoteId, original.id)
                XCTAssertEqual(row.otherPubkey, original.publicKey)
                XCTAssertEqual(target.repostsCount, 12)
                try context.save()
                return row.objectID
            }
            let reopened = DataProvider.shared().newTaskContext()
            try await reopened.perform {
                let row = try XCTUnwrap(reopened.existingObject(with: objectID) as? Nostur.Event)
                XCTAssertEqual(row.firstQuoteId, original.id)
                XCTAssertFalse(restoreRepostTarget(row, context: reopened))
                let request = Event.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", original.id)
                let target = try XCTUnwrap(reopened.fetch(request).first)
                XCTAssertEqual(target.repostsCount, 12)
                reopened.delete(row)
                reopened.delete(target)
                try reopened.save()
            }
        }
    }

    func testRepairDoesNotUseUnverifiedEmbeddedContentOrChangeNonReposts() async throws {
        var original = try signedEvent(kind: 20)
        original.content = "tampered"
        let repost = try signedEvent(kind: 16, content: original.eventJson())
        let note = try signedEvent(kind: 1, tags: [["e", original.id]])
        let context = DataProvider.shared().newTaskContext()
        await context.perform {
            let row = Event.fromNEvent(nEvent: repost, context: context)
            let noteRow = Event.fromNEvent(nEvent: note, context: context)
            defer { context.delete(row); context.delete(noteRow) }
            XCTAssertFalse(restoreRepostTarget(row, context: context))
            XCTAssertNil(row.firstQuoteId)
            XCTAssertFalse(restoreRepostTarget(noteRow, context: context))
            XCTAssertNil(noteRow.firstQuoteId)
        }
    }

    private func signedEvent(kind: Int, content: String = "", tags: [[String]] = []) throws -> NEvent {
        let keys = try Keys.newKeys()
        var event = NEvent(publicKey: keys.publicKeyHex, createdAt: NTimestamp(timestamp: 1_790_000_000),
                           content: content, kind: NEventKind(id: kind), tags: tags.map { Nostur.NostrTag($0) })
        return try event.sign(keys)
    }
}
