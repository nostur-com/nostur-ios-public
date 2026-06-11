# Anonymous (Ephemeral-Key) Replies Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Revision 2 (2026-06-11):** Corrected after a second adversarial pass that reviewed this plan against the real codebase. Five blockers and several majors were confirmed and fixed inline: the `OneOffEventPublisher` unsolicited-AUTH leak, the `activeAccount` guard in `buildFinalEvent`, the PostPreview real-account leak, the missing undo-data plumbing, the undeclared delete notification, a `bgAnonPubkeys` data race, a tautological §0 assertion, the stubbed read-relay API, the private-post anon-item leak, and the missing composer-repurpose reset. Every code block below reflects the **verified** current source.

**Goal:** Let a user reply in a thread under a freshly generated, per-thread ephemeral key instead of one of their accounts, with the anon identity persisted device-locally so they can continue or delete it later.

**Architecture:** A fully isolated anon send path that never reads `activeAccount`. A device-local keychain store (`EphemeralKeyStore`) maps a per-thread *root scope id* to a keypair. Anon events are built by the existing `buildFinalEvent` made anon-aware (correct reply tags, no client tag, no emoji tags, no relay hints, no NIP-70 protected tag), signed locally, and published over `OneOffEventPublisher` (a brand-new websocket per relay, with a **hard-throwing** AUTH signer so no NIP-42 AUTH is ever emitted) to a fixed relay set plus the parent author's NIP-65 read relays. A pre-publish assertion proves the signed event's pubkey is the ephemeral key AND is not any real-account key. Thread-ownership gates additionally consult the anon pubkey set so the user's own anon replies render as "mine" with delete/forget actions.

**Tech Stack:** Swift, SwiftUI, NostrEssentials (`Keys`, `NEvent`), KeychainAccess, Swift Testing (`import Testing`, `@Test`, `#expect`), Core Data.

**Spec:** `docs/superpowers/specs/2026-06-10-anon-replies-design.md` — read it before starting. The non-negotiable invariant is spec §0: nothing on the anon path may sign with, authenticate as, persist under, or publish over a connection associated with the real account.

**Build/test commands:**
- Build: `xcodebuild -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
- Test: `xcodebuild test -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 16 Pro (18.5),OS=18.5' -only-testing:NosturTests/<TestType>`

---

## Verified codebase facts (confirmed against source 2026-06-11)

These are the ground-truth signatures the plan depends on. Confirmed present:
- `NewPostModel.swift:779-781`: `guard var nEvent = self.nEvent else { return nil }` / `guard let account = activeAccount else { return nil }` / `let publicKey = account.publicKey`. `self.nEvent` (`:165`) defaults to nil and is only set in `loadReplyTo` (`:1577`).
- `NewPostModel.swift:1025-1035` emoji-tag block; `:1037-1041` NIP-70 `["-"]` protected-tag block (appended when `Drafts.shared.lockToThisRelay != nil && lockToSingleRelay`); `:1047-1049` client-tag block.
- NIP-22 reply tags add relay hints via `resolveRelayHint(forPubkey:receivedFromRelays:)` in `addRootScopeTags`/`addReplyToTags` (`~1894-1965`).
- `OneOffEventPublisher.swift:194-204`: `case .AUTH:` calls `sendAuthResponse()` **with no `allowAuth` guard**; `:262-281` `sendAuthResponse` calls `signNEventHandler(...)` then sends an AUTH message; `:369` is the only `allowAuth` guard (OK/auth-required path only). The `.AUTH` call is wrapped in `do { try await sendAuthResponse() } catch { L.og.debug(...) }`, so a **throwing** `signNEventHandler` aborts the AUTH cleanly with nothing sent.
- `Nostr.swift:380` `mutating func sign(_ keys: Keys) throws -> NEvent` sets the event's `publicKey` from the keys (so a post-sign `pubkey == thoseKeys` check is tautological — see Task 5).
- `OutboxLoader.swift:280-288` `getInboxRelays(forPubkey:)` computes read relays then **`return []`** (stub) — do not depend on it; read kind:10002 directly.
- `Event.fetchReplacableEvent(10002, pubkey:context:)` exists and returns the kind:10002 `Event?`; `event.fastTags` are `(String, String, String?, ...)` tuples.
- `ViewUpdates.shared.updateNRPost` is a `PassthroughSubject<Event, Never>` (`_Temp/ViewUpdates.swift:41`); sending an `Event` on it updates that post's `NRPost.ownPostAttributes` (subscription in `NRPost.swift`). `OwnPostFooter.swift:175` already uses it. This is how an anon post gets a live `cancellationId` for the undo footer.
- `Notifications.swift:109` declares `.requestDeletePost`. `.requestDeleteAnonPost` does **not** exist and must be declared.
- `Event.cancellationId` is a transient in-memory `var` (`Event+CoreDataClass.swift:21`), not persisted.
- `normalizeRelayUrl(_)`, `bg()` (background `NSManagedObjectContext`), `sendNotification(_,_)`, `NEventKind.delete`, `NTimestamp(date:)`, `NostrTag` `.type`/`.tag`/`[safe:]`, `Keys.newKeys()`/`Keys(privateKeyHex:)`/`.publicKeyHex`/`.privateKeyHex` all confirmed.

---

## Phase ordering and scope

- **Phase 1 — Foundation:** `EphemeralKeyStore`, `SendIdentity`, root-scope helper (pure logic, full TDD).
- **Phase 2 — Event building:** anon-aware `buildFinalEvent` + strengthened pre-publish assertion (TDD).
- **Phase 3 — Transport:** `AnonPublisher` (isolated send, throwing AUTH signer, OK threshold, 9s undo, registry for undo data, `publishRaw` for deletes).
- **Phase 4 — Composer UI:** switcher anon item (reply-only, not on private posts), private-reply mutual exclusion, media/emoji hard-block, draft isolation, single send dispatcher.
- **Phase 5 — Thread integration:** ownership gates, "you (anon)" indicator, anon delete, forget identity, mentions self-exclusion.
- **Phase 6 — Explainer + wiring:** first-use alert, startup load, composer-repurpose reset.
- **Phase 7 — 🔒 Gate 3:** realistic-relay smoke (human-in-the-loop, pre-merge).

Each phase ends in a buildable, committable state.

---

## Phase 1 — Foundation

### Task 1: Root scope resolution helper

The per-thread key is keyed by a stable "root scope id" derived from the reply's tags. Kind:1 replies carry a NIP-10 marked `root` `e`-tag; NIP-22 replies (kind 1111/1244) carry an uppercase `E`/`A`/`I` root scope tag. This helper derives one canonical string from a built event's tags, used both for key lookup and for the pre-publish assertion.

