//  AnonPublisher.swift
//  Isolated, IMMEDIATE publish path for anonymous replies. NEVER uses ConnectionPool's
//  pooled (identified) connections, and NEVER signs a NIP-42 AUTH (the signer throws). Spec §0/§4.
import Foundation
import NostrEssentials

enum AnonSendError: Error { case mustNotSign }
struct AnonPublishResult { let okCount: Int; let attempted: Int; var success: Bool { okCount >= 1 } }

@MainActor
final class AnonPublisher {
    static let shared = AnonPublisher()
    static let fixedRelays: [String] = ["wss://relay.damus.io", "wss://nos.lol", "wss://relay.primal.net"]

    /// Save locally for immediate thread display, then publish to relays in the BACKGROUND.
    /// Returns immediately — does NOT block the caller/UI on relay round-trips. The fixed +
    /// parent-read relay set can take many seconds (slow/unreachable relays hit 8s connect +
    /// 8s publish timeouts); blocking the composer on that is the "stuck sending" bug. The
    /// local save below makes the reply appear in the thread instantly; delivery completes
    /// in the background. Spec §0/§4.
    func publish(signedEvent: NEvent, parentAuthorPubkey: String) {
        // Local-consume for immediate display — save on bg context, notify on main thread.
        // Matches Unpublisher.swift pattern: bgContext.perform { save } → DispatchQueue.main.async { notify }.
        bg().perform {
            let saved = Event.saveEvent(event: signedEvent, context: bg())
            // Do NOT set cancellationId and do NOT mark own — anon posts get no real-account footer.
            DispatchQueue.main.async {
                sendNotification(.newPostSaved, saved)
            }
        }
        // Relay publish in the background — never block the composer on network.
        Task { await self.fire(signedEvent: signedEvent, parentAuthorPubkey: parentAuthorPubkey) }
    }

    @discardableResult
    private func fire(signedEvent: NEvent, parentAuthorPubkey: String) async -> AnonPublishResult {
        let relays = await relayTargets(parentAuthorPubkey: parentAuthorPubkey)
        var okCount = 0
        await withTaskGroup(of: Bool.self) { group in
            for relay in relays {
                group.addTask {
                    do {
                        let pub = try OneOffEventPublisher(relay, allowAuth: false,
                                    signNEventHandler: { _ in throw AnonSendError.mustNotSign })  // never AUTH
                        try await pub.connect(timeout: 8)
                        try await pub.publish(signedEvent, timeout: 8)
                        return true
                    } catch { return false }
                }
            }
            for await ok in group where ok { okCount += 1 }
        }
        let result = AnonPublishResult(okCount: okCount, attempted: relays.count)
        if !result.success { sendNotification(.anyStatus, ("Anon reply may not have been delivered", "NewPost")) }
        return result
    }

    private func relayTargets(parentAuthorPubkey: String) async -> [String] {
        var set = Set(Self.fixedRelays.map { normalizeRelayUrl($0) })
        for r in await parentReadRelays(parentAuthorPubkey) { set.insert(normalizeRelayUrl(r)) }
        return Array(set)
    }

    /// Read kind:10002 directly (getInboxRelays is a `return []` stub). Cap to bound exposure.
    private func parentReadRelays(_ pubkey: String) async -> [String] {
        await withCheckedContinuation { cont in
            bg().perform {
                guard let ev = Event.fetchReplacableEvent(10002, pubkey: pubkey, context: bg()) else {
                    cont.resume(returning: []); return
                }
                let read = ev.fastTags.filter { $0.0 == "r" && ($0.2 == nil || $0.2 == "read") }.map { normalizeRelayUrl($0.1) }
                cont.resume(returning: Array(Set(read).prefix(4)))
            }
        }
    }
}
