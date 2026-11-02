import Foundation

struct PollRelayResult: Sendable {
    var votes: [PollVote] = []
    var eventJSON: [String] = []
    var complete = false
    var reachedRelay = false
    var nextCursor: PollRelayCursor?
    var hitBoundaryLimit = false
    var failure: PollRelayFailure?
}

/// Poll queries use the existing short-lived relay transport, independently of feed imports.
/// The shared gate bounds connections across every visible poll, not just within one card.
actor PollRelayClient {
    static let shared = PollRelayClient()
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    private func acquire() async {
        if active < 3 { active += 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty { active -= 1 }
        else { waiting.removeFirst().resume() }
    }

    func fetch(poll: NostrPoll, relay: String, author: String?, cursor: PollRelayCursor? = nil,
               authentication: PollRelayAuthentication? = nil) async -> PollRelayResult {
        await acquire()
        defer { release() }
        guard !Task.isCancelled, let url = URL(string: relay) else { return PollRelayResult() }
        return await Self.query(poll: poll, transport: ProfileRelaySocket(url: url), author: author, cursor: cursor,
                                relayURL: relay, authentication: authentication)
    }

    /// An explicit relay OK is required before a vote is reflected in the tally.
    func publish(json: String, eventID: String, relay: String) async -> Bool {
        await acquire()
        defer { release() }
        guard !Task.isCancelled, let url = URL(string: relay) else { return false }
        let transport = ProfileRelaySocket(url: url)
        return await Self.publish(json: json, eventID: eventID, transport: transport)
    }

    static func publish(json: String, eventID: String, transport: any ProfileRelayTransport) async -> Bool {
        let watchdog = Task {
            do { try await Task.sleep(nanoseconds: 8_000_000_000); transport.close() } catch { }
        }
        defer { watchdog.cancel(); transport.close() }
        return await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                try await transport.send("[\"EVENT\",\(json)]")
                for _ in 0..<64 {
                    let message = try await message(transport)
                    if message.count >= 4, message[0] as? String == "OK", message[1] as? String == eventID {
                        return message[2] as? Bool == true
                    }
                }
            } catch { }
            return false
        } onCancel: { transport.close() }
    }

    static func query(poll: NostrPoll, transport: any ProfileRelayTransport, author: String?,
                      pageSize: Int = 250, maxPages: Int = 8, cursor: PollRelayCursor? = nil,
                      relayURL: String? = nil, authentication: PollRelayAuthentication? = nil,
                      timeoutNanoseconds: UInt64? = nil) async -> PollRelayResult {
        let timeout = timeoutNanoseconds ?? (authentication == nil ? 12_000_000_000 : 30_000_000_000)
        let started = DispatchTime.now().uptimeNanoseconds
        let watchdog = Task {
            do { try await Task.sleep(nanoseconds: timeout); transport.close() } catch { }
        }
        defer { watchdog.cancel(); transport.close() }
        return await withTaskCancellationHandler {
            var result = PollRelayResult()
            var until = min(cursor?.until ?? Int.max, poll.endsAt ?? Int.max, Int(Date().timeIntervalSince1970))
            var seen = cursor?.boundaryIDs ?? []
            var challenge: String?
            var authenticated = false
            do {
                for page in 0..<maxPages {
                    try Task.checkCancellation()
                    let subscription = "POLL-" + UUID().uuidString
                    var filter: [String: Any] = ["kinds": [1018], "#e": [poll.id],
                                                "since": poll.createdAt, "until": until, "limit": pageSize]
                    if let author { filter["authors"] = [author] }
                    let data = try JSONSerialization.data(withJSONObject: ["REQ", subscription, filter])
                    let request = String(decoding: data, as: UTF8.self)
                    try await transport.send(request)
                    var received = 0
                    var oldest = until
                    var newEvents = 0
                    var eose = false
                    // Bound even a relay that ignores the filter or never sends EOSE.
                    for _ in 0..<(pageSize * 2 + 64) {
                        try Task.checkCancellation()
                        let response = try await message(transport)
                        if response.first as? String == "AUTH", response.count == 2,
                           let offered = response[1] as? String, offered.utf8.count <= 4096 {
                            challenge = offered
                            continue
                        }
                        guard response.count >= 2, response[1] as? String == subscription else { continue }
                        let closed = response[0] as? String == "CLOSED"
                        let ended = response[0] as? String == "EOSE"
                        let reason = closed && response.count > 2 ? (response[2] as? String ?? "") : ""
                        let authHint = ended && response.count > 2 && (response[2] as? [String] ?? []).contains("auth")
                        if reason.hasPrefix("auth-required:") || authHint {
                            guard let authentication, let relayURL else {
                                throw PollRelayFailure(.authenticationRequired, detail: String(localized: "Enable Auth for this relay and use a signing account.") + (reason.isEmpty ? "" : " " + reason))
                            }
                            guard !authenticated else {
                                throw PollRelayFailure(.authenticationRejected, detail: reason.isEmpty ? String(localized: "The relay still requires authentication after accepting it.") : reason)
                            }
                            try await authenticate(transport: transport, relayURL: relayURL,
                                                   challenge: challenge, using: authentication)
                            authenticated = true
                            received = 0
                            oldest = until
                            newEvents = 0
                            try await transport.send(request)
                            continue
                        }
                        if ended { eose = true; result.reachedRelay = true; break }
                        if closed {
                            throw PollRelayFailure(.requestRejected, detail: reason.isEmpty ? String(localized: "The relay closed the subscription without giving a reason.") : reason)
                        }
                        guard response[0] as? String == "EVENT", response.count == 3,
                              let object = response[2] as? [String: Any] else { continue }
                        received += 1
                        guard let data = try? JSONSerialization.data(withJSONObject: object),
                              let event = try? JSONDecoder().decode(NEvent.self, from: data),
                              event.kind.id == 1018, event.tags.contains(where: { $0.type == "e" && $0.value == poll.id }),
                              author == nil || author == event.publicKey,
                              event.createdAt.timestamp >= poll.createdAt, event.createdAt.timestamp <= until,
                              isHex(event.id, length: 64), isHex(event.publicKey, length: 64),
                              isHex(event.signature ?? "", length: 128),
                              (try? event.verified(logInvalidID: false)) == true else { continue }
                        oldest = min(oldest, event.createdAt.timestamp)
                        if seen.insert(event.id).inserted {
                            result.votes.append(PollVote(event: event))
                            if let json = String(data: data, encoding: .utf8) {
                                result.eventJSON.append(json)
                            }
                            newEvents += 1
                        }
                    }
                    // EOSE already completed this page; cleanup failure must not erase success.
                    try? await transport.send("[\"CLOSE\",\"\(subscription)\"]")
                    guard eose else {
                        result.failure = PollRelayFailure(.responseLimit, detail: String(localized: "Too many messages arrived without the relay completing the request."))
                        return result
                    }
                    if received < pageSize { result.complete = true; return result }
                    // Keep the oldest second inclusive so tied timestamps aren't silently skipped.
                    // A saturated second cannot be paginated with NIP-01; report partial results.
                    guard newEvents > 0 || oldest < until else {
                        result.hitBoundaryLimit = true
                        return result
                    }
                    if page + 1 == maxPages {
                        let boundaryIDs = Set(result.votes.filter { $0.createdAt == oldest }.map(\.id))
                            .union(oldest == cursor?.until ? (cursor?.boundaryIDs ?? []) : [])
                        result.nextCursor = PollRelayCursor(until: oldest, boundaryIDs: boundaryIDs)
                        return result
                    }
                    until = oldest
                }
            } catch {
                if Task.isCancelled {
                    result.failure = PollRelayFailure(.cancelled)
                } else if DispatchTime.now().uptimeNanoseconds - started >= timeout {
                    result.failure = PollRelayFailure(.timedOut, detail: String(localized: "The request did not finish within \(Int(timeout / 1_000_000_000)) seconds."))
                } else if error is CancellationError {
                    result.failure = PollRelayFailure(.cancelled)
                } else if let failure = error as? PollRelayFailure {
                    result.failure = failure
                } else if let urlError = error as? URLError, urlError.code == .timedOut {
                    result.failure = PollRelayFailure(.timedOut, detail: urlError.localizedDescription)
                } else if let urlError = error as? URLError, urlError.code == .cannotParseResponse {
                    result.failure = PollRelayFailure(.invalidResponse)
                } else {
                    result.failure = PollRelayFailure(.connectionFailed, detail: error.localizedDescription)
                }
            }
            return result
        } onCancel: { transport.close() }
    }

    private static func authenticate(transport: any ProfileRelayTransport, relayURL: String,
                                     challenge: String?, using authentication: PollRelayAuthentication) async throws {
        var challenge = challenge
        if challenge == nil {
            for _ in 0..<64 {
                let incoming = try await message(transport)
                if incoming.first as? String == "AUTH", incoming.count == 2,
                   let offered = incoming[1] as? String, offered.utf8.count <= 4096 {
                    challenge = offered
                    break
                }
            }
        }
        guard let challenge else { throw PollRelayFailure(.authenticationRequired, detail: String(localized: "The relay did not supply an authentication challenge.")) }
        try Task.checkCancellation()
        let event = NEvent(publicKey: authentication.publicKey, content: "", kind: .auth,
                           tags: [NostrTag(["relay", relayURL]), NostrTag(["challenge", challenge])])
        let signed: NEvent
        do { signed = try await authentication.sign(event) }
        catch is CancellationError { throw CancellationError() }
        catch { throw PollRelayFailure(.signingFailed, detail: String(localized: "Check that your signer is available, then retry.")) }
        try Task.checkCancellation()
        guard signed.publicKey == event.publicKey, signed.kind == event.kind,
              signed.tags.map(\.tag) == event.tags.map(\.tag), signed.content == event.content,
              signed.createdAt.timestamp == event.createdAt.timestamp,
              (try? signed.verified(logInvalidID: false)) == true else {
            throw PollRelayFailure(.signingFailed, detail: String(localized: "The signer returned an invalid authentication event."))
        }
        try await transport.send("[\"AUTH\",\(signed.eventJson())]")
        for _ in 0..<64 {
            let incoming = try await message(transport)
            if incoming.first as? String == "OK", incoming.count >= 3, incoming[1] as? String == signed.id {
                guard incoming[2] as? Bool == true else {
                    throw PollRelayFailure(.authenticationRejected, detail: incoming.count > 3 ? incoming[3] as? String : nil)
                }
                return
            }
        }
        throw PollRelayFailure(.authenticationRejected, detail: String(localized: "The relay did not acknowledge authentication."))
    }

    private static func isHex(_ value: String, length: Int) -> Bool {
        value.utf8.count == length && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private static func message(_ transport: any ProfileRelayTransport) async throws -> [Any] {
        let text = try await transport.receive()
        guard text.utf8.count <= 262_144,
              let result = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [Any] else {
            throw URLError(.cannotParseResponse)
        }
        return result
    }
}
