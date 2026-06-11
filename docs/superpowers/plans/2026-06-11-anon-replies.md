# Anonymous (Ephemeral-Key) Replies Implementation Plan — v1 (truly ephemeral)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Revision 3 (2026-06-11) — truly-ephemeral pivot.** v1 mints a fresh key per reply and discards it on send (Amethyst-parity). This removes the keychain key store, per-thread root-scope keying, delete, forget, startup load, multi-device, and the undo-burn registry — the persistence machinery where the prior adversarial pass found most blockers. The §0 invariant and the isolated leak-proof transport are unchanged. Per-thread continuity + delete are deferred to v2. All code below reflects source verified 2026-06-11.

**Goal:** Let a user reply in a thread under a freshly generated, one-time ephemeral key instead of one of their accounts. The key is minted at send and discarded — not persisted.

**Architecture:** A fully isolated anon send path that never reads `activeAccount`. At send: mint `Keys.newKeys()`, build the reply via the existing `buildFinalEvent` made anon-aware (ephemeral pubkey; no client/emoji/relay-hint/NIP-70 tags), sign locally, run the §0 assertion, publish over `OneOffEventPublisher` (fresh websocket per relay, with a **hard-throwing** AUTH signer so no NIP-42 AUTH is ever emitted) to a fixed relay set plus the parent author's kind:10002 read relays, then discard the key. An in-memory session set of anon pubkeys drives "you · anon" thread display. No keychain, no Core Data, no CloudKit.

**Tech Stack:** Swift, SwiftUI, NostrEssentials (`Keys`, `NEvent`), Swift Testing (`import Testing`, `@Test`, `#expect`), Core Data (read/local-consume only).

**Spec:** `docs/superpowers/specs/2026-06-10-anon-replies-design.md` — read it first. §0 invariant: nothing on the anon path may sign with, authenticate as, persist under, or publish over a connection associated with the real account.

**Build/test:**
- Build: `xcodebuild -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
- Test: `xcodebuild test -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 16 Pro (18.5),OS=18.5' -only-testing:NosturTests/<TestType>`

---

## Verified codebase facts (confirmed against source 2026-06-11)

- `NewPostModel.swift:779-781`: `guard var nEvent = self.nEvent else { return nil }` / `guard let account = activeAccount else { return nil }` / `let publicKey = account.publicKey`. `self.nEvent` (`:165`) defaults nil, set only in `loadReplyTo` (`:1577`).
- `NewPostModel.swift:1025-1035` emoji block; `:1037-1041` NIP-70 `["-"]` block (when `Drafts.shared.lockToThisRelay != nil && lockToSingleRelay`); `:1047-1049` client-tag block.
- NIP-22 reply tags embed relay hints via `resolveRelayHint(...)` in `addRootScopeTags`/`addReplyToTags` (`~1894-1965`).
- `OneOffEventPublisher.swift:194-204`: `case .AUTH:` calls `sendAuthResponse()` with **no `allowAuth` guard**, wrapped in `do { ... } catch { L.og.debug(...) }`; `:262-281` `sendAuthResponse` calls `signNEventHandler(...)` then sends AUTH. A **throwing** `signNEventHandler` aborts AUTH cleanly with nothing sent. Constructor: `init(_ urlString:String, allowAuth:Bool=false, signNEventHandler: @escaping (NEvent) async throws -> NEvent)`; `connect(timeout:)`, `publish(_:timeout:)`.
- `Nostr.swift:380` `mutating func sign(_ keys: Keys) throws -> NEvent` sets the event pubkey from the keys (so post-sign `pubkey == thoseKeys` is tautological — Task 3).
- `Unpublisher.swift:188-216`: local-consume pattern — `Event.saveEvent(event:context:)` then `sendNotification(.newPostSaved, saved)`.
- `OutboxLoader.swift:280-288` `getInboxRelays(forPubkey:)` computes read relays then `return []` (stub — read kind:10002 directly via `Event.fetchReplacableEvent(10002, pubkey:context:)`, parse `fastTags` `r`/read).
- `_Temp/ViewUpdates.swift:41` `updateNRPost = PassthroughSubject<Event, Never>()` — sending an `Event` updates that post's `ownPostAttributes` (drives the undo footer's `cancellationId`). Used at `OwnPostFooter.swift:175`.
- `NRPost.swift:470` `isOwnPost` from `bgFullAccountPubkeys`; `:1371`/`:1391` WoT reply filters; these run on the bg context.
- `Keys.newKeys()`/`Keys(privateKeyHex:)` throw; `.publicKeyHex`; `NEvent.sign(_:) throws`; `NTimestamp(date:)`; `NostrTag` `.type`/`.tag`/`[safe:]`; `normalizeRelayUrl(_)`; `bg()`; `sendNotification(_,_)` — all confirmed.

