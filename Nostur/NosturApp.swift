//
//  NosturApp.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI
import NostrEssentials
import NavigationBackport
import AVKit

@main
struct AppLoader {
    static func main() {
        if isXcodePreviewCanvas() {
            TestApp.main() // XCODE PREVIEW CANVAS
        }
        else if isTestRun() { // TEST RUN
            TestApp.main()
        }
        else { // NORMAL APP
            iOSApp.main()
        }
    }
    
    private static func isTestRun() -> Bool {
         return NSClassFromString("XCTestCase") != nil
    }
    
    private static func isXcodePreviewCanvas() -> Bool {
#if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return true
        }
#endif
        return false
    }
}

struct iOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private let appState = AppState.shared
    private let accountsState = AccountsState.shared
    private let wot = WebOfTrust.shared
    private let nsecBunker = NSecBunkerManager.shared
    private let feedsCoordinator = FeedsCoordinator.shared
    private let deduplicator = Deduplicator.shared
    private let screenSpace = ScreenSpace.shared // Needed for "full screen" window size on desktop
    private let unpublisher = Unpublisher.shared
    
    private let dataProvider = DataProvider.shared()
    private let ceb: NRContentElementBuilder = .shared
    private let cp: ConnectionPool = .shared
    private let npn: NewPostNotifier = .shared
    private let ss: SettingsStore = .shared
    private let live: LiveEventsModel = .shared
    
    // There is a NotificationsViewModel for every notifications column as @StateObject. (for example multiple accounts in columns)
    // But this .shared is the main one for the currently logged in account
    private let nvm: NotificationsViewModel = .shared
    
    private let dm: DirectMessageViewModel = .default
    private let networkMonitor: NetworkMonitor = .shared
    private let importer: Importer = .shared
    private let backlog: Backlog = .shared
    private let cloudSyncManager: CloudSyncManager = .shared
    private let vmc: ViewModelCache = .shared
    
    private let puc: LRUCache2<String, String> = PubkeyUsernameCache.shared
    private let nrcc: LRUCache2<String, NRContact> = NRContactCache.shared
    private let evc: LRUCache2<String, Event> = EventCache.shared
    private let lpc: LinkPreviewCache = .shared
    
    private let dlm: DownloadManager = .shared
    
    private let regexes = NostrRegexes.default
    
    private let themes: Themes = .default
    
    var body: some Scene {
        WindowGroup {
            AppView()
                .environmentObject(themes)
                .environmentObject(accountsState)
                .environment(\.managedObjectContext, DataProvider.shared().container.viewContext)
                .onAppear {
                    enableAudioPlayback()
                    hideTitleBarOnCatalyst()
#if DEBUG
                    // Log connection counts after a short delay to see startup state
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                        ConnectionPool.shared.logConnectionCounts()
                    }
                    // And again after 30 seconds to see normal operation state
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
                        ConnectionPool.shared.logConnectionCounts()
                    }
#endif
                }
        }
    }
}

func enableAudioPlayback() {
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
    try? AVAudioSession.sharedInstance().setActive(true)
}

func hideTitleBarOnCatalyst() {
#if targetEnvironment(macCatalyst)
    (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.titlebar?.titleVisibility = .hidden
#endif
}

struct TestApp: App {
    var body: some Scene {
        WindowGroup { }
    }
}
