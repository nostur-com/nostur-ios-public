import Foundation

/// A direct, short-lived connection. Verification never depends on the importer or its queues.
protocol ProfileRelayTransport: Sendable {
    func send(_ message: String) async throws
    func receive() async throws -> String
    func close()
}

final class ProfileRelaySocket: ProfileRelayTransport, @unchecked Sendable {
    private let session: URLSession
    private let socket: URLSessionWebSocketTask

    init(url: URL) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        session = URLSession(configuration: configuration)
        socket = session.webSocketTask(with: url)
        socket.maximumMessageSize = 262_144
        socket.resume()
    }

    func send(_ message: String) async throws {
        try await socket.send(.string(message))
    }

    func receive() async throws -> String {
        switch try await socket.receive() {
        case .string(let value): return value
        case .data(let data):
            guard let value = String(data: data, encoding: .utf8) else { throw VerificationError.invalidResponse }
            return value
        @unknown default: throw VerificationError.invalidResponse
        }
    }

    func close() {
        socket.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }
}

private enum VerificationError: Error {
    case invalidResponse
}

actor ProfileRelayVerifier {
    private let transport: any ProfileRelayTransport

    init(transport: any ProfileRelayTransport) {
        self.transport = transport
    }

    /// An OK alone is insufficient: the relay must return valid signed kind 0 metadata,
    /// at least as recent as the locally known profile, over this same connection.
    func verify(pubkey: String, minimumCreatedAt: Int?, publishing events: [String] = [], timeoutNanoseconds: UInt64 = 6_000_000_000) async -> Bool {
        let transport = self.transport
        let watchdog = Task {
            do {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                transport.close()
            } catch { }
        }
        defer {
            watchdog.cancel()
            transport.close()
        }
        return await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                if let metadata = events.compactMap(NEvent.fromString).first(where: { $0.kind.id == 0 }) {
                    for event in events { try await transport.send("[\"EVENT\",\(event)]") }
                    // Wait until kind 0 has been processed before querying it back.
                    // A duplicate/rejected response can still be followed by a successful read-back.
                    var acknowledged = false
                    for _ in 0..<64 {
                        let response = try await nextMessage()
                        if response.first as? String == "OK", response.count >= 4,
                           response[1] as? String == metadata.id {
                            acknowledged = true
                            break
                        }
                    }
                    guard acknowledged else { return false }
                }
                try Task.checkCancellation()
                let subscription = "SHARE-VERIFY-" + UUID().uuidString
                let filter: [String: Any] = ["authors": [pubkey], "kinds": [0], "limit": 1]
                let request = try JSONSerialization.data(withJSONObject: ["REQ", subscription, filter])
                try await transport.send(String(decoding: request, as: UTF8.self))
                for _ in 0..<64 {
                    try Task.checkCancellation()
                    let response = try await nextMessage()
                    guard response.count >= 2, response[1] as? String == subscription else { continue }
                    switch response.first as? String {
                    case "EVENT":
                        guard response.count == 3,
                              let dictionary = response[2] as? [String: Any],
                              let data = try? JSONSerialization.data(withJSONObject: dictionary),
                              let event = try? JSONDecoder().decode(NEvent.self, from: data),
                              event.kind.id == 0, event.publicKey == pubkey,
                              let signature = event.signature, signature.count == 128,
                              signature.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                              event.createdAt.timestamp >= (minimumCreatedAt ?? 0),
                              (try? event.verified()) == true else { continue }
                        return true
                    case "EOSE", "CLOSED": return false
                    default: continue
                    }
                }
            } catch { }
            return false
        } onCancel: {
            // Cancelling receive alone may leave a suspended WebSocket read; close it explicitly.
            transport.close()
        }
    }

    private func nextMessage() async throws -> [Any] {
        let message = try await transport.receive()
        guard let data = message.data(using: .utf8), data.count <= 262_144,
              let array = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw VerificationError.invalidResponse
        }
        return array
    }
}

enum ProfileRelayVerification {
    /// At most two connections are active, six candidates are tried, and only two successes are shared.
    static func confirmedRelays(_ candidates: [String], verify: @escaping @Sendable (String) async -> Bool) async -> [String] {
        await withTaskGroup(of: (String, Bool).self) { group in
            let candidates = Array(candidates.prefix(6))
            var next = 0
            var confirmed: [String] = []
            for _ in 0..<min(2, candidates.count) {
                let relay = candidates[next]
                next += 1
                group.addTask { (relay, await verify(relay)) }
            }
            while let (relay, success) = await group.next() {
                guard !Task.isCancelled else { group.cancelAll(); return [] }
                if success { confirmed.append(relay) }
                if confirmed.count == 2 { group.cancelAll(); break }
                if next < candidates.count {
                    let relay = candidates[next]
                    next += 1
                    group.addTask { (relay, await verify(relay)) }
                }
            }
            // Keep the chosen candidates' preference order stable despite completion order.
            return candidates.filter { confirmed.contains($0) }
        }
    }
}

struct ProfileSharingSnapshot: Sendable {
    let advertised: [String]
    let received: [String]
    let events: [String]
    let minimumCreatedAt: Int?

    @MainActor
    static func load(pubkey: String) async -> Self {
        let ctx = DataProvider.shared().newTaskContext()
        return await ctx.perform {
            let metadata = Event.fetchReplacableEvent(0, pubkey: pubkey, context: ctx)
            let relayList = Event.fetchReplacableEvent(10002, pubkey: pubkey, context: ctx)
            return Self(
                advertised: relayList?.fastTags.filter { $0.0 == "r" && ($0.2 == nil || $0.2 == "write") }.map { $0.1 } ?? [],
                received: metadata?.relays.components(separatedBy: " ") ?? [],
                events: [metadata, relayList].compactMap { $0?.toNEvent().eventJson() },
                minimumCreatedAt: metadata.map { Int($0.created_at) }
            )
        }
    }
}
