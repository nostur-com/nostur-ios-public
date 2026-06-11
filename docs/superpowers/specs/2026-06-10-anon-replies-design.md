# Anonymous (Ephemeral-Key) Replies — Design

**Date:** 2026-06-10
**Status:** Approved
**Scope:** Replies only (v1)

## Summary

Add an "Anon" option to the reply composer's inline account switcher that signs the
reply with a freshly generated, per-thread ephemeral keypair instead of one of the
user's accounts. The goal is casual pseudonymity: say something in a thread without
attaching it to your main identity. It is not designed to defeat a determined
adversary (relays still see your IP; writing style and timing can correlate).

Prior art: Amethyst's anonymous reply feature (PR #1932, commit `0ad3180f`), which
uses a per-compose-session throwaway key discarded on send. This design deliberately
deviates in two ways: keys persist per-thread (so the user can continue a
conversation as the same anon identity and delete posts later) and anon posts go to
a fixed set of large public relays instead of the user's write relays.

## Decisions

| Question | Decision |
|---|---|
| Threat model | Casual pseudonymity; strip client tag; publish to large public relays |
| Key lifetime | One key per thread (keyed by NIP-10 root event id) |
| Persistence | Local keychain only, never CloudKit; "forget" action to burn a key |
| Anon profile | No kind:0 published (matches Amethyst, pools with their anon posts) |
| Scope | Replies only; no new posts, quotes, DMs, or highlights |
| Anon activity | Thread-view only; no notifications or subscriptions for anon keys |
| Media | Disabled while anon is active (v1 is text-only) |
| Architecture | Separate anon path in `NewPostModel` + `EphemeralKeyStore`; no `CloudAccount` involvement |

## 1. UX

- In the reply composer only (`ComposePost` with a `replyTo` set), the
  `InlineAccountSwitcher` fan-out (`Nostur/Post/PostComposer/PostAccountSwitcher.swift`)
  shows one extra item after the user's full accounts: an incognito icon
  (`theatermasks.fill` in a circle). Selecting it puts the composer in anon mode:
  the pfp slot shows the incognito glyph and the name area reads "Anon". Reopening
  the switcher lets the user return to a real account.
- First use shows a one-time explainer alert (flag in UserDefaults):
  - The reply is posted from a new one-time identity not linked to any account.
  - The identity is remembered per-thread, on this device only, so the user can
    keep replying in the thread or delete the post later.
  - Limits: relays still see the device IP; writing style can identify the author.
- While anon is active, media attachment controls are hidden and draft auto-save is
  suppressed for the anon association (no signed or account-linked artifacts).
- Anon is never auto-selected. Every reply starts as the real active account; the
  user opts into anon per reply. If the thread already has a persisted anon key,
  toggling anon reuses it silently.

## 2. Key management — `EphemeralKeyStore`

- New component backed by its own keychain service (separate from
  `nostur.com.Nostur` and `nc`), items stored with `synchronizable = false` and
  `.afterFirstUnlock`. Never touches Core Data or CloudKit.
- Storage shape: one JSON dictionary
  `threadRootEventId → { privkeyHex, pubkeyHex, createdAt }`.
- API:
  - `existingKeys(forRoot:) -> Keys?`
  - `persist(keys:forRoot:)`
  - `forget(root:)`
  - published in-memory `Set<String>` of all anon pubkeys (loaded at startup) for
    fast "is mine" checks on the main thread.
- Toggling anon generates keys in memory only; they are persisted on the first
  send attempt. Cancelling the composer leaves no trace.

## 3. Composer changes — `NewPostModel`

- New state `anonKeys: Keys?` alongside `activeAccount`. Anon scope is the NIP-10
  root id of the post being replied to; if the replied-to event is itself the root,
  its own id is the scope.
- `_sendNow` gets an anon branch:
  - Build the reply exactly as today (same NIP-10 tags, p-tags, mentions, content).
  - Pubkey = anon pubkey; sign locally with `Keys` (NostrEssentials).
  - Skip the client tag (append sites at `NewPostModel.swift:839` and `:1048`).
  - Never enter the NIP-46 / remote signer path.
  - Publish via the anon relay set (section 4).
  - Consume the event locally so it appears in the thread immediately.
  - Unpublisher's undo-send delay window still applies.

## 4. Event and relays

- The published event is an ordinary reply (same kind the current reply flow
  produces). No kind:0, no NIP-13 PoW, no NIP-40 expiration, no anon-marker tags —
  matching Amethyst so anon posts from both clients are indistinguishable as a pool.
- Publish only to a hardcoded constant list of large public relays:
  `wss://relay.damus.io`, `wss://nos.lol`, `wss://relay.primal.net`,
  `wss://relay.nostr.band`, `wss://offchain.pub` — via ad-hoc connections, never the
  user's configured write relays. `Unpublisher` currently supports locking a publish
  to a single relay (`lockToThisRelay`); extend it (or add a sibling path) to lock
  to a set of relays.
- Accepted residual exposure, by design: device IP visible to the public relays,
  client-shape fingerprinting (tag ordering, relay set), timing, writing style.

## 5. Thread view integration

- Posts whose pubkey is in the anon-pubkey set render a subtle "you (anon)"
  indicator within the thread. Replies to them are visible in-thread like any other
  reply. No notification or subscription machinery references anon keys.
- Context menu on the user's own anon posts:
  - **Delete**: kind:5 signed with the ephemeral key, published to the anon relay
    set.
  - **Forget this anon identity**: removes the key from `EphemeralKeyStore` after a
    confirmation that warns delete/continue becomes impossible afterward.

## 6. Error handling and edge cases

- Publish failures behave like any post (retry/undo). The key is persisted at first
  send attempt, so a crash mid-send does not orphan the identity.
- `AccountsState` is never touched: anon mode is composer-local state. Removing or
  logging out of real accounts leaves anon keys intact, and vice versa.
- If the thread root cannot be determined from NIP-10 tags, fall back to the
  replied-to event's id as the key scope.
- Constraints learned from Amethyst's leak bugs, encoded as rules for this and all
  future work on the anon path:
  - Nothing in the anon path may sign with, reference, or persist via the real
    account (Amethyst's draft and NIP-95 events were real-key-signed while anon).
  - If media support is added later, upload auth events (NIP-98/Blossom) must be
    signed with the ephemeral key, because some services echo the auth pubkey into
    the returned media URL.

## 7. Testing

- Unit tests: `EphemeralKeyStore` CRUD and persistence across instances; anon event
  building (no client tag, correct pubkey, NIP-10 tags intact, correct kind).
- Manual verification with `nak`:
  - Fetch the anon reply by id from one of the public relays.
  - Confirm the event is absent from the user's personal write relays.
  - Confirm a second anon reply in the same thread uses the same pubkey.
  - Confirm key persistence across app restart.
  - Confirm kind:5 delete is accepted and honored by the public relays.

## Out of scope (v1)

- Anon top-level posts, quote posts, DMs, highlights.
- Media attachments while anon.
- Notifications for anon identities.
- Any anon identity management UI beyond the per-post context menu actions.
- Tor/proxy routing or other network-level anonymity.
