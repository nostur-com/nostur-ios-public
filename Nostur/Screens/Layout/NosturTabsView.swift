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
        let _ = Self._printChanges()
#endif
        Zoomable {
            HStack(spacing: GUTTER) {
                AvailableWidthContainer {
                    if #available(iOS 26.0, *) {
                        if IS_CATALYST {
                            MainTabsDesktop()
                        }
                        else { // Has tab placement var
                            MainTabs26()
                        }
                    }
                    else {
                        MainTabs15()
                    }
                }
                .frame(maxWidth: 600)
                if UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular {
                    AvailableWidthContainer(id: "DetailPane") {
                        DetailPane()
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


