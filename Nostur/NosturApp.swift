//
//  NosturApp.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI

@main
struct NosturApp: App {
    @Environment(\.openWindow) private var openWindow
    private let ceb = NRContentElementBuilder.shared
    private var cp:ConnectionPool = .shared
    private let npn:NewPostNotifier = .shared
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
            }
        }
        .onChange(of: phase) { newPhase in
            switch newPhase {
            case .active:
                npn.reload()
            case .background:
                break
//                scheduleAppRefresh()
            default: 
                break
            }
        }
//        .backgroundTask(.appRefresh("nostur-app-refresh")) {
//            let request = URLRequest(url: URL(string: "your_backend")!)
//            guard let data = try? await URLSession.shared.data(for: request).0 else {
//                return
//            }
//            
//            let decoder = JSONDecoder()
////            guard let products = try? decoder.decode([Product].self, from: data) else {
////                return
////            }
//            
////            if !products.isEmpty && !Task.isCancelled {
////                await notifyUser(for: products)
////            }
//        }
        
//        #if DEBUG
//        WindowGroup("Debug window", id: "debug-window") {
//            DebugWindow()
//                .environmentObject(cp)
//                .frame(minWidth: 640, minHeight: 480)
//        }
//        #endif
    }
}

//import BackgroundTasks
//
//func scheduleAppRefresh() {
//    let request = BGAppRefreshTaskRequest(identifier: "nostur-app-refresh")
//    request.earliestBeginDate = .now.addingTimeInterval(60 * 10)
//    try? BGTaskScheduler.shared.submit(request)
//}
