# Anonymous (Ephemeral-Key) Replies Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user reply in a thread under a freshly generated, per-thread ephemeral key instead of one of their accounts, with the anon identity persisted device-locally so they can continue or delete it later.

**Architecture:** A fully isolated anon send path that never reads `activeAccount`. A device-local keychain store (`EphemeralKeyStore`) maps a per-thread *root scope id* to a keypair. Anon events are built by the existing `buildFinalEvent` made anon-aware (correct reply tags, no client tag, no emoji tags), signed locally, and published over `OneOffEventPublisher` (a brand-new websocket per relay, `allowAuth: false`) to a fixed relay set plus the parent author's NIP-65 read relays. A pre-publish assertion guarantees the signed event's pubkey is the ephemeral key. Thread-ownership gates additionally consult the anon pubkey set so the user's own anon replies render as "mine" with delete/forget actions.

**Tech Stack:** Swift, SwiftUI, NostrEssentials (`Keys`, `NEvent`), KeychainAccess, Swift Testing (`import Testing`, `@Test`, `#expect`), Core Data.

**Spec:** `docs/superpowers/specs/2026-06-10-anon-replies-design.md` — read it before starting. The non-negotiable invariant is spec §0: nothing on the anon path may sign with, authenticate as, persist under, or publish over a connection associated with the real account.

**Build/test commands:**
- Build: `xcodebuild -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
- Test: `xcodebuild test -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 16 Pro (18.5),OS=18.5' -only-testing:NosturTests/<TestType>`

---

## Phase ordering and scope

- **Phase 1 — Foundation:** `EphemeralKeyStore`, `SendIdentity`, root-scope helper (pure logic, full TDD).
- **Phase 2 — Event building:** anon-aware `buildFinalEvent` + pre-publish assertion (TDD).
- **Phase 3 — Transport:** `AnonPublisher` (isolated send, OK threshold, 9s undo).
- **Phase 4 — Composer UI:** switcher anon item, private-reply mutual exclusion, media/emoji hard-block, draft isolation.
- **Phase 5 — Thread integration:** ownership gates, "you (anon)" indicator, anon delete, forget identity.
- **Phase 6 — Explainer + wiring:** first-use alert, startup load.
- **Phase 7 — 🔒 Gate 3:** realistic-relay smoke (human-in-the-loop, pre-merge).

Each phase ends in a buildable, committable state. Phases 1–2 are unit-tested; 3–6 are integration work verified by build + the Phase 7 smoke.

---

## Phase 1 — Foundation

### Task 1: Root scope resolution helper

The per-thread key is keyed by a stable "root scope id" derived from the reply's tags. Kind:1 replies carry a NIP-10 marked `root` `e`-tag; NIP-22 replies (kind 1111/1244) carry an uppercase `E`/`A`/`I` root scope tag. This helper derives one canonical string from a built event's tags, and is the single source of truth used both for key lookup and for the pre-publish assertion.

**Files:**
- Create: `Nostur/Post/PostComposer/Anon/AnonReplyHelper.swift`
- Test: `NosturTests/AnonReplyHelperTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import Nostur

struct AnonReplyHelperTests {

    // Helper: build an NEvent with given tags
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
        let e = event(tags: [
            ["e", "ROOT123", "", "root"]
        ])
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
//  Root-scope resolution for anonymous (ephemeral-key) replies.
//  The root scope id is the stable per-thread key under which an ephemeral
//  identity is stored, so all anon replies in one thread reuse one key.

import Foundation

enum AnonReplyHelper {

    /// Derive the canonical per-thread root scope id from a (built) event's tags.
    /// Preference order matches how the reply was tagged:
    ///   NIP-22 uppercase A (addressable) > E (event) > I (external) root,
    ///   then NIP-10 marked "root" e-tag, then a single e-tag (direct reply to root).
    static func rootScopeId(fromTags tags: [NostrTag]) -> String? {
        // NIP-22 root scope tags (uppercase). A is preferred for addressable roots.
        if let a = tags.first(where: { $0.type == "A" }), a.tag.count > 1 {
            return "A:" + a.tag[1]
        }
        if let e = tags.first(where: { $0.type == "E" }), e.tag.count > 1 {
            return "E:" + e.tag[1]
        }
        if let i = tags.first(where: { $0.type == "I" }), i.tag.count > 1 {
            return "I:" + i.tag[1]
        }
        // NIP-10 marked root e-tag: ["e", <id>, <relay>, "root"]
        if let root = tags.first(where: { $0.type == "e" && $0.tag[safe: 3] == "root" }),
           root.tag.count > 1 {
            return "E:" + root.tag[1]
        }
        // Direct reply to root: a single e-tag with no marker
        if let e = tags.first(where: { $0.type == "e" }), e.tag.count > 1 {
            return "E:" + e.tag[1]
        }
        return nil
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: same command as Step 2.
Expected: PASS (all 6 tests).

- [ ] **Step 5: Commit**

```bash
git add Nostur/Post/PostComposer/Anon/AnonReplyHelper.swift NosturTests/AnonReplyHelperTests.swift
git commit -m "feat(anon): add root-scope resolution helper for per-thread ephemeral keys"
```

> **Note for the implementer:** confirm `NostrTag` exposes `.type` and `.tag` (array of strings) and that `[safe:]` subscript exists — both are used elsewhere (`NewPostModel.swift:1030`, `NRChatMessage.swift:96`). If `NostrTag` does not expose `.tag` publicly, use the existing `.type`/`.value`/`tag[safe:]` accessors visible at those call sites.

---

### Task 2: `SendIdentity` enum

A single explicit value for "who is sending", so the anon path never co-mingles with `activeAccount`.

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

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 16 Pro (18.5),OS=18.5' -only-testing:NosturTests/SendIdentityTests`
Expected: FAIL — `SendIdentity` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
//  SendIdentity.swift
//  Nostur

import Foundation
import NostrEssentials

