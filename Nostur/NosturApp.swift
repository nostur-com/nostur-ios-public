//
//  NosturApp.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI

@main
struct NosturApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow
    private let dataProvider = DataProvider.shared()
    private let ceb:NRContentElementBuilder = .shared
    private let cp:ConnectionPool = .shared
    private let npn:NewPostNotifier = .shared
    private let ss:SettingsStore = .shared
    private let nvm:NotificationsViewModel = .shared
    private let dm:DirectMessageViewModel = .default
    private let networkMonitor = NetworkMonitor()
    private let ns:NRState = .shared
    private let importer:Importer = .shared
    private let backlog:Backlog = .shared
    
    private let puc:LRUCache2<String, String> = PubkeyUsernameCache.shared
    private let fuc:LRUCache2<String, Date> = FailedURLCache.shared
    private let lpc:LRUCache2<URL, [String: String]> = LinkPreviewCache.shared
    
    @Environment(\.scenePhase) private var phase
    
    var body: some Scene {
        WindowGroup {
            // Not sure why the preview canvas is loading this on every other view so wrap in condition:
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                AppView()
                    .onAppear {
                        #if DEBUG
                      //  openWindow(id: "debug-window")
                        #endif
                    }
                    .environment(\.managedObjectContext, DataProvider.shared().container.viewContext)
                    .environmentObject(cp)
                    .environmentObject(npn)
                    .environmentObject(ss)
                    .environmentObject(nvm)
                    .environmentObject(dm)
                    .environmentObject(networkMonitor)
                    .environmentObject(ns)
                    .environmentObject(dataProvider)
            }
        }
        .onChange(of: phase) { newPhase in
            switch newPhase {
            case .active:
                npn.reload()
            case .background:
                if SettingsStore.shared.receiveLocalNotifications {
                    guard let account = account() else { return }
                    if account.lastSeenPostCreatedAt == 0 {
                        account.lastSeenPostCreatedAt = Int64(Date.now.timeIntervalSince1970)
                    }
                    UserDefaults.standard.setValue(Date.now.timeIntervalSince1970, forKey: "last_dm_local_notification_timestamp")
                    UserDefaults.standard.setValue(Date.now.timeIntervalSince1970, forKey: "last_local_notification_timestamp")
                    scheduleAppRefresh()
                }
            default:
                break
            }
        }
        .backgroundTask(.appRefresh("com.nostur.app-refresh")) {
            if !IS_CATALYST {
                NRState.shared.appIsInBackground = true
            }
            guard ss.receiveLocalNotifications else {
                L.og.debug(".appRefresh() - receiveLocalNotifications: false - skipping")
                return
            }
            L.og.debug(".appRefresh()")
            // Always schedule the next refresh
            scheduleAppRefresh(seconds: 180.0)
            
            // Check for any new notifications (relays), if there are unread mentions it will trigger a (iOS) notification
            await checkForNotifications() // <-- Must await, "The system considers the task completed when the action closure that you provide returns. If the action closure has not returned when the task runs out of time to complete, the system cancels the task. Use withTaskCancellationHandler(operation:onCancel:) to observe whether the task is low on runtime."
             
            
        }
        
//        #if DEBUG
//        WindowGroup("Debug window", id: "debug-window") {
//            DebugWindow()
//                .environmentObject(cp)
//                .frame(minWidth: 640, minHeight: 480)
//        }
//        #endif
    }
}


