# Anonymous (Ephemeral-Key) Replies Implementation Plan — v1 (truly ephemeral, immediate send)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Revision 4 (2026-06-11) — immediate-send pivot.** A second plan-level adversarial pass (verified against source) found the 9s undo window was the source of 2 blockers + 3 majors (Undo deleted the local copy but still published; the footer never cleared; a Core Data threading violation; a background-drop; a subject race). v1 now **sends immediately, no undo** (Amethyst parity). Also fixed: the broken DEBUG test seam, the voice/mic real-account leak, the `.anyStatus`-toast explainer, the `connectAllWrite` same-IP correlation (documented), and the `isOwnPost` footer mistake. All code below reflects source verified 2026-06-11.

**Goal:** Let a user reply in a thread under a freshly generated, one-time ephemeral key. The key is minted at send, used to sign, and discarded — not persisted. The send is immediate and irreversible.

**Architecture:** A fully isolated anon send path that never reads `activeAccount`. At send: mint `Keys.newKeys()`, build the reply via `buildFinalEvent` made anon-aware (ephemeral pubkey; no client/emoji/relay-hint/NIP-70 tags), sign locally, run the §0 assertion, publish **immediately** over `OneOffEventPublisher` (fresh websocket per relay, with a **hard-throwing** AUTH signer so no NIP-42 AUTH is ever emitted) to a fixed relay set plus the parent author's kind:10002 read relays, save the event to the local store for thread display, then discard the key. An in-memory session set of anon pubkeys drives the "you · anon" badge (anon posts are NOT marked `isOwnPost`). No keychain, no CloudKit, no undo window.

**Tech Stack:** Swift, SwiftUI, NostrEssentials (`Keys`, `NEvent`), Swift Testing, Core Data (local read/save only).

**Spec:** `docs/superpowers/specs/2026-06-10-anon-replies-design.md` — read it first. §0 invariant: nothing on the anon path may sign with, authenticate as, persist under, or publish over a connection associated with the real account.

**Build/test:**
- Build: `xcodebuild -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
- Test: `xcodebuild test -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 16 Pro (18.5),OS=18.5' -only-testing:NosturTests/<TestType>`

---

## Verified codebase facts (confirmed against source 2026-06-11)

