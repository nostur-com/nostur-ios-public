//
//  NosturApp.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI
import NostrEssentials
import NavigationBackport

@main
struct AppLoader {
    static func main() {
        iOSApp.main()
    }
}

struct iOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private let appState = AppState.shared
    private let accountsState = AccountsState.shared
    private let wot = WebOfTrust.shared
    private let nsecBunker = NSecBunkerManager.shared
    private let feedsCoordinator = FeedsCoordinator.shared
    private let screenSpace = ScreenSpace.shared // Needed for "full screen" window size on desktop
    
    private let dataProvider = DataProvider.shared()
    private let ceb: NRContentElementBuilder = .shared
    private let cp: ConnectionPool = .shared
    private let npn: NewPostNotifier = .shared
    private let ss: SettingsStore = .shared
    private let nvm: NotificationsViewModel = .shared
    private let dm: DirectMessageViewModel = .default
    private let networkMonitor: NetworkMonitor = .shared
    private let importer: Importer = .shared
    private let backlog: Backlog = .shared
    private let cloudSyncManager: CloudSyncManager = .shared
    
    private let puc: LRUCache2<String, String> = PubkeyUsernameCache.shared
    private let nrcc: LRUCache2<String, NRContact> = NRContactCache.shared
    private let evc: LRUCache2<String, Event> = EventCache.shared
    private let lpc: LinkPreviewCache = .shared
    
    private let regexes = NostrRegexes.default
    
    var body: some Scene {
        WindowGroup {
            AppView()
                .environmentObject(accountsState)
                .environment(\.managedObjectContext, DataProvider.shared().container.viewContext)
        }
    }
}
