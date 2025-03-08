//
//  NosturApp.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI
import NostrEssentials
import NavigationBackport

struct AppScene: Scene {
    private let dataProvider = DataProvider.shared()
    private let ceb: NRContentElementBuilder = .shared
    private let cp: ConnectionPool = .shared
    private let npn: NewPostNotifier = .shared
    private let ss: SettingsStore = .shared
    private let nvm: NotificationsViewModel = .shared
    private let dm: DirectMessageViewModel = .default
    private let networkMonitor: NetworkMonitor = .shared
    private let ns: NRState = .shared
    private let importer: Importer = .shared
    private let backlog: Backlog = .shared
    private let cloudSyncManager: CloudSyncManager = .shared
    
    private let puc: LRUCache2<String, String> = PubkeyUsernameCache.shared
    private let nrcc: LRUCache2<String, NRContact> = NRContactCache.shared
    private let evc: LRUCache2<String, Event> = EventCache.shared
    private let lpc: LinkPreviewCache = .shared
    
    private let regexes = NostrRegexes.default
    
    @Environment(\.scenePhase) private var phase
    
    private let themes: Themes = .default
    
    var body: some Scene {
        WindowGroup {
            // Not sure why the preview canvas is loading this on every other view so wrap in condition:
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                AppView()
                .environmentObject(themes)
                .environment(\.managedObjectContext, DataProvider.shared().container.viewContext)
                .environmentObject(cp)
                .environmentObject(themes)
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
                UIApplication.shared.isIdleTimerDisabled = true // must be in Scene or it doesn't work?
                npn.reload()
            case .background:
                if !IS_CATALYST {
                    scheduleDatabaseCleaningIfNeeded()
                }
                if SettingsStore.shared.receiveLocalNotifications {
                    guard let account = account() else { return }
                    if account.lastSeenPostCreatedAt == 0 {
                        account.lastSeenPostCreatedAt = Int64(Date.now.timeIntervalSince1970)
                    }
                    UserDefaults.standard.setValue(Date.now.timeIntervalSince1970, forKey: "last_dm_local_notification_timestamp")
                    UserDefaults.standard.setValue(Date.now.timeIntervalSince1970, forKey: "last_local_notification_timestamp")
                }
            default:
                break
            }
        }
    }
}

@available(iOS 16, *)
struct RefreshingAppScene: Scene {
    private let dataProvider = DataProvider.shared()
    private let ceb: NRContentElementBuilder = .shared
    private let cp: ConnectionPool = .shared
    private let npn: NewPostNotifier = .shared
    private let ss: SettingsStore = .shared
    private let nvm: NotificationsViewModel = .shared
    private let dm: DirectMessageViewModel = .default
    private let networkMonitor: NetworkMonitor = .shared
    private let ns: NRState = .shared
    private let importer: Importer = .shared
    private let backlog: Backlog = .shared
    private let cloudSyncManager: CloudSyncManager = .shared
    
    private let puc: LRUCache2<String, String> = PubkeyUsernameCache.shared
    private let nrcc: LRUCache2<String, NRContact> = NRContactCache.shared
    private let evc: LRUCache2<String, Event> = EventCache.shared
    private let lpc: LinkPreviewCache = .shared
    
    private let regexes = NostrRegexes.default
    
    @Environment(\.scenePhase) private var phase
    
    private let themes: Themes = .default
    
    var body: some Scene {
        WindowGroup {
            // Not sure why the preview canvas is loading this on every other view so wrap in condition:
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                AppView()
                .environmentObject(themes)
                .environment(\.managedObjectContext, DataProvider.shared().container.viewContext)
                .environmentObject(cp)
                .environmentObject(npn)
                .environmentObject(ss)
                .environmentObject(nvm)
                .environmentObject(dm)
                .environmentObject(networkMonitor)
                .environmentObject(ns)
                .environmentObject(dataProvider)
                .environmentObject(themes)
            }
        }
        .onChange(of: phase) { newPhase in
            switch newPhase {
            case .active:
                UIApplication.shared.isIdleTimerDisabled = true // must be in Scene or it doesn't work?
                npn.reload()
            case .background:
                if !IS_CATALYST {
                    scheduleDatabaseCleaningIfNeeded()
                }
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
    }
}

@main
struct AppLoader {
    static func main() {
        if #available(iOS 16, *) {
            New_iOSApp.main()
        } else {
            Old_iOSApp.main()
        }
    }
}


// Only Text = 37 MB
@available(iOS 16, *)
struct SimpleScene: Scene {
    private let networkMonitor: NetworkMonitor = .shared
    private let importer: Importer = .shared
    private let puc: LRUCache2<String, String> = PubkeyUsernameCache.shared
    private let nrcc: LRUCache2<String, NRContact> = NRContactCache.shared
    private let evc: LRUCache2<String, Event> = EventCache.shared
    private let lpc: LinkPreviewCache = .shared
    // ^ 37,4 MB
    
    private let dataProvider = DataProvider.shared()
    // ^ 37,7 MB
    
    private let backlog: Backlog = .shared
    // ^ 41 MB
    
    private let ns: NRState = .shared
    private let ss: SettingsStore = .shared
    private let ceb: NRContentElementBuilder = .shared
    private let cp: ConnectionPool = .shared
    // ^ 41 MB
    
    private let npn: NewPostNotifier = .shared
    // ^ 41 MB
    
    private let nvm: NotificationsViewModel = .shared
    // ^ 42 MB
    
    private let dm: DirectMessageViewModel = .default
    // ^ 42 MB
    
    private let viewUpdates: ViewUpdates = .shared
    
    private let cloudSyncManager: CloudSyncManager = .shared
    
    private let regexes = NostrRegexes.default
    
    @Environment(\.scenePhase) private var phase
    
    
    var body: some Scene {
        WindowGroup {
            AppView()
//            Text("DD")
//                .environment(\.managedObjectContext, DataProvider.shared().container.viewContext)
                .environmentObject(cp)
                .environmentObject(npn)
                .environmentObject(ss)
                .environmentObject(nvm)
                .environmentObject(dm)
                .environmentObject(networkMonitor)
                .environmentObject(ns)
                .environmentObject(dataProvider)
        }
        .onChange(of: phase) { newPhase in
            switch newPhase {
            case .active:
                UIApplication.shared.isIdleTimerDisabled = true // must be in Scene or it doesn't work?
                npn.reload()
            case .background:
                if !IS_CATALYST {
                    scheduleDatabaseCleaningIfNeeded()
                }
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
    }
}

@available (iOS 16, *)
struct New_iOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
//        SimpleScene()
        RefreshingAppScene()
    }
}

struct Old_iOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        AppScene()
    }
}


