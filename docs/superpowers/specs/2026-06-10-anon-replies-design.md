# Anonymous (Ephemeral-Key) Replies — Design

**Date:** 2026-06-10 (revised 2026-06-11 after adversarial review)
**Status:** Approved design; revised post-review, pending re-approval
**Scope:** Replies only (v1)

## Summary

Add an "Anon" option to the reply composer's inline account switcher that signs the
reply with a freshly generated, per-thread ephemeral keypair instead of one of the
user's accounts. The goal is casual pseudonymity: say something in a thread without
attaching it to your main identity. It is not designed to defeat a determined
adversary (relays still see your IP; writing style and timing can correlate).

Prior art: Amethyst's anonymous reply feature (PR #1932, commit `0ad3180f`), which
uses a per-compose-session throwaway key discarded on send. This design deliberately
deviates in three ways: keys persist per-thread (so the user can continue a
conversation as the same anon identity and delete posts later); anon posts publish
over **dedicated ephemeral relay connections** (never the user's pooled, identified
connections); and the transport is a **fully isolated send path**, not a reuse of
the real-account publish pipeline.

> **Review note (2026-06-11):** An adversarial panel reviewed the first draft and
> found three reachable deanonymization paths that the naive "reuse `_sendNow`,
> swap the pubkey" design would have shipped (private/DM-reply giftwrap branch,
> leftover-media upload auth, and pooled-connection NIP-42 AUTH). The architecture
> below replaces that approach with an isolated anon send path and an explicit
> identity model. The non-negotiable invariant is in §0.

## 0. The core invariant

**Nothing on the anon path may sign with, authenticate as, persist under, or
publish over a connection associated with the real account.** Every design choice
below derives from this. The implementation MUST include a runtime assertion
immediately before publish: the signed event's `pubkey` equals the intended
ephemeral pubkey, and no real-account signature or NIP-42 AUTH occurred during the
send. On mismatch: abort and alert, never publish.

## Decisions

| Question | Decision |
|---|---|
| Threat model | Casual pseudonymity; strip client tag; isolated ephemeral transport |
| Key lifetime | One key per thread, keyed by a resolved **root scope identifier** (§2) |
| Persistence | Local keychain, `ThisDeviceOnly`, never CloudKit; "forget" action to burn a key |
| Anon profile | No kind:0 published (matches Amethyst, pools with their anon posts) |
| Scope | Replies only; **not** private/DM replies; no new posts, quotes, highlights |
| Anon activity | Thread-view only; no notifications or subscriptions for anon keys |
| Media / emoji | Hard-blocked while anon (text-only); custom-emoji picker disabled too |
| Transport | Dedicated ephemeral connections to a relay set; isolated send path |
| Architecture | `SendIdentity` enum + isolated anon path; no `CloudAccount` involvement |

## 1. UX

- In the reply composer only (`ComposePost` with `replyTo` set, text or voice reply
  kinds), the `InlineAccountSwitcher` (`PostAccountSwitcher.swift`) shows one extra
  item after the user's full accounts: an incognito icon. **The switcher is shared
  across five composer contexts** (voice, highlight, picture, short-video, default
  text — `ComposePost.swift:89,156,240,281,419`) and is `CloudAccount`-typed
  throughout, so the anon item requires (a) an explicit `showAnonOption: Bool`
  parameter, true only when `replyTo != nil` and the kind is a text/voice reply, and
  (b) a selection channel that does not fabricate a `CloudAccount` (see §3
  `SendIdentity`). It must never appear in highlight/picture/vine/new-post composers.
- Selecting it puts the composer in anon mode: the pfp slot shows the incognito
  glyph, the name reads "Anon". Reopening the switcher returns to a real account.
- First use shows a one-time explainer alert (UserDefaults flag):
  - The reply posts from a new one-time identity not linked to any account.
  - The identity, **and the ability to continue or delete it, lives only on this
    device** (keys are device-local and not backed up; see §2).
  - Limits: relays still see the device IP; writing style can identify the author;
    deletion is a *request* that relays and other apps may ignore.
