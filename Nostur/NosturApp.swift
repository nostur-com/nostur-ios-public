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
    
    @StateObject var ns = NosturState(viewContext:EventsProvider.shared.container.viewContext)
    @State var isViewDisplayed = false
    
    let loopyRunny = Timer.publish(every: 2, tolerance: 1, on: .main, in: .common).autoconnect()
    let sp:SocketPool = .shared
//    @State var path = NavigationPath()
    
    var body: some Scene {        
        WindowGroup {
//                PaginationTest3()
                NosturRootMenu() // <--- put this one instead of ContentView to bring back sidebar menu
//                ContentView(showMenu: $showMenu)
                .environment(\.managedObjectContext, EventsProvider.shared.container.viewContext)
                .environmentObject(ns)
                .environmentObject(sp)
                .onAppear {
                    startNosturing(); self.isViewDisplayed = true
                }
                .onDisappear { self.isViewDisplayed = false }
                .onReceive(loopyRunny) { time in
                    if (!isViewDisplayed) { return }
                    Task { await Importer.shared.importEvents() }
                }
                .statusBarHidden(true)
        }
    }

    func startNosturing() {
        // Daily cleanup
//        EventsProvider.shared.removeOldEvents()
        
        // One time fix
        //        repairDb()
        //        maintenance()
        
        // Get relays from Core Data, create sockets in SocketPool and connect.
        EventsProvider.shared.container.viewContext.perform {
            do {
                // Fetch RELAYS from CORE DATA
                let fetchRequest: NSFetchRequest<Relay> = Relay.fetchRequest()
                let relays = try fetchRequest.execute()
                let sp = SocketPool.shared
                
                // CONNECT TO RELAYS
                for relay in relays {
                    _ = sp.addSocket(relayId: relay.objectID, url: relay.url!, read:relay.read, write: relay.write
                    )
                }
            } catch {
                print("🔴🔴🔴 Unable to Execute Fetch Request, \(error)")
            }
        }
    }
}