**Files:**
- Create: `Nostur/Post/PostComposer/Anon/AnonReplyHelper.swift`
- Test: `NosturTests/AnonReplyHelperTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Nostur

struct AnonReplyHelperTests {

    private func event(tags: [[String]]) -> NEvent {
        var e = NEvent(content: "hi")
        e.tags = tags.map { NostrTag($0) }
        return e
    }

    @Test func nip10_marked_root_etag() {
        let e = event(tags: [
            ["e", "ROOT123", "", "root"],
            ["e", "PARENT456", "", "reply"],
            ["p", "abc"]
        ])
        #expect(AnonReplyHelper.rootScopeId(fromTags: e.tags) == "E:ROOT123")
    }

    @Test func nip10_single_etag_direct_reply_to_root() {
        let e = event(tags: [["e", "ROOT123", "", "root"]])
        #expect(AnonReplyHelper.rootScopeId(fromTags: e.tags) == "E:ROOT123")
    }

    @Test func nip22_uppercase_E_root() {
        let e = event(tags: [
            ["E", "ROOTEVENT", "wss://relay", "pub"],
            ["e", "PARENT", "", "pub"],
            ["K", "1"]
        ])
        #expect(AnonReplyHelper.rootScopeId(fromTags: e.tags) == "E:ROOTEVENT")
    }

    @Test func nip22_uppercase_A_coordinate_root() {
        let e = event(tags: [
            ["A", "30023:pubkeyhex:my-article", "wss://relay", "pub"],
            ["e", "PARENT"]
        ])
        #expect(AnonReplyHelper.rootScopeId(fromTags: e.tags) == "A:30023:pubkeyhex:my-article")
    }

    @Test func nip22_uppercase_I_external_root() {
        let e = event(tags: [
            ["I", "https://example.com/thread"],
            ["e", "PARENT"]
        ])
        #expect(AnonReplyHelper.rootScopeId(fromTags: e.tags) == "I:https://example.com/thread")
    }

    @Test func returns_nil_when_no_reply_tags() {
        let e = event(tags: [["p", "abc"]])
        #expect(AnonReplyHelper.rootScopeId(fromTags: e.tags) == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 16 Pro (18.5),OS=18.5' -only-testing:NosturTests/AnonReplyHelperTests`
Expected: FAIL — `AnonReplyHelper` is not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
//  AnonReplyHelper.swift
//  Nostur
//
//  Root-scope resolution + the §0 pre-publish safety gate for anonymous replies.

import Foundation
import NostrEssentials

enum AnonReplyHelper {