- **Anon is mutually exclusive with private/DM replies.** When the parent is a
  private post (`replyingToPrivatePost` is locked on, `Entry.swift:561`), the anon
  item is hidden. When anon is selected, `replyInPrivate` is forced false.
- Anon is never auto-selected. Every reply starts on the real active account. If the
  thread already has a persisted anon key, toggling anon reuses it silently.

## 2. Key management — `EphemeralKeyStore`

- New component backed by its own keychain service (separate from
  `nostur.com.Nostur` and `nc`), `synchronizable = false` and
  **`.afterFirstUnlockThisDeviceOnly`** so keys are excluded from encrypted device
  backups and never migrate to another device. Never touches Core Data or CloudKit.
- **Root scope identifier (not "event id").** The map key is an opaque string
  resolved by a single shared helper (§3), because Nostur's reply flow produces
  different shapes per parent kind:
  - kind:1 reply → the NIP-10 marked **root `e`** id.
  - NIP-22 reply (kind 1111/1244, used for parents like 1222/1244 voice, 20
    pictures, 30023 articles, 34236 vines, 9735 zap receipts) → the uppercase
    **`E`** id, **`A`** coordinate (`kind:pubkey:dtag`), or **`I`** value, copied
    verbatim from the parent's root scope tags.
  - Fallback (no resolvable root) → the replied-to event's id.
  Storage shape: `rootScopeId(String) → { privkeyHex, pubkeyHex, createdAt }`. The
  `A`/`I` cases are why the key must be a string, not an event id.
- API: `existingKeys(forRoot:) -> Keys?`, `persist(keys:forRoot:)`, `forget(root:)`,
  plus a published in-memory `Set<String>` of all anon pubkeys (loaded at startup)
  for fast main-thread "is mine" checks.
- Toggling anon generates keys in memory, **keyed by the resolved root scope** (not
  a flat field), and persists on first send. Cancelling leaves no trace.
- **Lifecycle:** keys persist across app restart but are purged on account-wipe /
  app-reset. Document that iOS keychain survives app *uninstall*; provide the
  per-identity "forget" action and an app-reset purge as the cleanup paths.
- **Multi-device (documented limitation, not solved in v1):** anon keys are
  device-local. An anon reply made on iPhone shows the "you (anon)" indicator and
  delete/forget only on that device; on another device it renders as a stranger and
  cannot be deleted, and toggling anon in the same thread there mints a *new*
  identity. Surfaced in the first-use explainer copy.

## 3. Send identity model — `SendIdentity`

- Replace the implicit "`activeAccount` + side flag" with one explicit value
  resolved once and threaded through `sendNow`/`_sendNow`:
  `enum SendIdentity { case account(CloudAccount); case anon(Keys) }`.
  Three send buttons independently capture identity today
  (`Entry.swift:601`, `PostPreview.swift:73`, `AudioRecorder.swift:565`); all three
  resolve a `SendIdentity` instead.
- `buildFinalEvent` becomes anon-aware rather than relying on `sign()` to retro-scrub
  the pubkey: for `.anon`, set the ephemeral pubkey directly, skip the client-tag
  logic, and skip all real-account-derived tags. The anon branch must **not** touch
  `activeAccount` (in particular it must not write `account.lastLoginAt`, which
  mutates a CloudKit-synced object — `NewPostModel.swift:566`).

## 4. The anon send path (isolated)

The original draft proposed extending `Unpublisher.lockToThisRelay`. **Rejected:**
that routes through `ConnectionPool.sendMessage`, which filters the *already-pooled*
connections (it does not open sockets), so the anon event would ride the user's
existing identified connection to relays like nos.lol/damus — and a NIP-42 AUTH
challenge there is answered with the **real** account key. That is the headline
deanonymization bug. Instead:

