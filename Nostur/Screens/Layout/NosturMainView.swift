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
                if #available(iOS 16.0, *) {
                    Zoomable {
                        MacListsView()
                    }
                } else {
                    // Fallback on earlier versions
                    Text("Not yet")
                }
            }
            else {
                WithSidebar {
                    NosturTabsView()
                }
            }
        }
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

#Preview("with Posts") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadFollows()
    }) {
        NosturMainView()
    }
}
