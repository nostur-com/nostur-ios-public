//
//  DMExpirationTests.swift
//  NosturTests
//
//  Unit tests for NIP-40 DM message expiration:
//  - duration math with a randomized (NIP-17) created_at
//  - the 2-day-minimum enforcement
//  - tag placement per DM type (NIP-04 event vs NIP-17 gift wrap)
//  - the local purge/expiry predicate
//

import Foundation
import Testing
import NostrEssentials
@testable import Nostur

struct DMExpirationTests {

    // MARK: - Duration math (strategy A: expiration = created_at + duration)

    @Test func expiresAt_is_createdAt_plus_duration() {
        let createdAt = 1_700_000_000
        #expect(DMExpiry.expiresAt(createdAt: createdAt, durationSeconds: DMExpiry.sevenDaysSeconds)
                == createdAt + DMExpiry.sevenDaysSeconds)
    }

    @Test func randomized_past_anchor_expires_up_to_two_days_early() {
        // NIP-17 anchors expiration to a created_at up to ~48h in the past, so the countdown at send
        // is shorter than the nominal duration, never longer, and at most ~2 days early.
        let realNow = 1_700_000_000
        let anchorMaxObfuscation = realNow - (2 * 24 * 3600) // 48h in the past
        let expiresAt = DMExpiry.expiresAt(createdAt: anchorMaxObfuscation, durationSeconds: DMExpiry.sevenDaysSeconds)
        let remaining = expiresAt - realNow

        #expect(remaining == DMExpiry.sevenDaysSeconds - 2 * 24 * 3600)          // exactly 5 days here
        #expect(remaining <= DMExpiry.sevenDaysSeconds)                          // never more than nominal
        #expect(remaining >= DMExpiry.sevenDaysSeconds - DMExpiry.minDurationSeconds) // at most 2 days early
    }

    // MARK: - 2-day minimum

    @Test func two_day_minimum_enforced() {
        #expect(DMExpiry.minDurationSeconds == 2 * 24 * 3600)
        #expect(DMExpiry.isValidDuration(2 * 24 * 3600))          // exactly 2 days is allowed
        #expect(!DMExpiry.isValidDuration(2 * 24 * 3600 - 1))     // one second under is not
        #expect(!DMExpiry.isValidDuration(3600))                 // 1 hour is not
        #expect(DMExpiry.isValidDuration(DMExpiry.sevenDaysSeconds))
        #expect(DMExpiry.isValidDuration(DMExpiry.thirtyDaysSeconds))
    }

    @Test func resolved_duration_prefers_draft_and_enforces_minimum() {
        let sevenDayAuto = DMExpirySetting(enabled: true, durationSeconds: DMExpiry.sevenDaysSeconds, label: "7 days")

        // Explicit per-message duration overrides the auto-apply setting.
        #expect(DMExpiry.resolvedDuration(draft: .duration(DMExpiry.thirtyDaysSeconds), setting: sevenDayAuto) == DMExpiry.thirtyDaysSeconds)
        // .auto + auto-apply enabled → the setting's duration.
        #expect(DMExpiry.resolvedDuration(draft: .auto, setting: sevenDayAuto) == DMExpiry.sevenDaysSeconds)
        // .auto + auto-apply disabled → no expiration.
        #expect(DMExpiry.resolvedDuration(draft: .auto, setting: .off) == nil)
        // .off explicitly clears this message even when auto-apply is enabled (chip ✕ / sheet "Off").
        #expect(DMExpiry.resolvedDuration(draft: .off, setting: sevenDayAuto) == nil)
        // A sub-minimum explicit duration is rejected (treated as no expiry).
        #expect(DMExpiry.resolvedDuration(draft: .duration(3600), setting: .off) == nil)
        // A sub-minimum auto-apply setting is rejected too.
        let badAuto = DMExpirySetting(enabled: true, durationSeconds: 3600, label: "bad")
        #expect(DMExpiry.resolvedDuration(draft: .auto, setting: badAuto) == nil)
    }

    // MARK: - Countdown formatting

    @Test func countdown_label_rolls_days_hours_minutes() {
        let now = 1_700_000_000
        #expect(DMExpiry.countdownLabel(expiresAt: now + 29 * 86_400 + 100, now: now) == "29d left")
        #expect(DMExpiry.countdownLabel(expiresAt: now + 86_400, now: now) == "1d left")
        #expect(DMExpiry.countdownLabel(expiresAt: now + 5 * 3_600, now: now) == "5h left")
        #expect(DMExpiry.countdownLabel(expiresAt: now + 30 * 60, now: now) == "30m left")
        #expect(DMExpiry.countdownLabel(expiresAt: now, now: now) == "1m left") // clamped; the sweep removes it at 0
    }

    // MARK: - Tag placement per DM type

    @Test func nip04_places_expiration_on_the_kind4_event() {
        // Mirrors sendMessage04: the tag sits on the (publicly visible) kind-4 event itself.
        let expiresAt = 1_700_600_000
        var nEvent = NEvent(content: "ciphertext")
        nEvent.kind = .legacyDirectMessage
        nEvent.tags.append(NostrTag(["p", String(repeating: "a", count: 64)]))
        nEvent.tags.append(NostrTag(["expiration", String(expiresAt)]))

        #expect(nEvent.kind == .legacyDirectMessage)
        #expect(nEvent.tagNamed("expiration") == String(expiresAt))
    }

    @Test func nip17_places_expiration_on_the_gift_wrap_and_round_trips() throws {
        let sender = try Keys.newKeys()
        let receiver = try Keys.newKeys()

        let inner = NostrEssentials.Event(
            pubkey: sender.publicKeyHex,
            content: "secret",
            kind: 14,
            created_at: 1_700_000_000,
            tags: [Tag(["p", receiver.publicKeyHex])]
        )
        let rumor = createRumor(inner)
        let expiresAt = 1_700_600_000

        let wrap = try createGiftWrapWithExpiration(rumor, receiverPubkey: receiver.publicKeyHex, keys: sender, expiresAt: expiresAt)

        // The publicly visible gift wrap (kind 1059) carries the NIP-40 expiration.
        #expect(wrap.kind == 1059)
        #expect(wrap.tags.first(where: { $0.type == "expiration" })?.value == String(expiresAt))

        // ...and it still decrypts back to the original rumor.
        let (unwrapped, _) = try unwrapGift(wrap, ourKeys: receiver)
        #expect(unwrapped.kind == 14)
        #expect(unwrapped.content == "secret")
    }

    @Test func nip17_without_a_duration_has_no_expiration_tag() throws {
        let sender = try Keys.newKeys()
        let receiver = try Keys.newKeys()
        let inner = NostrEssentials.Event(pubkey: sender.publicKeyHex, content: "hi", kind: 14, created_at: 1_700_000_000, tags: [Tag(["p", receiver.publicKeyHex])])
        let rumor = createRumor(inner)

        let wrap = try createGiftWrapWithExpiration(rumor, receiverPubkey: receiver.publicKeyHex, keys: sender, expiresAt: nil)
        #expect(wrap.kind == 1059)
        #expect(!wrap.tags.contains(where: { $0.type == "expiration" }))
    }

    // MARK: - Local purge / expiry predicate (shared by getMessages, the in-conversation sweep, maintenance)

    @Test func purge_predicate_drops_expired_keeps_live() {
        let now = 1_700_000_000
        #expect(DMExpiry.isExpired(expiresAt: now - 1, now: now))   // past → expired
        #expect(DMExpiry.isExpired(expiresAt: now, now: now))       // exactly now → expired
        #expect(!DMExpiry.isExpired(expiresAt: now + 1, now: now))  // future → live
        #expect(!DMExpiry.isExpired(expiresAt: now + 86_400, now: now))
    }
}
