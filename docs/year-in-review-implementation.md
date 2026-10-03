# Year review: first implementation

The feature is available on iOS 17 and later through **Settings → Your year on
Nostr**. This is the first milestone toward the full proposal.

## Available

- Year selection, with the previous year selected by default during January.
- A preview from existing saved history, or collection from selected relays.
- Configured/advertised relay defaults, optional relay additions, and up to 20
  selected sources. Disabled relay and VPN settings remain effective.
- A separate per-account SQLite archive in Application Support, opened only for
  individual operations. It retains original signed public events and provenance;
  it does not use the live Event store or CloudKit.
- A durable work list for pause/resume, restart, and retry of incomplete sources.
- Bounded author, incoming interaction, event-reference, and parent requests.
  Capped date ranges are subdivided, with inclusive timestamp boundaries.
- Gang, most replied-to post, and explicit-mentions cards, with mutual reply
  counts, stable ties, duplicate suppression, and block/deletion filtering.
- Card selection, hiding people, summary or gang-only image sharing through the
  system share sheet, signed-public-history JSONL export, and archive deletion.

The initial report deliberately uses own follows and people the account publicly
replied to as trust inputs. It does not reuse another account's global WoT or
allow strangers based on incoming interaction volume. Full follows-of-follows
preparation and a review interface for excluded people remain future work.

## Important limits

The zap-value and combined supporters cards are not implemented yet. Original
receipts are collected for later validation; no payment totals are inferred from
cached amounts. Private event kinds are rejected, and private zap identities are
not decoded.

The current archive limit is 50,000 events / 64 MB of signed-event JSON per
account. These limits exclude SQLite indexing overhead. Each response is capped
at 256 event frames / 4 MB, individual frames at 70 KB, and saved events at 64 KB.
Collection uses one in-flight request, an 18-second deadline, a yield between
requests, and a 240-request session budget. A failing relay's remaining work is
saved for retry rather than timing out repeatedly in the same session.

EOSE without a completeness hint produces estimated coverage, including when
fewer events arrive than requested. An unresolved capped single-second range
remains an incomplete work item. No view claims to have downloaded all of Nostr.
Missing parent lookups are bounded to 2,048 IDs per pass.

Collection continues while navigating elsewhere in the running app; execution
while the app is suspended is not guaranteed. Checkpoints allow a later resume.
The current raw JSONL export does not include the collection manifest, and archive
import, automatic late-history refresh, richer indexed relationship queries, and
immutable saved report snapshots are not implemented yet.

Names and pictures use cached contacts; profile discovery and clickable evidence
drill-downs are follow-up work. Known deleted events are suppressed in reports
and exports. The screen invalidates previews when it observes new blocks or
deletions, and changing accounts cancels the old job before preparing the new one.

## Executor and integration review

`RelayConnection.receiveMessage` is the sole caller of
`MessageParser.socketReceivedMessage`. Before the existing background-context
dispatch, a small envelope check routes only `year-*` history responses to the
dedicated inbox. Normal feed, notification, and priority subscriptions keep their
existing path. History responses avoid feed duplicate shortcuts and zap-content
transforms. AUTH messages retain the existing connection handling.

Inbox locks protect registry access and response reservations only. JSON parsing
runs on a utility queue; original-event validation, archive transactions, and
analysis run on an actor. Cancellation removes the registered continuation
without waiting for either worker. The new integration does not change Backlog,
ReqTask, the importer, connection priority scheduling, or existing Core Data
executors. It reuses ConnectionPool-owned ephemeral connections and closes only
its own subscriptions, respecting relay-disable and VPN guards.

Local seeding uses a new private context with asynchronous bounded fetches and
immutable snapshots. No managed objects cross executors. There is no synchronous
main-thread wait in the new implementation.

## Verification

`YearReviewTests` covers counting, mentions versus replies/quotes, trust, blocks,
authenticated deletions, year boundaries, older/missing parents, original signed
events, tampering, private-kind rejection, deduplication, export/deletion,
checkpoint reopening, EOSE hints, CLOSED/authentication failures, cancellation
with a saturated history worker, and archive/UI work while the importer context
is held. Storage exhaustion preserves existing reports, and malformed parent IDs
do not reach relay filters. On October 2, 2026, all 25 focused tests passed (21
year-review tests and 4 existing Backlog tests) on iPhone 17 Pro / iOS 26.5,
built with Xcode 27.1. No tests were skipped and no runtime warnings were recorded.

Build/install/launch uses `./scripts/run-sim.sh --no-ui`. This new option avoids
opening simulator windows, changing simulator UI preferences, or shutting down
other devices. It retains the default script's normal behaviour when omitted.

No UI automation was used. Live relay coverage, card layout, and physical-iPhone
navigation/heat under active collection remain manually unverified.

## Report presentation follow-up

The report screen leads with individual highlight cards. Year, sources, saved-history
preview, archive actions, sharing choices, and people exclusions are available under
the gear button. The info button contains collection and coverage explanations.
Empty highlights are omitted, and the mentions highlight requires at least eleven
explicit standalone posts from the same author.

