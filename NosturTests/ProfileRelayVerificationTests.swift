import XCTest
import NostrEssentials
@testable import Nostur

final class ProfileRelayVerificationTests: XCTestCase {
    private func metadata(timestamp: Int = 100, kind: NEventKind = .setMetadata) throws -> NEvent {
        let keys = try Keys(privateKeyHex: String(repeating: "0", count: 63) + "1")
        var event = NEvent(publicKey: keys.publicKeyHex, createdAt: NTimestamp(timestamp: timestamp), content: "{\"name\":\"Test\"}", kind: kind)
        return try event.sign(keys)
    }

    func testPublishAcknowledgementAloneDoesNotConfirmRelay() async throws {
        let event = try metadata()
        let transport = ScriptedProfileTransport(event: nil)
        let result = await ProfileRelayVerifier(transport: transport).verify(
            pubkey: event.publicKey, minimumCreatedAt: 100, publishing: [event.eventJson()])
        XCTAssertFalse(result)
        XCTAssertTrue(transport.wasClosed)
        XCTAssertEqual(transport.messageTypes, ["EVENT", "REQ"])
    }

    func testSignedReadBackConfirmsRelayAfterPublishing() async throws {
        let event = try metadata()
        let transport = ScriptedProfileTransport(event: event)
        let result = await ProfileRelayVerifier(transport: transport).verify(
            pubkey: event.publicKey, minimumCreatedAt: 100, publishing: [event.eventJson()])
        XCTAssertTrue(result)
        XCTAssertTrue(transport.wasClosed)
        XCTAssertEqual(transport.messageTypes, ["EVENT", "REQ"])
    }

    func testExistingProfileCanBeVerifiedWithoutRepublishing() async throws {
        let event = try metadata()
        let transport = ScriptedProfileTransport(event: event)
        let result = await ProfileRelayVerifier(transport: transport).verify(pubkey: event.publicKey, minimumCreatedAt: 100)
        XCTAssertTrue(result)
        XCTAssertEqual(transport.messageTypes, ["REQ"])
    }

    func testDuplicateResponseStillRequiresSuccessfulReadBack() async throws {
        let event = try metadata()
        let transport = ScriptedProfileTransport(event: event, accepted: false)
        let result = await ProfileRelayVerifier(transport: transport).verify(
            pubkey: event.publicKey, minimumCreatedAt: 100, publishing: [event.eventJson()])
        XCTAssertTrue(result)
    }

    func testRejectsInvalidSignatureWrongAuthorStaleMetadataAndWrongSubscription() async throws {
        let event = try metadata()
        var invalid = event
        invalid.content = "tampered"
        let wrongKind = try metadata(kind: .textNote)
        for (returned, pubkey, minimum, wrongSubscription) in [
            (invalid, event.publicKey, 100, false),
            (event, String(repeating: "ab", count: 32), 100, false),
            (event, event.publicKey, 101, false),
            (wrongKind, event.publicKey, 100, false),
            (event, event.publicKey, 100, true)
        ] {
            let transport = ScriptedProfileTransport(event: returned, wrongSubscription: wrongSubscription)
            let result = await ProfileRelayVerifier(transport: transport).verify(pubkey: pubkey, minimumCreatedAt: minimum)
            XCTAssertFalse(result)
        }
    }

    func testTimeoutAndCancellationCloseStalledConnections() async throws {
        let event = try metadata()
        let stalled = ScriptedProfileTransport(event: nil, stalled: true)
        let started = Date()
        let timedOut = await ProfileRelayVerifier(transport: stalled).verify(
            pubkey: event.publicKey, minimumCreatedAt: 100, timeoutNanoseconds: 30_000_000)
        XCTAssertFalse(timedOut)
        XCTAssertTrue(stalled.wasClosed)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)

