# In-app Nostr browser

Open **Web apps** in the sidebar. The browser opens full screen, with a single
bottom control area using native Liquid Glass on iOS 26 and later, instead of separate navigation, address and bottom bars.
Controls are centered and capped at 600 points on wide windows, while fitting
smaller phones and folded layouts naturally. Opening a site collapses controls to a small domain/account strip. Tap the strip
or scroll upward to reveal controls; scroll downward or tap Hide to collapse.
Close remains accessible. Blocked signing requests quietly add a shield/count
in the toolbar. Tap it to review the action and reason; they do not show banners.
Page-loading and address errors may still show a brief notice. Safe areas and the website's own navigation stay intact.

Use **Minimize** (minus) beside Close to return to Nostur while retaining the live
page, browsing history, session cookies and in-page drafts. The **Return to web
app** button above the app's bottom controls reopens it; the sidebar's Web apps
entry also resumes it. Close (xmark) unloads the page but retains saved website logins. The browser is
owned by an app-level presenter, rather than by the sidebar or modal view. A
minimized browser cannot read the public key through the bridge or request signatures; pending
requests are canceled immediately. Retention is in memory, not across app
termination or a WebKit content-process crash.

The bundled, native starting page works offline and uses compact category panels
and descriptive links inspired by Startpagina. Categories include Social, Reading
& writing, Photos & media, Live streams, Communities, Relay services, and Tools &
discovery, plus Games with Word5. Favorites work locally; there is no directory
search field. Add future entries in `BrowserDirectory.swift`; directory
membership does not grant signing privileges. Links are discovery suggestions,
not a claim of full compatibility with this browser's signing policy.

The relay section links to nostr.wine, nostr.land, nostr1.com and Feeds by
relay.tools. nostr1.com currently directs new hosted-relay customers to Feeds.
Source links checked 2026-11-03: https://nostr.wine, https://nostr.land,
https://nostr1.com, https://ditto.pub, https://github.com/soapbox-pub/ditto,
https://github.com/coracle-social/coracle,
https://github.com/sandwichfarm/nostr-watch, https://njump.me,
https://zap.stream, https://shosho.live, https://flotilla.social,
https://snort.social, https://nostrudel.ninja, https://yakihonne.com.

Choose the site's **browser extension** login to use the account shown in the
browser toolbar. Recommended homepage apps automatically use a reviewed native
default profile; no permission setup or signing popups are required. Site controls
are optional overrides. Account selection is independent of the main Nostur account.
Changing accounts reloads the page using that account’s isolated website profile.

## Signing defaults

The main frame gets NIP-07 `getPublicKey()` and `signEvent()`. Private keys stay in
native code. Websites handle their own relay connections and publication; Nostur
returns signed events without publishing them itself.

- All homepage entries have exact-origin defaults for public-key access and
  website login, public social actions and bounded upload authorization. These
  defaults are identical for all homepage apps and their deployment aliases. Unknown origins start disconnected. Explicit user
  overrides remain per account and origin.
- App actions permit new and unfamiliar event kinds, including games and
  processing requests, without adding them to a kind allowlist. The App actions
  toggle controls this default. Shared profile/follow changes, deletion, all
  replaceable account settings (10000–19999), and known shared addressable lists
  still need an extra action grant where supported. Private-message, remote-signer and group-administration protocols remain
  unavailable. NWC signing requires Wallet actions or an explicit kind grant. Relay,
  HTTP and Blossom authorization retain their separate checks. Unknown kinds
  can acquire new meanings outside Nostur; this is compatibility-first signing,
  not a guarantee about the meaning or consequences of an unfamiliar event.
- Relay authentication (22242) is allowed only when **Enable authentication** is
  on for that relay in Nostur's saved app relay settings and the site is connected. Requests require a fresh
  timestamp, empty content, one relay URL and one nonempty challenge. Endpoint
  matching preserves paths and query strings and normalizes only scheme, host,
  default ports and the root slash. Unknown, disabled, conflicting or malformed
  settings fail closed. Relay settings are read asynchronously on their owning
  context for each request, including unsaved toggle changes. No connection-pool
  or importer queue is involved. The web app owns its WebSocket, so it remains
  responsible for obtaining the challenge from that relay.
