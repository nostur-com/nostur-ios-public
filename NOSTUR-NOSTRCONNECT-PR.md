# PR Plan: Add `nostrconnect://` Deep Link Support to Nostur

**Target repo**: `/Users/baris/Projects/nostr/nostur-ios-public`  
**Date**: 2026-02-14  
**Scope**: Register `nostrconnect://` and `bunker://` URL schemes, handle deep links to auto-connect remote signers  
**Complexity**: Medium — touches 4-5 existing files, adds ~150 lines

---

## Problem

Nostur already supports NIP-46 remote signing via `RemoteSignerManager`, and users can
manually paste a `bunker://` URI into the "Add Existing Account" text field. However:

1. **No URL scheme registered** for `nostrconnect://` or `bunker://` — tapping a bunker link
   in Safari, another app, or a QR scanner does nothing.
2. **No deep link handling** — `handleUrl()` in `View+withNavigationDestinations.swift` handles
   `nostur://`, `nostr://`, and `nostr+login://` but not `bunker://` or `nostrconnect://`.
3. **User must manually navigate** to Settings > Accounts > Add Existing Account > paste the URI.
   This is friction that other clients avoid.

## What Already Works

| Component | File | Status |
|-----------|------|--------|
| `parseBunkerUrl()` | `NostrEssentials` → `RemoteSigningHelpers.swift` | Works for `bunker://` URIs |
| `RemoteSignerManager.connect()` | `NIP46-NC/RemoteSignerManager.swift:265` | Full NIP-46 connect flow |
| `NIP46SecretManager` | `NIP46-NC/NIP46SecretManager.swift` | Session key Keychain storage |
| `addExistingBunkerAccount()` | `AddExistingAccountSheet.swift:419` | Account creation + connect |
| NIP-04 encryption for requests | `RemoteSignerManager.swift:309` | Encrypts with `Keys.encryptDirectMessageContent` |
| NIP-04/NIP-44 decryption for responses | `RemoteSignerManager.swift:65` | Tries NIP-04, falls back to NIP-44 |

The happy path is all implemented. The gap is just **getting the URI into the app from outside**.

---

## Proposed Changes

### 1. Register URL Schemes in Info.plist

**File**: `Nostur/Info.plist`

Add two new URL scheme entries inside the existing `CFBundleURLTypes` array:

```xml
<!-- Add after the existing nostr+login scheme dict -->
<dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLName</key>
    <string>nostur-bunker</string>
    <key>CFBundleURLSchemes</key>
    <array>
        <string>bunker</string>
    </array>
</dict>
<dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLName</key>
    <string>nostur-nostrconnect</string>
    <key>CFBundleURLSchemes</key>
    <array>
        <string>nostrconnect</string>
    </array>
</dict>
```

### 2. Add Deep Link Handler in `handleUrl()`

**File**: `Nostur/Utils/View+withNavigationDestinations.swift`

Add a new handler block near the top of `handleUrl(_ url: URL)`, before the existing
`nostur:add_relay:` handler (around line 359):

```swift
// HANDLE BUNKER:// DEEP LINKS (NIP-46 Remote Signer)
if url.scheme == "bunker" {
    handleBunkerDeepLink(url)
    return
}

// HANDLE NOSTRCONNECT:// DEEP LINKS (NIP-46 client-initiated)
if url.scheme == "nostrconnect" {
    handleNostrConnectDeepLink(url)
    return
}
```

Then add the handler functions (at the bottom of the file or in a new file):