    /// Derive the canonical per-thread root scope id from a (built) event's tags.
    /// Order matches how the reply was tagged: NIP-22 A > E > I roots, then NIP-10
    /// marked "root" e-tag, then a single e-tag (direct reply to root).
    static func rootScopeId(fromTags tags: [NostrTag]) -> String? {
        if let a = tags.first(where: { $0.type == "A" }), a.tag.count > 1 { return "A:" + a.tag[1] }
        if let e = tags.first(where: { $0.type == "E" }), e.tag.count > 1 { return "E:" + e.tag[1] }
        if let i = tags.first(where: { $0.type == "I" }), i.tag.count > 1 { return "I:" + i.tag[1] }
        if let root = tags.first(where: { $0.type == "e" && $0.tag[safe: 3] == "root" }), root.tag.count > 1 {
            return "E:" + root.tag[1]
        }
        if let e = tags.first(where: { $0.type == "e" }), e.tag.count > 1 { return "E:" + e.tag[1] }
        return nil
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: same as Step 2. Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Nostur/Post/PostComposer/Anon/AnonReplyHelper.swift NosturTests/AnonReplyHelperTests.swift
git commit -m "feat(anon): add root-scope resolution helper for per-thread ephemeral keys"
```

---

### Task 2: `SendIdentity` enum

**Files:**
- Create: `Nostur/Post/PostComposer/Anon/SendIdentity.swift`
- Test: `NosturTests/SendIdentityTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
import NostrEssentials
@testable import Nostur

struct SendIdentityTests {
    @Test func anon_exposes_ephemeral_pubkey() throws {
        let keys = try Keys.newKeys()
        let identity = SendIdentity.anon(keys)
        #expect(identity.pubkey == keys.publicKeyHex)
        #expect(identity.isAnon == true)
    }
}
```

- [ ] **Step 2: Run to verify failure** — Expected: FAIL (`SendIdentity` undefined).

- [ ] **Step 3: Implement**

```swift
//  SendIdentity.swift
//  Nostur
import Foundation
import NostrEssentials

enum SendIdentity {
    case account(CloudAccount)
    case anon(Keys)

    var pubkey: String {
        switch self {
        case .account(let a): return a.publicKey
        case .anon(let k): return k.publicKeyHex
        }
    }
    var isAnon: Bool { if case .anon = self { return true }; return false }
}
```

- [ ] **Step 4: Run to verify pass.** **Step 5: Commit**

```bash
git add Nostur/Post/PostComposer/Anon/SendIdentity.swift NosturTests/SendIdentityTests.swift
git commit -m "feat(anon): add SendIdentity enum"
```

---

### Task 3: `EphemeralKeyStore` — device-local per-thread key store

Keychain-backed (`service: "nostur.anon"`, `synchronizable(false)`, `.afterFirstUnlockThisDeviceOnly`). Maps root scope id → keypair. Keychain account name = URL-safe base64 of the root scope id (root ids contain `:` and `/`); value = private key hex.

**Threading (corrected):** `bgAnonPubkeys` is written **only inside `bg().perform`** (single writer = the bg serial queue), exactly matching `AccountsState`. Main-thread callers must use the lock-guarded `isAnonPubkey(_:)`, never read `bgAnonPubkeys` directly. NRPost (bg context) reads `bgAnonPubkeys`.

**Files:**
- Create: `Nostur/Post/PostComposer/Anon/EphemeralKeyStore.swift`
- Test: `NosturTests/EphemeralKeyStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
import NostrEssentials
@testable import Nostur

struct EphemeralKeyStoreTests {

    private func freshStore() -> EphemeralKeyStore {
        EphemeralKeyStore(service: "nostur.anon.test." + UUID().uuidString)
    }

    @Test func mint_then_lookup_same_root_returns_same_keys() throws {
        let store = freshStore(); defer { store.wipeAllForTesting() }
        let root = "E:ROOT_A"
        let first = try store.existingOrMint(forRoot: root)
        #expect(first.isNew == true)
        let second = try store.existingOrMint(forRoot: root)
        #expect(second.isNew == false)
        #expect(second.keys.publicKeyHex == first.keys.publicKeyHex)
    }

    @Test func different_roots_get_different_keys() throws {
        let store = freshStore(); defer { store.wipeAllForTesting() }
        let a = try store.existingOrMint(forRoot: "E:ROOT_A").keys
        let b = try store.existingOrMint(forRoot: "A:30023:pub:slug").keys
        #expect(a.publicKeyHex != b.publicKeyHex)
    }

    @Test func anon_pubkey_membership_tracks_minted_keys() throws {
        let store = freshStore(); defer { store.wipeAllForTesting() }
        let keys = try store.existingOrMint(forRoot: "E:ROOT_A").keys
        #expect(store.isAnonPubkey(keys.publicKeyHex) == true)
        #expect(store.isAnonPubkey("not_an_anon_pubkey") == false)
    }

    @Test func keys_for_pubkey_enables_delete_signing() throws {
        let store = freshStore(); defer { store.wipeAllForTesting() }
        let keys = try store.existingOrMint(forRoot: "E:ROOT_A").keys
        #expect(store.keys(forPubkey: keys.publicKeyHex)?.privateKeyHex == keys.privateKeyHex)
    }

    @Test func persistence_survives_reload_from_keychain() throws {
        let service = "nostur.anon.test." + UUID().uuidString
        let store1 = EphemeralKeyStore(service: service)
        let pub = try store1.existingOrMint(forRoot: "E:ROOT_A").keys.publicKeyHex
        let store2 = EphemeralKeyStore(service: service)
        store2.load(); defer { store2.wipeAllForTesting() }
        #expect(store2.isAnonPubkey(pub) == true)
        #expect(store2.keys(forRoot: "E:ROOT_A")?.publicKeyHex == pub)
    }

    @Test func forget_root_removes_key() throws {
        let store = freshStore()
        let keys = try store.existingOrMint(forRoot: "E:ROOT_A").keys
        store.forget(root: "E:ROOT_A")
        #expect(store.keys(forRoot: "E:ROOT_A") == nil)
        #expect(store.isAnonPubkey(keys.publicKeyHex) == false)
    }
}
```

- [ ] **Step 2: Run to verify failure** — Expected: FAIL (`EphemeralKeyStore` undefined).

- [ ] **Step 3: Implement**

```swift
//  EphemeralKeyStore.swift
//  Nostur
//
//  Device-local store of per-thread ephemeral ("anon") keypairs.
//  Keychain service "nostur.anon", synchronizable=false (never iCloud),
//  accessibility .afterFirstUnlockThisDeviceOnly (excluded from backups,
//  never migrates to another device). See spec §0, §2.

import Foundation
import NostrEssentials
import KeychainAccess

final class EphemeralKeyStore {
    static let shared = EphemeralKeyStore()

    private let service: String
    private let lock = NSLock()
    private var keysByRoot: [String: Keys] = [:]
    private var keysByPubkey: [String: Keys] = [:]

    /// Background-context-only set for NRPost build/sort. NEVER read from main — use isAnonPubkey(_:).
    public private(set) var bgAnonPubkeys: Set<String> = []

    init(service: String = "nostur.anon") { self.service = service }

    private var keychain: Keychain { Keychain(service: service).synchronizable(false) }

    private func encode(_ root: String) -> String {
        Data(root.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }
    private func decode(_ account: String) -> String? {
        var s = account.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        guard let data = Data(base64Encoded: s) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Call once at startup.
    func load() {
        lock.lock(); defer { lock.unlock() }
        keysByRoot.removeAll(); keysByPubkey.removeAll()
        var pubkeys = Set<String>()
        let kc = keychain
        for account in kc.allKeys() {          // allKeys() is non-throwing
            guard let root = decode(account),
                  let priv = try? kc.get(account), let priv,
                  let keys = try? Keys(privateKeyHex: priv) else { continue }
            keysByRoot[root] = keys
            keysByPubkey[keys.publicKeyHex] = keys
            pubkeys.insert(keys.publicKeyHex)
        }
        publishSet(pubkeys)
    }

    /// Single-writer: only the bg serial queue mutates bgAnonPubkeys (matches AccountsState).
    private func publishSet(_ pubkeys: Set<String>) {
        bg().perform { [weak self] in self?.bgAnonPubkeys = pubkeys }
    }

    // MARK: - Thread-safe lookups (main or bg)
    func keys(forRoot root: String) -> Keys? { lock.lock(); defer { lock.unlock() }; return keysByRoot[root] }
    func keys(forPubkey pubkey: String) -> Keys? { lock.lock(); defer { lock.unlock() }; return keysByPubkey[pubkey] }
    func isAnonPubkey(_ pubkey: String) -> Bool { lock.lock(); defer { lock.unlock() }; return keysByPubkey[pubkey] != nil }

    /// Existing key for the thread, or mint + persist a new one.
    /// `isNew` is true only when freshly generated this call (used by undo-burn).
    func existingOrMint(forRoot root: String) throws -> (keys: Keys, isNew: Bool) {
        lock.lock()
        if let existing = keysByRoot[root] { lock.unlock(); return (existing, false) }
        let keys = try Keys.newKeys()
        keysByRoot[root] = keys
        keysByPubkey[keys.publicKeyHex] = keys
        let pubkeys = Set(keysByPubkey.keys)
        lock.unlock()

        try keychain
            .accessibility(.afterFirstUnlockThisDeviceOnly)
            .label("nostur anon reply")
            .set(keys.privateKeyHex, key: encode(root))
        publishSet(pubkeys)
        return (keys, true)
    }

    func forget(root: String) {
        lock.lock()
        let removed = keysByRoot[root]
        keysByRoot[root] = nil
        if let pub = removed?.publicKeyHex { keysByPubkey[pub] = nil }
        let pubkeys = Set(keysByPubkey.keys)
        lock.unlock()
        try? keychain.remove(encode(root))
        publishSet(pubkeys)
    }

    func forget(pubkey: String) {
        lock.lock()
        let root = keysByRoot.first(where: { $0.value.publicKeyHex == pubkey })?.key
        lock.unlock()
        if let root { forget(root: root) }
    }

    func wipeAllForTesting() {
        try? keychain.removeAll()
        lock.lock(); keysByRoot.removeAll(); keysByPubkey.removeAll(); lock.unlock()
        publishSet([])
    }
}
```

- [ ] **Step 4: Run to verify pass** (6 tests).

> Note: the persistence test calls `load()` and then `isAnonPubkey`/`keys(forRoot:)`, which read the lock-guarded maps (populated synchronously inside `load()`), so they do not depend on the async `bgAnonPubkeys` write — the test is deterministic.

- [ ] **Step 5: Commit**

```bash
git add Nostur/Post/PostComposer/Anon/EphemeralKeyStore.swift NosturTests/EphemeralKeyStoreTests.swift
git commit -m "feat(anon): add device-local EphemeralKeyStore (ThisDeviceOnly keychain, single-writer bg set)"
```

---

## Phase 2 — Anon-aware event building

### Task 4: Make `buildFinalEvent` anon-aware (no activeAccount read, no client/emoji/relay-hint/NIP-70 tags)

**Files:**
- Modify: `Nostur/Post/PostComposer/NewPostModel.swift` (`buildFinalEvent`, ~778–1059; `addRootScopeTags`/`addReplyToTags`, ~1894–1965)
- Test: `NosturTests/AnonEventBuildingTests.swift`

- [ ] **Step 1: Read the current code** — `NewPostModel.swift:778–1059` and `1894–1965`. Confirm lines 779/780/781, the emoji block (1025–1035), the NIP-70 block (1037–1041), the client block (1047–1049).

- [ ] **Step 2: Add the parameter**

```swift
private func buildFinalEvent(imetas: [Imeta], replyTo: ReplyTo? = nil, quotePost: QuotePost? = nil, isPreviewContext: Bool = false, anonPubkey: String? = nil) -> NEvent?
```

- [ ] **Step 3: Replace the identity guard (lines 780–781) so the anon branch NEVER reads activeAccount**

Replace:
```swift
        guard let account = activeAccount else { return nil }
        let publicKey = account.publicKey
```
with:
```swift
        let publicKey: String
        if let anonPubkey {
            publicKey = anonPubkey                 // anon path: no activeAccount read at all
        } else {
            guard let account = activeAccount else { return nil }
            publicKey = account.publicKey
        }
```
(Leave `guard var nEvent = self.nEvent else { return nil }` on line 779 as-is — `self.nEvent` is set by `loadReplyTo`, which always runs for a reply.)

- [ ] **Step 4: Guard the emoji block (1025–1035), NIP-70 block (1037–1041), and client block (1047–1049) for anon**

Wrap each block:
```swift
if anonPubkey == nil {
    // ... existing emoji-tag block (1025–1035) ...
}
```
```swift
if anonPubkey == nil {
    // ... existing NIP-70 protected ["-"] block (1037–1041) ...
}
```
```swift
if anonPubkey == nil,
   SettingsStore.shared.postUserAgentEnabled,
   !SettingsStore.shared.excludedUserAgentPubkeys.contains(nEvent.publicKey) {
    nEvent.tags.append(NostrTag(["client", NIP89_APP_NAME, NIP89_APP_REFERENCE]))
}
```

- [ ] **Step 5: Strip relay hints from NIP-22 root/reply tags on the anon path**

`addRootScopeTags`/`addReplyToTags` embed `resolveRelayHint(...)` (the user's connection footprint) into the relay-hint slot of `E`/`A`/`e`/`a` tags — an identity-correlation vector (spec §4). Thread an `anon` flag through both functions and pass `""` for the hint when anon:

```swift
func addRootScopeTags(nEvent input: NEvent, replyTo: ReplyTo, anon: Bool = false) -> NEvent { ... 
    let relayHint: String? = anon ? "" : resolveRelayHint(...).first
    ... }
func addReplyToTags(nEvent input: NEvent, replyTo: ReplyTo, anon: Bool = false) -> NEvent { ...
    let relayHint: String? = anon ? "" : resolveRelayHint(...).first
    ... }
```
At their call sites in `buildFinalEvent` (~1016–1019), pass `anon: anonPubkey != nil`.

- [ ] **Step 6: Add a DEBUG test seam**

```swift
#if DEBUG
func buildFinalEventForTesting(replyTo: ReplyTo, anonPubkey: String) -> NEvent? {
    loadReplyTo(replyTo)                 // sets self.nEvent + reply tags (required by line 779)
    return buildFinalEvent(imetas: [], replyTo: replyTo, anonPubkey: anonPubkey)
}
#endif
```

- [ ] **Step 7: Write the test**

This needs a real `ReplyTo` fixture (so `self.nEvent` is non-nil). Use the project's preview/test helpers (`testNRPost(...)` / `PreviewFetcher`) to build an `NRPost` and wrap it in `ReplyTo`. If a `ReplyTo` fixture cannot be constructed in the test target, mark this test `@Test(.disabled("buildFinalEvent needs a composer fixture; covered by Gate 3"))` up front — do NOT claim expected-PASS without a fixture.

```swift
import Foundation
import Testing
import NostrEssentials
@testable import Nostur

struct AnonEventBuildingTests {
    @Test func anon_event_has_ephemeral_pubkey_and_no_leaky_tags() throws {
        SettingsStore.shared.postUserAgentEnabled = true   // would normally add a client tag
        let keys = try Keys.newKeys()
        let replyTo = try makeKind1ReplyFixture()          // build via testNRPost/PreviewFetcher
        let vm = NewPostModel()
        vm.typingTextModel.text = "hello from anon :customemoji:"
        let built = try #require(vm.buildFinalEventForTesting(replyTo: replyTo, anonPubkey: keys.publicKeyHex))
        #expect(built.publicKey == keys.publicKeyHex)
        #expect(!built.tags.contains(where: { $0.type == "client" }))
        #expect(!built.tags.contains(where: { $0.type == "emoji" }))
        #expect(!built.tags.contains(where: { $0.type == "-" }))
    }
}
```

- [ ] **Step 8: Run.** Expected: PASS, or DISABLED-with-reason if no fixture. **Step 9: Commit**

```bash
git add Nostur/Post/PostComposer/NewPostModel.swift NosturTests/AnonEventBuildingTests.swift
git commit -m "feat(anon): buildFinalEvent anon-aware (no activeAccount, no client/emoji/relay-hint/NIP-70 tags)"
```

---

### Task 5: Strengthened §0 pre-publish assertion

A post-sign `pubkey == theKeysWeSignedWith` check is tautological (`NEvent.sign` sets pubkey from the keys). The real guarantee is: the signed pubkey **is** the expected ephemeral key, **is** in the anon set, and is **not** any real-account pubkey — plus the root scope matches.

**Files:**
- Modify: `Nostur/Post/PostComposer/Anon/AnonReplyHelper.swift`
- Test: `NosturTests/AnonReplyHelperTests.swift` (extend)

- [ ] **Step 1: Add the failing tests**

```swift
    @Test func assertion_passes_for_anon_key_matching_root() throws {
        let keys = try Keys.newKeys()
        var e = NEvent(content: "hi"); e.tags = [NostrTag(["e", "ROOT123", "", "root"])]
        e.publicKey = keys.publicKeyHex
        #expect(AnonReplyHelper.isAnonSendSafe(signedEvent: e, expectedKeys: keys, expectedRoot: "E:ROOT123",
                                               realAccountPubkeys: ["realpub"]) == true)
    }

    @Test func assertion_fails_when_pubkey_is_a_real_account() throws {
        let keys = try Keys.newKeys()
        var e = NEvent(content: "hi"); e.tags = [NostrTag(["e", "ROOT123", "", "root"])]
        e.publicKey = keys.publicKeyHex
        // expectedKeys match, but the same pubkey is (pathologically) also a real account => must fail
        #expect(AnonReplyHelper.isAnonSendSafe(signedEvent: e, expectedKeys: keys, expectedRoot: "E:ROOT123",
                                               realAccountPubkeys: [keys.publicKeyHex]) == false)
    }

    @Test func assertion_fails_on_root_drift() throws {
        let keys = try Keys.newKeys()
        var e = NEvent(content: "hi"); e.tags = [NostrTag(["e", "OTHER", "", "root"])]
        e.publicKey = keys.publicKeyHex
        #expect(AnonReplyHelper.isAnonSendSafe(signedEvent: e, expectedKeys: keys, expectedRoot: "E:ROOT123",
                                               realAccountPubkeys: []) == false)
    }