- NIP-98 requires website-account-access permission, HTTPS, a fresh timestamp,
  empty content, one URL/method and valid payload hashes when supplied. Homepage
  apps (including explicit deployment aliases) may authorize any HTTPS target;
  other connected sites are limited to their own origin. GET, HEAD, POST, PUT
  and PATCH are accepted; DELETE remains excluded. There are no provider or
  upload-path allowlists. This is general HTTP authorization, including possible
  service-specific account actions, not a guarantee that a request is an upload.
- Blossom upload authorization works with any provider for connected apps with
  uploads enabled. Tokens require the upload action, one SHA-256 file hash and
  expiration within ten minutes. Listing, downloading and deletion stay blocked.
- Kind 30078 app data is allowed for every connected site without per-app
  payload exceptions or extra toggles, including Word5 room lookups and scores.
  Shared profile/follow/relay updates and deletion need an extra action grant;
  DMs, native encryption/decryption and delegation remain unavailable. NWC
  signing is separately controlled by Wallet actions. App-data namespaces are not
  isolated by Nostr; services may interpret app data as service-specific commands.
- At most 20 signatures per minute, four pending signatures, and 120 bridge
  requests per minute per browser instance. Event size, tags and timestamps are
  bounded. Denials reject the JavaScript promise and appear in a dismissible
  toolbar badge and recent activity. There are no automatic permission popups.
  Relay authentication denials are kept in activity only, without a badge or banner.

Blocked notices and signing activity use readable kind descriptions, retaining
the kind number for troubleshooting. Relay authentication (22242) and app-specific
data (30078) include an explanation. Relay previews show only the scheme, host
and port; paths, tokens, challenges and event contents are not displayed.
Descriptions follow the NIPs event-kind table and do not grant permissions.

Site controls remember explicit capabilities per exact HTTPS origin and
account. A directory listing is not a guarantee that every feature of that app
will work under these defaults. Automatic social signing trusts the site's
scripts: Nostur cannot infer which requests represent an intentional tap.

## Isolation and lifecycle

Only the active main frame can access the bridge. The native handler checks
WebKit's security origin against the committed page, not a JavaScript URL. The
native handler runs in an isolated content world, unavailable to page scripts;
native code issues a private per-document token and checks it on every request.
Embedded frames, insecure pages, inactive app states, and pages in provisional
navigation cannot sign. The browser must also be presented in a window.
Navigation, Home, minimizing, closing, disconnecting, and account
changes invalidate pending replies. Home unloads the website.

Website storage is isolated per account and persists on iOS 17 and later.
Closing unloads the page while retaining website logins; minimizing retains the
live page too. Favorites and site controls also persist across app launches. Key handling lives in `NativeBrowserEventSigner`, outside the browser host.
The host supplies a policy-issued approval and receives only fixed public event
fields. Local signing runs on its own queue with immutable snapshots, without
passing managed objects between queues. Remote signing uses the existing NIP-46
path with a browser-owned request ID, a 15-second timeout and callback cleanup.
The shared callback registry uses a narrow lock for registration, cancellation
and consumption, and executes callbacks after releasing it.
Returned remote events must match the request and have a valid signature. An
external signer's own approval policy still applies.

## Verification

`BrowserSigningPolicyTests` covers exact origins, unrelated APIs, protected kinds,
permission toggles, oversized/stale requests, malformed auth, bounded upload
tokens, and signing under Nostur's identity despite attacker-supplied identity
fields. `BrowserBridgeTests` exercises NIP-07 promises and embedded-frame isolation
inside WebKit, using a fake signer and local pages without publishing anything.
`RemoteSignerCallbacksTests` checks single consumption, cancellation, reentrant
callbacks and prompt UI operations while the background delivery queue is held.
`BrowserRelaySettingsTests` checks unsaved auth changes and deletion.
`BrowserSessionTests` checks live DOM/draft/cookie retention, rejection of native
bridge requests while minimized, an actual full-screen minimize/return cycle,
and prompt UI operations while a Core Data queue is held.
`BrowserSecurityBoundaryTests` exercises real native bridge grants, stale tokens,
late callbacks and account isolation. `NativeBrowserEventSignerTests` verifies
signature/output sanitization and cancellation under a held signing queue.
See [the security boundary review](in-app-browser-security.md) for the threat model,
residual limits and adversarial test coverage.

