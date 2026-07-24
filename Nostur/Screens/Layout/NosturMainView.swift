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
    @Environment(\.scenePhase) private var scenePhase
#if DEBUG
    @State private var firstNotificationMeasurementStart: Date?
    @State private var previousUnreadNotifications = 0
    @State private var wasInBackground = false
#endif
    
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
        .modifier(MacTextSizeEnvironmentModifier(textSize: ss.macTextSizeOption))
        .withAppSheets(la: la)
        .onAppear {
#if DEBUG
            startFirstNotificationMeasurement()
#endif
        }
        .onChange(of: scenePhase) { newPhase in
#if DEBUG
            if newPhase == .background {
                wasInBackground = true
            }
            else if newPhase == .active, wasInBackground {
                wasInBackground = false
                startFirstNotificationMeasurement()
            }
#endif
        }
        .onReceive(NotificationsViewModel.shared.unreadPublisher) { unread in
#if DEBUG
            if previousUnreadNotifications == 0, unread > 0, let firstNotificationMeasurementStart {
                let elapsed = Date().timeIntervalSince(firstNotificationMeasurementStart)
                let elapsedString = String(format: "%.3f", locale: Locale(identifier: "nl_NL"), elapsed)
                L.og.debug("⏱️⏱️ First new notification after \(elapsedString) sec")
                self.firstNotificationMeasurementStart = nil
            }
            previousUnreadNotifications = unread
#endif
        }
    }
    
#if DEBUG
    private func startFirstNotificationMeasurement() {
        firstNotificationMeasurementStart = Date()
        previousUnreadNotifications = NotificationsViewModel.shared.unread
        L.og.debug("⏱️⏱️ NosturMainView visible, starting measurement.")
    }
#endif
}

/// Applies the Mac in-app text size as SwiftUI Dynamic Type (Catalyst only).
private struct MacTextSizeEnvironmentModifier: ViewModifier {
    let textSize: SettingsStore.MacTextSizeOption
    
    func body(content: Content) -> some View {
        if IS_CATALYST {
            content.dynamicTypeSize(textSize.dynamicTypeSize)
        } else {
            content
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
