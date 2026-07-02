//
//  DMExpiration.swift
//  Nostur
//
//  NIP-40 message expiration for Direct Messages (NIP-04 & NIP-17).
//
//  Overview:
//  - Users can attach a NIP-40 ["expiration", <unix-seconds>] tag to messages they send,
//    per-message or via a per-conversation device-local "auto-apply" default.
//  - The tag goes on the publicly-visible event: the gift wrap (kind:1059) for NIP-17,
//    the message event itself for NIP-04.
//  - Expiration is immutable after send. Nostur hides + purges expired messages locally,
//    independent of relays (see Maintenance.deleteExpiredDMs / DMConversationVM sweep).
//

import Foundation
import NostrEssentials

// MARK: - Duration math & formatting (pure, testable)

enum DMExpiry {

    /// NIP-17 randomizes the wrap/seal created_at up to ~48h into the past, so a duration
    /// anchored to created_at can land up to ~2 days early. A duration shorter than this
    /// risks being born already-expired, hence a hard 2-day minimum.
    static let minDurationSeconds: Int = 2 * 24 * 3600

    static let sevenDaysSeconds: Int = 7 * 24 * 3600
    static let thirtyDaysSeconds: Int = 30 * 24 * 3600

    /// Strategy A (NIP-40 mental model): the event carries its own lifetime.
    /// `expiration = created_at + duration`. For NIP-17 pass a randomized anchor
    /// (`nip59CreatedAt()`); for NIP-04 pass the real send time. Because the NIP-17 anchor
    /// is in the past, a "7 day" timer can honestly land ~5 days out, hence the "~".
    static func expiresAt(createdAt: Int, durationSeconds: Int) -> Int {
        createdAt + durationSeconds
    }

    static func isValidDuration(_ seconds: Int) -> Bool {
        seconds >= minDurationSeconds
    }

    /// The single expiry rule shared by the display filter, the in-conversation sweep, and the
    /// maintenance purge: an event is expired once `now` reaches its expiration timestamp.
    static func isExpired(expiresAt: Int, now: Int) -> Bool {
        expiresAt <= now
    }

    /// Resolve the duration to apply to a send. A per-message draft (.duration/.off) overrides the
    /// conversation's auto-apply setting. Enforces the 2-day minimum defensively: anything shorter
    /// is treated as "no expiration" rather than shipping an invalid timer.
    static func resolvedDuration(draft: DMDraftExpiry, setting: DMExpirySetting) -> Int? {
        switch draft {
        case .off:
            return nil
        case .duration(let seconds):
            return isValidDuration(seconds) ? seconds : nil
        case .auto:
            guard setting.enabled else { return nil }
            return isValidDuration(setting.durationSeconds) ? setting.durationSeconds : nil
        }
    }

    /// Countdown label for a sent bubble: ">1d → {n}d left", "<1d → {n}h left", "<1h → {n}m left".
    static func countdownLabel(expiresAt: Int, now: Int) -> String {
        // Values are interpolated as String so the localization key uses %@ (not the size-specific %lld).
        let remaining = max(0, expiresAt - now)
        if remaining >= 86_400 {
            let days = String(remaining / 86_400)
            return String(localized: "\(days)d left", comment: "DM expiration countdown in days")
        }
        else if remaining >= 3_600 {
            let hours = String(remaining / 3_600)
            return String(localized: "\(hours)h left", comment: "DM expiration countdown in hours")
        }
        else {
            // Keep at least "1m left" while the message is still alive; the sweep removes it at 0.
            let minutes = String(max(1, remaining / 60))
            return String(localized: "\(minutes)m left", comment: "DM expiration countdown in minutes")
        }
    }

    /// Human label for a duration, used in the composer chip ("~{label}") and info row.
    static func presetLabel(forDuration seconds: Int) -> String {
        // Interpolated as String so the localization key is "%@ days" (not "%lld days").
        let days = String(max(1, seconds / 86_400))
        return String(localized: "\(days) days", comment: "DM expiration duration label, e.g. '7 days'")
    }
}

