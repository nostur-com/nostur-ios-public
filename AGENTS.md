# AGENTS.md

This file provides guidance coding agents when working in this repository.

## About Nostur

Nostur is a social media client for the Nostr protocol, built for Mac, iPhone, and iPad with SwiftUI.

## Build And Setup

1. Requirements: Xcode 26.x, iOS SDK 26.x
2. Copy `Config.xcconfig.dist` to `Config.xcconfig` and set required API keys
3. Open `Nostur.xcodeproj` in Xcode
4. Dependencies are managed by Swift Package Manager (`Package.resolved`)

### Build Commands

```bash
# iOS Simulator (omit -derivedDataPath to share Xcode's default DerivedData/cache)
xcodebuild -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Physical device
xcodebuild -scheme Nostur -destination 'platform=iOS,id=<device_id>' build

# Archive
xcodebuild -scheme Nostur -archivePath Nostur.xcarchive archive
```

### When finishing code changes

After changes are mode:

1. Build and launch with `./scripts/run-sim.sh` (shares Xcode’s default DerivedData; use `--no-build` only if the app is already built and only reinstall/launch is needed).
2. Tell the user the app is ready to test — do **not** only print the command for them to run.

### Tests

- Run tests:
  `xcodebuild test -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
- Test files: `NosturTests/`
- Test plans: `Nostur.xctestplan`, `NostrEssentials.xctestplan`
- Current automated coverage is limited; previews and manual verification are common.
- Mac Catalyst note: avoid `ExecuteSnippet` while Catalyst is selected; switch to an iPhone simulator for snippet runs because generated snippet code imports `Playgrounds`.

## Architecture

- Pattern: MVVM with SwiftUI and Combine (existing codebase)
- Storage: Core Data with CloudKit sync
- Networking: Custom WebSocket-based relay communication for Nostr
- State: Central app and account state with feature-specific view models

### Core Files

- `NosturApp.swift`: app entry point and dependency injection
- `AppView.swift`: root view
- `AppState.swift`: app-wide state and timers
- `AppEnvironment.swift`: environment configuration
- `Nostur/Nostr/Nostr.swift`: protocol/event handling
- `Nostur/Post/ContentRenderer.swift`: post rendering
- `Nostur/Feeds/NXColumnView.swift`: feed display architecture

### Important Directories

- `Nostur/`: main app code
- `Nostur/CoreData/`: entities and data layer
- `NosturTests/`: tests
- `Libraries/`: internal/custom library code
- `Assets.xcassets/`, `Themes.xcassets/`: assets and theming

## Development Patterns

- Organize by feature (Posts, Profiles, DMs, etc.)
- Put shared UI in `ViewFragments/`
- Put helpers/extensions in `Utils/`
- Use SwiftUI previews for UI iteration
- Use environment objects for shared state where already established
- Respect existing theming in `NosturStyles.swift` and theme assets
- Use `Nostur/Playground/` for component-level experimentation

## Performance Notes

- Prefer lazy/on-demand loading in feed-like views
- Reuse existing caches (`LRUCache2`, `EventCache`, etc.)
- Keep heavy processing off the main thread
- Avoid retention cycles

### Main-thread responsiveness guardrails

- Never synchronously wait from the main thread for Core Data, the importer,
  relay/network work, feed processing, or another dispatch queue. In particular,
  do not use `performAndWait`, `DispatchQueue.sync`, `DispatchGroup.wait`, or
  `DispatchSemaphore.wait` in a user-initiated/UI path.
- Do not use a managed object context as a general-purpose synchronization queue.
  Plain in-memory state must use its own narrowly scoped lock, serial queue, or
  actor. Keep lock critical sections to collection/state access only; never hold
  a lock while doing I/O, logging large values, invoking callbacks, or touching
  Core Data.
- Navigation, tab selection, button handlers, and view appearance must return
  immediately. They may schedule asynchronous work, but feed imports and relay
  responses must never be prerequisites for updating navigation UI.
- Preserve priority separation: opening a post, resolving its parent, and loading
  notification detail must not queue behind feed backfill or pagination. Bound
  relay fan-out and imported event volume for background/feed requests.
- Before changing `Backlog`, `ReqTask`, `Importer`, `ConnectionPool`, feed loading,
  or Core Data scheduling, trace every caller and explicitly check whether it can
  run on `@MainActor`. Treat replacing an async operation with a synchronous one
  as a high-risk performance change requiring a regression test.
- Any synchronization fix must include a test that holds or saturates the
  background/import queue and proves the UI-facing operation still completes
  promptly. A test that only proves ordering is not sufficient.
- For feed/network performance changes, smoke-test on a physical iPhone while
  imports are active: switch Following → another feed, reach a sparse feed's end,
  switch tabs, open a notification post, and return. Verify pagination appears,
  taps remain responsive, and the device does not sustain abnormal CPU/heat.
- Do not call a responsiveness issue fixed based only on a successful build or
  happy-path unit test. Report what stress/navigation scenario was actually run;
  if it was not run, say that manual responsiveness remains unverified.

## Configuration And Flags

- Main config: `Config.xcconfig`
- Feature toggle: `NOSTUR_IS_DESKTOP` for non-App Store features
- Debugging uses existing logging/debug windows

## Working In This Repo

- Keep changes scoped to the user request
- Follow existing code style and naming in nearby files
- Prefer updating existing flows over introducing parallel architecture
- If adding new Nostr event types:
  1. Update `NEventKind`
  2. Extend parsing in `Nostr.swift`
  3. Add handling in the relevant feature module
  4. Update relay communication logic as needed

## Large / Sensitive Paths

Agents should avoid these unless the user explicitly asks:

- `Config.xcconfig` — secrets / API keys (gitignored). Use `Config.xcconfig.dist` as the template.
- `Nostur/Nostr/DummyData/DummyEvents.swift` — multi‑MB fixture; do not open or search into it by default.
- Build products and archives: `build/`, `DerivedData/`, `*.xcarchive/`, `/tmp/NosturDerived` if present.
- Local/tooling noise: `*.log`, `*.dump`, large generated dumps.

Prefer listing, grepping, and reading under `Nostur/` feature code; skip dummy fixtures and secrets.

## Notes about Core Data
- Different Core Data managed object contexts are used, leading to crashes when accessing attributes from the wrong context. 
- Usually there is a main context and a bg context. 
- Usually CloudAccount and CloudFeed is accessed from main and Event from bg
- Look for bg().perform { } or Task { @MainActor } or DispatchQueue.main... to make sure we are in the right context.
