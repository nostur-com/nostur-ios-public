//  AnonReplySession.swift
//  In-memory only. No persistence. Tracks anon pubkeys created this launch so the user's
//  own anon reply shows a "you · anon" badge during the session.
import Foundation

final class AnonReplySession {
    static let shared = AnonReplySession()
    private let lock = NSLock()
    private var pubkeys: Set<String> = []

    /// bg-context-only mirror for NRPost WoT filters (read on bg). Never read from main.
    public private(set) var bgAnonPubkeys: Set<String> = []

    func register(_ pubkey: String) {
        lock.lock(); pubkeys.insert(pubkey); let snap = pubkeys; lock.unlock()
        bg().perform { [weak self] in self?.bgAnonPubkeys = snap }
    }
    /// Thread-safe membership for main-thread call sites (badge).
    func isAnonPubkey(_ pubkey: String) -> Bool { lock.lock(); defer { lock.unlock() }; return pubkeys.contains(pubkey) }
}
