# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## About Nostur

Nostur is a social media oriented client for the Nostr protocol, built for Mac, iPhone and iPad using SwiftUI. It's a native iOS/macOS application that implements the Nostr decentralized social media protocol.

## Build System and Development

### Development Setup
1. **Requirements**: Xcode 15.x, iOS SDK 16.x
2. **Configuration**: Copy `Config.xcconfig.dist` to `Config.xcconfig` and add required API keys
3. **Project File**: Open `Nostur.xcodeproj` in Xcode
4. **Dependencies**: Swift Package Manager handles all dependencies (see `Package.resolved`)

### Build Commands
```bash
# Build for iOS Simulator
xcodebuild -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 16 Pro (18.5),OS=18.5' build

# Build for device
xcodebuild -scheme Nostur -destination 'platform=iOS,id=<device_id>' build

# Archive for distribution
xcodebuild -scheme Nostur -archivePath Nostur.xcarchive archive
```

### Testing
- **Test Command**: `xcodebuild test -scheme Nostur -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.0'`
- **In Xcode**: Use ⌘+U to run tests or use Test Navigator
- **Test Files**: Located in `NosturTests/` directory
- **Test Plans**: `Nostur.xctestplan` and `NostrEssentials.xctestplan`
- **Note**: Current test suite is minimal - primarily uses SwiftUI previews and manual testing views

## Architecture Overview

### Core Architecture
- **Pattern**: MVVM with SwiftUI and Combine
- **Data Layer**: Core Data with CloudKit sync
- **Networking**: Custom WebSocket implementation for Nostr relays
- **State Management**: Centralized with `AppState`, `AccountsState`, and various ViewModels

### Key Components

#### App Structure
- **Entry Point**: `NosturApp.swift` - Main app with dependency injection
- **Main View**: `AppView.swift` - Root application view
- **State Management**: `AppState.swift` - Global app state and timers
- **Environment**: `AppEnvironment.swift` - Environment configuration

#### Nostr Protocol Implementation
- **Core Protocol**: `Nostur/Nostr/Nostr.swift` - Event handling, signing, verification
- **Message Types**: `NEvent`, `NMessage`, `CommandResult` structures
- **Relay Communication**: `RelayConnection.swift` - WebSocket management
- **Connection Pool**: `ConnectionPool.swift` - Manages multiple relay connections

#### Data Management
- **Core Data**: `Nostur/CoreData/` - All entity definitions and data models
- **CloudKit Sync**: `CloudSyncManager.swift` - Sync with iCloud
- **Caching**: Multiple LRU caches for performance (`LRUCache2`, `EventCache`, etc.)

#### UI Architecture
- **Feed System**: `Nostur/Feeds/` - Column-based feed architecture with `NXColumnView`
- **Post Rendering**: `Nostur/Post/` - Content rendering with `ContentRenderer`
- **Profile System**: `Nostur/Profiles/` - User profile management
- **Navigation**: Custom navigation with `NRNavigationStack`

#### Key Features
- **Live Events**: `Nostur/LiveEvents/` - Real-time chat and streaming
- **Direct Messages**: `Nostur/DMs/` - Private messaging
- **Zaps**: `Nostur/Zaps/` - Lightning network payments
- **Custom Feeds**: `Nostur/CustomFeeds/` - User-defined content feeds
- **Communities**: `Nostur/Communities/` - Group functionality

### Data Flow
1. **Input**: User actions trigger ViewModels
2. **Processing**: ViewModels update via Combine publishers
3. **Storage**: Core Data persistence with CloudKit sync
4. **Relay Communication**: Events published to Nostr relays
5. **UI Updates**: SwiftUI views automatically update via @Published properties

### Dependency Management
- **Swift Package Manager**: All external dependencies managed through SPM
- **Key Dependencies**: 
  - **NostrEssentials** - Core Nostr protocol implementation (linked at `./NostrEssentials/`)
  - **secp256k1** - Cryptographic signing and verification
  - **Nuke** - Image loading and caching
  - **LiveKit** - Real-time audio/video streaming
- **Internal Libraries**: Custom implementations in `Libraries/` directory

## Development Patterns

### Code Organization
- **Feature-Based**: Code organized by feature (Posts, Profiles, DMs, etc.)
- **Shared Components**: Common UI components in `ViewFragments/`
- **Utilities**: Helper functions and extensions in `Utils/`
- **Theming**: Color themes in `Themes.xcassets/`

### SwiftUI Patterns
- **Preview-Based Testing**: Extensive use of SwiftUI previews for development
- **Environment Objects**: Shared state via `@EnvironmentObject`
- **Custom View Modifiers**: Common styling in `NosturStyles.swift`
- **Playground**: Development testing views in `Nostur/Playground/`

### Performance Considerations
- **Lazy Loading**: Feed content loaded on-demand
- **Caching Strategy**: Multiple cache layers for events, contacts, and media
- **Background Processing**: Heavy operations on background queues
- **Memory Management**: Careful retention cycle management with weak references

### Configuration
- **Build Configuration**: `Config.xcconfig` for API keys and build settings
- **Feature Flags**: `NOSTUR_IS_DESKTOP` toggles for non-App Store features
- **Environment Variables**: Debug flags and logging levels

## File Structure Key Points

### Critical Files
- `NosturApp.swift` - App entry point and dependency injection
- `AppState.swift` - Global application state management
- `Nostur/Nostr/Nostr.swift` - Core Nostr protocol implementation
- `Nostur/Post/ContentRenderer.swift` - Main post rendering logic
- `Nostur/Feeds/NXColumnView.swift` - Feed display architecture

### Main Directories
- `Nostur/` - Main application code
- `NosturTests/` - Test files (minimal current implementation)
- `Libraries/` - Custom third-party library implementations
- `Assets.xcassets/` - App icons and images
- `Themes.xcassets/` - Color themes and styling

### Special Considerations
- **Localization**: `Localizable.xcstrings` for multi-language support
- **Share Extension**: `Share selected text with Nostur/` for system integration
- **CloudKit**: `NosturCloud.xcdatamodeld` for data model versioning
- **Debugging**: Extensive logging and debug windows for development

## Common Development Workflows

### Adding New Features
1. Create feature directory under `Nostur/`
2. Implement ViewModels with Combine publishers
3. Create SwiftUI views with preview support
4. Add Core Data entities if needed
5. Update navigation and routing as required

### UI Development
1. Use SwiftUI previews for rapid iteration
2. Follow existing theming patterns
3. Implement accessibility features
4. Test on multiple device sizes
5. Use `Playground/` for component testing

### Nostr Protocol Extensions
1. Update `NEventKind` enum for new event types
2. Add parsing logic in `Nostr.swift`
3. Create specific handling in appropriate feature modules
4. Update relay communication as needed

This architecture supports the complex requirements of a decentralized social media client while maintaining good separation of concerns and testability.