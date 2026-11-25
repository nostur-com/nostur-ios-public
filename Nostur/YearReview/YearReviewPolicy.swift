import Foundation

/// History kinds retained in the private archive. Report policy decides whether
/// relay-restricted events are included; gift wraps, DMs and rumors stay excluded.
enum YearReviewKinds {
    static let content: Set<Int> = [1, 20, 21, 22, 1068, 1111, 1222, 1244, 9802, 30023, 34235, 34236]
    static let replies: Set<Int> = [1, 1111, 1244]
    static let support: Set<Int> = [6, 7, 16, 1018, 9735]
    static let archived = content.union(support).union([5])
}

/// Durable cooldowns prevent Resume from immediately retrying a throttled relay.
struct YearReviewRelayPacing: Codable, Equatable, Sendable {
    enum FailureScope: String, Codable, Sendable { case connection, request }
    var nextRequest: [String: Date] = [:]
    var failures: [String: Int] = [:]
    var updatedAt: [String: Date]? = nil
    var failureScopes: [String: FailureScope]? = nil

    func delay(for relay: String, now: Date = .now) -> TimeInterval {
        max(0, nextRequest[relay, default: .distantPast].timeIntervalSince(now))
    }

    mutating func started(_ relay: String, now: Date = .now, jitter: Double = Double.random(in: 0...0.5)) {
        nextRequest[relay] = now.addingTimeInterval(2 + jitter)
        if updatedAt == nil { updatedAt = [:] }
        updatedAt?[relay] = now
    }

    mutating func failed(_ relay: String, now: Date = .now, scope: FailureScope = .request) {
        let count = min(6, failures[relay, default: 0] + 1)
        failures[relay] = count
        nextRequest[relay] = now.addingTimeInterval(min(3_600, 60 * pow(2, Double(count - 1))))
        if updatedAt == nil { updatedAt = [:] }
        updatedAt?[relay] = now
        if failureScopes == nil { failureScopes = [:] }
        failureScopes?[relay] = scope
    }

    mutating func succeeded(_ relay: String, now: Date = .now) {
        failures.removeValue(forKey: relay)
        if updatedAt == nil { updatedAt = [:] }
        updatedAt?[relay] = now
        if failureScopes == nil { failureScopes = [:] }
        failureScopes?[relay] = .request
    }

    func canRecoverConnection(_ relay: String, legacyFailures: [YearReviewSourceFailure]) -> Bool {
        if let scope = failureScopes?[relay] { return scope == .connection }
        // Older checkpoints did not distinguish connection failures from queries.
        // Permit one recovery on a healthy socket unless a saved response explicitly
        // records rate limiting or denied access. A new failure always has a scope.
        return !legacyFailures.contains { failure in
            guard failure.work.relay == relay else { return false }
            return ["rate-limited:", "auth-required:", "restricted:", "blocked:", "invalid:"].contains { failure.reason.contains($0) }
                || failure.reason.range(of: "\\(HTTP 4[0-9]{2}\\)", options: .regularExpression) != nil
        }
    }

    mutating func recoveredConnection(_ relay: String, now: Date = .now) {
        succeeded(relay, now: now)
        nextRequest[relay] = now
    }

    /// Newer success can reset failures without an older parallel save restoring them.
    mutating func merge(_ incoming: Self) {
        for relay in Set(incoming.nextRequest.keys).union(incoming.failures.keys).union(incoming.updatedAt?.keys.map { $0 } ?? []) {
            let incomingDate = incoming.updatedAt?[relay]
            let currentDate = updatedAt?[relay]
            if let incomingDate, incomingDate > (currentDate ?? .distantPast) {
                nextRequest[relay] = incoming.nextRequest[relay]
                failures[relay] = incoming.failures[relay]
                if failureScopes == nil { failureScopes = [:] }
                failureScopes?[relay] = incoming.failureScopes?[relay]
                if updatedAt == nil { updatedAt = [:] }
                updatedAt?[relay] = incomingDate
            } else if incomingDate == currentDate {
                nextRequest[relay] = max(nextRequest[relay, default: .distantPast], incoming.nextRequest[relay, default: .distantPast])
                failures[relay] = max(failures[relay, default: 0], incoming.failures[relay, default: 0])
                if let scope = incoming.failureScopes?[relay] {
                    if failureScopes == nil { failureScopes = [:] }
                    if failureScopes?[relay] == nil || scope == .request { failureScopes?[relay] = scope }
                }
            }
        }
    }
}

/// One small, cached NIP-11 lookup per relay; no retry loop during collection.
actor YearReviewRelayLimits {
    static let shared = YearReviewRelayLimits()
    private var cache: [String: Int] = [:]

    func pageSize(for relay: String) async -> Int {
        if let value = cache[relay] { return value }
        var limit = 500
        if var parts = URLComponents(string: relay) {
            parts.scheme = parts.scheme == "wss" ? "https" : "http"
            if let url = parts.url {
                var request = URLRequest(url: url)
                request.timeoutInterval = 5
                request.setValue("application/nostr+json", forHTTPHeaderField: "Accept")
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if (response as? HTTPURLResponse)?.statusCode == 200 {
                        var data = Data()
                        for try await byte in bytes {
                            guard data.count < 64_000 else { break }
                            data.append(byte)
                        }
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let limitations = json["limitation"] as? [String: Any],
                           let maximum = limitations["max_limit"] as? Int, maximum >= 0 {
                            limit = min(500, maximum)
                        }
                    }
                } catch { /* Ordinary relays need not implement NIP-11. */ }
            }
        }
        cache[relay] = limit
        return limit
    }
}

enum YearReviewRelayAdditionError: Error {
    case invalidURL, disabled, selectionLimit
    @available(iOS 16.0, *)
    var label: LocalizedStringResource {
        switch self {
        case .invalidURL: "Enter a valid ws:// or wss:// relay URL."
        case .disabled: "This relay is disabled in your relay settings. Enable it there first."
        case .selectionLimit: "You can select up to 20 relays. Deselect one before adding another."
        }
    }

    static func validate(_ value: String, selected: Set<String>, disabled: (String) -> Bool) throws -> String {
        guard let url = ScannedProfile.relayHints([value.trimmingCharacters(in: .whitespacesAndNewlines)], limit: 1).first else { throw Self.invalidURL }
        guard !disabled(url) else { throw Self.disabled }
        guard selected.count < 20 || selected.contains(url) else { throw Self.selectionLimit }
        return url
    }
}