// MARK: - Per-draft (per-message) expiry override

/// The composer's expiry state for the message being typed. Three distinct states so that an
/// explicit "clear" (the chip ✕ / the sheet's "Off") can override an enabled auto-apply default,
/// which a plain `Int?` could not express (nil would be ambiguous with "use auto-apply").
enum DMDraftExpiry: Equatable {
    case auto              // follow the conversation's auto-apply setting
    case duration(Int)     // an explicit per-message duration
    case off               // explicitly no expiration for this message (overrides auto-apply)
}

// MARK: - Per-conversation device-local setting (never published)

/// Auto-apply expiration setting for one conversation. Device-local, never sent to relays.
struct DMExpirySetting: Codable, Equatable {
    var enabled: Bool
    var durationSeconds: Int
    var label: String

    /// Default: auto-apply off, 7 days pre-selected.
    static let off = DMExpirySetting(enabled: false, durationSeconds: DMExpiry.sevenDaysSeconds, label: "7 days")
}

/// Device-local store for `DMExpirySetting`, keyed by account + conversation id.
/// Backed by `UserDefaults` (never published, never CloudKit-synced).
enum DMExpiryStore {

    // Matches the app's `accountSpecificKey` convention ("as_<pubkey>_<key>").
    private static func storageKey(account: String, conversationId: String) -> String {
        "as_\(account)_dm_expiration_\(conversationId)"
    }

    static func setting(account: String, conversationId: String) -> DMExpirySetting {
        let key = storageKey(account: account, conversationId: conversationId)
        guard let data = UserDefaults.standard.data(forKey: key),
              let setting = try? JSONDecoder().decode(DMExpirySetting.self, from: data)
        else { return .off }
        return setting
    }

    static func save(_ setting: DMExpirySetting, account: String, conversationId: String) {
        let key = storageKey(account: account, conversationId: conversationId)
        if let data = try? JSONEncoder().encode(setting) {
            UserDefaults.standard.setValue(data, forKey: key)
        }
    }
}

// MARK: - Gift wrap with NIP-40 expiration

/// Mirrors `NostrEssentials.createGiftWrap` but adds an `["expiration", <unix>]` tag to the
/// kind:1059 gift wrap so relays and other clients can honor NIP-40. NostrEssentials is a
/// remote package and its `createGiftWrap` doesn't accept extra tags, so we assemble the wrap
/// here from its public primitives. Pass `expiresAt == nil` to build a normal (non-expiring) wrap.
func createGiftWrapWithExpiration(_ rumor: NostrEssentials.Event, receiverPubkey: String, keys: NostrEssentials.Keys, expiresAt: Int?) throws -> NostrEssentials.Event {
    guard let expiresAt else {
        // No expiration → identical to the stock helper.
        return try createGiftWrap(rumor, receiverPubkey: receiverPubkey, keys: keys)
    }

    guard rumor.isRumor() else { throw GiftWrapError.InvalidRumorError }
    guard let oneTimeUseKeys = try? NostrEssentials.Keys.newKeys() else { throw GiftWrapError.OneOffKeyGenerationError }
    guard let seal = try? createSignedSeal(rumor, ourKeys: keys, receiverPubkey: receiverPubkey) else { throw GiftWrapError.SignSealError }
    guard let sealJson = seal.json() else { throw GiftWrapError.EncodeSealError }
    guard let sealJsonEncrypted = NostrEssentials.Keys.encryptDirectMessageContent44(withPrivatekey: oneTimeUseKeys.privateKeyHex, pubkey: receiverPubkey, content: sealJson) else { throw GiftWrapError.EncryptSealError }

    var giftWrap = NostrEssentials.Event(
        pubkey: oneTimeUseKeys.publicKeyHex,
        content: sealJsonEncrypted,
        kind: 1059,
        created_at: nip59CreatedAt(),
        tags: [
            Tag(["p", receiverPubkey]),
            Tag(["expiration", String(expiresAt)])
        ]
    )
    return try giftWrap.sign(oneTimeUseKeys)
}
