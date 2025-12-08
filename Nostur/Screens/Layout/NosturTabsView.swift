//
//  NosturTabsView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI
import NavigationBackport
@_spi(Advanced) import SwiftUIIntrospect

struct NosturTabsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        Zoomable {
            HStack(spacing: GUTTER) {
                AvailableWidthContainer {
                    // Old tabs for pre-26
                    if !AVAILABLE_26 {
                        MainTabs15()
                    }
                    else if IS_CATALYST, #available(iOS 26, *) { // got 26, but can't handle new tabs (Tahoe)
                        MainTabsDesktop() // so use own custom tabs
                    }
                    else if #available(iOS 26, *) { // remaining 26+ can use new tabs (iPhone, iPad)
                        MainTabs26()
                    }
                }
                .frame(maxWidth: 600)
                if UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular {
                    AvailableWidthContainer {
                        DetailPane()
                            .environment(\.containerID, "DetailPane")
                            .background(theme.listBackground)
                    }
                }
            }
            .contentShape(Rectangle())
            .background(theme.background) // GUTTER
            .withLightningEffect()
            
            .task {
                if SettingsStore.shared.receiveLocalNotifications {
                    requestNotificationPermission()
                }
            }

            .overlay(alignment: .center) {
                OverlayPlayer()
                    .edgesIgnoringSafeArea(.bottom)   
            }
        }
    }

    
}

#Preview {
    PreviewContainer {
        NosturTabsView()
    }
}


