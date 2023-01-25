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
    
    // Timer to check for stuff to parse every 3 sec..
    let parseRunLoop = Timer.publish(every: 3, tolerance: 1, on: .main, in: .common).autoconnect()
    
    let eventsProvider = EventsProvider.shared
    @StateObject var accountState = AccountState(viewContext:EventsProvider.shared.container.viewContext)
    
    //    @StateObject var accountState = AccountState(viewContext:PersistenceController.shared.container.viewContext)
    @StateObject var cm = ConnectionManager()
    
    
    @State var isViewDisplayed = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext,
                              eventsProvider.container.viewContext)
                .environmentObject(accountState)
                .environmentObject(cm)
                .environmentObject(eventsProvider)
                .onAppear {
                    startNosturing()
                    self.isViewDisplayed = true
                }
                .onDisappear {
                    self.isViewDisplayed = false
                }
                .onReceive(parseRunLoop) { time in
                    
                    if (!isViewDisplayed) {
                        return
                    }
                    
                    eventsProvider.startParsing()
                }
                .statusBarHidden(true)
        }
    }
    
    func maintenance() {
        eventsProvider.container.viewContext.perform {
            
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
                try eventsProvider.container.viewContext.save()
            }
            
            catch let error as NSError {
                // TODO: handle the error
                print("😢😢😢 XX \(error)")
            }
        }
    }
    
    func repairDb() {
        eventsProvider.container.viewContext.perform {
            do {
                let r = NSFetchRequest<Contact>()
                r.entity = Contact.entity()
                r.sortDescriptors = [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)]
                
                guard let allContacts = try? r.execute() else {
                    print("😢 XX")
                    return
                }
                
                for contact in allContacts {
                    eventsProvider.container.viewContext.delete(contact)
                }
                
                try eventsProvider.container.viewContext.save()
            } catch let error as NSError {
                // TODO: handle the error
                print("😢😢😢 XX \(error)")
            }
        }
    }
    
    func startNosturing() {
        // One time fix
        //        repairDb()
        //        maintenance()
        
        let delegate = eventsProvider
        eventsProvider.cm = cm
        
        // Perform Fetch Request
        eventsProvider.container.viewContext.perform {
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

