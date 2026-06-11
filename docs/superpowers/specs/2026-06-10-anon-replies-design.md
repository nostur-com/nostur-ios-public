# Anonymous (Ephemeral-Key) Replies — Design

**Date:** 2026-06-10 (revised 2026-06-11)
**Status:** Approved design; **v1 pivoted to truly-ephemeral keys** (see revision note)
**Scope:** Text replies only (v1)

## Summary

Add an "Anon" option to the reply composer's inline account switcher that signs the
reply with a **freshly generated ephemeral keypair, minted at send time and discarded
immediately after** — never persisted. The goal is casual pseudonymity: say something
in a thread without attaching it to your main identity. It is not designed to defeat a
determined adversary (relays still see your IP; writing style can correlate).

This matches Amethyst's anonymous-reply model (PR #1932): one throwaway key per post,
unrecoverable after send. Where this design is more careful than the naive approach is
the **transport**: anon events publish over dedicated, isolated websocket connections
that can never answer NIP-42 AUTH with a real key (the §0 invariant).

> **Revision note (2026-06-11) — why truly-ephemeral.** The first design persisted one
> key per thread (device-local keychain) to allow "continue as the same anon" and
> "delete later." Three adversarial review passes, plus an opsec analysis of key
> *reuse*, showed that persistence adds a class of risk with no equivalent in the
> amnesiac model: a persisted private key is **cryptographic proof of authorship** on
> device seizure; repeated replies under one pubkey build a **linkable stylometric
> corpus** and an **activity-timing fingerprint**; and the persistence machinery
> (keychain, undo-burn registry, delete-signing, cross-restart ownership, multi-device)
> was where nearly every implementation blocker lived. Truly-ephemeral keys eliminate
> the entire reuse/opsec class and the riskiest code, while keeping the genuinely hard
> and valuable part — the isolated, leak-proof send path — unchanged. **Per-thread
> continuity and delete are explicitly deferred to v2**, to be layered on a proven core.

## 0. The core invariant (unchanged)

**Nothing on the anon path may sign with, authenticate as, persist under, or publish
over a connection associated with the real account.** The implementation MUST include
a runtime assertion immediately before publish: the signed event's `pubkey` equals the
freshly minted ephemeral pubkey **and is not any real-account pubkey**. On mismatch:
abort and alert, never publish. NIP-42 AUTH must never be emitted with a real key on
the anon path.

## Decisions

| Question | Decision (v1) |
|---|---|
| Threat model | Casual pseudonymity; strip client tag; isolated ephemeral transport |
| Key lifetime | **One key per reply, minted at send, discarded after** (truly ephemeral) |
| Persistence | No key store, no CloudKit sync. The private key is never persisted; the reply body is saved to the **local on-disk** Core Data store for thread display (see §7) |
| Send model | **Immediate send** (Amethyst parity) — no undo window. The action is irreversible (no delete in v1) |
| Anon profile | No kind:0 published (matches Amethyst, pools with their anon posts) |
| Scope | Text replies only; **not** private/DM replies; no new posts, quotes, voice, highlights |
| Anon activity | In-session thread display only; no notifications, **no delete, no continue, no undo** |
| Media / emoji | Hard-blocked while anon (text-only); custom-emoji picker disabled too |
| Transport | Dedicated isolated websockets; AUTH signer throws (no NIP-42 AUTH ever) |
| Architecture | Isolated send path; no `CloudAccount`, **no key store** |

## 1. UX

- In the reply composer only (`ComposePost` with `replyTo` set, **text reply kinds
  only** — kind:1 and NIP-22 text comments; voice replies out of scope), the
  `InlineAccountSwitcher` (`PostAccountSwitcher.swift`) shows one extra item after the
  user's full accounts: an incognito icon. The switcher is shared across five composer
  contexts and is `CloudAccount`-typed, so the anon item needs (a) an explicit
  `showAnonOption: Bool`, true only when `replyTo != nil`, the reply is a text reply,
  **and the parent is not a private post**, and (b) a selection channel that does not
  fabricate a `CloudAccount`. It must never appear in highlight/picture/vine/voice/
  new-post composers.
- Selecting it puts the composer in anon mode: the pfp slot shows the incognito glyph,
  the name reads "Anon". Reopening the switcher returns to a real account.
- **Anon is mutually exclusive with private/DM replies.** When the parent is private
  (`replyingToPrivatePost` locked on), the anon item is hidden; when anon is selected,
  `replyInPrivate` is forced false.
- First use shows a one-time explainer **modal with Cancel / Continue buttons** (not a
  transient toast — it must be dismissible by an explicit choice). The "shown" flag is
  set only when the user taps **Continue**, so a user who cancels sees it again next time;
  **Cancel** calls `exitAnonMode()` and restores the real draft. Copy (one-shot, honest):
  - This reply posts from a new one-time identity not linked to any of your accounts.
  - It's a throwaway: you **can't edit, delete, undo, or reply again as** this identity.
  - Limits: relays still see your IP address; your writing style may identify you.
  - If a draft attachment/recording is present, warn that switching to anon discards it.