Manual checks: open each directory app, choose extension login, confirm the shown
account, try a post/reaction and an upload, inspect blocked requests, switch
accounts, disconnect, and return Home. Check file selection, keyboard and browser
controls on physical devices. Automated bridge tests and a successful launch do
not establish live-site compatibility or physical-device UI verification.

Word5 has automatic account access, public posts and general kind-30078 app
requests. Encrypted sync remains outside the bridge's capabilities.

Post links offer **Open in Nostur Browser** on press-and-hold (or a Mac context
click). HTTPS link previews and individual links in selectable text expose the
choice. Fast feed text lists the destinations when several links are present.
Normal taps retain the existing system-browser behavior. Opening a link reuses
the browser session and its selected account; unknown sites still start
unconnected. Non-web Nostr destinations retain their existing handling.

Website cookies and local storage persist per Nostur account on iOS 17 and later,
including after closing the browser or restarting Nostur. On older iOS, isolated
stores survive browser close/reopen while Nostur remains running. Websites can
still expire their own sessions. Disconnect revokes signing immediately and
asynchronously clears that website’s stored data. No private key is put in a
website profile.

Link-preview cards expose a visible ellipsis **Link actions** menu as well as a
direct long-press action dialog. Their long press is exclusive with the normal
tap, so completing a hold does not also open the external browser. This avoids
depending on context-menu recognition inside swipeable Bookmarks rows.

Website controls has five capability switches: App actions (including media
uploads), Sign in to services, Account changes, Delete content and Wallet actions.
The Use account switch controls the connection. Each switch explains
its effect. These choices apply to one account and exact website origin.

## Optional action grants

The blocked-request sheet offers **Allow today** and **Always allow** for
recognized public/account action kinds. Grants apply to one kind, exact HTTPS
origin and selected account. Today expires at the local calendar day's end
(including daylight-saving transitions); always persists until removed in the
sheet or Website controls. Existing connected-app defaults still apply.

Eligible, valid requests remain pending for up to 120 seconds. Native approval
rechecks the original page/account scope, saves the grant, and retries those exact
pending events. If the request timed out, the permission is saved for a fresh app
retry; the old request is never signed. Navigation, minimizing, account changes,
connection/permission changes or closing cancel pending work and clear page
requests. Grants are rechecked before signing and before delivering a result.

Invalid, expired-at-arrival, oversized, delegated, private-message, remote-
signer and unrecognized requests cannot bypass checks with a grant. NIP-98 and Blossom grants retain their full protocol validation; they cannot
allow an invalid target/method, malformed upload, or a Blossom deletion. Relay
authentication remains governed by native relay settings. Website
controls are accessible from the sheet. Turning App actions off also removes
existing extra grants for ordinary app actions. Removed grants cancel pending work.

Website controls keeps the account and permission toggles visible. Requested
actions and extra permissions appear only when relevant; recent activity is
collapsed and omitted when empty. The info button beside What this app can do explains the current website/account
scope. General browser documentation is not shown in this website sheet. Allow
today/Always allow explanations appear only beside actionable blocked requests. Shared-account warnings stay inline beside
relevant requests, and retry wording appears only after a request expires.

## Website control categories

App actions combines public/app event signing and file-specific Blossom uploads.
The existing social choice is retained; the obsolete independent uploads choice
is ignored. Sign in to services still controls HTTP authorization, which can also
be needed by media providers. Account changes, Delete content and Wallet actions
are separate, off by default, per account and exact origin. Account changes covers
profile/follow/list settings, excluding wallet protocols. Delete content covers
kinds 5 and 62. Wallet actions covers NWC kinds 13194 and 23194–23197; it does not
provide saved wallet credentials, native encryption/decryption, Cashu wallet
access, spending limits or per-payment approval. The wallet manages its own
connection permissions. Ordinary NWC uses a connection key rather than the
user's Nostr identity; allowing identity signing alone is not a wallet connection.
Existing per-kind action grants remain visible; switching a category off removes
its saved grants and cancels pending work. All categories retain request, origin,
account, document and signed-event validation.
