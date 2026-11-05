# Browser / signer security boundary

The threat model treats every website and its JavaScript as untrusted, including
third-party scripts on a previously trusted website. The goal is to prevent a
website from obtaining a private key, accessing Nostur's native data, selecting a
different signing account, or exceeding the permissions granted in native UI.
This is an implementation review and regression-test plan, not a proof that
WebKit, the operating system or the cryptographic dependencies have no defects.

## Three components

1. **Web content** receives the NIP-07 `getPublicKey` and `signEvent` functions.
   Requests contain only a method and the four unsigned-event fields. The page
   cannot select an account, pass native selectors, read a native file or invoke
   encryption, decryption, wallet operations, database queries or key export.
2. **Browser host** owns native site/account permissions and WebKit lifecycle.
   The actual native message handler lives in a named, isolated `WKContentWorld`,
   not the page world. A small isolated transport validates messages and enforces
   size/rate/concurrency limits before crossing into the native process. It
   accepts only trusted `postMessage` events from the main window itself. Native
   code separately checks WebKit's main-frame/security-origin information, the
   actual displayed web view, foreground/presentation state, the selected account
   and a per-document token assigned at commit. The token never crosses the DOM
   message channel. Neither the native handler nor this token is available to
   page JavaScript.
3. **Native signer** (`NativeBrowserEventSigner`, outside the Browser folder)
   alone resolves account key material. It has no WebKit dependency and accepts
   only a policy-issued `BrowserSigningApproval`. It returns a typed public
   `BrowserSignedEvent`, never a managed object, key, credential, arbitrary object
   or underlying error. Local and remote results must match the approved account
   and event and pass signature verification. Extra response fields are discarded
   before encoding the public DTO. Browser request/response payloads are excluded
   from the remote signer's debug payload logs.

The Browser folder contains no private-key, keychain or local-signing operations.
The native signer is an in-process code boundary, not a separate cryptographic
hardware enclave or a guarantee against native-process compromise.

## Permissions

- Every compiled homepage app and its exact deployment aliases receives the
  same defaults: connection, public social signing, website authorization and
  bounded Blossom uploads. Public app actions use a protection list rather than a
  finite kind allowlist: unfamiliar kinds are allowed when App actions is enabled.
  Shared account settings (all 10000–19999 kinds), profile/follow updates, known
  shared addressable lists and deletion require explicit grants where supported.
  Known private-message, signer and group-administration kinds remain
  blocked; NWC signing requires its separate wallet permission; relay/HTTP/Blossom events keep their specific validation. This trades
  semantic certainty about future kinds for compatibility; page scripts can sign
  unfamiliar public events, not just actions caused by a tap. Outside sites start disconnected with capabilities
  off. Directory membership grants these defaults, so additions require review.
  Removing an entry removes its automatic defaults; explicit user overrides are
  retained. There are no separate per-app capability tiers.
- Native site controls are optional per-account/origin overrides. Explicit user
  choices take precedence over defaults. A capability supplied by a recommended
  default can be exercised by that site's scripts, just like an explicit override.
  Defaults do not expose native secrets or add arbitrary signing methods.
- Relay authentication requires both a connected site and **Enable
  authentication** for the exact relay in Nostur's app relay settings. The event
  needs one nonempty challenge, one matching relay, empty content and a fresh
  timestamp. Scheme/host/default-port/root-slash normalization does not widen
  permission to a different path, query, port or scheme. The latest setting is
  checked before dispatch and again before delivery after signer delays.
- Signed HTTP requests to the app’s own HTTPS origin are enabled after account
  connection by default, with a website setting to turn them off. External HTTPS
  destinations require a separate allowance from Recent activity for the exact
  source site, destination, and account, regardless of directory membership.
  HTTPS, freshness, URL, method and payload-hash validation still apply.
- Blossom authorization is provider-neutral and requires the upload grant, upload
  action, a single file hash and a short expiration. Other storage actions remain
  blocked. Tokens are portable as defined by the protocol.
- Profile/follow/relay changes and deletion are blocked by default but may receive
  explicit native action grants. Private-message/decryption operations,
  delegation remains unavailable; NWC signing needs its separate wallet permission. Kind 30078 is allowed for
  connected sites without schema, namespace or content-shape exceptions. This
  trusts services with app data and service-specific commands encoded in that
  kind. Nostr does not isolate namespaces: another connected site can overwrite
  app settings using the same author/kind/d tag. Native keys, storage and wallet
  APIs remain inaccessible. Input bounds and account, document, connection and
  cancellation checks still apply.

## Revocation, isolation and input bounds

