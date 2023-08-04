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
    
    var body: some Scene {
        WindowGroup {
            // Not sure why the preview canvas is loading this on every other view so wrap in condition:
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                AppView()
            }
        }
        .onChange(of: scenePhase) { newScenePhase in
            switch newScenePhase {
            case .active:
                sendNotification(.scenePhaseActive)
                L.og.notice("scenePhase active")
                SocketPool.shared.connectAll()
                lvmManager.restoreSubscriptions()
            case .background:
                sendNotification(.scenePhaseBackground)
                if !IS_CATALYST {
                    SocketPool.shared.disconnectAll()
                    lvmManager.stopSubscriptions()
                }
                saveState()
                
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