/// Explicit "who is publishing this event" value. The anon case carries the
/// ephemeral keypair directly so the anon send path never reads `activeAccount`.
enum SendIdentity {
    case account(CloudAccount)
    case anon(Keys)

    var pubkey: String {
        switch self {
        case .account(let a): return a.publicKey
        case .anon(let k): return k.publicKeyHex
        }
    }

    var isAnon: Bool {
        if case .anon = self { return true }
        return false
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Nostur/Post/PostComposer/Anon/SendIdentity.swift NosturTests/SendIdentityTests.swift
git commit -m "feat(anon): add SendIdentity enum"
```

---

### Task 3: `EphemeralKeyStore` — device-local per-thread key store

Keychain-backed (`service: "nostur.anon"`, `synchronizable(false)`, `.afterFirstUnlockThisDeviceOnly`), maps root scope id → keypair. Keychain account name is the URL-safe base64 of the root scope id (root scope ids contain `:` and `/`), value is the private key hex. In-memory it keeps `[rootScopeId: Keys]`, `[pubkey: Keys]`, and a background-readable `bgAnonPubkeys: Set<String>`.

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

    // Use a unique service per test run so we never touch real anon keys.
    private func freshStore() -> EphemeralKeyStore {
        EphemeralKeyStore(service: "nostur.anon.test." + UUID().uuidString)
    }

    @Test func mint_then_lookup_same_root_returns_same_keys() throws {
        let store = freshStore()
        defer { store.wipeAllForTesting() }

        let root = "E:ROOT_A"
        let first = try store.existingOrMint(forRoot: root)
        #expect(first.isNew == true)

        let second = try store.existingOrMint(forRoot: root)
        #expect(second.isNew == false)
        #expect(second.keys.publicKeyHex == first.keys.publicKeyHex)
    }

    @Test func different_roots_get_different_keys() throws {
        let store = freshStore()
        defer { store.wipeAllForTesting() }

        let a = try store.existingOrMint(forRoot: "E:ROOT_A").keys
        let b = try store.existingOrMint(forRoot: "A:30023:pub:slug").keys
        #expect(a.publicKeyHex != b.publicKeyHex)
    }

    @Test func anon_pubkey_set_tracks_minted_keys() throws {
        let store = freshStore()
        defer { store.wipeAllForTesting() }

        let keys = try store.existingOrMint(forRoot: "E:ROOT_A").keys
        #expect(store.isAnonPubkey(keys.publicKeyHex) == true)
        #expect(store.isAnonPubkey("not_an_anon_pubkey") == false)
    }

    @Test func keys_for_pubkey_enables_delete_signing() throws {
        let store = freshStore()
        defer { store.wipeAllForTesting() }

        let keys = try store.existingOrMint(forRoot: "E:ROOT_A").keys
        let found = store.keys(forPubkey: keys.publicKeyHex)
        #expect(found?.privateKeyHex == keys.privateKeyHex)
    }

    @Test func persistence_survives_reload_from_keychain() throws {
        let service = "nostur.anon.test." + UUID().uuidString
        let store1 = EphemeralKeyStore(service: service)
        let pub = try store1.existingOrMint(forRoot: "E:ROOT_A").keys.publicKeyHex

        // New instance, same service: simulates app restart.
        let store2 = EphemeralKeyStore(service: service)
        store2.load()
        defer { store2.wipeAllForTesting() }
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

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 16 Pro (18.5),OS=18.5' -only-testing:NosturTests/EphemeralKeyStoreTests`
Expected: FAIL — `EphemeralKeyStore` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
//  EphemeralKeyStore.swift
//  Nostur
//
//  Device-local store of per-thread ephemeral ("anon") keypairs.
//  Keychain: service "nostur.anon", synchronizable=false (never iCloud),
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

    /// Background-readable set of all anon pubkeys, for "is mine" checks in NRPost (bg context).
    public private(set) var bgAnonPubkeys: Set<String> = []

    init(service: String = "nostur.anon") {
        self.service = service
    }

    private var keychain: Keychain {
        Keychain(service: service).synchronizable(false)
    }

    // MARK: - Encoding of root scope id <-> keychain account name
    private func encode(_ root: String) -> String {
        Data(root.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }
    private func decode(_ account: String) -> String? {
        var s = account.replacingOccurrences(of: "-", with: "+")
                       .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        guard let data = Data(base64Encoded: s) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Load (call once at startup)
    func load() {
        lock.lock(); defer { lock.unlock() }
        keysByRoot.removeAll(); keysByPubkey.removeAll()
        var pubkeys = Set<String>()
        let kc = keychain
        for account in (try? kc.allKeys()) ?? [] {
            guard let root = decode(account),
                  let priv = try? kc.get(account),
                  let priv,
                  let keys = try? Keys(privateKeyHex: priv) else { continue }
            keysByRoot[root] = keys
            keysByPubkey[keys.publicKeyHex] = keys
            pubkeys.insert(keys.publicKeyHex)
        }
        publishSet(pubkeys)
    }

    private func publishSet(_ pubkeys: Set<String>) {
        let snapshot = pubkeys
        bg().perform { [weak self] in
            self?.bgAnonPubkeys = snapshot
        }
        // also set synchronously so freshly-minted keys are visible immediately on bg reads
        self.bgAnonPubkeys = snapshot
    }

    // MARK: - Lookup / mint
    func keys(forRoot root: String) -> Keys? {
        lock.lock(); defer { lock.unlock() }
        return keysByRoot[root]
    }

    func keys(forPubkey pubkey: String) -> Keys? {
        lock.lock(); defer { lock.unlock() }
        return keysByPubkey[pubkey]
    }

    func isAnonPubkey(_ pubkey: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return keysByPubkey[pubkey] != nil
    }

    /// Returns the existing key for the thread, or mints + persists a new one.
    /// `isNew` is true only when a key was freshly generated this call (used by undo-burn).
    func existingOrMint(forRoot root: String) throws -> (keys: Keys, isNew: Bool) {
        lock.lock()
        if let existing = keysByRoot[root] {
            lock.unlock()
            return (existing, false)
        }
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

    // MARK: - Forget
    func forget(root: String) {
        lock.lock()
        let keys = keysByRoot[root]
        keysByRoot[root] = nil
        if let pub = keys?.publicKeyHex { keysByPubkey[pub] = nil }
        let pubkeys = Set(keysByPubkey.keys)
        lock.unlock()

        try? keychain.remove(encode(root))
        publishSet(pubkeys)
    }

    func forget(pubkey: String) {
        lock.lock()
        guard let root = keysByRoot.first(where: { $0.value.publicKeyHex == pubkey })?.key else {
            lock.unlock(); return
        }
        lock.unlock()
        forget(root: root)
    }

    // MARK: - Testing
    func wipeAllForTesting() {
        try? keychain.removeAll()
        lock.lock()
        keysByRoot.removeAll(); keysByPubkey.removeAll()
        lock.unlock()
        publishSet([])
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: same as Step 2. Expected: PASS (all 6 tests).

- [ ] **Step 5: Commit**

```bash
git add Nostur/Post/PostComposer/Anon/EphemeralKeyStore.swift NosturTests/EphemeralKeyStoreTests.swift
git commit -m "feat(anon): add device-local EphemeralKeyStore (ThisDeviceOnly keychain)"
```

> **Implementer notes:**
> - Confirm the KeychainAccess import name (`import KeychainAccess`) matches existing usage in `AccountManager.swift`. If the project uses a vendored copy under a different module name, mirror that import.
> - `Keys.newKeys()`, `Keys(privateKeyHex:)`, `.publicKeyHex`, `.privateKeyHex` are used in `AccountManager.swift` and `NosturTests/ProfileHighlightsTests.swift` — confirm signatures there.
> - `bg()` is the project's background `NSManagedObjectContext` accessor used throughout (`AccountsState.swift:51`). If `bgAnonPubkeys` reads happen on the bg context, writing it inside `bg().perform` matches the existing `bgAccountPubkeys` pattern.

---

## Phase 2 — Anon-aware event building

### Task 4: Make `buildFinalEvent` anon-aware

Add an optional `anonPubkey: String?` parameter. When set: use it as the event pubkey, and skip the client tag and emoji tags. This is surgical — three guarded edits.

**Files:**
- Modify: `Nostur/Post/PostComposer/NewPostModel.swift` (`buildFinalEvent`, ~778–1059)
- Test: `NosturTests/AnonEventBuildingTests.swift`

- [ ] **Step 1: Read the current code**

Read `NewPostModel.swift:778–1059`. Locate exactly:
- the pubkey source (~781–783): `let publicKey = ...activeAccount...; nEvent.publicKey = publicKey`
- the emoji tag block (~1025–1035)
- the client tag block (~1047–1049)

- [ ] **Step 2: Add the parameter and guards**

Change the signature:
```swift
private func buildFinalEvent(imetas: [Imeta], replyTo: ReplyTo? = nil, quotePost: QuotePost? = nil, isPreviewContext: Bool = false, anonPubkey: String? = nil) -> NEvent?
```

Change the pubkey source (~781–783) to:
```swift
let publicKey = anonPubkey ?? (activeAccount?.publicKey ?? "")
nEvent.publicKey = publicKey
```

Wrap the emoji tag block (~1025–1035) so it is skipped for anon:
```swift
if anonPubkey == nil {
    let usedEmojiShortcodes = extractCustomEmojiShortcodes(from: content)
    for shortcode in usedEmojiShortcodes {
        // ... existing emoji-tag appending unchanged ...
    }
}
```

Wrap the client tag block (~1047–1049) so it is skipped for anon, unconditionally (do NOT also honor `postUserAgentEnabled` for anon — anon must never carry it):
```swift
if anonPubkey == nil,
   SettingsStore.shared.postUserAgentEnabled,
   !SettingsStore.shared.excludedUserAgentPubkeys.contains(nEvent.publicKey) {
    nEvent.tags.append(NostrTag(["client", NIP89_APP_NAME, NIP89_APP_REFERENCE]))
}
```

- [ ] **Step 3: Write the failing test**

This test drives the VM far enough to build an anon reply event. It uses the in-memory/preview helpers if available; if the VM cannot be unit-instantiated, mark this test `@Test(.disabled("covered by Gate 3 smoke"))` and rely on Phase 7 — but attempt the unit test first.

```swift
import Foundation
import Testing
import NostrEssentials
@testable import Nostur

struct AnonEventBuildingTests {

    @Test func anon_event_has_ephemeral_pubkey_and_no_client_or_emoji_tags() throws {
        SettingsStore.shared.postUserAgentEnabled = true   // would normally add client tag
        let keys = try Keys.newKeys()

        let vm = NewPostModel()
        vm.typingTextModel.text = "hello from anon :customemoji:"
        // Minimal kind:1 reply tags so rootScopeId resolves and buildFinalEvent runs the reply path.
        // (If a ReplyTo fixture is needed, construct it via the existing test/preview helpers.)
        let built = vm.buildFinalEventForTesting(anonPubkey: keys.publicKeyHex)

        let event = try #require(built)
        #expect(event.publicKey == keys.publicKeyHex)
        #expect(!event.tags.contains(where: { $0.type == "client" }))
        #expect(!event.tags.contains(where: { $0.type == "emoji" }))
    }
}
```

Add a tiny test seam to `NewPostModel` (next to `buildFinalEvent`):
```swift
#if DEBUG
func buildFinalEventForTesting(anonPubkey: String) -> NEvent? {
    buildFinalEvent(imetas: [], anonPubkey: anonPubkey)
}
#endif
```

- [ ] **Step 4: Run the test**

Run: `xcodebuild test -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 16 Pro (18.5),OS=18.5' -only-testing:NosturTests/AnonEventBuildingTests`
Expected: PASS. If `NewPostModel()` cannot be constructed in a test target, capture the exact error, disable the test with a reason referencing Gate 3, and proceed (the guards are still verified by build + smoke).

- [ ] **Step 5: Commit**

```bash
git add Nostur/Post/PostComposer/NewPostModel.swift NosturTests/AnonEventBuildingTests.swift
git commit -m "feat(anon): make buildFinalEvent anon-aware (no client tag, no emoji tags, ephemeral pubkey)"
```

---

### Task 5: Pre-publish identity assertion

A single chokepoint asserting the signed event's pubkey equals the intended ephemeral pubkey and the root scope matches the key's root. Used by the transport in Phase 3. Spec §0.

**Files:**
- Modify: `Nostur/Post/PostComposer/Anon/AnonReplyHelper.swift`
- Test: `NosturTests/AnonReplyHelperTests.swift` (extend)

- [ ] **Step 1: Add the failing test**

```swift
    @Test func assertion_passes_for_matching_pubkey_and_root() throws {
        let keys = try Keys.newKeys()
        var e = NEvent(content: "hi")
        e.tags = [NostrTag(["e", "ROOT123", "", "root"])]
        e.publicKey = keys.publicKeyHex
        #expect(AnonReplyHelper.isAnonSendSafe(signedEvent: e, expectedKeys: keys, expectedRoot: "E:ROOT123") == true)
    }

    @Test func assertion_fails_on_wrong_pubkey() throws {
        let keys = try Keys.newKeys()
        let other = try Keys.newKeys()
        var e = NEvent(content: "hi")
        e.tags = [NostrTag(["e", "ROOT123", "", "root"])]
        e.publicKey = other.publicKeyHex   // wrong identity!
        #expect(AnonReplyHelper.isAnonSendSafe(signedEvent: e, expectedKeys: keys, expectedRoot: "E:ROOT123") == false)
    }

    @Test func assertion_fails_on_root_drift() throws {
        let keys = try Keys.newKeys()
        var e = NEvent(content: "hi")
        e.tags = [NostrTag(["e", "DIFFERENT_ROOT", "", "root"])]
        e.publicKey = keys.publicKeyHex
        #expect(AnonReplyHelper.isAnonSendSafe(signedEvent: e, expectedKeys: keys, expectedRoot: "E:ROOT123") == false)
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild test ... -only-testing:NosturTests/AnonReplyHelperTests`
Expected: FAIL — `isAnonSendSafe` not defined.

- [ ] **Step 3: Implement**

Add to `AnonReplyHelper`:
```swift
    /// Final safety gate before an anon event leaves the device (spec §0).
    /// Returns true only if the event is signed by the expected ephemeral key
    /// AND threads under the expected root scope.
    static func isAnonSendSafe(signedEvent: NEvent, expectedKeys: Keys, expectedRoot: String) -> Bool {
        guard signedEvent.publicKey == expectedKeys.publicKeyHex else { return false }
        guard rootScopeId(fromTags: signedEvent.tags) == expectedRoot else { return false }
        return true
    }
```

- [ ] **Step 4: Run to verify pass**

Run: same. Expected: PASS (all AnonReplyHelper tests).

- [ ] **Step 5: Commit**

```bash
git add Nostur/Post/PostComposer/Anon/AnonReplyHelper.swift NosturTests/AnonReplyHelperTests.swift
git commit -m "feat(anon): add pre-publish identity+root assertion (spec §0)"
```

---

## Phase 3 — Isolated transport

### Task 6: `AnonPublisher` — isolated send with OK threshold and undo window

Publishes a signed anon event over fresh `OneOffEventPublisher` sockets (one per relay, `allowAuth: false`) to the fixed relay set plus the parent author's NIP-65 read relays. Saves the event locally for immediate thread display. Provides a 9s undo window; cancelling burns a freshly-minted key.

**Files:**
- Create: `Nostur/Post/PostComposer/Anon/AnonPublisher.swift`
- Reference (read, do not modify): `Nostur/Relays/Network/OneOffEventPublisher.swift` (constructor `init(_:allowAuth:signNEventHandler:)`, `connect(timeout:)`, `publish(_:timeout:)`), `Nostur/Nostr/Unpublisher.swift:188–216` (the `Event.saveEvent` + `.newPostSaved` local-consume pattern), `Nostur/Relays/Network/ConnectionPool.swift` (how NIP-65 read relays for a pubkey are resolved — `preferredRelays` / `resolveRelayHint`).

- [ ] **Step 1: Implement the publisher**

```swift
//  AnonPublisher.swift
//  Nostur
//
//  Isolated publish path for anonymous replies. NEVER uses ConnectionPool's
//  pooled (identified) connections. Each relay gets a brand-new websocket via
//  OneOffEventPublisher with allowAuth:false, so a NIP-42 AUTH challenge can
//  never be answered with a real account key (spec §0, §4).

import Foundation
import NostrEssentials

struct AnonPublishResult {
    let okCount: Int
    let attempted: Int
    var success: Bool { okCount >= 1 }   // threshold: at least one relay accepted
}

@MainActor
final class AnonPublisher {
    static let shared = AnonPublisher()

    /// Fixed public relays verified to accept writes from fresh keys (spec §5; live-checked 2026-06-11).
    static let fixedRelays: [String] = [
        "wss://relay.damus.io",
        "wss://nos.lol",
        "wss://relay.primal.net",
    ]

    private let undoWindow: TimeInterval = 9.0
    private var pending: [UUID: DispatchWorkItem] = [:]

    /// Queue an anon reply: save locally now (immediate thread display), fire after the undo window.
    /// Returns a cancellation id used by the Undo button.
    func publish(signedEvent: NEvent,
                 parentAuthorPubkey: String,
                 keysWereNewlyMinted: Bool,
                 rootScope: String) -> UUID {
        let cancellationId = UUID()

        // 1. Save locally + notify so the reply appears in the thread immediately.
        //    Mirror Unpublisher.sendToRelays local-consume (Unpublisher.swift:188–216).
        bg().perform {
            let saved = Event.saveEvent(event: signedEvent, context: bg())
            saved.cancellationId = cancellationId
            DispatchQueue.main.async { sendNotification(.newPostSaved, saved) }
        }

        // 2. Schedule the real send after the undo window.
        let work = DispatchWorkItem { [weak self] in
            self?.pending[cancellationId] = nil
            Task { await self?.fire(signedEvent: signedEvent, parentAuthorPubkey: parentAuthorPubkey) }
        }
        pending[cancellationId] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + undoWindow, execute: work)
        return cancellationId
    }

    /// Undo before the window elapses: remove local event, burn the key only if freshly minted (spec §6).
    func cancel(_ cancellationId: UUID, rootScope: String, keysWereNewlyMinted: Bool, eventId: String) -> Bool {
        guard let work = pending[cancellationId] else { return false }
        work.cancel()
        pending[cancellationId] = nil
        bg().perform {
            if let event = try? Event.fetchEvent(id: eventId, context: bg()) {
                bg().delete(event)
            }
        }
        if keysWereNewlyMinted {
            EphemeralKeyStore.shared.forget(root: rootScope)
        }
        return true
    }

    @discardableResult
    private func fire(signedEvent: NEvent, parentAuthorPubkey: String) async -> AnonPublishResult {
        let relays = relayTargets(parentAuthorPubkey: parentAuthorPubkey)
        let json = signedEvent.eventJson()   // confirm the existing NEvent->wire-JSON accessor name

        var okCount = 0
        await withTaskGroup(of: Bool.self) { group in
            for relay in relays {
                group.addTask {
                    do {
                        // allowAuth:false => never answers AUTH; signNEventHandler is never called.
                        let pub = try OneOffEventPublisher(relay, allowAuth: false, signNEventHandler: { ev in ev })
                        try await pub.connect(timeout: 8)
                        try await pub.publish(signedEvent, timeout: 8)
                        return true
                    } catch {
                        return false
                    }
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

    /// Fixed relays plus the parent author's NIP-65 read relays (deduped). Spec §5.
    private func relayTargets(parentAuthorPubkey: String) -> [String] {
        var set = Set(Self.fixedRelays.map { normalizeRelayUrl($0) })
        for r in parentReadRelays(parentAuthorPubkey) { set.insert(normalizeRelayUrl(r)) }
        return Array(set)
    }

    private func parentReadRelays(_ pubkey: String) -> [String] {
        // Resolve the author's NIP-65 (kind:10002) read relays via the existing mechanism.
        // ConnectionPool.shared.preferredRelays exposes reach/read relay plans; if a direct
        // per-pubkey read-relay lookup exists (used by the outbox model), use it here.
        // Cap to a small number (e.g. 4) to bound exposure and connection count.
        return Array(ConnectionPool.shared.readRelays(forPubkey: pubkey).prefix(4))
    }
}
```

- [ ] **Step 2: Resolve the three API names this task depends on**

Before building, confirm and fix these against source (they are the only unknowns):
1. `signedEvent.eventJson()` — the accessor that returns the `["EVENT", {...}]` wire string. Grep how `OneOffEventPublisher.sendEvent` / `ConnectionPool.sendMessage` serialize an `NEvent` and use the same call.
2. `Event.fetchEvent(id:context:)` — confirm the fetch-by-id API (grep `func fetchEvent` / `Event.fetchEvent`).
3. `ConnectionPool.shared.readRelays(forPubkey:)` — there is no guarantee this exact method exists. Grep for how the outbox model resolves a pubkey's read relays (search `kind 10002`, `preferredRelays`, `reachUserRelays`, `WritePlan`, `createWritePlan`). Replace `parentReadRelays` body with the real lookup. If no clean per-pubkey read-relay API exists, ship v1 with **fixed relays only** and add a `// TODO(anon): add parent NIP-65 read-relay delivery` plus `log()`-style comment — and note this scope cut in the PR description (it degrades reach, not safety).

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Nostur/Post/PostComposer/Anon/AnonPublisher.swift
git commit -m "feat(anon): isolated AnonPublisher (OneOffEventPublisher per relay, OK threshold, undo window)"
```

> **Why `OneOffEventPublisher` and not `sendEphemeralMessage`:** `sendEphemeralMessage` routes through `ConnectionPool` which can reuse a pooled, identified connection and trigger real-key AUTH (the headline blocker in the spec review). `OneOffEventPublisher` opens a private `URLSessionWebSocketTask` and, with `allowAuth:false`, throws on auth-required instead of signing AUTH with any account. This makes spec §0 structural.

---

### Task 7: Anon send entry point on `NewPostModel`

A `sendNowAnon` method that resolves the root scope, mints/looks up keys, builds the anon event, signs locally, runs the assertion, and hands off to `AnonPublisher`. It never reads `activeAccount`.

**Files:**
- Modify: `Nostur/Post/PostComposer/NewPostModel.swift`

- [ ] **Step 1: Add anon state**

Near `activeAccount` (~189):
```swift
@Published var anonMode: Bool = false   // reply-only; set by the switcher
```

- [ ] **Step 2: Add the send method**

```swift
@MainActor
func sendNowAnon(replyTo: ReplyTo, onDismiss: @escaping () -> Void) async {
    // Build the event first (anon-aware) so we can derive the real root scope from its tags.
    // Temporary placeholder pubkey; overwritten after we resolve/mint the key.
    guard let draftEvent = buildFinalEvent(imetas: [], replyTo: replyTo, anonPubkey: "0") else {
        sendNotification(.anyStatus, ("Could not build reply", "NewPost")); return
    }
    guard let rootScope = AnonReplyHelper.rootScopeId(fromTags: draftEvent.tags) else {
        sendNotification(.anyStatus, ("Could not determine thread root", "NewPost")); return
    }

    let minted: (keys: Keys, isNew: Bool)
    do { minted = try EphemeralKeyStore.shared.existingOrMint(forRoot: rootScope) }
    catch { sendNotification(.anyStatus, ("Could not create anon identity", "NewPost")); return }

    // Rebuild with the real ephemeral pubkey, then sign locally.
    guard var finalEvent = buildFinalEvent(imetas: [], replyTo: replyTo, anonPubkey: minted.keys.publicKeyHex) else {
        sendNotification(.anyStatus, ("Could not build reply", "NewPost")); return
    }
    finalEvent.createdAt = NTimestamp(date: Date())
    guard let signed = try? finalEvent.sign(minted.keys) else {
        sendNotification(.anyStatus, ("Could not sign anon reply", "NewPost")); return
    }

    // Spec §0 gate. Abort hard on any mismatch.
    guard AnonReplyHelper.isAnonSendSafe(signedEvent: signed, expectedKeys: minted.keys, expectedRoot: rootScope) else {
        if minted.isNew { EphemeralKeyStore.shared.forget(root: rootScope) }
        sendNotification(.anyStatus, ("Anon reply blocked: identity check failed", "NewPost"))
        return
    }

    let parentAuthor = replyTo.nrPost.kind == 9735 ? (replyTo.nrPost.fromPubkey ?? replyTo.nrPost.pubkey) : replyTo.nrPost.pubkey
    _ = AnonPublisher.shared.publish(
        signedEvent: signed,
        parentAuthorPubkey: parentAuthor,
        keysWereNewlyMinted: minted.isNew,
        rootScope: rootScope
    )
    onDismiss()
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
Expected: BUILD SUCCEEDED. (Fix `NTimestamp` init name if it differs — see `buildFinalEvent` ~785.)

- [ ] **Step 4: Commit**

```bash
git add Nostur/Post/PostComposer/NewPostModel.swift
git commit -m "feat(anon): add sendNowAnon entry point (resolve root, mint key, sign, assert, publish)"
```

> **Note:** building twice is intentional and cheap — the first build derives the true root scope from the reply tags; the second stamps the resolved ephemeral pubkey. The §0 assertion then cross-checks both, satisfying the spec's "compute root once, assert at publish" requirement.

---

## Phase 4 — Composer UI

### Task 8: Anon item in `InlineAccountSwitcher` (reply-only)

Add an opt-in anon entry that emits a distinct selection, without fabricating a `CloudAccount`.

**Files:**
- Modify: `Nostur/Post/PostComposer/PostAccountSwitcher.swift`
- Modify: `Nostur/Post/PostComposer/ComposePost.swift` (only the default text reply site, ~419)

- [ ] **Step 1: Extend the switcher**

Add stored properties:
```swift
public var showAnonOption: Bool = false
public var isAnonSelected: Bool = false
public var onSelectAnon: (() -> Void)? = nil
```
After the account rows in the fan-out `ForEach`, when `showAnonOption` add one more tappable item rendered with an incognito glyph (`Image(systemName: "theatermasks.fill")` in a `Circle`, sized `size`), whose tap (when already expanded) calls `onSelectAnon?()` then collapses. When `isAnonSelected`, the collapsed/primary slot shows the incognito glyph instead of a PFP. Keep the existing `Equatable` conformance correct by adding `isAnonSelected` to `==`.

- [ ] **Step 2: Wire the default text reply site only (ComposePost.swift ~419)**

```swift
InlineAccountSwitcher(
    activeAccount: account,
    onChange: { account in
        vm.anonMode = false
        vm.activeAccount = account
    },
    showAnonOption: (replyTo != nil),
    isAnonSelected: vm.anonMode,
    onSelectAnon: { vm.enterAnonMode() }
).equatable()
```
Leave the other four call sites (voice 89, highlight 156, picture 240, short-video 281) unchanged — anon must not appear there (spec §1).

- [ ] **Step 3: Build & visually confirm**

Run the app (`/run` or Xcode), open a reply composer on a normal kind:1 post, confirm the incognito item appears and selecting it flips the slot to the incognito glyph. Confirm it does NOT appear when composing a new post, quote, picture, highlight, or voice.

- [ ] **Step 4: Commit**

```bash
git add Nostur/Post/PostComposer/PostAccountSwitcher.swift Nostur/Post/PostComposer/ComposePost.swift
git commit -m "feat(anon): add reply-only anon item to InlineAccountSwitcher"
```

---

### Task 9: `enterAnonMode` — mutual exclusion, media/emoji/draft hard-block

**Files:**
- Modify: `Nostur/Post/PostComposer/NewPostModel.swift`
- Modify: `Nostur/Post/PostComposer/TypingTextModel` (the `text.didSet` draft write, ~33–37) and `Drafts` usage

- [ ] **Step 1: Implement `enterAnonMode`**

```swift
@MainActor
func enterAnonMode() {
    anonMode = true
    // Mutual exclusion with private/DM replies (spec §1) — anon must never enter the giftwrap branch.
    replyInPrivate = false
    // Hard-block media (spec §6): clear any buffers that would trigger real-key upload auth.
    typingTextModel.pastedImages = []
    typingTextModel.pastedVideos = []
    typingTextModel.voiceRecording = nil
    remoteIMetas = [:]
    // Custom emoji is disabled in anon mode (handled in buildFinalEvent; also clear any selection state).
}
```

- [ ] **Step 2: Gate the global draft write**

In `TypingTextModel.text.didSet` (~33–37), do not persist to the shared draft while anon. The model needs a reference to anon state; the simplest is a flag on the typing model set when entering/leaving anon:
```swift
@Published var anonMode: Bool = false
@Published var text: String = "" {
    didSet {
        if !anonMode { draft = text }
    }
}
```
Set `typingTextModel.anonMode = true` inside `enterAnonMode()` and `= false` in the `onChange` (account) closure. Also ensure the undo-send restore path (`OwnPostFooter.swift:107–113`) is not reached for anon (anon undo is handled by `AnonPublisher.cancel`, Task 11) — guarded by the anon ownership routing there.

- [ ] **Step 3: Disable media/emoji buttons in the reply composer UI when `vm.anonMode`**

In the default text reply composer (`ComposePost.swift` ~419 block and its toolbar/`Entry.swift`), hide or `.disabled(vm.anonMode)` the attachment and custom-emoji buttons, and disable drag-drop (`ComposePost.swift:529`) and paste (`Entry.swift:219`) handlers when `vm.anonMode`.

- [ ] **Step 4: Route the send button to the anon path**

In `Entry.swift` `sendNow()` (~601), branch at the top:
```swift
private func sendNow() {
    if vm.anonMode, let replyTo {
        typingTextModel.sending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Task { await self.vm.sendNowAnon(replyTo: replyTo, onDismiss: { onDismiss() }) }
        }
        return
    }
    // ... existing account path unchanged ...
}
```
Apply the same guard in `PostPreview.swift` (~69) if the preview send is reachable for replies. `AudioRecorder.swift` is not touched (voice is out of scope).

- [ ] **Step 5: Build & confirm**

Build; in a reply composer toggle anon and confirm attachment + emoji controls are disabled and the send routes to the anon path (breakpoint or a debug log in `sendNowAnon`).

- [ ] **Step 6: Commit**

```bash
git add Nostur/Post/PostComposer/NewPostModel.swift Nostur/Post/PostComposer/Entry.swift Nostur/Post/PostComposer/ComposePost.swift Nostur/Post/PostComposer/PostPreview.swift
git commit -m "feat(anon): enterAnonMode — private-reply exclusion, media/emoji/draft hard-block, send routing"
```

---

## Phase 5 — Thread integration

### Task 10: Ownership gates consult the anon pubkey set

So the user's own anon replies render as "mine" (not hidden by WoT) with footer/menu actions.

**Files:**
- Modify: `Nostur/Post/NR/NRPost.swift` (~470, ~1371, ~1391)

- [ ] **Step 1: `isOwnPost` (~470)**

```swift
self.ownPostAttributes = OwnPostAttributes(
    id: event.id,
    isOwnPost: AccountsState.shared.bgFullAccountPubkeys.contains(pubkey)
        || EphemeralKeyStore.shared.bgAnonPubkeys.contains(pubkey),
    relays: event.relays, cancellationId: cancellationId, flags: event.flags)
```

- [ ] **Step 2: WoT inclusion filter `sortGroupedReplies` (~1371)**

```swift
.filter { $0.inWoT
    || AccountsState.shared.bgAccountPubkeys.contains($0.pubkey)
    || EphemeralKeyStore.shared.bgAnonPubkeys.contains($0.pubkey)
    || $0.pubkey == self.pubkey }
```

- [ ] **Step 3: `sortGroupedRepliesNotWoT` (~1391)**

```swift
.filter { !$0.inWoT
    && !AccountsState.shared.bgAccountPubkeys.contains($0.pubkey)
    && !EphemeralKeyStore.shared.bgAnonPubkeys.contains($0.pubkey)
    && $0.pubkey != self.pubkey }
```

- [ ] **Step 4: Build & commit**

```bash
xcodebuild -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
git add Nostur/Post/NR/NRPost.swift
git commit -m "feat(anon): include anon pubkeys in ownership/WoT thread gates"
```

---

### Task 11: "you (anon)" indicator + anon undo routing + delete + forget

**Files:**
- Modify: `Nostur/Post/OwnPostFooter.swift` (undo routing)
- Modify: `Nostur/Post/PostMenu/PostMenu.swift` (~263) and the delete handler in `Nostur/Utils/View+withSheets.swift` (~176–201)
- Modify: a small indicator in the post header/footer for anon-owned posts

- [ ] **Step 1: Anon undo routing in `OwnPostFooter`**

The Undo button (~107) currently calls `nrPost.unpublish()` + restores the draft. For anon-owned posts (pubkey in `EphemeralKeyStore.shared.bgAnonPubkeys`), route to `AnonPublisher.shared.cancel(...)` instead and do NOT restore the global draft. You need the `cancellationId`, `rootScope`, and `keysWereNewlyMinted` for the post — store these on `ownPostAttributes` when saving the anon event (extend the save in `AnonPublisher.publish` to stamp them), or look up `rootScope` via `AnonReplyHelper.rootScopeId(fromTags:)` on the event and `keysWereNewlyMinted=false` (safe default: never burn on undo if unknown).

- [ ] **Step 2: Anon delete path**

In `PostMenu.swift` the delete item is gated `isOwnPost && isFullAccount`. Add an anon branch: when `EphemeralKeyStore.shared.bgAnonPubkeys.contains(nrPost.pubkey)`, show Delete (without the `isFullAccount` requirement). On tap, send a new notification `.requestDeleteAnonPost` carrying the event id.

In `View+withSheets.swift`, handle `.requestDeleteAnonPost`:
```swift
guard let keys = EphemeralKeyStore.shared.keys(forPubkey: nrPost.pubkey) else { return }
var deletion = NEvent(content: "")
deletion.kind = .delete
deletion.tags = [ NostrTag(["e", eventId]), NostrTag(["k", String(deletedKind)]) ] // NIP-09: include k tag
deletion.publicKey = keys.publicKeyHex
guard let signed = try? deletion.sign(keys) else { return }
// publish over the same isolated path:
await AnonPublisher.shared.publishRaw(signed, parentAuthorPubkey: nrPost.pubkey)
```
Add `publishRaw(_:parentAuthorPubkey:)` to `AnonPublisher` (a thin wrapper around `fire` with no undo window / no local-save), and a confirmation dialog reusing the existing "It's up to relays and other apps to honor your request" copy.

- [ ] **Step 3: Forget identity action**

Add a context-menu item on anon-owned posts: "Forget this anon identity" → confirmation ("You will no longer be able to continue or delete replies from this identity") → `EphemeralKeyStore.shared.forget(pubkey: nrPost.pubkey)`.

- [ ] **Step 4: Indicator**

Where the author name/handle renders for a post, when `EphemeralKeyStore.shared.bgAnonPubkeys.contains(nrPost.pubkey)` show a small "you · anon" badge.

- [ ] **Step 5: Build & commit**

```bash
xcodebuild -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
git add -A
git commit -m "feat(anon): you-anon indicator, anon undo routing, NIP-09 anon delete (e+k), forget identity"
```

> **Note (NIP-09):** the existing `makeDeleteEvent` (`Messages.swift:436`) emits only an `e` tag. The anon delete above adds the `k` tag per NIP-09 (Gate 1). Deletion is a *request* — the confirmation copy already says relays/apps may ignore it.

---

## Phase 6 — Explainer + startup wiring

### Task 12: First-use explainer + startup load

**Files:**
- Modify: `Nostur/NosturApp.swift` or `Nostur/AppState.swift` (call `EphemeralKeyStore.shared.load()` at launch)
- Modify: `Nostur/Post/PostComposer/NewPostModel.swift` (`enterAnonMode` shows the one-time alert)

- [ ] **Step 1: Load anon keys at startup**

In the startup path (mirror where `AccountsState` / other singletons load, e.g. `AppState` init or `loadAccountsState`), call `EphemeralKeyStore.shared.load()` so `bgAnonPubkeys` is populated before threads render.

- [ ] **Step 2: One-time explainer**

In `enterAnonMode()`, if `!UserDefaults.standard.bool(forKey: "anonReplyExplainerShown")`, post a notification that presents an alert with this copy, then set the flag:

> **Reply anonymously**
> This reply will be posted from a new one-time identity that isn't linked to any of your accounts.
> This identity — and your ability to continue or delete it — lives only on this device. It is not backed up and won't appear on your other devices.
> Note: relays can still see your IP address, and your writing style may identify you. Deletion is a request that relays and other apps may ignore.
> [Cancel] [Continue anonymously]

"Cancel" sets `anonMode = false`. (Implementer: reuse the project's existing alert/confirmation presentation pattern, e.g. an `AppSheetsModel` flag or a `.alert` bound in the composer.)

- [ ] **Step 3: Build & confirm the alert shows once**

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(anon): startup key load + one-time anonymity explainer"
```

---

## Phase 7 — 🔒 Gate 3: realistic-relay smoke (pre-merge, human-in-the-loop)

This gate is mandatory before merge (nostr-feature skill). Offline tests do not cover the wire, the key, or the relay. Use the `nak` skill for on-wire verification.

- [ ] **Step 1: Build and run on a simulator/device with a real logged-in account.**

- [ ] **Step 2: Post an anon reply to a normal kind:1 post.** Capture the event id (debug log it in `sendNowAnon`).

- [ ] **Step 3: Verify on the wire with `nak`** — fetch the event by id from `wss://relay.damus.io` and confirm field-by-field:
  - `pubkey` is the ephemeral key (NOT any of your account pubkeys),
  - no `["client", ...]` tag (with `postUserAgentEnabled` ON),
  - no `["emoji", ...]` tag,
  - correct NIP-10 / NIP-22 root+reply tags and `p` tags,
  - correct kind (1 for kind:1 parent; 1111 for a NIP-22 parent).

- [ ] **Step 4: Negative check — real-key leakage.** Confirm the event does NOT appear on your configured write relays that are outside the anon set, and (via logs / a relay that challenges AUTH) confirm no NIP-42 AUTH was sent with a real key during the publish.

- [ ] **Step 5: Cross-client visibility.** From a SECOND, unrelated account, view the thread on Damus, Amethyst, and Primal. Confirm the anon reply actually surfaces (fresh-key spam filtering is the risk). If it is filtered/hidden, add NIP-13 PoW to the anon event (spec §5 contingency) and re-test.

- [ ] **Step 6: Continuity + persistence.** Post a second anon reply in the same thread → confirm same `pubkey`. Force-quit and relaunch the app → confirm the thread still shows your anon replies as "you · anon" and Delete/Forget are available.

- [ ] **Step 7: Delete + undo.** Delete an anon reply (verify the kind:5 with `e`+`k` on the wire with `nak`). Post another and hit Undo within 9s → confirm it never reaches the relays (`nak` finds nothing) and, if it was the thread's first anon reply, the key is burned.

- [ ] **Step 8: Edge cases.** Max-length reply text; reply to a NIP-22 parent (article/voice) and confirm the root scope keys correctly (same identity across two replies under that article).

- [ ] **Step 9: Record evidence** (the `nak` outputs and the negative-leak confirmation) in the PR description, along with the abuse-considerations note (spec §7) and the "no kill-switch in v1" flag for the maintainer.

---

## Self-review checklist (run before handing off)

- [ ] Every spec section maps to a task: §0 invariant → Tasks 5,7; §1 UX → Tasks 8,9,12; §2 key store → Task 3; §3 SendIdentity/build → Tasks 2,4; §4 transport → Tasks 6,7; §5 event/relays/thread → Tasks 6,10,11; §6 edge cases/rules → Tasks 7,9,11; §7 abuse → Task 7 (PR note), §8 testing → Tasks 1–5,7.
- [ ] No real-account API is reachable from `sendNowAnon` / `AnonPublisher` (grep these for `activeAccount`, `account.signEvent`, `AccountManager`, `Unpublisher.shared`, `sendEphemeralMessage` — expect none).
- [ ] The §0 assertion (`isAnonSendSafe`) is the only path to publish in `sendNowAnon`, and aborts on mismatch.
- [ ] Three API names confirmed in Task 6 Step 2 (`eventJson`, `fetchEvent`, read-relay lookup).
- [ ] Voice/highlight/picture/short-video composers and new-post/quote do NOT show the anon item.
```