```

- [ ] **Step 2: Run to verify failure** (`isAnonSendSafe` undefined / wrong arity).

- [ ] **Step 3: Implement**

```swift
    /// Final safety gate before an anon event leaves the device (spec §0).
    /// True only if: signed by the expected ephemeral key, that pubkey is NOT any
    /// real-account pubkey, and the event threads under the expected root scope.
    static func isAnonSendSafe(signedEvent: NEvent, expectedKeys: Keys, expectedRoot: String,
                               realAccountPubkeys: Set<String>) -> Bool {
        guard signedEvent.publicKey == expectedKeys.publicKeyHex else { return false }
        guard !realAccountPubkeys.contains(signedEvent.publicKey) else { return false }
        guard rootScopeId(fromTags: signedEvent.tags) == expectedRoot else { return false }
        return true
    }
```

- [ ] **Step 4: Run to verify pass.** **Step 5: Commit**

```bash
git add Nostur/Post/PostComposer/Anon/AnonReplyHelper.swift NosturTests/AnonReplyHelperTests.swift
git commit -m "feat(anon): strengthen §0 assertion (anon key, not a real account, root match)"
```

---

## Phase 3 — Isolated transport

### Task 6: `AnonPublisher` — isolated send, throwing AUTH signer, undo registry, deletes

Publishes a signed anon event over fresh `OneOffEventPublisher` sockets (one per relay) to the fixed relay set plus the parent author's NIP-65 read relays (read directly from kind:10002 — `getInboxRelays` is a stub). Saves locally and emits `ViewUpdates.updateNRPost` so the undo footer can render. Keeps a registry so undo knows the root scope and whether the key was freshly minted.

**🔒 Blocker fix — AUTH leak:** `OneOffEventPublisher` answers **unsolicited** NIP-42 AUTH with no `allowAuth` check (`:194`). Therefore the anon path passes a `signNEventHandler` that **throws**, so any AUTH attempt aborts (caught at `:197-204`) and nothing is signed or sent. Do NOT rely on `allowAuth:false` for safety.

**Files:**
- Create: `Nostur/Post/PostComposer/Anon/AnonPublisher.swift`
- Reference (read only): `OneOffEventPublisher.swift` (`init`, `connect(timeout:)`, `publish(_:timeout:)`, `:194-204`), `Unpublisher.swift:188–216` (local-consume pattern), `OutboxLoader.swift:280` (`getInboxRelays` stub — do not call), `_Temp/ViewUpdates.swift:41`.

- [ ] **Step 1: Implement**

```swift
//  AnonPublisher.swift
//  Nostur
//
//  Isolated publish path for anonymous replies. NEVER uses ConnectionPool's
//  pooled (identified) connections, and NEVER signs a NIP-42 AUTH (the AUTH
//  signer throws). Each relay gets a fresh OneOffEventPublisher socket. Spec §0/§4.

