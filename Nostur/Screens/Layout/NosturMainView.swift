//
//  NosturRootMenu.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/01/2023.
//

import SwiftUI
import NavigationBackport

struct NosturMainView: View {
    @EnvironmentObject private var ss: SettingsStore
    
    var body: some View {
        AppEnvironment {
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