After analysis, missing names or pictures trigger a bounded eight-second kind-0
lookup through the existing read and search relay flow. Profile updates arrive as
immutable values and refresh the report on the main actor; metadata continues to
use the regular contact database and image cache. Collection and navigation do not
wait for profile lookup. Profiles that publish no name or picture retain a fallback.

## Expanded collection and reports

Collection schema 3 keeps the existing archive but starts fresh work checkpoints
for the expanded kinds: 1, 20, 21, 22, 1111, 1222, 1244, 30023, 34235 and 34236,
plus deletions, reactions, reposts (6/16) and zap receipts. DMs and gift wraps remain
excluded. Uppercase comment root tags, lowercase immediate-parent tags, quote
references and addressable coordinates have distinct collection paths.

Collection visits actual calendar months, newest first: all authored content first,
then incoming activity. Four combined primary queries per month/relay replace ten
separate groups. Reference lookups also combine compatible content/support kinds.
Fast relays refill their own request slot within the current month without waiting
for slower peers. Up to 20 different selected relays run in parallel, with at most one history REQ
active per relay. NIP-11 lookups also run concurrently. Each relay retains its
2–2.5-second pacing and durable exponential cooldown (60 seconds to 32 minutes).
Normal feed traffic has separate scheduling; this bounds only report requests.

Pages request up to 500 events, honoring a lower advertised NIP-11 max_limit.
Short responses finish their bucket without redundant oldest-second/empty probes.
Capped or explicitly unfinished responses split into seven-day, one-day, then
smaller disjoint ranges down to one second. Calendar operations respect the
collection timezone and daylight saving; a capped second remains incomplete.
Short non-exhaustive replies count as estimated coverage because unadvertised
relay caps cannot be ruled out. This is not a guarantee of all historical activity.
At most 1,200 requests run per session; unfinished work remains resumable.
Schema 3 rebuilds old work checkpoints, preserving the archived events themselves.

The main progress card is a 4-column, 12-month calendar in December-to-January order. Each current month spins
and shows completed-query progress plus a received-items count, including duplicates. In-flight counts poll ingress reservations four times per second without waiting for decoding; completed counts persist with collection checkpoints. Reference and parent checks do not inflate month counts. Orange checks mean the authored pass is
checked, green means both primary passes are checked. Failed sources show a
warning instead of a completed check. Future months are muted. Reference/parent
resolution and zap validation can follow those primary passes; a small busy header
continues showing that stage even when no month is active. Between month requests,
checkpoint writes and pacing retain the current calendar spinner until the month
handoff completes. Coverage remains
explicitly partial where responses are estimated. Detailed relay/query text is
only in the deeper settings. Month counters persist with the collection checkpoint.
Relay additions no longer reject valid URLs based on the number of available
choices; errors distinguish invalid URL, global disable, and the 20 selected cap.

Progress counts all saved archive items, split by event pubkey matching the owner
or another author. Counts restore before collection and increment after committed
new inserts, including local parents. The active card shows the current month/pass,
each active relay and date subrange, response state and elapsed seconds, completed
and queued queries, and last response received/new counts. No fixed ETA is claimed.

The archive permits 2 million events / 4 GB of original event JSON. Signature and
per-event size bounds remain; media files are never fetched. Ingest caches byte
statistics after the initial database scan. Report analysis makes streaming SQLite
passes and retains compact references and short previews rather than loading all
raw event JSON. Exports stream too. Addressable versions collapse to one logical
post and authenticated coordinate deletions suppress exported versions.

Reports include mutual gang, top replied-to/reacted-to/zapped posts and zap value,
most interactions, public conversations, top reply guy, top three supporters,
reaction givers/recipients, zap givers/recipients, repost/quote leaders and explicit
mentions above ten. Seven highlight cards are selected by default; additional
rankings are selectable in Year settings. Reactions/reposts deduplicate per author
and logical post. Negative reactions, blocks and untrusted incoming activity do
not inflate support, except cryptographically verified paid zaps from nonblocked senders count regardless of WoT membership. Supporters rank by reactions + reposts + validated zap count.

Zap validation checks the signed receipt and embedded request, recipient/provider
authorization, matching targets, exact integer invoice amount, invoice checksum,
payment hash and request-description hash. Payment hashes deduplicate receipts.
Provider keys come from the existing authorized contact cache, authenticated
metadata / LNURL discovery and the separate archive's provider cache. Historical
providers that cannot be authenticated are excluded, with a coverage count.
Anonymous/private zap requests never identify a payer; their verified receipts
contribute only to post totals. Provider attestation is not independent proof of
Lightning payment (the NIP-57 limitation).

Regression coverage adds silent-cap pagination, timestamp boundaries, durable
cooldowns, separated kinds, mixed media, comment mentions, addressable revisions
and deletions, support deduplication, outgoing reactions, signed zap validation,
invoice mismatch rejection, anonymous zaps and enlarged-archive long articles.
Live popular-account completeness and physical-device navigation/heat while
collecting remain manual checks; no simulator UI automation is used.