Requests are bound to document token, HTTPS origin and native-selected account.
Navigation, account changes, capability changes, disconnect, minimize, close and
process termination cancel outstanding requests. Cancellation does not wait for
an import or signing queue. Queued native work checks a cancellation flag before
signing; already-running cryptography cannot be undone, but canceled results are
not delivered to JavaScript. A 15-second native deadline bounds pending work.
Permission and scope are checked again before response delivery.

Native input must be a bounded JSON string with exactly the supported envelope
and event fields. Non-string IPC objects, unknown methods/fields, malformed
events, invalid keys/signatures, large payloads and stale tokens fail closed.
Limits also apply in the isolated transport, so page scripts cannot bypass the
normal wrapper by directly calling a page-world native handler. Native limits
remain authoritative. UTF-8 byte limits supplement JavaScript string lengths.

Website storage persists per account on iOS 17+ and is independent of Nostur's native URLSession,
database and keychain. Changing accounts replaces the web view and selects an isolated account-specific data store;
site grants are keyed by account and exact origin. Minimizing retains the web
session but disables native signing. Local/native/custom-scheme navigations are
blocked. Embedded frames cannot request native privileges. Cross-frame popups
cannot redirect the native browser. No camera, microphone, location, clipboard or
file permission is automatically granted by Nostur's signer; WebKit/system
permissions and explicit file selection remain separate user actions.

## Residual limits

A website can send its own data, a shared public key, granted signatures, text
entered into the page and selected files to its servers. It can publish any social
events it is authorized to sign, within the rate limit. Keeping the key private
does not make an authorized malicious website harmless. Removing these remaining
abilities would require withholding their grants or introducing native review of
individual actions. WebKit/OS sandbox escapes, device compromise, dependency bugs,
phishing and user-supplied secrets are outside what these application checks can
eliminate. Website logins and file selection do not expose Nostur's stored secrets
through a native API, but do create a trust relationship with that website.

## Regression evidence

`BrowserBridgeTests`: real WebKit-world isolation, no page-world native handler or
token, no iframe provider, rejection of cross-frame/forged messages, oversized
requests, unsupported capabilities and malformed native packet fields.

`BrowserSecurityBoundaryTests`: real native bridge with test identities and a fake
signer, zero-configuration recommended-app defaults, optional user overrides,
ignored page-selected identity fields, stale
document rejection, cancellation/late responses, account and cookie-store isolation.

`NativeBrowserEventSignerTests`: valid signatures, fixed public output fields,
extra-field sanitization, altered/wrong-account/invalid-signature rejection,
sanitized failure codes, and prompt cancellation while the signing queue is held.

Existing policy, relay-settings, session and navigation tests cover protected kinds,
endpoint binding, disabled grants, preference updates, native presentation/resume
and UI responsiveness while a Core Data queue is held. These tests use local pages
and fixture keys and do not publish events or upload user data. A successful test
run does not establish live-site compatibility or a physical-device security audit.

## Native action grants

Only native UI can store a grant: an exact origin/account/kind tuple, expiring at
local midnight or persisting until native revocation. The page bridge accepts no
permission/grant fields. Known public/account actions and replaceable account
data kinds are eligible for explicit grants. Grants cannot override structural, timestamp, size, delegation, account
or document checks. Private-message and remote-signer kinds cannot be enabled through these grants; NWC signing can.
HTTP and Blossom grants still require their normal protocol validation, and
relay-authentication permission remains authoritative in native relay settings. These protocol checks also apply under the broader app-action defaults.

A policy-blocked eligible request is retained for at most two minutes, within the
existing four-pending-request limit. No key work occurs before approval. The
native sheet approves only while its captured document/account/origin is current.
Each retry uses the immutable original event and passes normal signing and output
verification. Expired requests may save a permission but need a new web-app retry.
Grants are read again at delivery, so revocation and expiry stop late results.
Grants and their revocation are account/origin scoped and stored in native
preferences, independent of website cookies. Revoking a grant cancels pending
work. Denials appear quietly in native toolbar state; relay-auth denials retain
activity-only behavior. Closing the sheet alone does not approve anything.

## Category overrides

Account changes, Delete content and Wallet actions are off by default and scoped
to the selected account and exact origin. They are rechecked before signing and
before delivery. Account changes excludes NWC and other restricted wallet
protocols, even where their kind is in the account replacement range. Deletion
covers 5 and 62. NWC signing (13194, 23194–23197) can be explicitly enabled via
Wallet actions or an individual native action grant, without payment-content
inspection or browser spending limits. This never reads or exposes Nostur's saved
wallet connection credentials and does not add encryption or decryption APIs.
Turning a category off removes that category's saved grants and cancels pending
requests. App actions now also governs Blossom uploads; the old uploads preference
is ignored. HTTP authorization remains separately controlled and can authorize
media-service requests under its existing rules.
