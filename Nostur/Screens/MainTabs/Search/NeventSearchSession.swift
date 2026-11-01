import Foundation
import NostrEssentials

/// A lookup's UI deadline must survive backlog timer resets and queued imports.
/// Only the main actor owns completion; callbacks from an older lookup cannot win.
@MainActor
final class NeventSearchSession {
    enum State: Equatable { case pending, found, timedOut, cancelled }
    private(set) var state: State = .pending
    private var deadline: Task<Void, Never>?

    func start(timeoutNanoseconds: UInt64 = 12_000_000_000, onTimeout: @escaping @MainActor () -> Void) {
        guard state == .pending, deadline == nil else { return }
        deadline = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: timeoutNanoseconds) }
            catch { return }
            guard let self, self.state == .pending else { return }
            self.state = .timedOut
            self.deadline = nil
            onTimeout()
        }
    }

    @discardableResult
    func found() -> Bool {
        guard state == .pending else { return false }
        state = .found
        deadline?.cancel()
        deadline = nil
        return true
    }

    func cancel() {
        state = .cancelled
        deadline?.cancel()
        deadline = nil
    }

    deinit { deadline?.cancel() }
}

struct NeventSearchTarget: Sendable {
    let eventID: String
    let relays: [String]
    let hasRelayHints: Bool

    init?(_ term: String) {
        guard let identifier = try? ShareableIdentifier(term), identifier.prefix == "nevent",
              let eventID = identifier.eventId, eventID.count == 64 else { return nil }
        self.eventID = eventID
        hasRelayHints = !identifier.relays.isEmpty
        // Don't let an unavailable first hint prevent trying the other advertised relays.
        // Keep connection fan-out small even for identifiers containing hundreds of hints.
        var seen = Set<String>()
        relays = Array(identifier.relays.compactMap { value -> String? in
            guard let url = URL(string: value), let host = url.host, !host.isEmpty,
                  ["ws", "wss"].contains(url.scheme?.lowercased() ?? ""),
                  url.user == nil, url.password == nil, url.fragment == nil,
                  !value.contains(where: { $0.isWhitespace }) else { return nil }
            let normalized = normalizeRelayUrl(value)
            return seen.insert(normalized).inserted ? value : nil
        }.prefix(3))
    }
}