- Build a dedicated anon send path (a new `Unpublisher` sibling if the ~9s undo
  window is desired) whose fire action uses
  `ConnectionPool.addEphemeralConnection` / `sendEphemeralMessage`
  (`ConnectionPool.swift:164,707`) with `RelayData` `auth: false`, opening **fresh
  sockets** even when a pooled connection to the same relay exists.
- The path must: never register the event in `eventsThatMayNeedAuth`; never answer
  NIP-42 AUTH with any account (skip `resolveAuthAccount` entirely, including its
  `relayFeedAuthPubkeyMap` bypass); never set `lockToSingleRelay`; never append the
  NIP-70 `["-"]` protected tag.
- **No parent/quote rebroadcast.** The real-account `_sendNow` tail rebroadcasts the
  replied-to event over the user's write relays (`NewPostModel.swift:738`); this is
  an active real-identity event correlated to the anon reply within milliseconds.
  The anon path has its own minimal tail and does **not** rebroadcast the parent.
- Consume the event locally so it appears in the thread immediately (see §5 for the
  ownership-gate work that makes "immediately" actually true).

## 5. Event, relays, and thread integration

### Event shape
Ordinary reply, same kind the current flow produces (kind:1 or NIP-22
1111/1244). No kind:0, no NIP-40 expiration, no anon-marker tags. **Client tag:** the
only reply-relevant append is `NewPostModel.swift:1047-1049` (gated on
`postUserAgentEnabled`); the anon branch skips it unconditionally. (The `:839`
reference in the first draft was dead code in the vine branch — ignore it.)
**No custom-emoji tags:** the picker is disabled in anon mode and any
`["emoji", …]` tags are stripped, because their hosting URLs derive from the user's
follow graph / saved sets (`NewPostModel.swift:1025,1267`). **NIP-13 PoW:** not in
v1; revisit only if the Gate-3 smoke test shows anon replies are filtered.

### Relays
- Publish over ephemeral connections to a curated set. **Verified live 2026-06-11:**
  `relay.damus.io`, `nos.lol`, `relay.primal.net` accept writes from a fresh key;
  **`relay.nostr.band` is an indexer and unreachable for writes (dropped)**;
  `offchain.pub` returned no OK twice (drop or re-verify before use). Ship with the
  three confirmed relays.
- **Also publish to the parent author's NIP-65 read relays** over ephemeral
  connections, so the person being replied to actually receives it. Without this,
  delivery depends on their read relays happening to intersect the fixed set. The
  extra relay exposure is within the accepted threat model (ephemeral, unauthed
  connections; IP already accepted).
- **Per-relay OK tracking with a success threshold** (≥1 OK, target ≥2) before the
  UI reports the reply as sent — a hardcoded list otherwise gives no failure signal
  if relays silently shadow-drop.
- Accepted residual exposure: device IP visible to these relays, client-shape
  fingerprint, timing, writing style.

### Thread view (multiple ownership gates, not one)
"Is this mine" is recomputed in several disconnected places that all currently
exclude non-account pubkeys; each must consult the anon-pubkey set:
- WoT reply filter `sortGroupedReplies` (`NRPost.swift:1369`) — without this, with
  WoT enabled, the user's **own** anon reply is hidden under a collapsed "Show more".
- `NRPost.isOwnPost` (`NRPost.swift:470`) — gates the Undo-send footer.
- `PostMenu` delete (`PostMenu.swift:263`) and `PostDetailsMenuSheet`
  (`PostDetailsMenuSheet.swift:134`).
Render a subtle "you (anon)" indicator on these posts. No notification/subscription
machinery references anon keys.

### Context menu on own anon posts
- **Delete (request):** dedicated path — build kind:5 with `["e", id]` **and**
  `["k", "<deleted kind>"]` (NIP-09), sign with the thread's ephemeral `Keys`,
  publish over the same ephemeral connections. Surface via the anon-set "is mine"
  check, not `la.pubkey`. Explainer says "request deletion; copies elsewhere may
  remain."
- **Forget this anon identity:** removes the key from `EphemeralKeyStore` after a
  confirmation that delete/continue becomes impossible afterward.

