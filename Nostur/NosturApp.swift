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
    
    let up = Unpublisher(viewContext:EventsProvider.shared.container.viewContext)
    let ns = NosturState(container:EventsProvider.shared.container)
    let nav:NavigationModel = .shared
    let sp:SocketPool = .shared
    
    @State var isViewDisplayed = false
    
    let runLoop = Timer.publish(every: 2, tolerance: 1, on: .main, in: .common).autoconnect()

    var body: some Scene {        
        WindowGroup {
            Onboarding()
                .environment(\.managedObjectContext, EventsProvider.shared.container.viewContext)
                .environmentObject(ns)
                .environmentObject(sp)
                .environmentObject(nav)
                .environmentObject(up)
                .onAppear {startNosturing(); self.isViewDisplayed = true }
                .onDisappear { self.isViewDisplayed = false }
                .onReceive(runLoop) { time in
                    if (!isViewDisplayed) { return }
                    Task { await Importer.shared.importEvents() }
                }
//                .statusBarHidden(true)
        }
    }

    func startNosturing() {
        if (ns.account == nil && ns.accounts.count >= 1) {
            ns.setAccount(account: ns.accounts.last)
        }
        
        Maintenance.firstTimeStartup(context: EventsProvider.shared.container.viewContext)
        
        // Daily cleanup.
        //TODO: Is fast or do in background task?
        Maintenance.maintenance(context: EventsProvider.shared.container.viewContext)
        
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

