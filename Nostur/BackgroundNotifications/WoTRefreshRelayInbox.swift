import Foundation
import UIKit
import NostrEssentials

/// Explicit WoT maintenance traffic bypasses the importer. Signature checking
/// and decoding run on a utility worker; UI and relay ingress only access a lock.
final class WoTRefreshRelayInbox: @unchecked Sendable {
    static let shared = WoTRefreshRelayInbox()
    private let lock = NSLock()
    private let worker = DispatchQueue(label: "com.nostur.wot.relay", qos: .utility)
    private let header = try! NSRegularExpression(pattern: "^\\[\\s*\"(EVENT|EOSE|CLOSED)\"\\s*,\\s*\"(wot-night-[a-f0-9-]+)\"")
    private var pending: [String: Request] = [:]

    private final class Request {
        let authors: Set<String>
        let relay: String
        var count = 0
        var bytes = 0
        var result: Result<[String: WoTRefreshContactList], Error>?
        // Worker only.
        var lists: [String: WoTRefreshContactList] = [:]
        init(authors: Set<String>, relay: String) { self.authors = authors; self.relay = relay }
    }

    func fetch(authors: Set<String>, relay: RelayData, account: String) async throws -> [String: WoTRefreshContactList] {
        try await collect(authors: authors, relay: relay.id, send: { id in
            req(RM.getAuthorContactsLists(pubkeys: authors.sorted(), limit: authors.count, subscriptionId: id),
                activeSubscriptionId: id, relays: [relay], accountPubkey: account)
        }, close: { id in
            Task { @MainActor in ConnectionPool.shared.closeSubscription(id) }
        }, shouldContinue: {
            await MainActor.run { UIApplication.shared.applicationState == .background }
        })
    }

    func collect(authors: Set<String>, relay: String, timeout: TimeInterval = 18,
                 send: (String) -> Void, close: (String) -> Void = { _ in },
                 shouldContinue: () async -> Bool = { true }) async throws -> [String: WoTRefreshContactList] {
        let id = "wot-night-" + UUID().uuidString.lowercased()
        register(id, Request(authors: authors, relay: normalizeRelayUrl(relay)))
        defer { remove(id); close(id) }
        try Task.checkCancellation()
        send(id)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            guard await shouldContinue() else { throw CancellationError() }
            if let result = result(for: id) { return try result.get() }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw URLError(.timedOut)
    }

    private func register(_ id: String, _ request: Request) {
        lock.lock(); defer { lock.unlock() }
        pending[id] = request
    }
    private func remove(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        pending.removeValue(forKey: id)
    }
    private func result(for id: String) -> Result<[String: WoTRefreshContactList], Error>? {
        lock.lock(); defer { lock.unlock() }
        return pending[id]?.result
    }
    private func finish(_ id: String, _ result: Result<[String: WoTRefreshContactList], Error>) {
        lock.lock(); defer { lock.unlock() }
        if pending[id]?.result == nil { pending[id]?.result = result }
    }

    @discardableResult
    func route(text: String, relay: String) -> Bool {
        let prefix = String(text.prefix(110)) as NSString
        guard let match = header.firstMatch(in: prefix as String, range: NSRange(location: 0, length: prefix.length)) else { return false }
        let type = prefix.substring(with: match.range(at: 1))
        let id = prefix.substring(with: match.range(at: 2))
        let canonical = normalizeRelayUrl(relay)
        let bytes = text.utf8.count
        lock.lock()
        let request = pending[id]
        var exceedsLimit = bytes > 512_000
        if let request, request.relay == canonical, type == "EVENT" {
            request.count += 1
            request.bytes += bytes
            exceedsLimit = exceedsLimit || request.count > 40 || request.bytes > 4_000_000
        }
        lock.unlock()
        // Swallow late maintenance frames, including after cancellation.
        guard let request, request.relay == canonical else { return true }
        if exceedsLimit { finish(id, .failure(URLError(.dataLengthExceedsMaximum))); return true }
        worker.async { [weak self] in
            guard let self, self.result(for: id) == nil else { return }
            do {
                guard let envelope = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [Any] else { throw URLError(.cannotParseResponse) }
                switch type {
                case "EVENT":
                    guard envelope.count >= 3 else { throw URLError(.cannotParseResponse) }
                    let event = try JSONDecoder().decode(NEvent.self, from: JSONSerialization.data(withJSONObject: envelope[2]))
                    guard event.kind == .contactList, request.authors.contains(event.publicKey), try event.verified() else { throw URLError(.cannotParseResponse) }
                    let list = WoTRefreshContactList(createdAt: event.createdAt.timestamp, follows: Set(event.pTags()))
                    if request.lists[event.publicKey].map({ $0.createdAt < list.createdAt }) ?? true { request.lists[event.publicKey] = list }
                case "EOSE":
                    guard !(envelope.dropFirst(2).first as? [String] ?? []).contains("auth") else { throw URLError(.userAuthenticationRequired) }
                    self.finish(id, .success(request.lists))
                default:
                    throw URLError(.cannotLoadFromNetwork)
                }
            } catch { self.finish(id, .failure(error)) }
        }
        return true
    }
}
