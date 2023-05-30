//
//  NosturApp.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//
import SwiftUI
import CoreData


infix operator ?!: LogicalConjunctionPrecedence

func ?!(lhs: Bool?, rhs: Bool) -> Bool {
    return lhs ?? false && rhs
}

class DIMENSIONS: ObservableObject {
    
    static let shared = DIMENSIONS()
    
    // 428    - 10        - (10 + 50 + 10 ) -         (10) - 10
    // Screen - Box-left  - (10 + PFP+ 10 ) - (text-right) - Box-right
    static public let POST_ROW_HPADDING = 10.0
    static public let POST_ROW_PFP_WIDTH = 50.0
    static public let POST_ROW_PFP_HEIGHT = 50.0
    static public let POST_ROW_PFP_HPADDING = 10.0
    static public let KIND1_TRAILING = 10.0
    static public var ROW_PFP_SPACE:CGFloat { get { Self.POST_ROW_PFP_WIDTH + (2 * Self.POST_ROW_PFP_HPADDING) }}
    
    static public let PREVIEW_HEIGHT = 70.0
    
    @Published var listWidth = UIScreen.main.bounds.width // Should override for IS_IPAD / macOS
    
    // Substracts profile pic space from list width
    func availableNoteRowImageWidth() -> CGFloat {
        // 10 + ( 10+50+10 ) (availableWidth) + 10 + 10
        return (listWidth - (Self.POST_ROW_HPADDING * 2) - (Self.POST_ROW_PFP_WIDTH) - (Self.POST_ROW_PFP_HPADDING * 2) - Self.KIND1_TRAILING)
    }
    
    // No profile pic,  no shadow box padding, only Detail ContentRenderer padding
    func availablePostDetailImageWidth() -> CGFloat {
        return (listWidth - (Self.POST_ROW_HPADDING * 2))
    }
    
    // Substracts profile pic space from list width
    func availablePostDetailRowImageWidth() -> CGFloat {
        //( 10+50+10 ) (availableWidth) + 10
        return (listWidth - (Self.POST_ROW_PFP_WIDTH) - (Self.POST_ROW_PFP_HPADDING * 2) - Self.KIND1_TRAILING)
    }
}

@main
struct NosturApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var tm:DetailTabsModel = .shared
    
    
    
    // These singletons always exists during the apps lifetime, so we can use [unowned self] etc
    // the owner is NosturApp
    private var dataProvider = DataProvider.shared()
    private var eventRelationsQueue:EventRelationsQueue = .shared
    private var lvmManager:LVMManager = .shared
    private var importer:Importer = .shared // Need to initialize here on MAIN, else the first init will be in wrong background context
    private var queuedFetcher:QueuedFetcher = .shared
    private var sp:SocketPool = .shared
    private var mp:MessageParser = .shared
    private var zpvq:ZapperPubkeyVerificationQueue = .shared
    private var nip05verifier:NIP05Verifier = .shared
    
//    private let pe:PreviewEnvironment? = (ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" ? PreviewEnvironment.shared : nil)
    
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
                    L.og.notice("⭐️⭐️🏎️🏎️ \(Date.now) scenePhase active")
                    EventRelationsQueue.shared.removeAll()
                    SocketPool.shared.connectAll()
                    lvmManager.restoreSubscriptions()
                case .background:
                    SocketPool.shared.disconnectAll()
                    saveState()
                    
                default:
                    break
            }
        }
    }
    
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
        print("🏎️🏎️ \(Date.now) State saved")
    }
}

