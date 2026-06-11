//  AnonReplyHelper.swift
import Foundation
import NostrEssentials

enum AnonReplyHelper {
    /// Final §0 gate before an anon event leaves the device. True only if signed by the
    /// expected ephemeral key AND that pubkey is not any real-account key.
    static func isAnonSendSafe(signedEvent: NEvent, expectedKeys: Keys, realAccountPubkeys: Set<String>) -> Bool {
        guard signedEvent.publicKey == expectedKeys.publicKeyHex else { return false }
        guard !realAccountPubkeys.contains(signedEvent.publicKey) else { return false }
        return true
    }
}
