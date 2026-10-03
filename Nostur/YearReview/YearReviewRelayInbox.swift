import Foundation
import NostrEssentials

struct YearReviewRelayPage: Sendable {
    let events: [YearReviewEvent]
    let isExhaustive: Bool
    let hasMore: Bool
}

/// Only explicitly registered year-* requests use this sink. Ordinary relay
/// traffic never waits for its utility worker, archive writes, or the importer.
final class YearReviewRelayInbox: @unchecked Sendable {
    static let shared = YearReviewRelayInbox()
    private let lock = NSLock()
    private let worker: DispatchQueue
    private var pending: [String: Pending] = [:]
    private let header = try! NSRegularExpression(pattern: "^\\[\\s*\"(EVENT|EOSE|CLOSED)\"\\s*,\\s*\"(year-[a-f0-9-]+)\"")

    private final class Pending {
        let relay: String
        let completion: (Result<YearReviewRelayPage, Error>) -> Void
        // Reservations under lock; payload decoding and events on worker only.
        var reservedEvents = 0
        var reservedBytes = 0
        var events: [YearReviewEvent] = []
        init(relay: String, completion: @escaping (Result<YearReviewRelayPage, Error>) -> Void) {
            self.relay = normalizeRelayUrl(relay)
            self.completion = completion
        }
    }

    init(worker: DispatchQueue = DispatchQueue(label: "com.nostur.year-review.relay", qos: .utility)) {
        self.worker = worker
    }

    func register(id: String, relay: String, timeout: TimeInterval = 18, completion: @escaping (Result<YearReviewRelayPage, Error>) -> Void) {
        lock.lock()
        pending[id] = Pending(relay: relay, completion: completion)
        lock.unlock()
        // A saturated decoding queue must not delay the network watchdog.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finish(id, .failure(YearReviewError.relay(String(localized: "A relay did not finish responding. You can retry it later."))))
        }
    }

    /// Only reads ingress reservations; never waits for decoding or archive work.
    func receivedCount(_ id: String) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return pending[id]?.reservedEvents
    }

    func cancel(_ id: String) {
        // Remove immediately; an EOSE already queued cannot turn cancellation into success.
        finish(id, .failure(CancellationError()))
    }

    private func finish(_ id: String, _ result: Result<YearReviewRelayPage, Error>) {
        lock.lock()
        let request = pending.removeValue(forKey: id)
        lock.unlock()
        request?.completion(result)
    }

    @discardableResult
    func route(text: String, relay: String) -> Bool {
        // Inspect only the envelope prefix, never the event content, on ingress.
        let prefix = String(text.prefix(110)) as NSString
        guard let match = header.firstMatch(in: prefix as String, range: NSRange(location: 0, length: prefix.length)) else { return false }
        let type = prefix.substring(with: match.range(at: 1))
        let id = prefix.substring(with: match.range(at: 2))
        let canonicalRelay = normalizeRelayUrl(relay)
        let byteCount = text.utf8.count
        lock.lock()
        let request = pending[id]
        var exceedsLimit = byteCount > 768_000
        if let request, request.relay == canonicalRelay, type == "EVENT" {
            request.reservedEvents += 1
            request.reservedBytes += byteCount
            exceedsLimit = request.reservedEvents > 1_000 || request.reservedBytes > 16_000_000 || byteCount > 768_000
        }
        lock.unlock()
        // Late history payloads must not fall through to the live database.
        guard let request, request.relay == canonicalRelay else { return true }
        if exceedsLimit {
            finish(id, .failure(YearReviewError.relay(String(localized: "A relay exceeded the history response limit. This source is incomplete."))))
            return true
        }
        worker.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let active = self.pending[id] === request
            self.lock.unlock()
            guard active else { return }
            do {
                guard let envelope = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [Any], envelope.count >= 2 else {
                    throw YearReviewError.relay(String(localized: "A relay returned an unreadable history response."))
                }
                if type == "EVENT" {
                    guard envelope.count >= 3 else { throw YearReviewError.database("envelope") }
                    let data = try JSONSerialization.data(withJSONObject: envelope[2])
                    let event = try JSONDecoder().decode(YearReviewEvent.self, from: data)
                    request.events.append(event)
                } else if type == "EOSE" {
                    let hints = envelope.count > 2 ? envelope[2] as? [String] ?? [] : []
                    if hints.contains("auth") {
                        self.finish(id, .failure(YearReviewError.relay(String(localized: "This relay requires authentication for more history."))))
                    } else {
                        self.finish(id, .success(YearReviewRelayPage(events: request.events,
                            isExhaustive: hints.contains("finish"), hasMore: hints.contains("more"))))
                    }
                } else {
                    // CLOSED is a failure, even if a few events arrived first.
                    self.finish(id, .failure(YearReviewError.relay(String(localized: "A relay closed the history request. Check its access settings and retry.") + " " + String((envelope.last as? String ?? "").prefix(160)))))
                }
            } catch {
                self.finish(id, .failure(error))
            }
        }
        return true
    }

    @MainActor
    static func request(relay: RelayData, filter: [String: Any], onProgress: (@MainActor (Int) -> Void)? = nil) async throws -> YearReviewRelayPage {
        try Task.checkCancellation()
        guard !DisabledRelaysStore.isDisabled(relay.url), vpnGuardOK() else {
            throw YearReviewError.relay(String(localized: "This relay connection is paused by your relay or VPN settings."))
        }
        let id = "year-" + UUID().uuidString.lowercased()
        let data = try JSONSerialization.data(withJSONObject: ["REQ", id, filter])
        let message = String(decoding: data, as: UTF8.self)
        // ConnectionPool owns/reuses these connections. Do not disconnect a relay
        // that another feature may also use when this one request finishes.
        let connection = ConnectionPool.shared.addEphemeralConnection(relay)
        let progressTask = onProgress.map { update in
            Task { @MainActor in
                var previous = 0
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard !Task.isCancelled else { return }
                    if let count = shared.receivedCount(id), count != previous {
                        previous = count
                        update(count)
                    }
                }
            }
        }
        defer {
            progressTask?.cancel()
            connection.completeReqSubscription(id)
            connection.sendMessage("[\"CLOSE\",\"\(id)\"]")
        }
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                shared.register(id: id, relay: relay.url) { continuation.resume(with: $0) }
                if Task.isCancelled {
                    shared.cancel(id)
                } else {
                    if !connection.isConnected { connection.connect() }
                    connection.sendMessage(message, subscriptionId: id)
                }
            }
        }, onCancel: { shared.cancel(id) })
    }
}