import Foundation
import NostrEssentials

enum AnonSendError: Error { case mustNotSign }

struct AnonPublishResult { let okCount: Int; let attempted: Int; var success: Bool { okCount >= 1 } }

@MainActor
final class AnonPublisher {
    static let shared = AnonPublisher()

    /// Public relays verified to accept writes from fresh keys (spec §5; live-checked 2026-06-11).
    static let fixedRelays: [String] = ["wss://relay.damus.io", "wss://nos.lol", "wss://relay.primal.net"]

    private let undoWindow: TimeInterval = 9.0
    private var pending: [UUID: DispatchWorkItem] = [:]

    /// Undo metadata, keyed by published event id, so OwnPostFooter can route undo correctly.
    struct UndoInfo { let cancellationId: UUID; let rootScope: String; let keysWereNewlyMinted: Bool }
    private var undoByEventId: [String: UndoInfo] = [:]
    func undoInfo(forEventId id: String) -> UndoInfo? { undoByEventId[id] }

    /// Queue an anon reply: save locally now (immediate thread display + undo footer), fire after the window.
    @discardableResult
    func publish(signedEvent: NEvent, parentAuthorPubkey: String,
                 keysWereNewlyMinted: Bool, rootScope: String) -> UUID {
        let cancellationId = UUID()
        undoByEventId[signedEvent.id] = UndoInfo(cancellationId: cancellationId, rootScope: rootScope, keysWereNewlyMinted: keysWereNewlyMinted)

        // Save locally + drive the undo footer via updateNRPost (sets ownPostAttributes.cancellationId).
        bg().perform {
            let saved = Event.saveEvent(event: signedEvent, context: bg())
            saved.cancellationId = cancellationId
            DispatchQueue.main.async {
                sendNotification(.newPostSaved, saved)
                ViewUpdates.shared.updateNRPost.send(saved)
            }
        }

        let work = DispatchWorkItem { [weak self] in
            self?.pending[cancellationId] = nil
            self?.undoByEventId[signedEvent.id] = nil
            Task { await self?.fire(signedEvent: signedEvent, parentAuthorPubkey: parentAuthorPubkey) }
        }
        pending[cancellationId] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + undoWindow, execute: work)
        return cancellationId
    }

    /// Undo before the window: remove local event, burn key only if freshly minted (spec §6).
    @discardableResult
    func cancel(cancellationId: UUID, eventId: String) -> Bool {
        guard let work = pending[cancellationId] else { return false }
        work.cancel(); pending[cancellationId] = nil
        let info = undoByEventId[eventId]; undoByEventId[eventId] = nil
        bg().perform {
            if let event = Event.fetchEvent(id: eventId, context: bg()) { bg().delete(event) }
        }
        if let info, info.keysWereNewlyMinted { EphemeralKeyStore.shared.forget(root: info.rootScope) }
        return true
    }

    /// Fire-and-forget publish with no undo window or local save (used for kind:5 deletes).
    func publishRaw(_ signedEvent: NEvent, parentAuthorPubkey: String) async {
        _ = await fire(signedEvent: signedEvent, parentAuthorPubkey: parentAuthorPubkey)
    }

    @discardableResult
    private func fire(signedEvent: NEvent, parentAuthorPubkey: String) async -> AnonPublishResult {
        let relays = await relayTargets(parentAuthorPubkey: parentAuthorPubkey)
        var okCount = 0
        await withTaskGroup(of: Bool.self) { group in
            for relay in relays {
                group.addTask {
                    do {
                        // AUTH signer THROWS => no NIP-42 AUTH is ever emitted on the anon path (spec §0).
                        let pub = try OneOffEventPublisher(relay, allowAuth: false,
                                    signNEventHandler: { _ in throw AnonSendError.mustNotSign })
                        try await pub.connect(timeout: 8)
                        try await pub.publish(signedEvent, timeout: 8)
                        return true
                    } catch { return false }
                }
            }
            for await ok in group where ok { okCount += 1 }
        }
        let result = AnonPublishResult(okCount: okCount, attempted: relays.count)
        if !result.success {
            sendNotification(.anyStatus, ("Anon reply may not have been delivered", "NewPost"))
        }
        return result
    }

    /// Fixed relays + parent author's NIP-65 read relays (deduped, capped). Spec §5.
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
                let read = ev.fastTags
                    .filter { $0.0 == "r" && ($0.2 == nil || $0.2 == "read") }
                    .map { normalizeRelayUrl($0.1) }
                cont.resume(returning: Array(Set(read).prefix(4)))
            }
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
Expected: BUILD SUCCEEDED. Confirm `Event.saveEvent(event:context:)`, `Event.fetchEvent(id:context:)`, `Event.fetchReplacableEvent(_:pubkey:context:)`, and `OneOffEventPublisher.publish(_:timeout:)` signatures match (verified present 2026-06-11).

- [ ] **Step 3: Commit**

```bash
git add Nostur/Post/PostComposer/Anon/AnonPublisher.swift
git commit -m "feat(anon): isolated AnonPublisher (throwing AUTH signer, undo registry, kind:10002 read relays, publishRaw)"
```

> **Optional defense-in-depth (separate, reviewed change):** add `guard allowAuth else { return }` at the top of `OneOffEventPublisher`'s `case .AUTH:` so no AUTH is even attempted when `allowAuth` is false. Only do this after confirming no existing caller relies on unsolicited-AUTH-with-allowAuth-false; the throwing signer above already closes the leak without touching shared code.

---

