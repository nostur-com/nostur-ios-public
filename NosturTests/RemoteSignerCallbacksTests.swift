import XCTest
@testable import Nostur

final class RemoteSignerCallbacksTests: XCTestCase {
    func testCancellationAndDeliveryConsumeCallbackOnlyOnce() {
        let callbacks = RemoteSignerCallbacks()
        callbacks.register("cancelled") { _ in XCTFail("Cancelled callback must not run") }
        XCTAssertNotNil(callbacks.take("cancelled"))
        XCTAssertNil(callbacks.take("cancelled"))
        var delivered = false
        callbacks.register("delivered") { _ in
            // Re-entering the registry proves invocation isn't under its lock.
            callbacks.register("nested") { _ in }
            delivered = true
        }
        callbacks.take("delivered")?(NEvent(content: "test"))
        XCTAssertTrue(delivered)
        XCTAssertNil(callbacks.take("delivered"))
        XCTAssertNotNil(callbacks.take("nested"))
    }

    func testUIRegistrationAndCancellationDoNotWaitForSaturatedBackgroundQueue() async {
        let callbacks = RemoteSignerCallbacks()
        let background = DispatchQueue(label: "test.blocked.signer.delivery")
        let started = expectation(description: "Background delivery queue saturated")
        let completed = expectation(description: "UI callback operations complete while background is blocked")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        background.async {
            started.fulfill()
            release.wait()
        }
        await fulfillment(of: [started], timeout: 2)
        Task { @MainActor in
            callbacks.register("browser-request") { _ in }
            XCTAssertNotNil(callbacks.take("browser-request"))
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 1)
    }
}
