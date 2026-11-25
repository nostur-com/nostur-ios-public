import XCTest
@testable import Nostur

@MainActor
final class PostProofOfWorkOutboxTests: XCTestCase {
    func testPendingPostPreservesFeedContentWithoutInsertingAnUnsignedEvent() async {
        let id = UUID()
        let content = "Read this full post before sending it.\nCheck this second line too."
        let event = NEvent(publicKey: String(repeating: "1", count: 64), content: content, kind: .textNote)

        let preview = await withBgContext { context in
            let post = PostProofOfWorkOutbox.makePreview(event, id: id, replyToID: nil)
            return (post.pendingProofPostID, post.content, post.event?.managedObjectContext == nil,
                    Event.fetchEvent(id: post.id, context: context) == nil)
        }
        XCTAssertEqual(preview.0, id)
        XCTAssertEqual(preview.1, content)
        XCTAssertTrue(preview.2)
        XCTAssertTrue(preview.3)
    }

    func testCountdownDoesNotStartBeforePostIsPresented() {
        let outbox = PostProofOfWorkOutbox(undoWindow: 0)
        var sends = 0
        let id = outbox.enqueue(waitForPreview: true, publish: { _, _ in sends += 1 },
                                restore: { _ in XCTFail("Unexpected draft restoration") }, prepare: { _ in })
        outbox.markReady(NEvent(content: "Ready"), id: id)
        outbox.sendNow(id)
        XCTAssertEqual(sends, 0)
        outbox.startCountdown(id)
        outbox.sendNow(id)
        XCTAssertEqual(sends, 1)
    }

    func testPendingPostIsRevealedInFeedWithoutMarkingOtherPostsRead() async {
        let outbox = PostProofOfWorkOutbox.shared
        let id = outbox.enqueue(waitForPreview: true, publish: { _, _ in XCTFail("Unexpected send") },
                                restore: { _ in }, prepare: { _ in })
        defer { outbox.undo(id) }

        let (pending, existing) = await withBgContext { _ in
            let author = String(repeating: "2", count: 64)
            let pending = PostProofOfWorkOutbox.makePreview(NEvent(publicKey: author, content: "Check this post.", kind: .textNote),
                                                           id: id, replyToID: nil)
            var existingEvent = NEvent(publicKey: author, content: "Already in the feed", kind: .textNote)
            existingEvent = existingEvent.withId()
            let existing = NRPost(event: createPreviewEvent(existingEvent, insertIntoContext: false), withFooter: false)
            return (pending, existing)
        }
        let vm = NXColumnViewModel()
        vm.viewState = .posts([existing])
        vm.vmInner.unreadIds = [existing.id: 1]
        let config = NXColumnConfig(id: "in-feed-undo", name: "In-feed Undo Send")

        vm.putOnScreen([pending], config: config, revealAtTop: true)

        XCTAssertEqual(vm.currentNRPostsOnScreen.map(\.id), [pending.id, existing.id])
        XCTAssertEqual(vm.vmInner.unreadIds, [existing.id: 1])
    }

    func testSendNowWaitsForAReadyEventAndPublishesOnlyOnce() {
        let outbox = PostProofOfWorkOutbox(undoWindow: 60)
        var sent: [String] = []
        let id = outbox.enqueue(publish: { _, event in sent.append(event.content) },
                                restore: { _ in XCTFail("Unexpected draft restoration") }, prepare: { _ in })

        outbox.sendNow(id)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(outbox.posts.first?.status, .preparing)

        outbox.markReady(NEvent(content: "Ready"), id: id)
        XCTAssertEqual(outbox.posts.first?.status, .ready)
        XCTAssertTrue(sent.isEmpty)
        outbox.sendNow(id)
        outbox.sendNow(id)
        XCTAssertEqual(sent, ["Ready"])
        XCTAssertTrue(outbox.posts.isEmpty)
    }

    func testUndoDuringPreparationRestoresDraftAndIgnoresLateCompletion() async {
        let outbox = PostProofOfWorkOutbox(undoWindow: 0)
        let started = expectation(description: "Preparation started")
        var restores = 0
        let id = outbox.enqueue(publish: { _, _ in XCTFail("An undone post was sent") },
                                restore: { _ in restores += 1 }, prepare: { _ in started.fulfill() })
        await fulfillment(of: [started], timeout: 1)
        XCTAssertEqual(outbox.posts.first?.status, .preparing)

        outbox.undo(id)
        outbox.markReady(NEvent(content: "Late result"), id: id)
        outbox.sendNow(id)
        XCTAssertEqual(restores, 1)
        XCTAssertTrue(outbox.posts.isEmpty)
    }

    func testReadyAfterCountdownPublishesAutomatically() {
        let outbox = PostProofOfWorkOutbox(undoWindow: 0)
        var sends = 0
        let id = outbox.enqueue(publish: { _, _ in sends += 1 },
                                restore: { _ in XCTFail("Unexpected draft restoration") }, prepare: { _ in })
        XCTAssertEqual(sends, 0)
        outbox.markReady(NEvent(content: "Ready"), id: id)
        XCTAssertEqual(sends, 1)
        XCTAssertTrue(outbox.posts.isEmpty)
    }
}