- While anon is active, the **voice/mic entry, attachments, custom-emoji, Preview, and
  the private-reply toggle are all disabled** (each is its own real-account send path or
  identity surface). Switching to a real account in the switcher exits anon mode.
- Anon is never auto-selected. Every reply starts on the real active account.

## 2. Key handling — no persistence

- At send time, mint a keypair with `Keys.newKeys()` (NostrEssentials), sign the reply
  locally, hand the signed event to the transport, and **discard the private key** — it
  goes out of scope and is never written anywhere. There is **no key store, no keychain**,
  and the key never touches CloudKit. (The reply *event body* is saved to the local
  on-disk Core Data store for thread display — see §7 for that residual artifact.)
- An in-memory, session-scoped `Set<String>` of anon pubkeys created this launch is
  kept **only** so the user's just-posted anon reply renders as "you · anon" in the
  thread during the session. It is lost on app restart (after which a past anon reply
  renders as an ordinary stranger — accepted, matches Amethyst).
- Because v1 has no media, there is no upload-auth key to share, so the key need not
  even survive the compose session — mint at send, discard at send.

## 3. Send identity model — `SendIdentity`

- Resolve "who is sending" as one explicit value, so the anon path never co-mingles
  with `activeAccount`: `enum SendIdentity { case account(CloudAccount); case anon(Keys) }`.
- `buildFinalEvent` is made anon-aware: for the anon case it sets the ephemeral pubkey
  directly and never reads `activeAccount`, skips the client tag, skips emoji tags,
  skips the NIP-70 `["-"]` protected tag, and blanks relay-hint slots in reply tags
  (the user's connection footprint is a correlation vector).

## 4. The anon send path (isolated)

- Publish over fresh, isolated websockets — one `OneOffEventPublisher` per relay — never
  the user's pooled, identified `ConnectionPool` connections (which can answer NIP-42
  AUTH with the real key).
- **AUTH signer throws.** `OneOffEventPublisher` answers unsolicited NIP-42 AUTH with no
  `allowAuth` guard, so the anon path passes a `signNEventHandler` that throws — any AUTH
  attempt aborts and nothing is signed or sent. (Do not rely on `allowAuth: false`.)
- Relays: a fixed set verified to accept fresh-key writes (`relay.damus.io`, `nos.lol`,
  `relay.primal.net`; `relay.nostr.band` and `offchain.pub` dropped after live check
  2026-06-11), **plus the parent author's NIP-65 read relays** (read from kind:10002
  directly — `getInboxRelays` is a stub) so the reply reaches the person being replied
  to. Per-relay OK tracking with a ≥1 success threshold (target ≥2) before reporting sent.
- **No parent/quote rebroadcast** (the real-account `_sendNow` tail rebroadcasts the
  parent over the user's write relays — an active real-identity event correlated to the
  anon reply). The anon path has its own minimal tail.
- **Immediate send, no undo window.** On send: sign, publish over the isolated sockets,
  and save the event locally (consumed via `.newPostSaved` from inside `bg().perform` —
  the local-consume notify must not cross a bg Core Data object to the main thread) so it
  appears in the thread. There is no `Unpublisher` queue entry, no `cancellationId`, and
  the anon post is **not** marked `isOwnPost` (that would render the real-account footer
  with a misleading "0 relays" status, since the anon transport bypasses `ConnectionPool`).

## 5. Event, relays, and thread integration

- The published event is an ordinary reply (kind:1 or NIP-22 1111/1244). No kind:0, no
  NIP-13 PoW (revisit only if the Gate-3 smoke shows anon replies are spam-filtered), no
  NIP-40 expiration, no anon-marker tags, no client tag, no emoji tags, no relay hints,
  no NIP-70 protected tag — minimal footprint, matching Amethyst so anon posts pool
  together.
- Thread view: posts whose pubkey is in the in-session anon set render a subtle
  "you · anon" badge (computed directly from the session set, **not** via `isOwnPost`).
  The **WoT reply filters** must consult the in-session anon set so the user's own anon
  reply isn't hidden behind "Show more" with WoT on. `isOwnPost` is deliberately left
  false for anon posts (no real-account footer / undo / relay-status for them).
- **No delete, no forget, no undo** in v1 (the key is discarded, so a kind:5 can't be
  signed and there is no pending-send to cancel). The first-use explainer states the
  reply can't be edited, deleted, or undone. (Delete/continue return in v2 with
  per-thread persistence.)
- Optional nicety: exclude in-session anon pubkeys from the user's own Mentions feed, so
  an anon reply to your own post doesn't notify you as a stranger during the session.

## 6. Error handling, edge cases, and the anon-path rule set

- **Backgrounding:** because send is immediate (no 9s timer), there is no window in which
  app backgrounding could silently drop a pending anon send.
- **Drafts:** autosave is model-wide (`text.didSet → Drafts.shared.draft`). In anon mode,
  route text through an in-memory buffer only — never write the global draft — and restore
  the prior real draft on exit, so anon wording can't resurface in a later real-account
  composer.
