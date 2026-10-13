import Foundation

/// Owned by the connection queue. All deadlines use monotonic uptime.
struct RelaySocketRetryState {
    private var socket: ObjectIdentifier?
    private var openedAt: TimeInterval?
    private var hasResponse = false
    private var failures = 0
    private var retryAt: TimeInterval = 0
    private let healthyInterval: TimeInterval = 30

    mutating func begin(socket: ObjectIdentifier) {
        self.socket = socket
        openedAt = nil
        hasResponse = false
    }

    func isCurrent(socket: ObjectIdentifier) -> Bool {
        self.socket == socket
    }

    mutating func opened(now: TimeInterval) {
        openedAt = now
    }

    mutating func receivedResponse(now: TimeInterval) {
        hasResponse = true
        resetIfHealthy(now: now)
    }

    mutating func resetCooldown() {
        failures = 0
        retryAt = 0
    }

    func remainingCooldown(now: TimeInterval) -> TimeInterval {
        max(0, retryAt - now)
    }

    /// Nil means this socket's failure was already handled, or it was replaced.
    mutating func fail(socket: ObjectIdentifier, now: TimeInterval) -> TimeInterval? {
        guard isCurrent(socket: socket) else { return nil }
        resetIfHealthy(now: now)
        self.socket = nil
        failures = min(failures + 1, 9)
        let delay = min(300, pow(2, Double(failures)))
        retryAt = now + delay
        return delay
    }

    private mutating func resetIfHealthy(now: TimeInterval) {
        guard hasResponse, let openedAt, now - openedAt >= healthyInterval else { return }
        resetCooldown()
    }
}