```swift
/// Handle bunker:// deep links
/// Format: bunker://<remote-signer-pubkey>?relay=<wss://relay>&secret=<token>
/// This is signer-initiated: the signer generated this URI for us to scan/tap.
private func handleBunkerDeepLink(_ url: URL) {
    let urlString = url.absoluteString
    guard let bunkerURL = parseBunkerUrl(urlString) else {
        L.og.error("🏰 Invalid bunker:// URL: \(urlString)")
        return
    }
    
    guard isValidPubkey(bunkerURL.pubkey) else {
        L.og.error("🏰 Invalid pubkey in bunker URL: \(bunkerURL.pubkey)")
        return
    }
    
    // Show confirmation sheet before connecting
    DispatchQueue.main.async {
        AppSheetsModel.shared.bunkerConnectInfo = BunkerConnectInfo(
            pubkey: bunkerURL.pubkey,
            relay: bunkerURL.relay,
            secret: bunkerURL.secret
        )
    }
}

/// Handle nostrconnect:// deep links
/// Format: nostrconnect://<client-pubkey>?relay=<wss://relay>&secret=<secret>&name=<app-name>
/// This is client-initiated: another app wants US to connect to it.
/// For Nostur as a CLIENT (not a signer), this is less common but could be used for
/// cross-device flows where Nostur on device A connects to Nostur on device B.
///
/// In most cases, Nostur users will receive bunker:// URIs, not nostrconnect:// URIs.
/// We parse it the same way and present the same confirmation UI.
private func handleNostrConnectDeepLink(_ url: URL) {
    // nostrconnect:// has the same structure as bunker:// but with a different semantic:
    // the pubkey is the CLIENT's pubkey, not the signer's.
    // For now, treat identically — the RemoteSignerManager handles the handshake.
    let urlString = url.absoluteString
        .replacingOccurrences(of: "nostrconnect://", with: "bunker://")
    guard let bunkerURL = parseBunkerUrl(urlString) else {
        L.og.error("🏰 Invalid nostrconnect:// URL: \(url.absoluteString)")
        return
    }
    
    guard isValidPubkey(bunkerURL.pubkey) else {
        L.og.error("🏰 Invalid pubkey in nostrconnect URL")
        return
    }
    
    DispatchQueue.main.async {
        AppSheetsModel.shared.bunkerConnectInfo = BunkerConnectInfo(
            pubkey: bunkerURL.pubkey,
            relay: bunkerURL.relay,
            secret: bunkerURL.secret
        )
    }
}
```

### 3. Add Confirmation Sheet Model

**File**: `Nostur/Utils/AppSheetsModel.swift` (or wherever `AppSheetsModel` is defined)

Add a new published property and model:

```swift
// Add to AppSheetsModel:
@Published var bunkerConnectInfo: BunkerConnectInfo? = nil

// New model:
struct BunkerConnectInfo: Identifiable {
    let id = UUID()
    let pubkey: String
    let relay: String?
    let secret: String?
}
```

### 4. Add Confirmation Sheet View

**New file**: `Nostur/Nostr/NIP46-NC/BunkerConnectSheet.swift`

This is the confirmation UI that appears when the user taps a `bunker://` link.
It shows the signer pubkey, relay, and asks the user to confirm before connecting.

```swift
import SwiftUI
import NostrEssentials

struct BunkerConnectSheet: View {
    let info: BunkerConnectInfo
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.accountsState) var accountsState
    @ObservedObject private var bunkerManager = RemoteSignerManager.shared
    
    @State private var relay: String = ""
    @State private var connecting = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                
                Text("Connect to Remote Signer")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("Signer") {
                        Text(String(info.pubkey.prefix(8)) + "..." + String(info.pubkey.suffix(8)))
                            .font(.system(.caption, design: .monospaced))
                    }
                    
                    if let infoRelay = info.relay {
                        LabeledContent("Relay") {
                            Text(infoRelay)
                                .font(.caption)
                        }
                    }
                    
                    // Editable relay field (pre-filled from URI, user can override)
                    TextField("Relay address (wss://...)", text: $relay)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                if connecting {
                    ProgressView("Connecting...")
                }
                
                if !bunkerManager.error.isEmpty {
                    Text(bunkerManager.error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                Spacer()
                
                HStack(spacing: 16) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Connect") {
                        connectToBunker()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(connecting || relay.isEmpty)
                }
            }
            .padding()
            .navigationTitle("Remote Signer")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                relay = info.relay ?? ""
            }
            .onChange(of: bunkerManager.state) { newState in
                if newState == .connected {
                    dismiss()
                } else if newState == .error {
                    connecting = false
                }
            }
        }
    }
    
    private func connectToBunker() {
        connecting = true
        bunkerManager.ncRelay = relay
        
        // Reuse the existing account creation logic from AddExistingAccountSheet
        let pubkey = info.pubkey
        
        if let existingAccount = (try? CloudAccount.fetchAccount(publicKey: pubkey, context: viewContext)) {
            existingAccount.flagsSet.insert("full_account")
            bunkerManager.connect(existingAccount, token: info.secret)
            return
        }
        
        let account = CloudAccount(context: viewContext)
        account.flags = "full_account"
        account.createdAt = Date()
        account.publicKey = pubkey
        account.ncRemoteSignerPubkey_ = pubkey
        account.ncRelay = relay
        
        bunkerManager.connect(account, token: info.secret)
        accountsState.changeAccount(account)
    }
}
```

