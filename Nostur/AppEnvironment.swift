//
//  AppEnvironment.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/03/2025.
//

import SwiftUI

// EnvironmentObjects get lost in SwiftUI when used in .sheets so
// wrap in AppEnvironment { } to always have our EnvironmentObjects
struct AppEnvironment<Content: View>: View {
    
    @EnvironmentObject private var la: LoggedInAccount
    
    // Need here to use for .tint
    @ObservedObject private var themes: Themes = .default
    
    @ViewBuilder
    public let content: Content
        
    var body: some View {
        self.content
            .tint(themes.theme.accent)
            .accentColor(themes.theme.accent)
            .environmentObject(themes)
            .environmentObject(AppState.shared)
            .environmentObject(AccountsState.shared)
            .environmentObject(NewPostNotifier.shared)
            .environmentObject(DirectMessageViewModel.default)
            .environmentObject(NetworkMonitor.shared)
            .environmentObject(SettingsStore.shared)
            .environmentObject(la)
    }
}

struct ThemesEnvironmentKey: EnvironmentKey {
    static let defaultValue: Themes = .default
}

extension EnvironmentValues {
    var themes: Themes {
        get { self[ThemesEnvironmentKey.self] }
        set { self[ThemesEnvironmentKey.self] = newValue }
    }
}

struct AppStateEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppState = .shared
}

extension EnvironmentValues {
    var appState: AppState {
        get { self[AppStateEnvironmentKey.self] }
        set { self[AppStateEnvironmentKey.self] = newValue }
    }
}

struct AccountsStateEnvironmentKey: EnvironmentKey {
    static let defaultValue: AccountsState = .shared
}

extension EnvironmentValues {
    var accountsState: AccountsState {
        get { self[AccountsStateEnvironmentKey.self] }
        set { self[AccountsStateEnvironmentKey.self] = newValue }
    }
}

struct WoTEnvironmentKey: EnvironmentKey {
    static let defaultValue: WebOfTrust = .shared
}

extension EnvironmentValues {
    var wot: WebOfTrust {
        get { self[WoTEnvironmentKey.self] }
        set { self[WoTEnvironmentKey.self] = newValue }
    }
}

struct RemoteSignerEnvironmentKey: EnvironmentKey {
    static let defaultValue: NSecBunkerManager = .shared
}

extension EnvironmentValues {
    var remoteSigner: NSecBunkerManager {
        get { self[RemoteSignerEnvironmentKey.self] }
        set { self[RemoteSignerEnvironmentKey.self] = newValue }
    }
}


