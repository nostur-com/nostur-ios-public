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
//struct NosturApp: App, EventDelegate {
struct NosturApp: App {
    
    // FROM LOCAL QUEUE TO DATABASE.
    let loopyRunny = Timer.publish(every: 3, tolerance: 1, on: .main, in: .common).autoconnect()
    
    @StateObject var accountState = AccountState(viewContext:EventsProvider.shared.container.viewContext)
    
    //    @StateObject var accountState = AccountState(viewContext:PersistenceController.shared.container.viewContext)
    @StateObject var cm = ConnectionManager()
    
    
    @State var isViewDisplayed = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext,
                              EventsProvider.shared.container.viewContext)
                .environmentObject(accountState)
                .environmentObject(cm)
                .onAppear {
                    startNosturing()
                    self.isViewDisplayed = true
                }
                .onDisappear {
                    self.isViewDisplayed = false
                }
                .onReceive(loopyRunny) { time in
                    
                    if (!isViewDisplayed) {
                        return
                    }
                    
//                    Task(priority: .background) {
                    Task {
//                        try await Task.sleep(nanoseconds: 3_000_000_000)
                        try await EventsProvider.shared.importEvents()
                    }
                }
                .statusBarHidden(true)
        }
    }
    
    func maintenance() {
        EventsProvider.shared.container.viewContext.perform {
            
            do {
                let decoder = JSONDecoder()
                
                let er = NSFetchRequest<Event>(entityName: "Event")
                er.predicate = NSPredicate(format: "kind == 0")
                er.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
                let metaEvents = try! er.execute()
                
                let cr = NSFetchRequest<Contact>(entityName: "Contact")
                cr.sortDescriptors = [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)]
                let contacts = try! cr.execute()
                
                for contact in contacts {
                    // TODO: `replace with new function (updateContactFromMetaEvent)
                    if let lastEvent = metaEvents.first(where: { $0.pubkey == contact.pubkey }) {
                        guard let metaData = try? decoder.decode(NSetMetadata.self, from: (lastEvent.content?.data(using: .utf8, allowLossyConversion: false)!)!) else {
                            continue
                        }
                        if metaData.banner != nil {
                            contact.banner = metaData.banner!
                            print("🟡🟡 Updated banner \(metaData.banner!) for \(contact.pubkey!)")
                        }
                    }
                }
                try EventsProvider.shared.container.viewContext.save()
            }
            
            catch let error as NSError {
                // TODO: handle the error
                print("😢😢😢 XX \(error)")
            }
        }
    }
    
    func repairDb() {
        EventsProvider.shared.container.viewContext.perform {
            do {
                let r = NSFetchRequest<Contact>()
                r.entity = Contact.entity()
                r.sortDescriptors = [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)]
                
                guard let allContacts = try? r.execute() else {
                    print("😢 XX")
                    return
                }
                
                for contact in allContacts {
                    EventsProvider.shared.container.viewContext.delete(contact)
                }
                
                try EventsProvider.shared.container.viewContext.save()
            } catch let error as NSError {
                // TODO: handle the error
                print("😢😢😢 XX \(error)")
            }
        }
    }
    
    func startNosturing() {
        
        // Daily cleanuo
//        EventsProvider.shared.removeOldEvents()
        
        
        // One time fix
        //        repairDb()
        //        maintenance()
        
        let delegate = EventsProvider.shared
        EventsProvider.shared.cm = cm
        
        // Perform Fetch Request
        EventsProvider.shared.container.viewContext.perform {
            do {
                
                // Fetch RELAYS from CORE DATA
                let fetchRequest: NSFetchRequest<Relay> = Relay.fetchRequest()
                let relays = try fetchRequest.execute()
                
                // CONNECT TO RELAYS
                for relay in relays {
                    let relaySocket = RelaySocket(relay: relay, delegate: delegate)
                    print("🟠 connecting to \(relay.url ?? "?")")
                    relaySocket.connect()
                    cm.relaySockets.append(relaySocket)
                    cm.eventReceivingDelegate = delegate
                }
            } catch {
                print("🔴🔴🔴 Unable to Execute Fetch Request, \(error)")
            }
        }
    }
}

