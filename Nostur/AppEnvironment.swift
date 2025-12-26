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
    @Environment(\.theme) private var theme
    public var la: LoggedInAccount
    
    @ViewBuilder
    public let content: Content
        
    var body: some View {
        self.content
            .environment(\.theme, theme)
            .tint(theme.accent)
            .accentColor(theme.accent)
            .environmentObject(AppState.shared)
            .environmentObject(AccountsState.shared)
            .environmentObject(NewPostNotifier.shared)
            .environmentObject(DMsVM.shared)
            .environmentObject(NetworkMonitor.shared)
            .environmentObject(SettingsStore.shared)
            .environmentObject(la)
    }
}

struct ThemesEnvironmentKey: EnvironmentKey {
    static let defaultValue: Theme = Themes.default.theme
}

extension EnvironmentValues {
    var theme: Theme {
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
    static let defaultValue: RemoteSignerManager = .shared
}

extension EnvironmentValues {
    var remoteSigner: RemoteSignerManager {
        get { self[RemoteSignerEnvironmentKey.self] }
        set { self[RemoteSignerEnvironmentKey.self] = newValue }
    }
}

struct NXViewingContextEnvironmentKey: EnvironmentKey {
    static let defaultValue: Set<NXViewingContextOptions> = []
}

extension EnvironmentValues {
    var nxViewingContext: Set<NXViewingContextOptions> {
        get { self[NXViewingContextEnvironmentKey.self] }
        set { self[NXViewingContextEnvironmentKey.self] = newValue }
    }
}

enum NXViewingContextOptions {
    case selectableText // will use UITextView instead of Text
    
    case detailPane // contains postDetail/postParent/postReply in child views
    
    case postDetail // Actual detail post being viewed
    case postParent // a parent of a detail post
    case postReply // replies of a detail post
    
    case postEmbedded // a post embedded/quoted in another post
    
    case preview // Preview screen when composing a new post
    case screenshot // hide 'Sent to 0 relays' in preview footer, disable animated gifs, Text instead of NRText
    
    case feedPreview // to enable Follow button on every post for follow pack previews
}

struct AvailableWidthEnvironmentKey: EnvironmentKey {
    static let defaultValue: CGFloat = UIScreen.main.bounds.width
}

extension EnvironmentValues {
    var availableWidth: CGFloat {
        get { self[AvailableWidthEnvironmentKey.self] }
        set { self[AvailableWidthEnvironmentKey.self] = newValue }
    }
}

struct AvailableHeightEnvironmentKey: EnvironmentKey {
    static let defaultValue: CGFloat = UIScreen.main.bounds.height
}

extension EnvironmentValues {
    var availableHeight: CGFloat {
        get { self[AvailableHeightEnvironmentKey.self] }
        set { self[AvailableHeightEnvironmentKey.self] = newValue }
    }
}

struct ContainerIDEnvironmentKey: EnvironmentKey {
    static let defaultValue: String = "Default"
}

extension EnvironmentValues {
    var containerID: String {
        get { self[ContainerIDEnvironmentKey.self] }
        set { self[ContainerIDEnvironmentKey.self] = newValue }
    }
}


struct NetworkMonitorEnvironmentKey: EnvironmentKey {
    static let defaultValue: NetworkMonitor = .shared
}

extension EnvironmentValues {
    var networkMonitor: NetworkMonitor {
        get { self[NetworkMonitorEnvironmentKey.self] }
        set { self[NetworkMonitorEnvironmentKey.self] = newValue }
    }
}

struct PinnedPostIdEnvironmentKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var pinnedPostId: String? {
        get { self[PinnedPostIdEnvironmentKey.self] }
        set { self[PinnedPostIdEnvironmentKey.self] = newValue }
    }
}


extension UIApplication {
    var keyWindow: UIWindow? {
        connectedScenes
            .compactMap {
                $0 as? UIWindowScene
            }
            .flatMap {
                $0.windows
            }
            .first {
                $0.isKeyWindow
            }
    }
}

private struct SafeAreaInsetsKey: EnvironmentKey {
    static var defaultValue: EdgeInsets {
        UIApplication.shared.keyWindow?.safeAreaInsets.swiftUiInsets ?? EdgeInsets()
    }
}

extension EnvironmentValues {
    var safeAreaInsets: EdgeInsets {
        get { self[SafeAreaInsetsKey.self] }
        set { self[SafeAreaInsetsKey.self] = newValue }
    }
}

private extension UIEdgeInsets {
    var swiftUiInsets: EdgeInsets {
        EdgeInsets(top: top, leading: left, bottom: bottom, trailing: right)
    }
}
