import Foundation
import Testing
@testable import Nostur

@Suite("Relay socket retry lifecycle")
struct RelaySocketRetryStateTests {
    @Test("An opening handshake does not erase consecutive failures")
    func shortLivedConnections() {
        var state = RelaySocketRetryState()
        let sockets = (0..<10).map { _ in NSObject() }
        var now: TimeInterval = 100
        for (index, socket) in sockets.enumerated() {
            let id = ObjectIdentifier(socket)
            state.begin(socket: id)
            state.opened(now: now)
            // A relay can even send a greeting and still immediately fail.
            state.receivedResponse(now: now + 0.1)
            let expected = min(300, pow(2, Double(index + 1)))
            #expect(state.fail(socket: id, now: now + 0.2) == expected)
            #expect(abs(state.remainingCooldown(now: now + 0.2) - expected) < 0.000_001)
            now += expected + 1
        }
    }

    @Test("Receive, send, cancellation and completion failures count once")
    func duplicateCallbacks() {
        var state = RelaySocketRetryState()
        let socket = NSObject()
        let id = ObjectIdentifier(socket)
        state.begin(socket: id)
        #expect(state.fail(socket: id, now: 100) == 2)
        for _ in 0..<5 {
            #expect(state.fail(socket: id, now: 101) == nil)
        }
        #expect(state.remainingCooldown(now: 101) == 1)
        #expect(!state.isCurrent(socket: id))
    }

    @Test("Late callbacks cannot disconnect a replacement socket")
    func replacement() {
        var state = RelaySocketRetryState()
        let old = NSObject()
        let replacement = NSObject()
        state.begin(socket: ObjectIdentifier(old))
        state.begin(socket: ObjectIdentifier(replacement))
        #expect(state.fail(socket: ObjectIdentifier(old), now: 100) == nil)
        #expect(!state.isCurrent(socket: ObjectIdentifier(old)))
        #expect(state.isCurrent(socket: ObjectIdentifier(replacement)))
        #expect(state.remainingCooldown(now: 100) == 0)
    }

    @Test("Cooldown depends on elapsed time, not the number of column requests")
    func elapsedTime() {
        var state = RelaySocketRetryState()
        let socket = NSObject()
        state.begin(socket: ObjectIdentifier(socket))
        #expect(state.fail(socket: ObjectIdentifier(socket), now: 100) == 2)
        for _ in 0..<1_000 {
            #expect(state.remainingCooldown(now: 101) == 1)
        }
        #expect(state.remainingCooldown(now: 102) == 0)
        #expect(state.remainingCooldown(now: 1_000) == 0)
    }

    @Test("Healthy traffic over thirty seconds resets the failure streak")
    func healthyConnection() {
        var state = RelaySocketRetryState()
        let old = NSObject()
        let healthy = NSObject()
        state.begin(socket: ObjectIdentifier(old))
        #expect(state.fail(socket: ObjectIdentifier(old), now: 100) == 2)
        state.begin(socket: ObjectIdentifier(healthy))
        state.opened(now: 102)
        state.receivedResponse(now: 103)
        state.receivedResponse(now: 132)
        #expect(state.fail(socket: ObjectIdentifier(healthy), now: 133) == 2)
    }

    @Test("A silent open socket does not erase the failure streak")
    func silentConnection() {
        var state = RelaySocketRetryState()
        let first = NSObject()
        let silent = NSObject()
        state.begin(socket: ObjectIdentifier(first))
        #expect(state.fail(socket: ObjectIdentifier(first), now: 100) == 2)
        state.begin(socket: ObjectIdentifier(silent))
        state.opened(now: 102)
        #expect(state.fail(socket: ObjectIdentifier(silent), now: 200) == 4)
    }

    @Test("Planned disconnect ignores ensuing cancellation callbacks")
    func plannedDisconnect() {
        var state = RelaySocketRetryState()
        let socket = NSObject()
        state.begin(socket: ObjectIdentifier(socket))
        state = RelaySocketRetryState()
        #expect(state.fail(socket: ObjectIdentifier(socket), now: 100) == nil)
        #expect(state.remainingCooldown(now: 100) == 0)
    }

    @MainActor
    @Test("UI connect returns promptly while the connection queue is held")
    func connectDoesNotWaitForBackgroundQueue() async {
        let queue = DispatchQueue(label: "test-held-relay-queue")
        let connection = RelayConnection(
            RelayData(read: true, write: false, search: false, auth: false, url: "wss://relay.example.invalid", excludedPubkeys: []),
            queue: queue
        )
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
            queue.async {
                started.resume()
                _ = release.wait(timeout: .now() + 5)
            }
        }
        let start = ProcessInfo.processInfo.systemUptime
        connection.connect(reason: "responsiveness regression")
        connection.disconnect() // Cleanup is queued too; no network work is a UI prerequisite.
        #expect(ProcessInfo.processInfo.systemUptime - start < 0.1)
    }
}
