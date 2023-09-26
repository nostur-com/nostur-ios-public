//
//  NosturApp.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI
import CoreData
import Nuke
import AVFoundation

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
    private var avcache:AVAssetCache = .shared
    private var idr:ImageDecoderRegistry = .shared
    @StateObject private var theme:Theme = .default
    @StateObject private var nm:NotificationsViewModel = .shared
    
    var body: some Scene {
        WindowGroup {
            // Not sure why the preview canvas is loading this on every other view so wrap in condition:
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                AppView()
                    .background(theme.listBackground)
                    .environmentObject(theme)
                    .environmentObject(nm)
                    .buttonStyle(NRButtonStyle(theme: theme))
                    .tint(theme.accent)
                    .onAppear {
                        ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
                        configureAudioSession()
                    }
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
    
    func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        } catch {
            L.og.error("Failed to configure audio session: \(error.localizedDescription)")
        }
    }
    
    /// Saves state to disk
    func saveState() {
        DataProvider.shared().save()
        L.og.notice("State saved")
    }
}

