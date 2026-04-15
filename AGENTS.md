# AGENTS.md

This file provides guidance to Codex-style coding agents when working in this repository.

## About Nostur

Nostur is a social media client for the Nostr protocol, built for Mac, iPhone, and iPad with SwiftUI.

## Build And Setup

1. Requirements: Xcode 15.x, iOS SDK 16.x
2. Copy `Config.xcconfig.dist` to `Config.xcconfig` and set required API keys
3. Open `Nostur.xcodeproj` in Xcode
4. Dependencies are managed by Swift Package Manager (`Package.resolved`)

### Build Commands

```bash
# iOS Simulator
xcodebuild -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 16 Pro (18.5),OS=18.5' build

# Physical device
xcodebuild -scheme Nostur -destination 'platform=iOS,id=<device_id>' build

# Archive
xcodebuild -scheme Nostur -archivePath Nostur.xcarchive archive
```

### Tests

- Run tests:
  `xcodebuild test -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 16 Pro (18.5),OS=18.5'`
- Test files: `NosturTests/`
- Test plans: `Nostur.xctestplan`, `NostrEssentials.xctestplan`
- Current automated coverage is limited; previews and manual verification are common.

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

## Notes about Core Data
- Different Core Data managed object contexts are used, leading to crashes when accessing attributes from the wrong context. 
- Usually there is a main context and a bg context. 
- Usually CloudAccount is accessed from main and Event frorm bg
- Look for bg().perform { } or Task { @MainActor } or DispatchQueue.main... to make sure we are in the right context.

## Multi-Agent Compatibility

- `CLAUDE.md` is kept for Claude Code compatibility.
- `AGENTS.md` is the Codex-native equivalent and should be updated alongside `CLAUDE.md` when guidance changes.