### 5. Present the Sheet from AppView

**File**: `Nostur/AppView.swift`

Add a `.sheet` modifier for the bunker connect confirmation:

```swift
// Add after the existing .onOpenURL(perform: handleUrl)
.sheet(item: $AppSheetsModel.shared.bunkerConnectInfo) { info in
    BunkerConnectSheet(info: info)
}
```

> **Note**: The exact placement depends on how `AppSheetsModel` is consumed in `AppView`.
> Look at how other sheets (like `relayFeedPreviewSheetInfo`) are presented and follow the
> same pattern.

---

## Files Changed Summary

| File | Change | Lines |
|------|--------|-------|
| `Nostur/Info.plist` | Add `bunker` and `nostrconnect` URL schemes | ~16 |
| `Nostur/Utils/View+withNavigationDestinations.swift` | Add deep link handlers | ~50 |
| `Nostur/Utils/AppSheetsModel.swift` | Add `bunkerConnectInfo` property + model | ~12 |
| `Nostur/Nostr/NIP46-NC/BunkerConnectSheet.swift` | **New file** — confirmation UI | ~100 |
| `Nostur/AppView.swift` | Present the confirmation sheet | ~3 |

**Total**: ~180 lines across 5 files (1 new).

---

## Testing Plan

### Manual Testing

1. **bunker:// from Safari**:
   - Open Safari on device
   - Navigate to a page with a `bunker://` link (or type one in the address bar)
   - Tap the link → Nostur should open and show the connection confirmation sheet
   - Tap "Connect" → should establish NIP-46 connection

2. **bunker:// from QR scanner**:
   - Use iOS Camera app to scan a QR code containing a `bunker://` URI
   - iOS should offer to open in Nostur
   - Same flow as above

3. **bunker:// from clipboard paste** (existing flow, regression test):
   - Open Nostur → Settings → Accounts → Add Existing Account
   - Paste a `bunker://` URI → should still work as before

4. **nostrconnect:// from another app**:
   - Same as bunker:// but with `nostrconnect://` scheme

5. **Invalid URLs**:
   - `bunker://invalid-pubkey?relay=wss://relay.example.com` → should show error
   - `bunker://` with no pubkey → should be silently ignored
   - `bunker://` with no relay → should show relay input field for manual entry

6. **Already-connected account**:
   - Tap a bunker:// link for a pubkey that already has an account → should reconnect

### Edge Cases

- App is not running when link is tapped (cold start with deep link)
- App is in background when link is tapped
- Multiple rapid link taps
- Link with percent-encoded relay URL (e.g. `wss%3A%2F%2Frelay.nsec.app`)

---

## Notes for Implementation

### What NOT to change