### Task 7: `sendNowAnon` entry point on `NewPostModel`

Resolves the root scope, mints/looks up the key, builds the anon event, signs, runs the strengthened §0 assertion, hands to `AnonPublisher`. Never reads `activeAccount`.

**Files:**
- Modify: `Nostur/Post/PostComposer/NewPostModel.swift`

- [ ] **Step 1: Add anon state** (near `activeAccount`, ~189):

```swift
@Published var anonMode: Bool = false   // reply-only; set by enterAnonMode()
```

- [ ] **Step 2: Add the method**

```swift
@MainActor
func sendNowAnon(replyTo: ReplyTo, onDismiss: @escaping () -> Void) async {
    // First build derives the true root scope from the reply tags (no pubkey needed for tags).
    guard let draftEvent = buildFinalEvent(imetas: [], replyTo: replyTo, anonPubkey: "0") else {
        typingTextModel.sending = false
        sendNotification(.anyStatus, ("Could not build reply", "NewPost")); return
    }
    guard let rootScope = AnonReplyHelper.rootScopeId(fromTags: draftEvent.tags) else {
        typingTextModel.sending = false
        sendNotification(.anyStatus, ("Could not determine thread root", "NewPost")); return
    }

    let minted: (keys: Keys, isNew: Bool)
    do { minted = try EphemeralKeyStore.shared.existingOrMint(forRoot: rootScope) }
    catch { typingTextModel.sending = false
            sendNotification(.anyStatus, ("Could not create anon identity", "NewPost")); return }

    guard var finalEvent = buildFinalEvent(imetas: [], replyTo: replyTo, anonPubkey: minted.keys.publicKeyHex) else {
        typingTextModel.sending = false
        if minted.isNew { EphemeralKeyStore.shared.forget(root: rootScope) }
        sendNotification(.anyStatus, ("Could not build reply", "NewPost")); return
    }
    finalEvent.createdAt = NTimestamp(date: Date())
    guard let signed = try? finalEvent.sign(minted.keys) else {
        typingTextModel.sending = false
        if minted.isNew { EphemeralKeyStore.shared.forget(root: rootScope) }
        sendNotification(.anyStatus, ("Could not sign anon reply", "NewPost")); return
    }

    // §0 gate. Real-account pubkeys to reject against.
    let realPubkeys = Set(AccountsState.shared.accounts.map { $0.publicKey })
    guard AnonReplyHelper.isAnonSendSafe(signedEvent: signed, expectedKeys: minted.keys,
                                         expectedRoot: rootScope, realAccountPubkeys: realPubkeys) else {
        typingTextModel.sending = false
        if minted.isNew { EphemeralKeyStore.shared.forget(root: rootScope) }
        sendNotification(.anyStatus, ("Anon reply blocked: identity check failed", "NewPost"))
        return
    }

    let parentAuthor = replyTo.nrPost.kind == 9735 ? (replyTo.nrPost.fromPubkey ?? replyTo.nrPost.pubkey) : replyTo.nrPost.pubkey
    AnonPublisher.shared.publish(signedEvent: signed, parentAuthorPubkey: parentAuthor,
                                 keysWereNewlyMinted: minted.isNew, rootScope: rootScope)
    typingTextModel.sending = false
    onDismiss()
}
```

- [ ] **Step 3: Build & commit**

```bash
xcodebuild -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
git add Nostur/Post/PostComposer/NewPostModel.swift
git commit -m "feat(anon): sendNowAnon (resolve root, mint, build, sign, §0 assert, isolated publish)"
```

---

## Phase 4 — Composer UI

### Task 8: Anon item in `InlineAccountSwitcher` (reply-only, hidden on private posts)

**Files:**
- Modify: `Nostur/Post/PostComposer/PostAccountSwitcher.swift`
- Modify: `Nostur/Post/PostComposer/ComposePost.swift` (default text reply site only, ~419)

- [ ] **Step 1: Extend the switcher** — add stored properties and include them in `==`:

```swift
public var showAnonOption: Bool = false
public var isAnonSelected: Bool = false
public var onSelectAnon: (() -> Void)? = nil
```
After the account rows in the fan-out `ForEach`, when `showAnonOption` add one tappable incognito item (`Image(systemName: "theatermasks.fill")` in a `Circle`, size `size`) whose tap (when expanded) calls `onSelectAnon?()` then collapses. When `isAnonSelected`, render the primary/collapsed slot as the incognito glyph. Add `isAnonSelected` to the `==`.

- [ ] **Step 2: Wire ONLY the default text reply site (ComposePost.swift ~419)**

```swift
InlineAccountSwitcher(
    activeAccount: account,
    onChange: { account in
        vm.exitAnonMode()          // resets anonMode + typingTextModel.anonMode (Task 9)
        vm.activeAccount = account
    },
    showAnonOption: (replyTo != nil && !vm.replyingToPrivatePost),   // hidden on private posts (spec §1)
    isAnonSelected: vm.anonMode,
    onSelectAnon: { vm.enterAnonMode() }
).equatable()
```
Leave the other four call sites (voice 89, highlight 156, picture 240, short-video 281) unchanged.

- [ ] **Step 3: Build & visually confirm** — incognito item appears only on a normal kind:1/NIP-22 text reply; absent on new post, quote, picture, highlight, voice, **and private-post replies**.

- [ ] **Step 4: Commit**

```bash
git add Nostur/Post/PostComposer/PostAccountSwitcher.swift Nostur/Post/PostComposer/ComposePost.swift
git commit -m "feat(anon): reply-only anon switcher item, hidden on private posts"
```

---

### Task 9: `enterAnonMode`/`exitAnonMode` — exclusion, media/emoji/draft hard-block, single send dispatcher

**Files:**
- Modify: `Nostur/Post/PostComposer/NewPostModel.swift` (+ `TypingTextModel`)
- Modify: `Nostur/Post/PostComposer/Entry.swift` (send + preview routing, drag/paste gating)
- Modify: `Nostur/Post/PostComposer/PostPreview.swift` (send routing)

- [ ] **Step 1: `TypingTextModel` anon flag + draft isolation**

In `TypingTextModel` add `@Published var anonMode = false` and an in-memory anon buffer; gate the draft write AND seed-from-draft bidirectionally (spec §6):

```swift
@Published var anonMode: Bool = false
private var savedRealDraft: String = ""
@Published var text: String = "" {
    didSet { if !anonMode { draft = text } }   // never persist anon text
}
```

- [ ] **Step 2: `enterAnonMode`/`exitAnonMode` on `NewPostModel`**

```swift
@MainActor
func enterAnonMode() {
    guard !anonMode else { return }
    anonMode = true
    typingTextModel.anonMode = true                 // MUST be set here (draft guard depends on it)
    typingTextModel.savedRealDraftSnapshotAndClear() // snapshot real draft, clear visible text (§6)
    // Mutual exclusion with private/DM replies — anon must never enter the giftwrap branch.
    replyInPrivate = false
    // Hard-block media (spec §6): clear buffers that would trigger real-key upload auth.
    typingTextModel.pastedImages = []
    typingTextModel.pastedVideos = []
    typingTextModel.voiceRecording = nil
    remoteIMetas = [:]
    // Clear lock-to-relay so no NIP-70 ["-"] path is reachable.
    lockToSingleRelay = false
    maybeShowAnonExplainer()                         // Task 12
}

@MainActor
func exitAnonMode() {
    guard anonMode else { return }
    anonMode = false
    typingTextModel.anonMode = false
    typingTextModel.restoreRealDraft()              // restore pre-anon real draft (§6)
}
```
Add to `TypingTextModel`:
```swift
func savedRealDraftSnapshotAndClear() { savedRealDraft = draft; anonMode = true; text = "" }
func restoreRealDraft() { anonMode = false; text = savedRealDraft; savedRealDraft = "" }
```