- **Media hard-block (every send path):** entering anon clears
  `pastedImages`/`pastedVideos`/`voiceRecording`/`remoteIMetas` (warn first if present —
  don't silently destroy a recording), disables drag-drop, paste, attachments, the
  custom-emoji picker, the **voice/mic entry**, and the Preview button. All real-account
  send entry points (text send, Preview send, **AudioRecorder send**) are routed through a
  single dispatcher that checks `anonMode`, and the AudioRecorder send additionally guards
  on `!anonMode` so no real-account send can fire while the UI shows anon.
- **Exit anon:** switching to a real account in the switcher exits anon (centralized in
  `activeAccount.didSet`, covering all switcher sites) and restores the real draft.
- **Composer repurpose:** clear anon mode at the start of `loadReplyTo`/`loadQuotingEvent`
  and on the audio switch-back, so a reused composer can't carry stale anon state.
- `AccountsState` is never touched; anon mode is composer-local.
- **Rules for this and all future anon-path work:** nothing may sign with / reference /
  persist via the real account; if media is ever added, upload auth (NIP-98/Blossom) must
  be ephemeral-signed because services echo the auth pubkey into media URLs.

## 7. Opsec / why truly-ephemeral, and accepted residual risk

Truly-ephemeral keys eliminate the reuse/persistence concern class entirely:
- **No proof-of-authorship artifact** — nothing persists after send, so device seizure
  can't cryptographically prove you authored an anon reply.
- **No accumulating corpus or timing fingerprint** — each reply is its own island; there
  is no single pubkey aggregating your anon activity.
- **No key store to compromise**, no backup/sync/multi-device surface.

Accepted residual risk (inherent, disclosed):
- **Device IP** visible to the anon relays; per-post writing-style correlation; timing of
  an individual post.
- **Same-IP relay correlation.** Opening a reply composer calls
  `ConnectionPool.connectAllWrite()`, which opens the user's identified write sockets
  (and may NIP-42 AUTH them with the real key). Those write relays overlap the fixed anon
  set (damus/nos.lol/primal are common defaults), so a relay operator in both sets can see
  a real-account-AUTH'd connection and a fresh-key anon reply from the same IP seconds
  apart, and link them. This is beyond "relays see your IP" and is within the casual
  threat model (a relay operator correlating sockets is a determined adversary), but it is
  **called out explicitly in the PR** for the maintainer; a future mitigation is to defer
  `connectAllWrite()` while composing anon.
- **Local on-disk artifact.** The reply *event body* is written to the local Core Data
  store (Nostur.sqlite, the non-CloudKit `Local` configuration) for thread display, so a
  device-forensics adversary can recover the reply text and its local presence — though
  **not the private key** (never persisted) and it is **not synced to CloudKit/iCloud**.
  Accepted for v1 (the high-value artifact, the signing key, is gone).
- **Block/mute evasion.** Anon replies bypass any block/mute keyed on the real pubkey, and
  the parent author is still p-tagged — a block-evasion/harassment vector. No client-side
  cryptographic mitigation is possible (anyone can mint a key in any client). Documented
  for the maintainer to accept deliberately and **raised explicitly in the PR**.
- **Operational:** funneling anon traffic through a few named relays risks
  rate-limiting/bans — also flagged in the PR.

## 8. Testing

- **Unit:** `SendIdentity`; anon-aware event building (ephemeral pubkey; no client/emoji/
  relay-hint/NIP-70 tags; reply tags intact); the strengthened §0 assertion (passes for
  the ephemeral key, fails when the pubkey is a real-account key, fails on a forced
  mismatch).
- **🔒 Gate 3 — realistic-relay smoke, pre-merge, human-in-the-loop (`nak`):**
  - Publish an anon reply; verify on the wire field-by-field (ephemeral pubkey, no
    client/emoji/relay-hint/`["-"]` tags, correct reply+p tags, correct kind).
  - **§0 negative check:** the event does NOT appear on the user's configured write relays
    outside the anon set, and **no NIP-42 AUTH with a real key was emitted** during the
    publish (the throwing AUTH signer must abort it).
  - **Cross-client visibility:** view from a second unrelated account on Damus, Amethyst,
    Primal — confirm the anon reply surfaces (fresh-key spam filtering is the risk; add
    PoW if filtered).
  - In-session display shows "you · anon" with no real-account footer/undo/relay-status on
    it; after relaunch it renders as a stranger (expected).
  - **Voice-path leak check:** in anon mode the mic is disabled and cannot publish a voice
    reply under the real key.
  - Anon item absent on private-post replies; the private-reply toggle is disabled in anon;
    max-length input; reply to a NIP-22 parent.

## Out of scope (deferred to v2)

- **Per-thread key continuity** ("continue as the same anon") and **delete later** — the
  features that required persistence. v2 layers them on the proven isolated core.
- Anon top-level posts, quotes, private/DM replies, voice replies, highlights.
- Media attachments and custom emoji while anon.
- Notifications for anon identities; multi-device.
- NIP-13 PoW (conditional on smoke-test evidence).
- Tor/proxy routing or other network-level anonymity.