        let cancelled = ScriptedProfileTransport(event: nil, stalled: true)
        let task = Task { await ProfileRelayVerifier(transport: cancelled).verify(pubkey: event.publicKey, minimumCreatedAt: 100) }
        try await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()
        let result = await task.value
        XCTAssertFalse(result)
        XCTAssertTrue(cancelled.wasClosed)
    }

    func testCandidateFanOutIsBoundedAndOnlyConfirmedRelaysAreReturned() async {
        let tracker = VerificationTracker()
        let relays = await ProfileRelayVerification.confirmedRelays((0..<10).map { "relay\($0)" }) { relay in
            await tracker.begin(relay)
            try? await Task.sleep(nanoseconds: 10_000_000)
            await tracker.end()
            return relay == "relay2" || relay == "relay3"
        }
        XCTAssertEqual(relays, ["relay2", "relay3"])
        let maximum = await tracker.maximum
        let tried = await tracker.tried
        XCTAssertLessThanOrEqual(maximum, 2)
        XCTAssertLessThanOrEqual(tried.count, 6)
    }

    @MainActor
    func testImporterQueueSaturationDoesNotBlockSnapshotOrUI() async throws {
        let release = DispatchSemaphore(value: 0)
        let held = expectation(description: "Importer context queue is held")
        let importerContext = bg()
        let holding = Task {
            await importerContext.perform {
                held.fulfill()
                release.wait()
            }
        }
        defer { release.signal(); holding.cancel() }
        await fulfillment(of: [held], timeout: 2)
        let loaded = expectation(description: "Profile snapshot completes while importer queue is held")
        let snapshot = Task { @MainActor in
            _ = await ProfileSharingSnapshot.load(pubkey: String(repeating: "ab", count: 32))
            loaded.fulfill()
        }
        let ui = expectation(description: "Main actor remains available")
        Task { @MainActor in ui.fulfill() }
        await fulfillment(of: [loaded, ui], timeout: 1)
        snapshot.cancel()
    }
}

private actor VerificationTracker {
    var active = 0
    var maximum = 0
    var tried: [String] = []
    func begin(_ relay: String) {
        active += 1
        maximum = max(maximum, active)
        tried.append(relay)
    }
    func end() { active -= 1 }
}

private final class ScriptedProfileTransport: ProfileRelayTransport, @unchecked Sendable {
    private let stream: AsyncThrowingStream<String, Error>
    private let continuation: AsyncThrowingStream<String, Error>.Continuation
    private let event: NEvent?
    private let accepted: Bool
    private let stalled: Bool
    private let wrongSubscription: Bool
    private let lock = NSLock()
    private var types: [String] = []
    private var closed = false
    var messageTypes: [String] { lock.withLock { types } }
    var wasClosed: Bool { lock.withLock { closed } }

    init(event: NEvent?, accepted: Bool = true, stalled: Bool = false, wrongSubscription: Bool = false) {
        var captured: AsyncThrowingStream<String, Error>.Continuation!
        stream = AsyncThrowingStream { captured = $0 }
        continuation = captured
        self.event = event
        self.accepted = accepted
        self.stalled = stalled
        self.wrongSubscription = wrongSubscription
    }

    func send(_ message: String) async throws {
        let array = try JSONSerialization.jsonObject(with: Data(message.utf8)) as! [Any]
        let type = array[0] as! String
        lock.withLock { types.append(type) }
        guard !stalled else { return }
        if type == "EVENT", let object = array[1] as? [String: Any], object["kind"] as? Int == 0 {
            try yield(["OK", object["id"] as! String, accepted, accepted ? "" : "duplicate:"])
        } else if type == "REQ" {
            let subscription = array[1] as! String
            if let event {
                let object = try JSONSerialization.jsonObject(with: Data(event.eventJson().utf8))
                try yield(["EVENT", wrongSubscription ? "unrelated" : subscription, object])
            }
            try yield(["EOSE", subscription])
        }
    }

    func receive() async throws -> String {
        var iterator = stream.makeAsyncIterator()
        guard let value = try await iterator.next() else { throw CancellationError() }
        return value
    }

    func close() {
        lock.withLock { closed = true }
        continuation.finish(throwing: CancellationError())
    }

    private func yield(_ object: [Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        continuation.yield(String(decoding: data, as: UTF8.self))
    }
}
