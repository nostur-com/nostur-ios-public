//
//  NosturApp.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI
import CoreData
import SwiftyJSON

extension String: Error {}

@main
struct NosturApp: App {
//    let globalThings = GlobalThings.shared
//    let connectionManager = ConnectionManager.shared
//    let localContainer = PersistenceController.shared.localContainer
//    let container = PersistenceController.shared.container
    @StateObject var accountState = AccountState(viewContext:PersistenceController.shared.container.viewContext)
    @StateObject var cm = ConnectionManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext,
                              PersistenceController.shared.container.viewContext)
                .environmentObject(accountState)
                .environmentObject(cm)
                .onAppear {
                    print("onAppear 🍿🍿🍿🍿🍿")
                    getCoreDataDBPath()
                }
        }
    }
    
    func getCoreDataDBPath() {
            let path = FileManager
                .default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .last?
                .absoluteString
                .replacingOccurrences(of: "file://", with: "")
                .removingPercentEncoding

            print("👍👍👍👍 Core Data DB Path :: \(path ?? "Not found")")
        }
}