- `Nostur/Post/PostComposer/NewPostModel.swift:779-781`: `guard var nEvent = self.nEvent else { return nil }` / `guard let account = activeAccount else { return nil }` / `let publicKey = account.publicKey`. `self.nEvent` (`:165`) defaults nil and is assigned **asynchronously** inside `loadReplyTo` via `Task { @MainActor in self.nEvent = newReply }` (`:1576-1577`) — so it is NOT set synchronously after `loadReplyTo` returns (drives the Task 3 seam fix).
- `:1025-1035` emoji block; `:1037-1041` NIP-70 `["-"]` block; `:1047-1049` client-tag block; kind:1 reply e/a tags are built in `loadReplyTo` (`~1560-1572`) **already with empty relay-hint slots**; relay hints are only added for NIP-22 via `addRootScopeTags`/`addReplyToTags` (`~1894-1965`).
- `Nostur/Post/PostComposer/Entry.swift`: `previewButton` is defined with its `.disabled(shouldDisablePostButton)` modifier near `:575` (used at `:348/:400/:455`); `:219` is a CameraView `onUse` closure (NOT a paste handler). `sendNow()` ~`:601`.
- `Nostur/Post/PostComposer/PostPreview.swift` send action ~`:69-86` (real account). `Nostur/Post/VoiceMessage/AudioRecorder.swift:578` send → `vm.sendNow(...)` real account, button only `.disabled(shouldDisablePostButton)` (`:590`).
- `Nostur/Post/PostComposer/ComposePost.swift:611` calls `ConnectionPool.shared.connectAllWrite()` in `onAppear`; audio switch-back ~`:115`; 5 `InlineAccountSwitcher` sites at `:89/:156/:240/:281/:419`.
- `Nostur/Relays/Network/OneOffEventPublisher.swift:194-204`: `case .AUTH:` calls `sendAuthResponse()` with **no `allowAuth` guard**, wrapped in `do { … } catch { L.og.debug(…) }`; `:262-281` `sendAuthResponse` calls `signNEventHandler(...)` then sends AUTH. A **throwing** signer aborts AUTH with nothing sent. Init: `init(_ urlString:String, allowAuth:Bool=false, signNEventHandler: @escaping (NEvent) async throws -> NEvent)`; `connect(timeout:)`, `publish(_:timeout:)`.
- `Nostur/Nostr/Nostr.swift:380` `mutating func sign(_ keys: Keys) throws -> NEvent` sets the event pubkey from the keys (so a post-sign `pubkey == thoseKeys` check is near-tautological — the real §0 guards are "never read activeAccount" + the throwing AUTH signer; the assertion's value is the **not-a-real-account** check).
- `Nostur/Nostr/Unpublisher.swift:188-216` local-consume: `Event.saveEvent(event:context:)` then `sendNotification(.newPostSaved, saved)`, all **inside `bg().perform`** (the threading pattern AnonPublisher must follow — do not cross a bg managed object to main).
- `Nostur/Relays/Network/OutboxLoader.swift:280-288` `getInboxRelays(forPubkey:)` computes read relays then `return []` (stub — read kind:10002 directly via `Event.fetchReplacableEvent(10002, pubkey:context:)`, note spelling "Replacable", parse `fastTags` `r`/read).
- `Nostur/Post/NR/NRPost.swift:470` `isOwnPost` from `bgFullAccountPubkeys`; `:1371`/`:1391` WoT reply filters (bg context); author handle via `NRContact.instance(of:)` which renders a contactless pubkey as `pubkey.suffix(11)` (no crash for an unknown ephemeral pubkey).
- `Keys.newKeys()`/`Keys(privateKeyHex:)` throw; `.publicKeyHex`; `NEvent.sign(_:) throws`; `NTimestamp(date:)`; `NostrTag` `.type`/`.tag`/`[safe:]`; `normalizeRelayUrl(_)`; `bg()`; `sendNotification(_,_)`; `Event.saveEvent(event:context:)`; `Event.fetchReplacableEvent(_:pubkey:context:)`; `AccountsState.shared.accounts`/`.bgFullAccountPubkeys`/`.bgAccountPubkeys`; `SettingsStore.shared.postUserAgentEnabled`/`.excludedUserAgentPubkeys`; `NIP89_APP_NAME`/`NIP89_APP_REFERENCE` — all confirmed.

---

## Phase ordering

- **Phase 1:** `SendIdentity`, §0 assertion, anon-aware `buildFinalEvent` (TDD).
- **Phase 2:** `AnonReplySession` (in-memory set), `AnonPublisher` (isolated **immediate** send).
- **Phase 3:** `sendNowAnon`.
- **Phase 4:** composer UI — switcher item, single dispatcher across all 3 send paths, anon-mode hard-blocks (voice/preview/media/emoji/private), exit-on-account-switch.
- **Phase 5:** thread display (WoT inclusion + "you · anon" badge; NOT isOwnPost) + mentions self-exclusion.
- **Phase 6:** explainer modal + composer-repurpose reset.
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
- [ ] **Step 2: Run → FAIL.**
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

The post-sign `pubkey == ephemeralKey` check is near-tautological (`sign` sets pubkey from the keys). The substantive guard is **not a real-account pubkey** — keep both; the real §0 protections are the no-`activeAccount` build path (Task 3, unit-tested) and the throwing AUTH signer (Task 5).

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
    /// Final §0 gate before an anon event leaves the device. True only if signed by the
    /// expected ephemeral key AND that pubkey is not any real-account key.
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

**Files:** Modify `Nostur/Post/PostComposer/NewPostModel.swift`; Test `NosturTests/AnonEventBuildingTests.swift`

- [ ] **Step 1: Read** `buildFinalEvent` (~778-1059), `addRootScopeTags`/`addReplyToTags` (~1894-1965), and `loadReplyTo` (~1516-1578, noting the async `self.nEvent` assignment).
- [ ] **Step 2: Signature**
```swift
private func buildFinalEvent(imetas: [Imeta], replyTo: ReplyTo? = nil, quotePost: QuotePost? = nil, isPreviewContext: Bool = false, anonPubkey: String? = nil) -> NEvent?
```
- [ ] **Step 3: Replace the identity guard (780-781) so anon never reads activeAccount**
```swift
        let publicKey: String
        if let anonPubkey {
            publicKey = anonPubkey
        } else {
            guard let account = activeAccount else { return nil }
            publicKey = account.publicKey
        }
```
- [ ] **Step 4: Guard the three tag blocks**: wrap emoji (1025-1035) and NIP-70 (1037-1041) each in `if anonPubkey == nil { … }`; client block (1047-1049):
```swift
if anonPubkey == nil,
   SettingsStore.shared.postUserAgentEnabled,
   !SettingsStore.shared.excludedUserAgentPubkeys.contains(nEvent.publicKey) {
    nEvent.tags.append(NostrTag(["client", NIP89_APP_NAME, NIP89_APP_REFERENCE]))
}
```
- [ ] **Step 5: Strip relay hints for NIP-22 replies** (kind:1 reply tags from `loadReplyTo` are already hint-free, so this only affects 1111/1244). Add `anon: Bool = false` to `addRootScopeTags`/`addReplyToTags`; in each, set **every** `resolveRelayHint(...)` result to `""` when `anon` (enumerate both sites in each function). At the call sites (~1016-1019) pass `anon: anonPubkey != nil`.
- [ ] **Step 6: DEBUG test seam that sets `self.nEvent` SYNCHRONOUSLY** (do NOT call `loadReplyTo` — it assigns `self.nEvent` async inside `Task { @MainActor }`, so the seam would see nil):
```swift
#if DEBUG
/// Build a reply NEvent fixture synchronously, bypassing loadReplyTo's async assignment.
func buildAnonEventForTesting(replyToEventId: String, replyToPubkey: String, content: String, anonPubkey: String) -> NEvent? {
    var reply = NEvent(content: content)
    reply.kind = .textNote
    reply.tags = [
        NostrTag(["e", replyToEventId, "", "root"]),
        NostrTag(["p", replyToPubkey]),
    ]
    self.nEvent = reply                 // satisfies guard at :779 synchronously
    self.typingTextModel.text = content
    return buildFinalEvent(imetas: [], anonPubkey: anonPubkey)
}
#endif
```
- [ ] **Step 7: Test (must actually run — this is the only build-time §0 tag coverage)**
```swift
import Foundation
import Testing
import NostrEssentials
@testable import Nostur

struct AnonEventBuildingTests {
    @Test func anon_event_has_ephemeral_pubkey_and_no_leaky_tags() throws {
        SettingsStore.shared.postUserAgentEnabled = true
        let keys = try Keys.newKeys()
        let vm = NewPostModel()
        let built = try #require(vm.buildAnonEventForTesting(
            replyToEventId: "rootid", replyToPubkey: "authorpub",
            content: "hi :emoji:", anonPubkey: keys.publicKeyHex))
        #expect(built.publicKey == keys.publicKeyHex)
        #expect(!built.tags.contains(where: { $0.type == "client" }))
        #expect(!built.tags.contains(where: { $0.type == "emoji" }))
        #expect(!built.tags.contains(where: { $0.type == "-" }))
    }
}
```
If `NewPostModel()` cannot be constructed in the test target, fix the construction (inject what it needs) rather than disabling — this is the only unit guarantee that the anon event carries no leaky tags.
- [ ] **Step 8: Run → PASS. Step 9: Commit**
```bash
git add Nostur/Post/PostComposer/NewPostModel.swift NosturTests/AnonEventBuildingTests.swift
git commit -m "feat(anon): buildFinalEvent anon-aware (no activeAccount, no client/emoji/relay-hint/NIP-70); sync test seam"
```

---

## Phase 2 — Session set & isolated immediate transport

### Task 4: `AnonReplySession` — in-memory anon pubkey set

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
```
- [ ] **Step 4: Run → PASS. Step 5: Commit**
```bash
git add Nostur/Post/PostComposer/Anon/AnonReplySession.swift NosturTests/AnonReplySessionTests.swift
git commit -m "feat(anon): in-memory AnonReplySession (no persistence)"
```

---

### Task 5: `AnonPublisher` — isolated immediate send (throwing AUTH, OK threshold)

No undo window, no `cancellationId`, no `pending` map. Publish immediately over fresh `OneOffEventPublisher` sockets; save locally for thread display with the notify emitted **from inside `bg().perform`** (no bg managed object crosses to main).

**Files:** Create `Nostur/Post/PostComposer/Anon/AnonPublisher.swift`. Reference: `OneOffEventPublisher.swift`, `Unpublisher.swift:188-216` (local-consume threading), `OutboxLoader.swift:280` (stub — don't call).

- [ ] **Step 1: Implement**
```swift
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
        bg().perform {
            let saved = Event.saveEvent(event: signedEvent, context: bg())
            // Do NOT set cancellationId and do NOT mark own — anon posts get no real-account footer.
            sendNotification(.newPostSaved, saved)
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
```
- [ ] **Step 2: Build** — confirm `Event.saveEvent`/`fetchReplacableEvent` and `OneOffEventPublisher.publish(_:timeout:)` signatures.
- [ ] **Step 3: Commit**
```bash
git add Nostur/Post/PostComposer/Anon/AnonPublisher.swift
git commit -m "feat(anon): isolated immediate AnonPublisher (throwing AUTH signer, OK threshold, kind:10002 read relays)"
```

> **Optional defense-in-depth (separate reviewed change):** add `guard allowAuth else { return }` to `OneOffEventPublisher`'s `case .AUTH:` after confirming no existing caller relies on unsolicited-AUTH-with-allowAuth-false. The throwing signer already closes the leak.

---

## Phase 3 — Send entry point

### Task 6: `sendNowAnon` on `NewPostModel`

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

    AnonReplySession.shared.register(keys.publicKeyHex)   // for "you · anon" badge this session
    let parentAuthor = replyTo.nrPost.kind == 9735 ? (replyTo.nrPost.fromPubkey ?? replyTo.nrPost.pubkey) : replyTo.nrPost.pubkey
    await AnonPublisher.shared.publish(signedEvent: signed, parentAuthorPubkey: parentAuthor)
    // `keys` goes out of scope here → private key discarded. Truly ephemeral, immediate send.
    typingTextModel.sending = false
    onDismiss()
}
```
- [ ] **Step 3: Build & commit**
```bash
xcodebuild -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
git add Nostur/Post/PostComposer/NewPostModel.swift
git commit -m "feat(anon): sendNowAnon (mint, build, sign, §0 assert, immediate publish, discard)"
```

---

## Phase 4 — Composer UI

### Task 7: Anon switcher item (reply-only, not private) + exit-on-account-switch

**Files:** Modify `Nostur/Post/PostComposer/PostAccountSwitcher.swift`, `Nostur/Post/PostComposer/ComposePost.swift` (text reply site ~419), `NewPostModel.swift` (centralized exit).

- [ ] **Step 1: Extend the switcher** — add stored properties (include `isAnonSelected` in `==`):
```swift
public var showAnonOption: Bool = false
public var isAnonSelected: Bool = false
public var onSelectAnon: (() -> Void)? = nil
```
After the account rows, when `showAnonOption`, add a tappable incognito item (`Image(systemName: "theatermasks.fill")` in a `Circle`, size `size`); its tap (when expanded) calls `onSelectAnon?()` then collapses. When `isAnonSelected`, render the primary slot as the incognito glyph.

- [ ] **Step 2: Centralize anon-exit in `activeAccount.didSet`** (covers all switcher sites; the `didSet` already does emoji/DM-relay work):
```swift
@Published var activeAccount: CloudAccount? = nil {
    didSet {
        if anonMode { anonMode = false; typingTextModel.restoreRealDraft() }   // switching account exits anon
        // ... existing emoji + DM-relay logic unchanged ...
    }
}
```

- [ ] **Step 3: Wire ONLY the text reply site (~419)**
```swift
InlineAccountSwitcher(
    activeAccount: account,
    onChange: { account in vm.activeAccount = account },   // exit handled in didSet
    showAnonOption: (replyTo != nil && !vm.replyingToPrivatePost),
    isAnonSelected: vm.anonMode,
    onSelectAnon: { vm.enterAnonMode() }
).equatable()
```
Leave the other four call sites unchanged.

- [ ] **Step 4: Build & visually confirm** the incognito item appears only on a normal text reply; absent on new post/quote/picture/highlight/voice/private-post replies; switching to a real account clears anon. **Step 5: Commit**
```bash
git add Nostur/Post/PostComposer/PostAccountSwitcher.swift Nostur/Post/PostComposer/ComposePost.swift Nostur/Post/PostComposer/NewPostModel.swift
git commit -m "feat(anon): reply-only anon switcher item; exit anon on account switch"
```

---

### Task 8: enter/exit anon, single send dispatcher across ALL send paths, hard-blocks

**Files:** Modify `NewPostModel.swift` (+ `TypingTextModel`), `Entry.swift`, `PostPreview.swift`, `AudioRecorder.swift`, `ComposePost.swift`.

- [ ] **Step 1: `TypingTextModel` anon flag + draft isolation**
```swift
@Published var anonMode: Bool = false
private var savedRealDraft: String = ""
@Published var text: String = "" { didSet { if !anonMode { draft = text } } }   // never persist anon text
func savedRealDraftSnapshotAndClear() { savedRealDraft = draft; anonMode = true; text = "" }
func restoreRealDraft() { anonMode = false; text = savedRealDraft; savedRealDraft = "" }
```

- [ ] **Step 2: enter/exit on `NewPostModel`** (the explainer modal is presented by Task 10; here `enterAnonMode` only flips state once confirmed — see Task 10 for the gate)
```swift
@MainActor func enterAnonMode() {
    guard !anonMode else { return }
    anonMode = true
    typingTextModel.savedRealDraftSnapshotAndClear()   // sets typingTextModel.anonMode = true
    replyInPrivate = false
    typingTextModel.pastedImages = []; typingTextModel.pastedVideos = []
    typingTextModel.voiceRecording = nil; remoteIMetas = [:]
    lockToSingleRelay = false
}
@MainActor func exitAnonMode() {
    guard anonMode else { return }
    anonMode = false
    typingTextModel.restoreRealDraft()
}
```

- [ ] **Step 3: Single send dispatcher** — used by `Entry.swift` (~601) AND `PostPreview.swift` (~69):
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

- [ ] **Step 4: Close the THIRD send path (voice) — two layers**
  - Disable entering the audio recorder while anon: guard the mic/voice button (the control that sets `showAudioRecorder = true`) with `.disabled(vm.anonMode)` (and/or no-op its tap when `vm.anonMode`).
  - Belt-and-suspenders at the AudioRecorder send site (`AudioRecorder.swift:578`): `guard !vm.anonMode else { return }` before `vm.sendNow(...)`, so a real-account voice send can never fire while anon.

- [ ] **Step 5: Disable the remaining real-account surfaces in anon mode**
  - Preview button: point the edit at the `previewButton` definition (~`Entry.swift:575`) → `.disabled(shouldDisablePostButton || vm.anonMode)`.
  - Attachment + custom-emoji buttons: `.disabled(vm.anonMode)`.
  - Private-reply toggle button: `.disabled(vm.anonMode)` and guard the "ReplyingInPrivateTo" rendering on `!vm.anonMode`.
  - Drag-drop handler (`ComposePost.swift:529` area): no-op when `vm.anonMode`. (Skip the `:219` "paste" reference from the prior draft — that line is a CameraView closure; rely on the disabled attachment button + the media-buffer clear.)

- [ ] **Step 6: Build & confirm** — in anon mode: mic, Preview, attachments, emoji, private-toggle all disabled; text send + preview send route to `sendNowAnon`; voice send is unreachable; switching account exits anon and restores the draft. **Step 7: Commit**
```bash
git add Nostur/Post/PostComposer/NewPostModel.swift Nostur/Post/PostComposer/Entry.swift Nostur/Post/PostComposer/PostPreview.swift Nostur/Post/VoiceMessage/AudioRecorder.swift Nostur/Post/PostComposer/ComposePost.swift
git commit -m "feat(anon): single send dispatcher across all 3 paths; disable voice/preview/media/emoji/private in anon"
```

---

## Phase 5 — Thread display

### Task 9: WoT inclusion + "you · anon" badge (NOT isOwnPost) + mentions self-exclusion

Do **not** set `isOwnPost` for anon — that would render the real-account `OwnPostFooter` with a misleading "0 relays" status (anon bypasses `ConnectionPool`). The badge and visibility come from the session set directly.

**Files:** Modify `NRPost.swift` (~1371/1391 WoT filters, bg), the author-handle view (badge), `MentionsFeedModel.swift` (~72-75).

- [ ] **Step 1: WoT filter `sortGroupedReplies` (~1371, bg)** — add `|| AnonReplySession.shared.bgAnonPubkeys.contains($0.pubkey)` so the user's own anon reply isn't hidden under "Show more".
- [ ] **Step 2: `sortGroupedRepliesNotWoT` (~1391, bg)** — add `&& !AnonReplySession.shared.bgAnonPubkeys.contains($0.pubkey)`.
- [ ] **Step 3: Badge** — in the author-handle view, when `AnonReplySession.shared.isAnonPubkey(nrPost.pubkey)` (main-thread → `isAnonPubkey`), show a small "you · anon" badge. (Do NOT touch `isOwnPost` at `:470`.)
- [ ] **Step 4 (optional):** exclude `AnonReplySession.shared.bgAnonPubkeys` from the `MentionsFeedModel` predicate so an anon reply to your own post doesn't self-notify during the session.
- [ ] **Step 5: Build & commit**
```bash
xcodebuild -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
git add Nostur/Post/NR/NRPost.swift Nostur/Notifications/MentionsFeedModel.swift
git commit -m "feat(anon): WoT-visibility + you-anon badge via session set (no real-account footer)"
```

> No delete/forget/undo tasks — the key is discarded and the send is immediate. Deferred to v2.

---

## Phase 6 — Explainer + repurpose reset

### Task 10: One-time explainer MODAL (Cancel/Continue) + composer-repurpose reset

**Files:** Modify `NewPostModel.swift` (explainer gate, repurpose reset), the composer view (`ComposePost.swift` / `Entry.swift`) to present the modal, `ComposePost.swift` (audio switch-back ~115).

- [ ] **Step 1: Gate `enterAnonMode` behind the explainer on first use.** Add a `@Published var showAnonExplainer = false` on `NewPostModel`. The switcher's `onSelectAnon` calls a coordinator:
```swift
@MainActor func requestAnonMode() {
    if UserDefaults.standard.bool(forKey: "anonReplyExplainerAccepted") {
        enterAnonMode()
    } else {
        showAnonExplainer = true   // present modal; do NOT enter anon or clear draft yet
    }
}
```
Wire the switcher `onSelectAnon: { vm.requestAnonMode() }` (update Task 7 Step 3 accordingly).

- [ ] **Step 2: Present a real modal** (`.alert` or `.confirmationDialog` bound to `$vm.showAnonExplainer`) in the composer view with explicit buttons:
  - Title: **Reply anonymously**
  - Message: "This reply posts from a new one-time identity that isn't linked to any of your accounts. It's a throwaway — you can't edit, delete, undo it, or reply again as this identity. Relays can still see your IP address, and your writing style may identify you." + if `vm.hasDraftMedia` (pasted/voice present), append "Your attached media/recording will be removed."
  - **Continue anonymously** → `UserDefaults.standard.set(true, forKey: "anonReplyExplainerAccepted"); vm.enterAnonMode()`
  - **Cancel** → dismiss; do nothing (anon not entered; draft untouched).
  Set the accepted flag ONLY on Continue (never on mere presentation).

- [ ] **Step 3: Composer-repurpose reset (spec §6)** — at the START of `loadReplyTo` and `loadQuotingEvent`, and in the audio switch-back closure (`ComposePost.swift:115`):
```swift
anonMode = false
typingTextModel.anonMode = false
```

- [ ] **Step 4: Build & confirm** the modal shows with working Cancel/Continue, the flag persists only on Continue, Cancel leaves the real draft intact, and repurposing the composer clears anon. **Step 5: Commit**
```bash
git add -A
git commit -m "feat(anon): first-use explainer modal (Cancel/Continue) + composer-repurpose reset"
```

---

## Phase 7 — 🔒 Gate 3: realistic-relay smoke (pre-merge, human-in-the-loop)

Mandatory before merge. Use the `nak` skill.

- [ ] **Step 1:** Build/run with a real logged-in account.
- [ ] **Step 2:** Post an anon reply to a normal kind:1 post; capture the event id (debug log in `sendNowAnon`).
- [ ] **Step 3 (wire check):** `nak` fetch by id from `wss://relay.damus.io`; confirm: `pubkey` is the ephemeral key (NOT any account pubkey), no `client`/`emoji`/`["-"]` tags, empty relay-hint slots in `e`/`E`/`a`/`A`, correct reply+p tags, correct kind.
- [ ] **Step 4 (§0 negative):** event does NOT appear on the user's configured write relays outside the anon set; via relay logs / an AUTH-challenging relay, confirm **no NIP-42 AUTH with a real key was emitted** (throwing signer aborts it).
- [ ] **Step 5 (voice-path leak):** in anon mode, confirm the mic is disabled and there is no way to publish a voice reply under the real key.
- [ ] **Step 6 (cross-client):** from a second unrelated account, view the thread on Damus, Amethyst, Primal; confirm the reply surfaces. If filtered, add NIP-13 PoW and re-test.
- [ ] **Step 7 (display):** the reply shows "you · anon" with NO undo/relay-status footer this session; after force-quit+relaunch it renders as an ordinary stranger (shortened-hex handle) — expected.
- [ ] **Step 8 (edges):** anon item absent on a private-post reply; private-toggle disabled in anon; max-length text; reply to a NIP-22 parent (article/voice).
- [ ] **Step 9:** Record evidence (`nak` outputs + no-AUTH confirmation) in the PR, plus the spec §7 residual risks (same-IP relay correlation, local-disk artifact, block-evasion) and the "no kill-switch in v1" flag for the maintainer.

---

## Self-review checklist

- [ ] Spec → task map: §0 → Tasks 2,3,6 + Task 5 throwing-AUTH; §1 → Tasks 7,8,10; §2 → Tasks 4,6; §3 → Tasks 1,3; §4 → Tasks 5,6; §5 → Tasks 5,9; §6 → Tasks 8,10; §7 → PR notes; §8 → Tasks 1-3 + Phase 7.
- [ ] Grep `sendNowAnon` + `AnonPublisher` for `activeAccount`, `account.signEvent`, `AccountManager`, `Unpublisher.shared`, `ConnectionPool.shared.sendMessage`, `sendEphemeralMessage`, keychain, `cancellationId` → expect NONE. Grep the `buildFinalEvent` anon branch for `activeAccount` → NONE.
- [ ] `isAnonSendSafe` (with `realAccountPubkeys`) is the only publish path in `sendNowAnon`; the private key is discarded at scope-exit.
- [ ] No main-thread read of `bgAnonPubkeys` (main uses `isAnonPubkey`); only NRPost (bg) reads `bgAnonPubkeys`. `AnonPublisher` emits `.newPostSaved` from INSIDE `bg().perform`.
- [ ] Anon posts are NOT marked `isOwnPost`; no `OwnPostFooter`/undo renders for them.
- [ ] All THREE send paths (Entry, PostPreview, AudioRecorder) cannot publish under the real account while `anonMode`; mic disabled in anon.
- [ ] Explainer is a real Cancel/Continue modal; accepted flag set only on Continue; Cancel preserves the real draft.
- [ ] anon state cleared in `loadReplyTo`/`loadQuotingEvent`/audio switch-back and on account switch; anon text never written to the global draft.
- [ ] No undo/delete/forget/keychain/root-scope/cancellationId code exists (deferred to v2).
```