- `RemoteSignerManager.swift` — the connect flow already works, don't touch it
- `NIP46SecretManager.swift` — session key management is fine
- `NostrEssentials/parseBunkerUrl()` — already handles `bunker://` parsing correctly
- `AddExistingAccountSheet.swift` — keep the manual paste flow as-is (it's a fallback)

### NostrEssentials Enhancement (Optional, Separate PR)

`parseBunkerUrl()` in `NostrEssentials` currently **only** accepts `bunker://` prefix.
A small enhancement to also accept `nostrconnect://` would be cleaner than the
`replacingOccurrences` workaround in the deep link handler. This would be a separate
PR to the `nostur-com/nostr-essentials` repo:

```swift
// In RemoteSigningHelpers.swift, change:
guard input.starts(with: "bunker://") else { return nil }
let withoutScheme = input.dropFirst("bunker://".count)

// To:
let prefix: String
if input.starts(with: "bunker://") {
    prefix = "bunker://"
} else if input.starts(with: "nostrconnect://") {
    prefix = "nostrconnect://"
} else {
    return nil
}
let withoutScheme = input.dropFirst(prefix.count)
```

### NIP-46 Spec Nuance

Per the NIP-46 spec, `bunker://` and `nostrconnect://` have slightly different semantics:

- **`bunker://`** = Signer-initiated. The pubkey in the URI is the **signer's** pubkey.
  The client (Nostur) generates a session keypair and sends a `connect` request.
  **This is the common flow for Amber → Nostur.**

- **`nostrconnect://`** = Client-initiated. The pubkey is the **client's** ephemeral pubkey.
  The signer opens this URL and sends a response back.
  **This flow is less relevant for Nostur-as-client**, but registering the scheme
  prevents user confusion if they encounter such a URL.

For the initial PR, treating both schemes identically (as signer pubkey) is acceptable
since Nostur is always the client. A future enhancement could differentiate if needed.

---

## Dependencies

- None. All required functionality already exists in `NostrEssentials` and `RemoteSignerManager`.
- No new SPM packages needed.

## Breaking Changes

- None. Existing manual `bunker://` paste flow is unchanged.
- New URL schemes don't conflict with existing `nostur://`, `nostr://`, `nostr+login://` schemes.

---

## Appendix: GitHub Actions CI — Build & .ipa Generation

Nostur currently uses **Xcode Cloud** for CI and manual Xcode Organizer for releases.
There are no GitHub Actions workflows. Adding one enables automated builds on every PR
and produces a downloadable `.ipa` artifact for testing.

### Prerequisites

The project requires a `Config.xcconfig` file (gitignored) generated from `Config.xcconfig.dist`.
API keys are optional for building — the app compiles without them, features that need those
keys (GIF picker, Imgur uploads) will simply be unavailable in the build.

For **unsigned simulator builds** (free, no Apple Developer account needed):
- No secrets required.

For **signed .ipa for real devices / TestFlight** (requires Apple Developer account):
- Store these as GitHub repository secrets:
  - `CERTIFICATE_BASE64` — Base64-encoded .p12 distribution certificate
  - `CERTIFICATE_PASSWORD` — Password for the .p12 file
  - `PROVISIONING_PROFILE_BASE64` — Base64-encoded .mobileprovision file
  - `KEYCHAIN_PASSWORD` — Arbitrary password for the temporary build keychain

### Workflow: Build + Test (no signing needed)

**New file**: `.github/workflows/build.yml`

```yaml
name: Build & Test

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: macos-14
    timeout-minutes: 30

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_15.4.app

      - name: Generate Config.xcconfig
        run: |
          cat > Config.xcconfig << 'EOF'
          TENOR_API_KEY = placeholder
          TENOR_CLIENT_KEY = placeholder
          KLIPY_API_KEY = placeholder
          IMGUR_CLIENT_ID = placeholder
          NOSTRCHECK_PUBLIC_API_KEY = placeholder
          NOSTUR_IS_DESKTOP = NO
          NIP89_APP_NAME = Nostur
          NIP89_APP_REFERENCE =
          APPSTORE_VERSION = 0.0.1
          EOF

      - name: Resolve SPM Dependencies
        run: |
          xcodebuild -resolvePackageDependencies \
            -scheme Nostur \
            -clonedSourcePackagesDirPath .spm-cache

      - name: Build for Simulator
        run: |
          xcodebuild build \
            -scheme Nostur \
            -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' \
            -clonedSourcePackagesDirPath .spm-cache \
            CODE_SIGNING_ALLOWED=NO

      - name: Run Tests
        run: |
          xcodebuild test \
            -scheme Nostur \
            -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5' \
            -clonedSourcePackagesDirPath .spm-cache \
            -resultBundlePath TestResults \
            CODE_SIGNING_ALLOWED=NO
```

### Workflow: Build Signed .ipa (requires Apple Developer secrets)

**New file**: `.github/workflows/build-ipa.yml`

```yaml
name: Build .ipa

on:
  workflow_dispatch:       # Manual trigger only
  push:
    tags: ['v*']           # Or on version tags

jobs:
  build-ipa:
    runs-on: macos-14
    timeout-minutes: 45

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_15.4.app

      - name: Generate Config.xcconfig
        run: |
          cat > Config.xcconfig << 'EOF'
          TENOR_API_KEY = ${{ secrets.TENOR_API_KEY || 'placeholder' }}
          TENOR_CLIENT_KEY = ${{ secrets.TENOR_CLIENT_KEY || 'placeholder' }}
          KLIPY_API_KEY = ${{ secrets.KLIPY_API_KEY || 'placeholder' }}
          IMGUR_CLIENT_ID = ${{ secrets.IMGUR_CLIENT_ID || 'placeholder' }}
          NOSTRCHECK_PUBLIC_API_KEY = ${{ secrets.NOSTRCHECK_PUBLIC_API_KEY || 'placeholder' }}
          NOSTUR_IS_DESKTOP = NO
          NIP89_APP_NAME = Nostur
          NIP89_APP_REFERENCE =
          APPSTORE_VERSION = 0.0.1
          EOF

      - name: Install signing certificate
        env:
          CERTIFICATE_BASE64: ${{ secrets.CERTIFICATE_BASE64 }}
          CERTIFICATE_PASSWORD: ${{ secrets.CERTIFICATE_PASSWORD }}
          KEYCHAIN_PASSWORD: ${{ secrets.KEYCHAIN_PASSWORD }}
        run: |
          # Decode certificate
          CERTIFICATE_PATH=$RUNNER_TEMP/build_certificate.p12
          echo -n "$CERTIFICATE_BASE64" | base64 --decode -o $CERTIFICATE_PATH

          # Create temporary keychain
          KEYCHAIN_PATH=$RUNNER_TEMP/app-signing.keychain-db
          security create-keychain -p "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH
          security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH

          # Import certificate
          security import $CERTIFICATE_PATH -P "$CERTIFICATE_PASSWORD" \
            -A -t cert -f pkcs12 -k $KEYCHAIN_PATH
          security set-key-partition-list -S apple-tool:,apple: \
            -k "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH
          security list-keychain -d user -s $KEYCHAIN_PATH

      - name: Install provisioning profile
        env:
          PROVISIONING_PROFILE_BASE64: ${{ secrets.PROVISIONING_PROFILE_BASE64 }}
        run: |
          PP_PATH=$RUNNER_TEMP/build_pp.mobileprovision
          echo -n "$PROVISIONING_PROFILE_BASE64" | base64 --decode -o $PP_PATH
          mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
          cp $PP_PATH ~/Library/MobileDevice/Provisioning\ Profiles

      - name: Resolve SPM Dependencies
        run: |
          xcodebuild -resolvePackageDependencies \
            -scheme Nostur \
            -clonedSourcePackagesDirPath .spm-cache

      - name: Archive
        run: |
          xcodebuild archive \
            -scheme Nostur \
            -destination 'generic/platform=iOS' \
            -archivePath $RUNNER_TEMP/Nostur.xcarchive \
            -clonedSourcePackagesDirPath .spm-cache

      - name: Create ExportOptions.plist
        run: |
          cat > $RUNNER_TEMP/ExportOptions.plist << 'EOF'
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
            "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0">
          <dict>
              <key>method</key>
              <string>ad-hoc</string>
              <key>teamID</key>
              <string>5T4GDWX88Z</string>
              <key>signingStyle</key>
              <string>manual</string>
              <key>provisioningProfiles</key>
              <dict>
                  <key>nostur.com.Nostur</key>
                  <string>Nostur Ad Hoc</string>
              </dict>
          </dict>
          </plist>
          EOF

      - name: Export .ipa
        run: |
          xcodebuild -exportArchive \
            -archivePath $RUNNER_TEMP/Nostur.xcarchive \
            -exportOptionsPlist $RUNNER_TEMP/ExportOptions.plist \
            -exportPath $RUNNER_TEMP/ipa

      - name: Upload .ipa artifact
        uses: actions/upload-artifact@v4
        with:
          name: Nostur.ipa
          path: ${{ runner.temp }}/ipa/*.ipa

      - name: Clean up keychain
        if: always()
        run: |
          security delete-keychain $RUNNER_TEMP/app-signing.keychain-db
```

### Notes

- The **Build & Test** workflow requires no secrets and runs on every push/PR. This is
  the workflow to add first.
- The **Build .ipa** workflow is for ad-hoc distribution (testing on registered devices).
  For TestFlight/App Store, change `method` to `app-store` in ExportOptions.plist and
  add an upload step using `xcrun altool` or the App Store Connect API.
- SPM dependencies are cached via `-clonedSourcePackagesDirPath` to speed up builds.
- The `webm_to_m4a_ffmpeg.xcframework` is checked into the repo, so no extra build step
  is needed for that dependency.
- `macos-14` runner provides Xcode 15.x. Adjust the `xcode-select` path if a different
  version is needed.
- Team ID `5T4GDWX88Z` and bundle ID `nostur.com.Nostur` are from the existing project
  config — the repo owner would use their own values.