---

## Phase ordering

- **Phase 1:** `SendIdentity`, anon-aware `buildFinalEvent`, §0 assertion (TDD).
- **Phase 2:** `AnonReplySession` (in-memory anon pubkey set), `AnonPublisher` (isolated transport).
- **Phase 3:** `sendNowAnon`.
- **Phase 4:** composer UI (switcher item, exclusion, media/emoji/draft block, single dispatcher).
- **Phase 5:** thread display (ownership gates + indicator + optional mentions self-exclusion).
- **Phase 6:** explainer + composer-repurpose reset.
- **Phase 7:** 🔒 Gate 3 smoke.

---

## Phase 1 — Identity & event building

### Task 1: `SendIdentity` enum

**Files:** Create `Nostur/Post/PostComposer/Anon/SendIdentity.swift`; Test `NosturTests/SendIdentityTests.swift`

- [ ] **Step 1: Failing test**

```swift
import Foundation
import Testing
import NostrEssentials
@testable import Nostur

struct SendIdentityTests {
    @Test func anon_exposes_ephemeral_pubkey() throws {
        let keys = try Keys.newKeys()
        let id = SendIdentity.anon(keys)
        #expect(id.pubkey == keys.publicKeyHex)
        #expect(id.isAnon == true)
    }
}
```

- [ ] **Step 2: Run → FAIL** (`SendIdentity` undefined).
- [ ] **Step 3: Implement**

```swift
//  SendIdentity.swift
import Foundation
import NostrEssentials

enum SendIdentity {
    case account(CloudAccount)
    case anon(Keys)
    var pubkey: String {
        switch self { case .account(let a): return a.publicKey; case .anon(let k): return k.publicKeyHex }
    }
    var isAnon: Bool { if case .anon = self { return true }; return false }
}
```

- [ ] **Step 4: Run → PASS. Step 5: Commit**

```bash
git add Nostur/Post/PostComposer/Anon/SendIdentity.swift NosturTests/SendIdentityTests.swift
git commit -m "feat(anon): add SendIdentity enum"
```

---

### Task 2: §0 pre-publish assertion (`AnonReplyHelper`)

A post-sign `pubkey == theKeysWeSignedWith` check is tautological. The real guarantee: the signed pubkey **is** the ephemeral key and **is not** any real-account pubkey.

**Files:** Create `Nostur/Post/PostComposer/Anon/AnonReplyHelper.swift`; Test `NosturTests/AnonReplyHelperTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import Foundation
import Testing
import NostrEssentials
@testable import Nostur

struct AnonReplyHelperTests {
    @Test func passes_for_ephemeral_key_not_a_real_account() throws {
        let keys = try Keys.newKeys()
        var e = NEvent(content: "hi"); e.publicKey = keys.publicKeyHex
        #expect(AnonReplyHelper.isAnonSendSafe(signedEvent: e, expectedKeys: keys, realAccountPubkeys: ["realpub"]) == true)
    }
    @Test func fails_when_pubkey_is_a_real_account() throws {
        let keys = try Keys.newKeys()
        var e = NEvent(content: "hi"); e.publicKey = keys.publicKeyHex
        #expect(AnonReplyHelper.isAnonSendSafe(signedEvent: e, expectedKeys: keys, realAccountPubkeys: [keys.publicKeyHex]) == false)
    }
    @Test func fails_when_pubkey_is_not_the_expected_key() throws {
        let keys = try Keys.newKeys(); let other = try Keys.newKeys()
        var e = NEvent(content: "hi"); e.publicKey = other.publicKeyHex
        #expect(AnonReplyHelper.isAnonSendSafe(signedEvent: e, expectedKeys: keys, realAccountPubkeys: []) == false)
    }
}
```

- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement**

```swift
//  AnonReplyHelper.swift
import Foundation
import NostrEssentials

enum AnonReplyHelper {
    /// Final §0 gate before an anon event leaves the device. True only if the event is
    /// signed by the expected ephemeral key AND that pubkey is not any real-account key.
    static func isAnonSendSafe(signedEvent: NEvent, expectedKeys: Keys, realAccountPubkeys: Set<String>) -> Bool {
        guard signedEvent.publicKey == expectedKeys.publicKeyHex else { return false }
        guard !realAccountPubkeys.contains(signedEvent.publicKey) else { return false }
        return true
    }
}
```

- [ ] **Step 4: Run → PASS. Step 5: Commit**

```bash
git add Nostur/Post/PostComposer/Anon/AnonReplyHelper.swift NosturTests/AnonReplyHelperTests.swift
git commit -m "feat(anon): §0 pre-publish assertion (ephemeral key, not a real account)"
```

---

### Task 3: Anon-aware `buildFinalEvent`

Add `anonPubkey: String?`. When set: use it as the pubkey **without reading activeAccount**, and skip client / emoji / NIP-70 / relay-hint tags.

**Files:** Modify `Nostur/Post/PostComposer/NewPostModel.swift`; Test `NosturTests/AnonEventBuildingTests.swift`

- [ ] **Step 1: Read** `buildFinalEvent` (~778-1059) and `addRootScopeTags`/`addReplyToTags` (~1894-1965). Confirm lines 779/780/781, 1025-1035, 1037-1041, 1047-1049.

- [ ] **Step 2: Signature**

```swift
private func buildFinalEvent(imetas: [Imeta], replyTo: ReplyTo? = nil, quotePost: QuotePost? = nil, isPreviewContext: Bool = false, anonPubkey: String? = nil) -> NEvent?
```

- [ ] **Step 3: Replace the identity guard (780-781) so anon never reads activeAccount**

Replace:
```swift
        guard let account = activeAccount else { return nil }
        let publicKey = account.publicKey
```
with:
```swift
        let publicKey: String
        if let anonPubkey {
            publicKey = anonPubkey
        } else {
            guard let account = activeAccount else { return nil }
            publicKey = account.publicKey
        }
```

- [ ] **Step 4: Guard the three tag blocks for anon**

Wrap emoji (1025-1035) and NIP-70 (1037-1041) blocks each in `if anonPubkey == nil { ... }`. Replace the client block (1047-1049):
```swift
if anonPubkey == nil,
   SettingsStore.shared.postUserAgentEnabled,
   !SettingsStore.shared.excludedUserAgentPubkeys.contains(nEvent.publicKey) {
    nEvent.tags.append(NostrTag(["client", NIP89_APP_NAME, NIP89_APP_REFERENCE]))
}
```

- [ ] **Step 5: Strip relay hints on the anon path**

Add `anon: Bool = false` to `addRootScopeTags`/`addReplyToTags`; inside, use `let relayHint: String? = anon ? "" : resolveRelayHint(...).first`. At their call sites (~1016-1019) pass `anon: anonPubkey != nil`.

- [ ] **Step 6: DEBUG test seam**

```swift
#if DEBUG
func buildFinalEventForTesting(replyTo: ReplyTo, anonPubkey: String) -> NEvent? {
    loadReplyTo(replyTo)                  // sets self.nEvent + reply tags (line 779 needs it)
    return buildFinalEvent(imetas: [], replyTo: replyTo, anonPubkey: anonPubkey)
}
#endif
```