- [ ] **Step 3: Single send dispatcher (close the PostPreview leak)**

Add one dispatcher and call it from BOTH `Entry.swift` and `PostPreview.swift`:
```swift
// In Entry.swift / PostPreview.swift send button action:
private func dispatchSend() {
    typingTextModel.sending = true
    if vm.anonMode, let replyTo {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Task { await self.vm.sendNowAnon(replyTo: replyTo, onDismiss: { onDismiss() }) }
        }
        return
    }
    guard let account = vm.activeAccount, account.isFullAccount else {
        typingTextModel.sending = false
        sendNotification(.anyStatus, ("Problem with account", "NewPost")); return
    }
    let isNC = account.isNC, pubkey = account.publicKey
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        Task { await self.vm.sendNow(isNC: isNC, pubkey: pubkey, account: account, replyTo: replyTo, quotePost: quotePost, onDismiss: { onDismiss() }) }
    }
}
```
Replace the existing send-button bodies in `Entry.swift` (~601) and `PostPreview.swift` (~69) with `dispatchSend()`.

- [ ] **Step 4: Hard-disable the Preview button and media/emoji/drag/paste in anon mode**

- `Entry.swift`: the `previewButton` (~348/400/455) → add `.disabled(shouldDisablePostButton || vm.anonMode)` so anon never reaches the preview's real-account send.
- Attachment + custom-emoji buttons in the reply composer → `.disabled(vm.anonMode)`.
- Drag-drop handler (`ComposePost.swift:529`) and paste handler (`Entry.swift:219`) → no-op when `vm.anonMode`.

- [ ] **Step 5: Build & confirm** — toggle anon; confirm Preview is disabled, attachments/emoji disabled, send routes to `sendNowAnon` (debug log), and exiting anon restores the prior draft text.

- [ ] **Step 6: Commit**

```bash
git add Nostur/Post/PostComposer/NewPostModel.swift Nostur/Post/PostComposer/Entry.swift Nostur/Post/PostComposer/PostPreview.swift Nostur/Post/PostComposer/ComposePost.swift
git commit -m "feat(anon): enter/exitAnonMode, single send dispatcher, preview/media/emoji/draft hard-block"
```

---

## Phase 5 — Thread integration

### Task 10: Ownership gates + mentions self-exclusion

**Files:**
- Modify: `Nostur/Post/NR/NRPost.swift` (~470, ~1371, ~1391) — bg context, use `bgAnonPubkeys`
- Modify: `Nostur/Notifications/MentionsFeedModel.swift` (~72–75) — exclude anon pubkeys

- [ ] **Step 1: `isOwnPost` (~470, bg)**

```swift
isOwnPost: AccountsState.shared.bgFullAccountPubkeys.contains(pubkey)
    || EphemeralKeyStore.shared.bgAnonPubkeys.contains(pubkey),
```

- [ ] **Step 2: WoT inclusion filter `sortGroupedReplies` (~1371, bg)**

```swift
.filter { $0.inWoT
    || AccountsState.shared.bgAccountPubkeys.contains($0.pubkey)
    || EphemeralKeyStore.shared.bgAnonPubkeys.contains($0.pubkey)
    || $0.pubkey == self.pubkey }
```

- [ ] **Step 3: `sortGroupedRepliesNotWoT` (~1391, bg)**

```swift
.filter { !$0.inWoT
    && !AccountsState.shared.bgAccountPubkeys.contains($0.pubkey)
    && !EphemeralKeyStore.shared.bgAnonPubkeys.contains($0.pubkey)
    && $0.pubkey != self.pubkey }
```

- [ ] **Step 4: Mentions self-exclusion** — in `MentionsFeedModel` predicate (~72–75), exclude anon pubkeys so the user's own anon reply to their own post doesn't notify them as a stranger. Add `AND NOT (pubkey IN %@)` bound to `Array(EphemeralKeyStore.shared.bgAnonPubkeys)` (resolve on the same context the predicate runs on).

- [ ] **Step 5: Build & commit**

```bash
xcodebuild -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
git add Nostur/Post/NR/NRPost.swift Nostur/Notifications/MentionsFeedModel.swift
git commit -m "feat(anon): anon pubkeys in ownership/WoT gates; exclude from own mentions"
```

---

### Task 11: indicator + undo routing + NIP-09 delete + forget

**Files:**
- Modify: `Nostur/Utils/Notifications.swift` (declare `.requestDeleteAnonPost`)
- Modify: `Nostur/Post/OwnPostFooter.swift` (undo routing — main thread, use `isAnonPubkey`)
- Modify: `Nostur/Post/PostMenu/PostMenu.swift` (~263) and `Nostur/Utils/View+withSheets.swift` (~176)
- Modify: post header/footer (indicator)

- [ ] **Step 1: Declare the notification** in `Notifications.swift`:

```swift
static var requestDeleteAnonPost: Notification.Name { Notification.Name("requestDeleteAnonPost") }
```
And a payload type (so the handler has pubkey + kind, not just an id):
```swift
struct DeleteAnonPostRequest { let eventId: String; let pubkey: String; let kind: Int }
```

- [ ] **Step 2: Anon undo routing in `OwnPostFooter`** (main thread → `isAnonPubkey`)

The Undo button renders because `AnonPublisher.publish` sent `ViewUpdates.updateNRPost` with a `cancellationId`. In the Undo action, branch:
```swift
if EphemeralKeyStore.shared.isAnonPubkey(nrPost.pubkey),
   let cid = nrPost.ownPostAttributes.cancellationId {
    AnonPublisher.shared.cancel(cancellationId: cid, eventId: nrPost.id)   // burns key iff newly minted
    // do NOT touch Drafts.shared (anon text was never persisted)
} else {
    // ... existing real-account unpublish + draft restore ...
}
```

- [ ] **Step 3: Anon delete** — in `PostMenu.swift` (~263) add, alongside the existing `isOwnPost && isFullAccount` Delete:

```swift
if EphemeralKeyStore.shared.isAnonPubkey(nrPost.pubkey) {
    Button(role: .destructive) {
        sendNotification(.requestDeleteAnonPost,
            DeleteAnonPostRequest(eventId: nrPost.id, pubkey: nrPost.pubkey, kind: Int(nrPost.kind)))
    } label: { Label("Delete", systemImage: "trash") }
}
```
In `View+withSheets.swift`, handle it (note the `Task` wrapper — the closure is synchronous):
```swift
.onReceive(receiveNotification(.requestDeleteAnonPost)) { notification in
    guard let req = notification.object as? DeleteAnonPostRequest,
          let keys = EphemeralKeyStore.shared.keys(forPubkey: req.pubkey) else { return }
    // reuse the existing confirmation copy
    var deletion = NEvent(content: "")
    deletion.kind = .delete
    deletion.tags = [ NostrTag(["e", req.eventId]), NostrTag(["k", String(req.kind)]) ]  // NIP-09: e + k
    deletion.publicKey = keys.publicKeyHex
    guard let signed = try? deletion.sign(keys),
          signed.publicKey == keys.publicKeyHex else { return }       // mini §0 check
    Task { @MainActor in
        await AnonPublisher.shared.publishRaw(signed, parentAuthorPubkey: req.pubkey)
    }
}
```

