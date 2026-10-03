# My Nostr in 2026

Status: target product and implementation scope. The first milestone is described
in [year-in-review-implementation.md](year-in-review-implementation.md).

## First release

Use **My Nostr in 2026** as the share title and **Your year on Nostr** as the
feature name. The year is selectable. Before the year ends, label it **2026 so
far** and show the cutoff date. **My Nostr Gang** is the people card within the
report, and can also be shared by itself.

The proposed report now has five cards; users choose which to share:

| Card | What it shows | Counting rule |
| --- | --- | --- |
| My Nostr Gang | Up to five people with whom you exchanged public replies | Require replies in both directions; rank by the smaller directional count, then total replies, then pubkey for stable ties |
| You got people talking | Your post with the most direct public replies | Count distinct eligible reply events whose immediate parent is that post; also show unique respondents |
| Your most-zapped post | Your post that received the largest public zap value | Sum eligible validated receipts; show sats and zap count together |
| Your supporters | Up to three people who most often reposted, liked, and publicly zapped your posts | Rank by distinct supporter/post/action combinations across the three categories; show each category's count |
| Who can't stop talking about you? | The person who mentioned you in the most standalone public posts | Count distinct non-reply posts containing an explicit reference to your identity; count a post only once |

For the gang card, show both counts: “You replied 38 times · They replied 31
times.” Count each event once against its immediate parent's author. A mention,
quote, shared thread root, or reaction does not establish a conversation. This
keeps mass mentions and prolific one-sided replies from deciding the ranking.
The ranking formula is a proposal to evaluate on real accounts.

For **Your supporters**, give a like, repost, and zap equal weight as support
actions. Count at most one action per supporter, target post, and category during
the report interval. Repeated likes, reposts, or payments on the same post cannot
inflate the ranking. Show the breakdown, for example “18 reposts · 42 likes · 9
posts zapped,” so the combined ranking is understandable. Zap value may appear
as optional context, but does not buy a higher ranking. Resolve each target to a
post authored by the report owner, including older posts supported during the
year. Use positive kind 7 reactions, kind 6 reposts of eligible text notes, and
validated public receipts with an attributable sender. Break ties by distinct
posts supported, then pubkey. Anonymous or private zap senders cannot enter this
people ranking. A supporter need not have used all three action types.

For **Who can't stop talking about you?**, count explicit identity mentions in
post content, such as decoded npub/nprofile references, rather than every p-tag.
Exclude replies: clients can automatically carry participant p-tags through
threads. A standalone quote post can qualify if its author's own text explicitly
mentions the report owner; quoting or reposting their post alone does not qualify.
Count multiple references within one post once. Resolve structured references to
the pubkey; display-name text matching is too ambiguous. Show “Mentioned you in
24 posts,” with links to examples in the private preview. Break ties by distinct
active days, then pubkey. Apply the same trust, block, and deletion rules as the
other cards, and allow this card or its featured person to be omitted before
sharing. The playful title describes mention frequency, not sentiment.

Use kind 1 text notes initially, including replies authored by the user as
candidate posts. Explicitly label the scope “Public text notes.” Add other post
and comment kinds only with tested parent-resolution rules. Resolve kind 1
parents using NIP-10, including legacy tag conventions. Exclude self-interaction.

If a card has no eligible activity, omit it and explain that in the private
preview. Never pad the gang to five people or supporters to three, or label an
unknown result as zero. If zap validation cannot produce reliable results, defer
the most-zapped card and the combined supporters ranking until it is ready.
The gang, replies, and mentions cards can ship independently.

## Dates and eligibility

Define the calendar year using a timezone fixed when the report is created.
Persist its start and exclusive end as UTC timestamps. For a current-year
report, freeze a cutoff timestamp. Count interactions created within that
interval; candidate “your post” cards also require the post to be created within
the interval. Replies to older posts can still contribute to the gang ranking.
An older parent may be fetched as context, without counting it as a year's post.

Exclude blocked accounts, known deleted events, invalid signatures, unsupported
events, and self-interactions. Do not include DMs, decrypted private content, or
private zap identities. Use public zap receipts only for the initial share
cards. Keep anonymous public support unassigned to people rankings; its validated
value can contribute to the post card. Deduplicate receipts by event ID and
validated invoice/payment identity so multiple receipts cannot inflate one zap.
Store exact amounts as integer millisatoshis and round only for display.

Later additions can use the same event history: most-reacted-to post, people you
supported, top reply guy, and separate quote/repost highlights. Keep financial
totals separate from the supporters action ranking. For “liked,” define positive
reaction semantics rather than counting every kind 7 event as a like.

## Collection flow

The primary action is **Create my year**. Show four understandable stages:

1. **Choose your year.** Default to the current year, or the just-finished year
   during the early-year sharing period. Use existing local history immediately.
2. **Check your sources.** Preselect configured and advertised relays, with an
   optional edit screen. Explain which relays hold your posts and which receive
   replies. Offer a clearly marked fallback from Nostur's existing relay defaults
   if none are configured. Additional archive relays remain optional.
