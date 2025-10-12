//
//  NosturRootMenu.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/01/2023.
//

import SwiftUI
import NavigationBackport

struct NosturMainView: View {
    @ObservedObject private var ss: SettingsStore = .shared
    @EnvironmentObject private var la: LoggedInAccount
    
    var body: some View {
        AppEnvironment(la: la) {
            if IS_CATALYST && ss.proMode {
                WithSidebar {
                    MacMainWindow()
                }
            }
            else {
                WithSidebar {
                    NosturTabsView()
                }
            }
        }
        .withAppSheets(la: la)
    }
}

struct FullScreenSizeEnvironmentKey: EnvironmentKey {
    static let defaultValue: CGSize = CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
}

extension EnvironmentValues {
    var fullScreenSize: CGSize {
        get { self[FullScreenSizeEnvironmentKey.self] }
        set { self[FullScreenSizeEnvironmentKey.self] = newValue }
    }
}

#Preview("NosturMainView") {
    PreviewContainer {
        NosturMainView()
    }
}

#Preview("with Posts and Audio Only Bar") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadFollows()
    }) {
        NosturMainView()
        
            .task {
                await AnyPlayerModel
                    .shared
                    .loadVideo(
                        url: "https://data.zap.stream/stream/537a365c-f1ec-44ac-af10-22d14a7319fb.m3u8",
                        availableViewModes: [.audioOnlyBar])
            }
    }
}
