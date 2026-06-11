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

    /// Save locally for immediate thread display, then publish immediately. Returns the send result.
    @discardableResult
    func publish(signedEvent: NEvent, parentAuthorPubkey: String) async -> AnonPublishResult {
        // Local-consume for immediate display — notify from INSIDE bg().perform (no bg object to main).
        // Fire-and-forget: Task wraps the perform call so publish() can proceed without awaiting the save.
        Task {
            bg().perform {
                let saved = Event.saveEvent(event: signedEvent, context: bg())
                // Do NOT set cancellationId and do NOT mark own — anon posts get no real-account footer.
                sendNotification(.newPostSaved, saved)
            }
        }
        return await fire(signedEvent: signedEvent, parentAuthorPubkey: parentAuthorPubkey)
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
