import XCTest
import NostrEssentials
@testable import Nostur

@MainActor
final class NativeBrowserEventSignerTests: XCTestCase {
    private let fixtureKey = String(repeating: "0", count: 63) + "1"

    private func approval() throws -> BrowserSigningApproval {
        let keys = try Keys(privateKeyHex: fixtureKey)
        let event = BrowserUnsignedEvent(created_at: Int64(Date().timeIntervalSince1970), kind: 1, tags: [], content: "Public test content")
        return try XCTUnwrap(BrowserSigningPolicy.approval(for: event, accountPubkey: keys.publicKeyHex, origin: "https://example.test",
                                                         connected: true, social: true, websiteAuth: false, uploads: false, relaySettings: []))
    }

    func testNativeSignerReturnsOnlyVerifiedPublicEventFields() async throws {
        let approved = try approval()
        let key = fixtureKey
        let signer = NativeBrowserEventSigner(localKeyProvider: { _ in key })
        let result = await withCheckedContinuation { continuation in
            signer.sign(approved, requestID: UUID()) { continuation.resume(returning: $0) }
        }
        let signed = try result.get()
        let data = try JSONEncoder().encode(signed)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["id", "pubkey", "created_at", "kind", "tags", "content", "sig"])
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(fixtureKey))
        XCTAssertTrue(try JSONDecoder().decode(NEvent.self, from: data).verified())
        XCTAssertTrue(signed.matches(approved.event, accountPubkey: approved.accountPubkey))
    }

    func testSignerResponseValidationStripsExtraFieldsAndRejectsChangedEvents() throws {
        let approved = try approval()
        let native = try localSignNEvent(approved.event.nostrEvent(publicKey: approved.accountPubkey), pk: fixtureKey)
        let data = try JSONEncoder().encode(native)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["privateKey"] = fixtureKey
        object["nativeDatabase"] = ["private": "never-return-this"]
        let sanitized = try NativeBrowserEventSigner.validate(JSONSerialization.data(withJSONObject: object), approval: approved)
        let publicJSON = String(decoding: try JSONEncoder().encode(sanitized), as: UTF8.self)
        XCTAssertFalse(publicJSON.contains(fixtureKey))
        XCTAssertFalse(publicJSON.contains("never-return-this"))
        object["content"] = "Changed after authorization"
        XCTAssertThrowsError(try NativeBrowserEventSigner.validate(JSONSerialization.data(withJSONObject: object), approval: approved))
        object["content"] = approved.event.content
        object["sig"] = String(repeating: "0", count: 128)
        XCTAssertThrowsError(try NativeBrowserEventSigner.validate(JSONSerialization.data(withJSONObject: object), approval: approved))
        object["pubkey"] = String(repeating: "b", count: 64)
        XCTAssertThrowsError(try NativeBrowserEventSigner.validate(JSONSerialization.data(withJSONObject: object), approval: approved))
    }

    func testSigningErrorsContainNoKeyOrUnderlyingDiagnostic() async throws {
        let approved = try approval()
        let signer = NativeBrowserEventSigner(localKeyProvider: { _ in "invalid-private-key-sensitive-fixture" })
        let result = await withCheckedContinuation { continuation in
            signer.sign(approved, requestID: UUID()) { continuation.resume(returning: $0) }
        }
        switch result {
        case .failure(.failed): break
        default: XCTFail("An underlying key error must become a fixed failure code")
        }
    }

    func testCancellationReturnsPromptlyWhileSigningQueueIsHeld() async throws {
        let queue = DispatchQueue(label: "test.browser.signing.blocked")
        let started = expectation(description: "Signing queue held")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        queue.async { started.fulfill(); release.wait() }
        await fulfillment(of: [started], timeout: 2)
        let key = fixtureKey
        let signer = NativeBrowserEventSigner(queue: queue, localKeyProvider: { _ in key })
        let id = UUID()
        let callback = expectation(description: "Canceled request must not receive a signature")
        callback.isInverted = true
        signer.sign(try approval(), requestID: id) { _ in callback.fulfill() }
        let canceled = expectation(description: "UI cancellation completes while queue is held")
        Task { @MainActor in signer.cancel(id); canceled.fulfill() }
        await fulfillment(of: [canceled], timeout: 1)
        release.signal()
        let drained = expectation(description: "Signing queue drains")
        queue.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 2)
        await fulfillment(of: [callback], timeout: 0.2)
    }
}