3. **Gather your history.** Show stages for your posts, replies/support, and
   missing context. Show counts found, progress through date ranges, relay errors,
   Pause, and Resume. Allow normal app navigation while gathering.
4. **Preview and share.** Show cards, the collection date, and source status. Let
   the user omit cards or people before generating the image and editable post.

Avoid making relay or WoT expertise a prerequisite. NIP-65 write relays are the
first sources for authored content; read relays are first sources for incoming
mentions. Today's relay list may differ from the user's historical relays, so
also offer relays seen in existing event provenance and manual additions. Do not
claim to recover relay-list history that was already replaced or discarded.

Snapshot existing follows, follows-of-follows, learned trust, and blocks for the
report. Prepare missing follow-list data asynchronously, with progress and retry.
Do not change global WoT settings silently. The recommended report view uses
trusted interactions, and states that scope beside the results. A user can
inspect excluded public interactions and deliberately include a person without
adding them to global trust automatically.

When a trust graph is unavailable or small, default to own follows and people
the user deliberately replied to, and explain that this gives a narrower view.
Do not silently count all strangers or borrow another account's trust graph.
Avoid deriving trust from incoming volume; spam must not make its sender trusted.

## Fetching and coverage

Build a resumable history job scoped to pubkey, date interval, selected relays,
and requested event kinds. Persist work per relay, request category, and time
window. Account switching must not retarget an existing job.

Fetch authored notes, incoming notes tagged with the user, positive reactions,
reposts, and public zap receipts tagged with the recipient. Resolve actual
parents and explicit content references to distinguish replies from mentions.
Query references to authored event IDs in bounded batches as a second
pass, since p-tags alone are not sufficient evidence of all engagement. Fetch
missing parents by ID and resolve their authors before counting conversations.
Do not fetch entire unrelated threads by default. Keep unresolved relationships
separate from counted interactions.

For future outgoing zap statistics, receipt authors are service providers, and
the uppercase P sender tag is optional. It can be a fast discovery query, but
not the sole source of outgoing zap history. Signed embedded requests and local
payment evidence need a separate discovery/validation design.

Use bounded relay concurrency, subscriptions, response bytes, event sizes,
signature-validation work, disk use, and retries. Schedule this as utility work
that yields to feed navigation, post opening, and notifications. Reuse existing
connection ownership and protocol parsing; use a dedicated history sink and
worker, not an unbounded flood into the normal feed importer.

Paginate each relay independently using overlapping timestamp boundaries and
event-ID deduplication. Never advance to `oldest timestamp - 1` while boundary
events may remain. Subdivide time windows, and split authors or target-ID filters
where useful. A saturated single-second window or repeated nonadvancing response
must be marked uncertain and surfaced, not skipped or retried forever.

EOSE means the initial response ended; it does not by itself establish exhaustive
history. Fewer events than requested can also reflect an internal relay cap.
Use NIP-67 completion hints where actually advertised/returned, with a fallback
that retains uncertainty. Even an exhaustive response from one relay proves
only what that relay currently stores. A timeout or an authentication failure is
an incomplete work unit, never a successful empty result.

Persist selected relays, windows attempted, completion evidence, timeouts,
authentication requirements, validation exclusions, unresolved references,
trust-policy version, and collection cutoff. Show **Sources checked**, **Partial
history**, or **Needs attention**, with details. Do not show a guessed percentage
of “all Nostr content.” Local activity counters are previews, not final totals.

## Storage

Use a separate, local, indexed SQLite history store that opens on demand. Prefer
a separate Core Data container if that keeps implementation consistent with the
app; choose the adapter after measuring batch ingestion and querying. Keep this
outside the live Event store and CloudKit configuration. Organize records by
event ID, and associate them with account/year collections so overlapping years
and accounts do not duplicate raw events.

Store the original signed event fields before any app import transformation,
plus relay provenance and first/last observation. Store normalized parent,
target, sender, recipient, amount, and validation status in queryable columns or
related tables. Derivations need a parser/algorithm version and must be
rebuildable from the signed source. Keep report snapshots small and immutable,
with their event evidence, date interval, coverage, and trust snapshot.

Seed from the existing Event database in bounded asynchronous reads, passing
immutable values out of the owning context. Verify reconstructed events before
treating them as signed originals. Preserve useful derived seed data separately
when originals cannot be recovered; refetch source events when possible.

This matters particularly for zaps: the existing handler replaces stored receipt
content with the zap request comment. Reconstructing that Event as a signed
receipt can therefore fail validation. The archive must capture originals before
this transformation and before duplicate shortcuts discard received payloads.

Retain structurally valid, relevant public events within resource limits even
when excluded by the current report trust policy, so filtering can be recomputed
without downloading again. WoT should limit unnecessary fetching where useful,
and determine report eligibility; it must not irreversibly destroy all evidence
needed to review exclusions. Invalid or oversized events need not be retained.

Provide archive size, delete controls, export/import, and incremental refresh.
Do not make the only copy a purgeable cache. On deletion, remove dependent report
snapshots and generated local share files as appropriate. Use an atomic export
package containing JSONL signed events and a versioned manifest; obtain it from
the indexed store rather than maintaining two authoritative raw event copies.
Never include account keys or private content in the package. No automatic
CloudKit upload of bulk history in the first release.

