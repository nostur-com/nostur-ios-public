import Foundation
import XCTest
@testable import Nostur

@MainActor
final class AudioSessionControllerTests: XCTestCase {
    func testBlockedActivationLeavesMainQueueResponsiveAndDefersPlayback() async throws {
        let entered = expectation(description: "Activation entered")
        let mainResponded = expectation(description: "Main queue responded")
        let release = DispatchSemaphore(value: 0)
        let controller = AudioSessionController { _ in
            XCTAssertFalse(Thread.isMainThread)
            entered.fulfill()
            _ = release.wait(timeout: .now() + 5)
        }
        defer { release.signal() }
        var played = false
        let playback = Task { @MainActor in
            try await controller.prepare(.playback, owner: UUID())
            played = true
        }
        await fulfillment(of: [entered], timeout: 2)
        DispatchQueue.main.async { mainResponded.fulfill() }
        await fulfillment(of: [mainResponded], timeout: 0.5)
        XCTAssertFalse(played, "Playback must wait for activation")
        release.signal()
        try await playback.value
        XCTAssertTrue(played)
    }

    func testPauseDuringActivationPreventsDelayedPlayback() async throws {
        let entered = expectation(description: "Activation entered")
        let release = DispatchSemaphore(value: 0)
        let controller = AudioSessionController { _ in
            entered.fulfill()
            _ = release.wait(timeout: .now() + 5)
        }
        defer { release.signal() }
        let owner = UUID()
        let playback = Task { @MainActor in
            try await controller.prepare(.playback, owner: owner)
        }
        await fulfillment(of: [entered], timeout: 2)
        playback.cancel()
        controller.abandon(owner: owner)
        release.signal()
        do {
            try await playback.value
            XCTFail("Cancelled activation must not authorize playback")
        } catch is CancellationError {
        }
    }

    func testNewPlaybackSupersedesPendingPlayback() async throws {
        let entered = expectation(description: "First activation entered")
        let secondStarted = expectation(description: "Second request started")
        let release = DispatchSemaphore(value: 0)
        // Accessed only on the controller's serial queue.
        var count = 0
        let controller = AudioSessionController { _ in
            count += 1
            if count == 1 {
                entered.fulfill()
                _ = release.wait(timeout: .now() + 5)
            }
        }
        defer { release.signal() }
        let first = Task { try await controller.prepare(.playback, owner: UUID()) }
        await fulfillment(of: [entered], timeout: 2)
        let second = Task {
            secondStarted.fulfill()
            try await controller.prepare(.playback, owner: UUID())
        }
        await fulfillment(of: [secondStarted], timeout: 2)
        release.signal()
        do {
            try await first.value
            XCTFail("Superseded request must not start playback")
        } catch is CancellationError {
        }
        try await second.value
    }

    func testActivationFailureDoesNotAuthorizePlaybackAndCanRetry() async throws {
        enum Failure: Error { case activation }
        var count = 0
        let controller = AudioSessionController { _ in
            count += 1
            if count == 1 { throw Failure.activation }
        }
        do {
            try await controller.prepare(.playback, owner: UUID())
            XCTFail("Activation error must reach the caller")
        } catch Failure.activation {
        }
        try await controller.prepare(.playback, owner: UUID())
    }

    func testRecordingIsProtectedFromDefaultPlaybackAndEffects() async throws {
        let operations = Operations()
        let controller = AudioSessionController { operations.append($0) }
        let recorder = UUID()
        let effect = UUID()
        try await controller.prepare(.recording, owner: recorder)
        try await controller.prepareDefaultPlayback()
        try await controller.prepareEffect(owner: effect)
        do {
            try await controller.prepare(.playback, owner: UUID())
            XCTFail("Playback must not change an ongoing recording's category")
        } catch AudioSessionController.SessionError.recordingInProgress {
        }
        controller.abandon(owner: effect)
        try await controller.deactivate(owner: recorder)
        XCTAssertEqual(operations.values, [.configure(.recording), .activateCurrent, .deactivate])
    }

    func testStaleRecordingCleanupDoesNotDeactivateNewPlayback() async throws {
        let operations = Operations()
        let controller = AudioSessionController { operations.append($0) }
        let recorder = UUID()
        try await controller.prepare(.recording, owner: recorder)
        try await controller.deactivate(owner: recorder)
        try await controller.prepare(.playback, owner: UUID())
        try await controller.deactivate(owner: recorder)
        try await controller.prepareDefaultPlayback()
        XCTAssertEqual(operations.values, [.configure(.recording), .deactivate, .configure(.playback)])
    }

    func testEffectsPreserveMediaCategoryAndActivationIsNotCached() async throws {
        let operations = Operations()
        let controller = AudioSessionController { operations.append($0) }
        try await controller.prepare(.playback, owner: UUID())
        try await controller.prepareEffect(owner: UUID())
        try await controller.prepare(.playback, owner: UUID())
        XCTAssertEqual(operations.values, [.configure(.playback), .activateCurrent, .configure(.playback)])
    }

    func testCancelledRecordingActivationCanStillBeDeactivated() async throws {
        let entered = expectation(description: "Recording activation entered")
        let release = DispatchSemaphore(value: 0)
        let operations = Operations()
        let controller = AudioSessionController { operation in
            XCTAssertFalse(Thread.isMainThread)
            operations.append(operation)
            if operation == .configure(.recording) {
                entered.fulfill()
                _ = release.wait(timeout: .now() + 5)
            }
        }
        defer { release.signal() }
        let owner = UUID()
        let recording = Task { try await controller.prepare(.recording, owner: owner) }
        await fulfillment(of: [entered], timeout: 2)
        recording.cancel()
        release.signal()
        do {
            try await recording.value
            XCTFail("Cancelled recording must not start")
        } catch is CancellationError {
        }
        try await controller.deactivate(owner: owner)
        XCTAssertEqual(operations.values, [.configure(.recording), .deactivate])
    }

    func testRecordingStopDoesNotSilenceAnOngoingEffect() async throws {
        let operations = Operations()
        let controller = AudioSessionController { operations.append($0) }
        let recorder = UUID()
        let effect = UUID()
        try await controller.prepare(.recording, owner: recorder)
        try await controller.prepareEffect(owner: effect)
        try await controller.deactivate(owner: recorder)
        XCTAssertEqual(operations.values, [.configure(.recording), .activateCurrent])
        controller.abandon(owner: effect)
        try await controller.prepare(.playback, owner: UUID())
    }
}

private final class Operations {
    private let lock = NSLock()
    private var storage: [AudioSessionController.Operation] = []

    func append(_ operation: AudioSessionController.Operation) {
        lock.lock()
        storage.append(operation)
        lock.unlock()
    }

    var values: [AudioSessionController.Operation] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