## 6. Error handling, edge cases, and the anon-path rule set

- **In-memory key correctness:** keys are kept keyed by resolved root, computed via
  the single shared helper used for both lookup and event building; assert at
  publish that the chosen key's root equals the event's computed root. Clear anon
  state whenever the composer is repurposed (`loadReplyTo` / `loadQuotingEvent` /
  audio switch-back at `ComposePost.swift:117`) so a stale key can't sign for a new
  thread.
- **Undo-send:** undoing an anon send burns the persisted key (no orphan identity
  with no published event). Decision recorded here so the implementation is explicit.
- **Drafts:** autosave is model-wide (`text.didSet → Drafts.shared.draft`, a single
  global UserDefaults key, restored into the next composer; the undo-send restore at
  `OwnPostFooter.swift:95` repopulates it). In anon mode, route text through an
  in-memory buffer only — never write `simple_draft`/`restoreDraft` — so anon wording
  can't resurface in a later real-account composer.
- **Media hard-block (not just hidden controls):** entering anon clears
  `pastedImages`/`pastedVideos`/`voiceRecording`/`remoteIMetas`, disables drag-drop
  (`ComposePost.swift:529`) and paste (`Entry.swift:219`), and the send path asserts
  no media buffer is non-empty (the upload-auth branch signs NIP-98/Blossom with the
  real key — the exact Amethyst leak). Anon is disabled in the audio-recorder
  composer for v1.
- `AccountsState` is never touched; anon mode is composer-local. Account
  add/remove/logout leaves anon keys intact and vice versa.
- **Rules for this and all future anon-path work:** nothing may sign with /
  reference / persist via the real account (Amethyst's draft + NIP-95 events were
  real-key-signed while anon); if media is ever added, upload auth (NIP-98/Blossom)
  must be ephemeral-signed because services echo the auth pubkey into media URLs.

## 7. Abuse considerations

Anon replies are a block/mute-evasion vector: block/mute is keyed on pubkey, so a
fresh key bypasses any block the thread author placed on the user's real account,
while the author is still p-tagged and notified — a persistent (per-thread)
pseudonymous channel to a target. v1 ships no cryptographic mitigation (it isn't
enforceable client-side; anyone can mint a key in any client), but this trade-off is
**documented here and must be raised explicitly in the PR description for the
maintainer to accept deliberately.** Also note the operational risk of funneling all
client anon traffic through a few named relays (rate-limiting / bans).

## 8. Testing

- **Unit:** `EphemeralKeyStore` CRUD + persistence across instances; root-scope
  resolution for an `A`-root (article) thread, an `E`-root (comment-on-comment)
  thread, and a kind:1 thread; anon event building (correct ephemeral pubkey, NIP-10
  tags intact, **no** client tag with `postUserAgentEnabled = true`, no emoji tags);
  the pre-publish pubkey assertion fires on a forced mismatch.
- **🔒 Gate 3 — realistic-relay smoke, pre-merge, human-in-the-loop:**
  - Publish an anon reply; verify on the wire with `nak` field-by-field (ephemeral
    pubkey, no client tag, correct root scope tags, correct kind).
  - **Cross-client visibility:** view the anon reply from a second unrelated account
    on Damus, Amethyst, and Primal — not just `nak` fetch-by-id — to confirm it
    actually surfaces (fresh-key spam filtering is the risk). If filtered, add PoW.
  - Confirm the anon event does **not** appear on the user's configured write relays
    that are outside the anon set, and that no NIP-42 AUTH with the real key fired.
  - Second anon reply in the same thread reuses the same pubkey; persists across app
    restart; kind:5 delete is accepted.
  - Max-length input and the full flow (toggle anon → type → send → undo).

## Out of scope (v1)

- Anon top-level posts, quotes, **private/DM replies**, highlights.
- Media attachments and custom emoji while anon.
- Notifications for anon identities; multi-device anon sync.
- NIP-13 PoW (conditional on smoke-test evidence).
- Tor/proxy routing or other network-level anonymity.