- [ ] **Step 7: Test** (needs a `ReplyTo` fixture via `testNRPost`/`PreviewFetcher`; if not constructible in the test target, mark `@Test(.disabled("needs composer fixture; covered by Gate 3"))` — do not claim PASS without a fixture).

```swift
import Foundation
import Testing
import NostrEssentials
@testable import Nostur

struct AnonEventBuildingTests {
    @Test func anon_event_has_ephemeral_pubkey_and_no_leaky_tags() throws {
        SettingsStore.shared.postUserAgentEnabled = true
        let keys = try Keys.newKeys()
        let replyTo = try makeKind1ReplyFixture()       // build via testNRPost/PreviewFetcher
        let vm = NewPostModel(); vm.typingTextModel.text = "hi :emoji:"
        let built = try #require(vm.buildFinalEventForTesting(replyTo: replyTo, anonPubkey: keys.publicKeyHex))
        #expect(built.publicKey == keys.publicKeyHex)
        #expect(!built.tags.contains(where: { $0.type == "client" }))
        #expect(!built.tags.contains(where: { $0.type == "emoji" }))
        #expect(!built.tags.contains(where: { $0.type == "-" }))
    }
}
```

- [ ] **Step 8: Run → PASS or DISABLED-with-reason. Step 9: Commit**

```bash
git add Nostur/Post/PostComposer/NewPostModel.swift NosturTests/AnonEventBuildingTests.swift
git commit -m "feat(anon): buildFinalEvent anon-aware (no activeAccount, no client/emoji/relay-hint/NIP-70 tags)"
```

---

## Phase 2 — Session set & isolated transport

### Task 4: `AnonReplySession` — in-memory anon pubkey set

No keychain. Tracks pubkeys created this launch so the user's own anon reply renders as "you · anon" during the session (lost on restart, by design).

**Files:** Create `Nostur/Post/PostComposer/Anon/AnonReplySession.swift`; Test `NosturTests/AnonReplySessionTests.swift`

- [ ] **Step 1: Failing test**

```swift
import Foundation
import Testing
@testable import Nostur

struct AnonReplySessionTests {
    @Test func tracks_registered_pubkeys() {
        let s = AnonReplySession()
        s.register("anonpub")
        #expect(s.isAnonPubkey("anonpub") == true)
        #expect(s.isAnonPubkey("other") == false)
    }
}
```

- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement** (single-writer bg set, matching `AccountsState`; lock-guarded membership for main-thread reads)

```swift
//  AnonReplySession.swift
//  In-memory only. No persistence. Tracks anon pubkeys created this launch
//  so the user's own anon reply shows as "you · anon" during the session.
import Foundation

final class AnonReplySession {
    static let shared = AnonReplySession()
    private let lock = NSLock()
    private var pubkeys: Set<String> = []

    /// bg-context-only mirror for NRPost build/sort (read on bg). Never read from main.
    public private(set) var bgAnonPubkeys: Set<String> = []

    func register(_ pubkey: String) {
        lock.lock(); pubkeys.insert(pubkey); let snap = pubkeys; lock.unlock()
        bg().perform { [weak self] in self?.bgAnonPubkeys = snap }
    }
    /// Thread-safe membership for main-thread call sites (PostMenu, OwnPostFooter, indicator).
    func isAnonPubkey(_ pubkey: String) -> Bool { lock.lock(); defer { lock.unlock() }; return pubkeys.contains(pubkey) }
}
```

- [ ] **Step 4: Run → PASS. Step 5: Commit**

```bash
git add Nostur/Post/PostComposer/Anon/AnonReplySession.swift NosturTests/AnonReplySessionTests.swift
git commit -m "feat(anon): in-memory AnonReplySession (no persistence)"
```

---

### Task 5: `AnonPublisher` — isolated send (throwing AUTH, OK threshold, 9s undo)

**🔒 AUTH leak fix:** `OneOffEventPublisher` answers unsolicited NIP-42 AUTH with no `allowAuth` check. The anon path passes a **throwing** `signNEventHandler`, so any AUTH attempt aborts and nothing is signed/sent. Do not rely on `allowAuth:false`.

