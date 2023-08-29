//
//  NosturApp.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI
import CoreData

@main
struct NosturApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var tm:DetailTabsModel = .shared
    
    // These singletons always exists during the apps lifetime
    private var er:ExchangeRateModel = .shared
    private var dataProvider = DataProvider.shared()
    private var eventRelationsQueue:EventRelationsQueue = .shared
    private var lvmManager:LVMManager = .shared
    private var importer:Importer = .shared
    private var queuedFetcher:QueuedFetcher = .shared
    private var sp:SocketPool = .shared
    private var mp:MessageParser = .shared
    private var zpvq:ZapperPubkeyVerificationQueue = .shared
    private var nip05verifier:NIP05Verifier = .shared
    private var ip:ImageProcessing = .shared
    @StateObject private var theme:Theme = .default
    
    var body: some Scene {
        WindowGroup {
            // Not sure why the preview canvas is loading this on every other view so wrap in condition:
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                AppView()
                    .background(theme.listBackground)
                    .environmentObject(theme)
                    .buttonStyle(NRButtonStyle(theme: theme))
                    .tint(theme.accent)
            }
        }
        .onChange(of: scenePhase) { newScenePhase in
            switch newScenePhase {
            case .active:
                L.og.notice("scenePhase active")
                sendNotification(.scenePhaseActive)
                SocketPool.shared.connectAll()
                lvmManager.restoreSubscriptions()
            case .background:
                L.og.notice("scenePhase background")
                sendNotification(.scenePhaseBackground)
                if !IS_CATALYST {
                    SocketPool.shared.disconnectAll()
                    lvmManager.stopSubscriptions()
                }
                saveState()
            case .inactive:
                L.og.notice("scenePhase inactive")
                if IS_CATALYST {
                    saveState()
                }

            default:
                break
            }
        }
    }
    
    /// Saves state to disk
    func saveState() {
        let ns = NosturState.shared
        if let account = ns.account {
            if ns.lastNotificationReceivedAt != account.lastNotificationReceivedAt {
                account.lastNotificationReceivedAt = ns.lastNotificationReceivedAt
            }
            if ns.lastProfileReceivedAt != account.lastProfileReceivedAt {
                account.lastProfileReceivedAt = ns.lastProfileReceivedAt
            }
        }
        DataProvider.shared().save()
        L.og.notice("State saved")
    }
}