Refresh with overlap for late-arriving old events; a timestamp high-water mark
alone will miss backfilled history. Add authenticated deletion-event handling
and invalidate affected results. Reproducible snapshots record their policy,
but a newly learned deletion or user block must still update the current preview.

This archive can later support personal search, conversation history, and
statistics. Keep query APIs scoped to the feature; loading the archive must not
instantiate every historical post or contact into the live app state.

## Sharing

Generate one portrait summary image and optional individual card images, with
editable text and nostr links to featured posts. The gang card should carry the
year and “My Nostr Gang” prominently. Include a small readable provenance line,
for example “Trusted public interactions found through Dec 31 · via Nostur.”
Show a partial-history label when applicable. Offer **Create yours in Nostur**
as the sharing call to action; verify the install/open link before shipping it.

Use the existing composer and native share sheet. Preview must allow removal of
names, amounts, or excerpts before export; do not publish automatically. Show a
localized icon-only Share toolbar action and checkmark Done action according to
repository conventions. Empty or very sparse accounts should get an honest
preview without competitive rankings or embarrassing placeholder cards.

## Existing code and integration risks

- `Nostur/CoreData/Event+CoreDataProperties.swift` already contains reply links,
  quote links, counters, zap targets, and sender/recipient information. Cached
  counters do not encode a report-year interval or establish complete history.
- `Nostur/Profiles/ProfileInteractions*VM.swift` provides useful UI and query
  precedents; current conversation and zap screens cap results and have TODOs
  for pagination. They are not annual-history collectors.
- `Nostur/Utils/Maintenance.swift` deletes certain replies, reactions, and zaps
  mentioning own accounts after roughly two months. A report cannot rely on
  these records remaining in the live store.
- `Nostur/Nostr/LearnedWoTStore.swift` records first/last interaction and kinds,
  globally across accounts, without annual per-direction counts. Use it as one
  trust input, not as the gang statistics source.
- `Nostur/Nostr/WebOfTrust.swift` can allow all authors with absent configuration
  or a small trust graph. Its allow result alone does not prove report spam
  filtering is ready.
- `Nostur/Nostr/NXRelayMessage.swift` applies WoT filtering to particular feed
  subscription prefixes and short-circuits existing events. A history
  subscription needs an explicit policy and original-event capture point.
- `Nostur/Nostr/EventImportHandlers/ZapHandler.swift` caches decoded zap fields
  and transforms receipt content. Audit the full validation path before reusing
  it for annual payment totals, especially historical provider identities.
- `Nostur/Screens/Settings/Exporter.swift` exports authored cached events and
  uses synchronous context work. Reuse its format conventions, not that
  execution pattern or its scope, for large history exports.

Before changing shared parser, importer, Backlog, ReqTask, connection scheduling,
or Core Data behavior, trace callers and their executors. Keep UI operations
asynchronous and avoid passing managed objects to archive workers.

## Implementation order and verification

1. Implement value-only metric definitions and a small fixture-based analyzer.
   Verify direct replies versus mentions/quotes, mutual rankings, stable ties,
   duplicate events, year boundaries, older parents, and unresolved parents.
   Cover supporters using only one category, repeated actions on the same post,
   and equal weighting regardless of zap value. Cover automatic reply p-tags,
   explicit identity mentions, repeated mentions within a post, quote-only
   references, ambiguous display names, and stable people-ranking ties.
2. Implement archive storage, migrations, provenance, policy snapshots, and
   restart checkpoints. Verify idempotent ingestion, crashes between batches,
   safe export/import, deletion, and account isolation.
3. Implement bounded relay history collection and trust preparation. Exercise
   silent caps, same-second boundaries, late arrivals, authentication, partial
   relay failure, pause/resume, and multiple relays returning the same events.
4. Build the preview and gang/replies/mentions sharing cards. Add the zap and
   supporters cards once receipt
   validation tests cover duplicate payments, false senders, changed provider
   keys, amount mismatches, and anonymous/private handling.
5. Build and launch with `./scripts/run-sim.sh` and report the actual build ID.
   Run a physical-iPhone smoke test during history collection: change feeds,
   paginate a sparse feed, switch tabs, open a notification post, and return.
   Also test cancellation, account changes, memory growth, and sustained heat.
   A build alone does not verify responsiveness.

## Protocol references

- [NIP-01: events, filters, limits, EOSE](https://github.com/nostr-protocol/nips/blob/master/01.md)
- [NIP-10: public text-note threads](https://github.com/nostr-protocol/nips/blob/master/10.md)
- [NIP-25: reaction semantics](https://github.com/nostr-protocol/nips/blob/master/25.md)
- [NIP-57: zap receipts and validation](https://github.com/nostr-protocol/nips/blob/master/57.md)
- [NIP-65: write/read relay selection](https://github.com/nostr-protocol/nips/blob/master/65.md)
- [NIP-67: optional per-relay completeness hints](https://github.com/nostr-protocol/nips/blob/master/67.md)