Local seeding also finds outgoing receipts through the feed's fromPubkey cache.
When the importer replaced the receipt body with display text, the empty-body
NIP-57 original is recovered only if its original event ID and signature verify.
Older outgoing receipts without P tags that exist only on unknown relays remain
undiscoverable through the standard sender filter. Collection does not compensate
by downloading all reactions to every post the account ever liked.

On October 2, 2026, the expanded suite passed all 37 focused tests (33 year-review
and 4 Backlog tests), with no skips or runtime warnings, on iPhone 17 Pro / iOS
26.5. The completed app was rebuilt and launched using run-sim.sh --no-ui.

Reference work searches e/q/a tags across the year after the monthly scans; green
cells indicate the monthly scans, not completion of these extra lookups. The active
card shows reference queries completed/queued. Each session stops dispatching new
reference work after 60 seconds and parent work after 30 seconds, lets in-flight
requests finish, and produces a partial report with remaining work saved for resume.
These limits do not apply to the primary month passes. The 18-second relay watchdog
runs independently of the history decoding worker, so a saturated decoder cannot
prevent timeouts. Physical-device stress/navigation remains manually unverified.

Report-ready screens call resumable collection “Continue unfinished checks” and
explain that history checks remain; resuming keeps saved events and retries the
remaining work rather than starting a new download. Highlight post previews use
the same passive text/thumbnail component as reaction notifications. Only the
four selected highlight events are read by ID from SQLite and parsed on a private
context into immutable display snapshots, without saving preview objects to the
feed. Tapping a post asynchronously promotes that single archived event to the
normal detail cache and uses existing post/article/video navigation. Person rows
use existing profile navigation; hide controls remain separate. Share rendering
uses the same previews with navigation controls omitted.

## iCloud history batches

The working per-profile SQLite databases remain in Application Support. The app's
existing `iCloud.com.nostur.data` container now also has Cloud Documents entitlements.
The signing profile must allow iCloud Documents for that container on physical devices.

`Documents/HistoryArchive-v1/<profile>/<generation>/<UTC month>/` contains immutable
versioned JSON batches of original signed public events, with at most 200 events and
approximately 2 MB per batch (3 MB hard read/write ceiling). Media files and private
messages are excluded. Existing local archives populate an incremental SQLite outbox
once. Upload cursors advance only after successful coordinated writes; cloud-imported
events do not enter the outbox. The merge verifies signatures and deduplicates event IDs.
Local deletion metadata travels in separately bounded batches; signed kind-5 events
are preserved normally. Relay provenance and report collection checkpoints remain local.

An NSMetadataQuery discovers iCloud Documents on the main run loop and only schedules
bounded utility work. Sync also retries every minute while the app runs. Each pass
imports up to eight unprocessed files and exports up to twenty pages per profile;
SQLite, cloud coordination, download requests, decoding and validation run off the UI
executor. iCloud itself controls actual transfer timing. Unavailable iCloud never
prevents local history collection. Sync state is separated by iCloud sign-in identity.

Clearing a profile archive writes a durable local reset before removing SQLite. The
next available sync publishes an immutable reset generation; other devices discard
older generations, and old batch folders are reclaimed. Concurrent resets converge
on the newest timestamp/UUID marker. New browsing can collect history again. Reset
markers remain to prevent an offline device from resurrecting deleted batches.

Tests use independent local archive registries and a shared temporary batch directory,
covering merging, no echo uploads, incremental restart, bounded export, private/invalid
event rejection, local deletion metadata and offline reset propagation. Actual iCloud
transport and signing entitlement availability require two signed devices using the
same iCloud account; simulator tests alone do not confirm those.

## Report discovery

“Your year on Nostr” is available below Profile in the sidebar year-round, rather
than in Settings. A compact Following-feed reminder appears December 18–January 14
using the device's local calendar date. December opens that year's report; January
opens the previous year's report. Dismissing or opening a report hides its reminder
for that account and report year. Other accounts and future years remain independent.
The card says “Your Nostr year is ready” only when the model has that account/year's
report; otherwise it invites the user to see their year. Relay options remain behind
the report's settings action and archive storage remains under Database & Cache.

## Highlight detail cache

Report reply totals come from signed events in the independent archive, including
nested replies. Once a report is ready, only its enabled post highlights are prepared
in the normal cache: the highlighted post, its archived reply descendants, and its
direct reactions, reposts, zap receipts and quote references. Opening a highlight
retries preparation after navigation and refreshes its grouped/nested replies.

Archive thread/support indices match actual parent/root and interaction targets;
mentions are not thread edges. Existing archives backfill those indices in pages of
200 with actor yields. Detail reads paginate by event ID, including advancing past
deleted events; normal imports run in context.perform batches of 25. Duplicate
restoration does not increment counts again. Legacy descendants without root tags
receive a derived cache root only after archive ancestry establishes their membership.
Signed original events remain unchanged in the archive. No wholesale archive import
or new relay requests are introduced by detail preparation.