- [ ] **Step 4: Forget identity** — context-menu item on anon-owned posts → confirmation ("You will no longer be able to continue or delete replies from this identity") → `EphemeralKeyStore.shared.forget(pubkey: nrPost.pubkey)`.

- [ ] **Step 5: Indicator** — where the author handle renders, when `EphemeralKeyStore.shared.isAnonPubkey(nrPost.pubkey)` show a small "you · anon" badge.

- [ ] **Step 6: Build & commit**

```bash
xcodebuild -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
git add -A
git commit -m "feat(anon): you-anon indicator, undo routing via registry, NIP-09 anon delete (e+k), forget identity"
```

---

## Phase 6 — Explainer + startup + repurpose reset

### Task 12: First-use explainer, startup load, composer-repurpose reset

**Files:**
- Modify: `Nostur/AppState.swift` or `NosturApp.swift` (startup `load()`)
- Modify: `Nostur/Post/PostComposer/NewPostModel.swift` (`maybeShowAnonExplainer`, repurpose reset)
- Modify: `Nostur/Post/PostComposer/ComposePost.swift` (audio switch-back ~115)

- [ ] **Step 1: Startup load** — call `EphemeralKeyStore.shared.load()` where other singletons load (mirror `AccountsState.loadAccountsState`), so `bgAnonPubkeys` is populated before threads render.

- [ ] **Step 2: Composer-repurpose reset (spec §6)** — at the START of `loadReplyTo` and `loadQuotingEvent`, and in the audio switch-back closure (`ComposePost.swift:115-118`), reset anon state so a stale key can't sign a new thread:
```swift
anonMode = false
typingTextModel.anonMode = false
```

- [ ] **Step 3: One-time explainer** — `maybeShowAnonExplainer()`:
```swift
private func maybeShowAnonExplainer() {
    guard !UserDefaults.standard.bool(forKey: "anonReplyExplainerShown") else { return }
    UserDefaults.standard.set(true, forKey: "anonReplyExplainerShown")
    sendNotification(.anyStatus, ("anonExplainer", "NewPost"))   // or present via the project's alert pattern
}
```
Present an alert with this copy (reuse the project's alert/confirmation presentation):

> **Reply anonymously**
> This reply will be posted from a new one-time identity that isn't linked to any of your accounts.
> This identity — and your ability to continue or delete it — lives only on this device. It is not backed up and won't appear on your other devices.
> Note: relays can still see your IP address, and your writing style may identify you. Deletion is a request that relays and other apps may ignore.
> [Cancel] [Continue anonymously]

"Cancel" calls `exitAnonMode()`.

- [ ] **Step 4: Build & confirm the alert shows once; repurposing the composer clears anon mode.**

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(anon): startup key load, one-time explainer, composer-repurpose reset"
```

---

## Phase 7 — 🔒 Gate 3: realistic-relay smoke (pre-merge, human-in-the-loop)

Mandatory before merge. Offline tests do not cover the wire, the key, or the relay. Use the `nak` skill.

- [ ] **Step 1:** Build and run with a real logged-in account.
- [ ] **Step 2:** Post an anon reply to a normal kind:1 post; capture the event id (debug log in `sendNowAnon`).
- [ ] **Step 3 (wire check):** `nak` fetch the event by id from `wss://relay.damus.io`; confirm field-by-field: `pubkey` is the ephemeral key (NOT any account pubkey), **no** `client` tag (with `postUserAgentEnabled` ON), **no** `emoji` tag, **no** `["-"]` tag, **empty** relay-hint slots in `e`/`E`/`a`/`A` tags, correct NIP-10/NIP-22 root+reply+p tags, correct kind.
- [ ] **Step 4 (negative / §0):** Confirm the event does NOT appear on your configured write relays outside the anon set, and capture relay logs / use a relay that challenges AUTH to confirm **no NIP-42 AUTH event was emitted** during the publish (the throwing signer must abort it). This is the spec §0 hard gate.
- [ ] **Step 5 (cross-client):** From a SECOND unrelated account, view the thread on Damus, Amethyst, and Primal; confirm the anon reply surfaces. If filtered, add NIP-13 PoW (spec §5 contingency) and re-test.
- [ ] **Step 6 (continuity/persistence):** Second anon reply in the same thread → same `pubkey`. Force-quit + relaunch → thread still shows your anon replies as "you · anon" with Delete/Forget available.
- [ ] **Step 7 (undo/delete):** Post an anon reply, hit Undo within 9s → `nak` finds nothing on the relays AND (if it was the thread's first anon reply) the keychain entry is gone (key burned). Delete an existing anon reply → verify kind:5 with `e`+`k` on the wire.
- [ ] **Step 8 (private-post + edges):** Confirm the anon item is absent when replying to a private post. Max-length text. Reply to a NIP-22 parent (article/voice) twice → same identity (root scope keyed correctly).
- [ ] **Step 9:** Record evidence (the `nak` outputs + the no-AUTH confirmation) in the PR, plus the abuse note (spec §7) and the "no kill-switch in v1" flag for the maintainer.

---

## Self-review checklist (run before handing off)

- [ ] Spec → task map: §0 → Tasks 5,7 + Task 6 throwing-AUTH; §1 → Tasks 8,9,12; §2 → Task 3; §3 → Tasks 2,4; §4 → Tasks 4,6,7; §5 → Tasks 6,10,11; §6 → Tasks 4,7,9,12; §7 → Task 7 (PR note); §8 → Tasks 1–5,7 + Phase 7.
- [ ] Grep `sendNowAnon` + `AnonPublisher` for `activeAccount`, `account.signEvent`, `AccountManager`, `Unpublisher.shared`, `ConnectionPool.shared.sendMessage`, `sendEphemeralMessage` → expect NONE. Grep `buildFinalEvent` anon branch for `activeAccount` → expect NONE.
- [ ] `isAnonSendSafe` (with `realAccountPubkeys`) is the only publish path in `sendNowAnon`; the anon delete has its own mini pubkey check.
- [ ] No main-thread read of `bgAnonPubkeys` (those use `isAnonPubkey`); only NRPost (bg) reads `bgAnonPubkeys`.
- [ ] `.requestDeleteAnonPost` is declared; the delete handler binds pubkey + kind from the payload and wraps publish in `Task`.
- [ ] Undo data (cancellationId/rootScope/isNew) reaches the footer via `ViewUpdates.updateNRPost` + the registry; no false-default `keysWereNewlyMinted`.
- [ ] Anon item hidden on private-post replies; Preview button disabled in anon mode; both send buttons go through `dispatchSend`.
- [ ] anon state cleared in `loadReplyTo`/`loadQuotingEvent`/audio switch-back.
```