**Files:** Create `Nostur/Post/PostComposer/Anon/AnonPublisher.swift`. Reference: `OneOffEventPublisher.swift`, `Unpublisher.swift:188-216`, `_Temp/ViewUpdates.swift:41`, `OutboxLoader.swift:280` (stub — don't call).

- [ ] **Step 1: Implement**

```swift
//  AnonPublisher.swift
//  Isolated publish path for anonymous replies. NEVER uses ConnectionPool's pooled
//  (identified) connections, and NEVER signs a NIP-42 AUTH (the signer throws). Spec §0/§4.
import Foundation
import NostrEssentials

enum AnonSendError: Error { case mustNotSign }
struct AnonPublishResult { let okCount: Int; let attempted: Int; var success: Bool { okCount >= 1 } }

@MainActor
final class AnonPublisher {
    static let shared = AnonPublisher()
    static let fixedRelays: [String] = ["wss://relay.damus.io", "wss://nos.lol", "wss://relay.primal.net"]

    private let undoWindow: TimeInterval = 9.0
    private var pending: [UUID: DispatchWorkItem] = [:]

    /// Queue an anon reply: save locally now (immediate display + undo footer), fire after the window.
    @discardableResult
    func publish(signedEvent: NEvent, parentAuthorPubkey: String) -> UUID {
        let cancellationId = UUID()
        bg().perform {
            let saved = Event.saveEvent(event: signedEvent, context: bg())
            saved.cancellationId = cancellationId
            DispatchQueue.main.async {
                sendNotification(.newPostSaved, saved)
                ViewUpdates.shared.updateNRPost.send(saved)   // drives the undo footer's cancellationId
            }
        }
        let work = DispatchWorkItem { [weak self] in
            self?.pending[cancellationId] = nil
            Task { await self?.fire(signedEvent: signedEvent, parentAuthorPubkey: parentAuthorPubkey) }
        }
        pending[cancellationId] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + undoWindow, execute: work)
        return cancellationId
    }

    /// Undo before the window: cancel the send and remove the local event. No key state to clean up.
    @discardableResult
    func cancel(cancellationId: UUID, eventId: String) -> Bool {
        guard let work = pending[cancellationId] else { return false }
        work.cancel(); pending[cancellationId] = nil
        bg().perform { if let e = Event.fetchEvent(id: eventId, context: bg()) { bg().delete(e) } }
        return true
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
```

- [ ] **Step 2: Build** — confirm `Event.saveEvent`/`fetchEvent`/`fetchReplacableEvent` and `OneOffEventPublisher.publish(_:timeout:)` signatures.
- [ ] **Step 3: Commit**

```bash
git add Nostur/Post/PostComposer/Anon/AnonPublisher.swift
git commit -m "feat(anon): isolated AnonPublisher (throwing AUTH signer, OK threshold, 9s undo, kind:10002 read relays)"
```

> **Optional defense-in-depth (separate reviewed change):** add `guard allowAuth else { return }` to `OneOffEventPublisher`'s `case .AUTH:` after confirming no existing caller relies on unsolicited-AUTH-with-allowAuth-false. The throwing signer already closes the leak without touching shared code.

---

## Phase 3 — Send entry point

### Task 6: `sendNowAnon` on `NewPostModel`

Mint → build → sign → §0 assert → register pubkey → publish → discard. Never reads `activeAccount`.

**Files:** Modify `Nostur/Post/PostComposer/NewPostModel.swift`

- [ ] **Step 1: State** (near `activeAccount`, ~189): `@Published var anonMode: Bool = false`
- [ ] **Step 2: Method**

```swift
@MainActor
func sendNowAnon(replyTo: ReplyTo, onDismiss: @escaping () -> Void) async {
    let keys: Keys
    do { keys = try Keys.newKeys() }
    catch { typingTextModel.sending = false
            sendNotification(.anyStatus, ("Could not create anon identity", "NewPost")); return }

    guard var finalEvent = buildFinalEvent(imetas: [], replyTo: replyTo, anonPubkey: keys.publicKeyHex) else {
        typingTextModel.sending = false
        sendNotification(.anyStatus, ("Could not build reply", "NewPost")); return
    }
    finalEvent.createdAt = NTimestamp(date: Date())
    guard let signed = try? finalEvent.sign(keys) else {
        typingTextModel.sending = false
        sendNotification(.anyStatus, ("Could not sign anon reply", "NewPost")); return
    }

    let realPubkeys = Set(AccountsState.shared.accounts.map { $0.publicKey })
    guard AnonReplyHelper.isAnonSendSafe(signedEvent: signed, expectedKeys: keys, realAccountPubkeys: realPubkeys) else {
        typingTextModel.sending = false
        sendNotification(.anyStatus, ("Anon reply blocked: identity check failed", "NewPost")); return
    }

    AnonReplySession.shared.register(keys.publicKeyHex)   // for "you · anon" display this session
    let parentAuthor = replyTo.nrPost.kind == 9735 ? (replyTo.nrPost.fromPubkey ?? replyTo.nrPost.pubkey) : replyTo.nrPost.pubkey
    AnonPublisher.shared.publish(signedEvent: signed, parentAuthorPubkey: parentAuthor)
    // `keys` goes out of scope here → private key discarded. Truly ephemeral.
    typingTextModel.sending = false
    onDismiss()
}
```

- [ ] **Step 3: Build & commit**

```bash
xcodebuild -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
git add Nostur/Post/PostComposer/NewPostModel.swift
git commit -m "feat(anon): sendNowAnon (mint, build, sign, §0 assert, publish, discard)"
```

---

## Phase 4 — Composer UI

### Task 7: Anon item in `InlineAccountSwitcher` (reply-only, not on private posts)

**Files:** Modify `Nostur/Post/PostComposer/PostAccountSwitcher.swift`, `Nostur/Post/PostComposer/ComposePost.swift` (default text reply site ~419).

- [ ] **Step 1: Extend the switcher** — add stored properties and include `isAnonSelected` in `==`:
```swift
public var showAnonOption: Bool = false
public var isAnonSelected: Bool = false
public var onSelectAnon: (() -> Void)? = nil
```
After the account rows, when `showAnonOption`, add a tappable incognito item (`Image(systemName: "theatermasks.fill")` in a `Circle`, size `size`); its tap (when expanded) calls `onSelectAnon?()` then collapses. When `isAnonSelected`, render the primary slot as the incognito glyph.

- [ ] **Step 2: Wire ONLY the default text reply site (~419)**
```swift
InlineAccountSwitcher(
    activeAccount: account,
    onChange: { account in vm.exitAnonMode(); vm.activeAccount = account },
    showAnonOption: (replyTo != nil && !vm.replyingToPrivatePost),   // hidden on private posts
    isAnonSelected: vm.anonMode,
    onSelectAnon: { vm.enterAnonMode() }
).equatable()
```
Leave the other four call sites unchanged.

- [ ] **Step 3: Build & visually confirm** — incognito item appears only on a normal text reply; absent on new post/quote/picture/highlight/voice/private-post replies. **Step 4: Commit**

```bash
git add Nostur/Post/PostComposer/PostAccountSwitcher.swift Nostur/Post/PostComposer/ComposePost.swift
git commit -m "feat(anon): reply-only anon switcher item, hidden on private posts"
```

---

### Task 8: `enterAnonMode`/`exitAnonMode`, single send dispatcher, media/emoji/draft block

**Files:** Modify `NewPostModel.swift` (+ `TypingTextModel`), `Entry.swift`, `PostPreview.swift`, `ComposePost.swift`.

- [ ] **Step 1: `TypingTextModel` anon flag + draft isolation**
```swift
@Published var anonMode: Bool = false
private var savedRealDraft: String = ""
@Published var text: String = "" { didSet { if !anonMode { draft = text } } }   // never persist anon text
func savedRealDraftSnapshotAndClear() { savedRealDraft = draft; anonMode = true; text = "" }
func restoreRealDraft() { anonMode = false; text = savedRealDraft; savedRealDraft = "" }
```

- [ ] **Step 2: enter/exit on `NewPostModel`**
```swift
@MainActor func enterAnonMode() {
    guard !anonMode else { return }
    anonMode = true
    typingTextModel.savedRealDraftSnapshotAndClear()   // also sets typingTextModel.anonMode = true
    replyInPrivate = false
    typingTextModel.pastedImages = []; typingTextModel.pastedVideos = []
    typingTextModel.voiceRecording = nil; remoteIMetas = [:]
    lockToSingleRelay = false
    maybeShowAnonExplainer()   // Task 10
}
@MainActor func exitAnonMode() {
    guard anonMode else { return }
    anonMode = false
    typingTextModel.restoreRealDraft()   // also sets typingTextModel.anonMode = false
}
```

- [ ] **Step 3: Single send dispatcher (closes the PostPreview real-account leak)** — call from BOTH `Entry.swift` (~601) and `PostPreview.swift` (~69):
```swift
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

- [ ] **Step 4: Hard-disable Preview + media/emoji/drag/paste in anon mode**
- `Entry.swift` previewButton (~348/400/455): `.disabled(shouldDisablePostButton || vm.anonMode)`.
- Attachment + custom-emoji buttons: `.disabled(vm.anonMode)`.
- Drag-drop (`ComposePost.swift:529`) + paste (`Entry.swift:219`): no-op when `vm.anonMode`.

- [ ] **Step 5: Build & confirm** — anon disables Preview/attachments/emoji; send routes to `sendNowAnon`; exiting anon restores prior draft. **Step 6: Commit**

```bash
git add Nostur/Post/PostComposer/NewPostModel.swift Nostur/Post/PostComposer/Entry.swift Nostur/Post/PostComposer/PostPreview.swift Nostur/Post/PostComposer/ComposePost.swift
git commit -m "feat(anon): enter/exit anon, single send dispatcher, preview/media/emoji/draft hard-block"
```

---

## Phase 5 — Thread display

### Task 9: Ownership gates + "you · anon" indicator + optional mentions self-exclusion

**Files:** Modify `NRPost.swift` (~470/1371/1391, bg), the author-handle view (indicator), `MentionsFeedModel.swift` (~72-75, optional).

- [ ] **Step 1: `isOwnPost` (~470, bg)**
```swift
isOwnPost: AccountsState.shared.bgFullAccountPubkeys.contains(pubkey)
    || AnonReplySession.shared.bgAnonPubkeys.contains(pubkey),
```
- [ ] **Step 2: WoT filter `sortGroupedReplies` (~1371)** — add `|| AnonReplySession.shared.bgAnonPubkeys.contains($0.pubkey)`.
- [ ] **Step 3: `sortGroupedRepliesNotWoT` (~1391)** — add `&& !AnonReplySession.shared.bgAnonPubkeys.contains($0.pubkey)`.
- [ ] **Step 4: Indicator** — where the author handle renders, when `AnonReplySession.shared.isAnonPubkey(nrPost.pubkey)` (main-thread → use `isAnonPubkey`), show a small "you · anon" badge.
- [ ] **Step 5 (optional):** exclude `AnonReplySession.shared.bgAnonPubkeys` from the `MentionsFeedModel` predicate so an anon reply to your own post doesn't self-notify during the session.
- [ ] **Step 6: Build & commit**
```bash
xcodebuild -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
git add -A
git commit -m "feat(anon): in-session ownership gates + you-anon indicator"
```

> No delete / forget tasks in v1 — the key is discarded, so a kind:5 can't be signed. Deferred to v2 with persistence.

---

## Phase 6 — Explainer + repurpose reset

### Task 10: One-time explainer + composer-repurpose reset

**Files:** Modify `NewPostModel.swift` (`maybeShowAnonExplainer`, repurpose reset), `ComposePost.swift` (audio switch-back ~115).

- [ ] **Step 1: Repurpose reset (spec §6)** — at the START of `loadReplyTo` and `loadQuotingEvent`, and in the audio switch-back closure:
```swift
anonMode = false
typingTextModel.anonMode = false
```
- [ ] **Step 2: One-time explainer**
```swift
private func maybeShowAnonExplainer() {
    guard !UserDefaults.standard.bool(forKey: "anonReplyExplainerShown") else { return }
    UserDefaults.standard.set(true, forKey: "anonReplyExplainerShown")
    sendNotification(.anyStatus, ("anonExplainer", "NewPost"))   // or present via the project's alert pattern
}
```
Copy (one-shot, honest):
> **Reply anonymously**
> This reply posts from a new one-time identity that isn't linked to any of your accounts.
> It's a throwaway — you can't edit it, delete it, or reply again as this identity.
> Note: relays can still see your IP address, and your writing style may identify you.
> [Cancel] [Continue anonymously]

"Cancel" calls `exitAnonMode()`.

- [ ] **Step 3: Build & confirm** the alert shows once and repurposing clears anon mode. **Step 4: Commit**
```bash
git add -A
git commit -m "feat(anon): one-time explainer + composer-repurpose reset"
```

---

## Phase 7 — 🔒 Gate 3: realistic-relay smoke (pre-merge, human-in-the-loop)

Mandatory before merge. Use the `nak` skill.

- [ ] **Step 1:** Build/run with a real logged-in account.
- [ ] **Step 2:** Post an anon reply to a normal kind:1 post; capture the event id (debug log in `sendNowAnon`).
- [ ] **Step 3 (wire check):** `nak` fetch by id from `wss://relay.damus.io`; confirm: `pubkey` is the ephemeral key (NOT any account pubkey), no `client`/`emoji`/`["-"]` tags, empty relay-hint slots in `e`/`E`/`a`/`A`, correct reply+p tags, correct kind.
- [ ] **Step 4 (§0 negative):** event does NOT appear on the user's configured write relays outside the anon set; confirm via relay logs / an AUTH-challenging relay that **no NIP-42 AUTH with a real key was emitted** (the throwing signer aborts it).
- [ ] **Step 5 (cross-client):** from a second unrelated account, view the thread on Damus, Amethyst, Primal; confirm the reply surfaces. If filtered, add NIP-13 PoW and re-test.
- [ ] **Step 6 (session display + undo):** the reply shows "you · anon" this session; after force-quit+relaunch it renders as a stranger (expected). Post another and Undo within 9s → `nak` finds nothing on the relays.
- [ ] **Step 7 (edges):** anon item absent on a private-post reply; max-length text; reply to a NIP-22 parent (article/voice).
- [ ] **Step 8:** Record evidence (`nak` outputs + no-AUTH confirmation) in the PR, plus the abuse note (spec §7) and the "no kill-switch in v1" flag for the maintainer.

---

## Self-review checklist

- [ ] Spec → task map: §0 → Tasks 2,6 + Task 5 throwing-AUTH; §1 → Tasks 7,8,10; §2 → Tasks 4,6; §3 → Tasks 1,3; §4 → Tasks 5,6; §5 → Tasks 5,9; §6 → Tasks 8,10; §7 → Task 8 + PR note; §8 → Tasks 1-3 + Phase 7.
- [ ] Grep `sendNowAnon` + `AnonPublisher` for `activeAccount`, `account.signEvent`, `AccountManager`, `Unpublisher.shared`, `ConnectionPool.shared.sendMessage`, `sendEphemeralMessage`, keychain → expect NONE. Grep the `buildFinalEvent` anon branch for `activeAccount` → NONE.
- [ ] `isAnonSendSafe` (with `realAccountPubkeys`) is the only publish path in `sendNowAnon`; the private key is discarded at scope-exit (no store).
- [ ] No main-thread read of `bgAnonPubkeys` (main uses `isAnonPubkey`); only NRPost (bg) reads `bgAnonPubkeys`.
- [ ] Anon item hidden on private-post replies; Preview disabled in anon mode; both send buttons go through `dispatchSend`.
- [ ] anon state cleared in `loadReplyTo`/`loadQuotingEvent`/audio switch-back; anon text never written to the global draft.
- [ ] No delete/forget/keychain/startup-load/root-scope code exists (deferred to v2).
```
