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
    
    // Timer to check for stuff to parse every 5 sec..
    let parseRunLoop = Timer.publish(every: 5, tolerance: 1, on: .main, in: .common).autoconnect()
    
    //    let connectionManager = ConnectionManager.shared
    //    let localContainer = PersistenceController.shared.localContainer
    //    let container = PersistenceController.shared.container
    //    @StateObject var accountState = AccountState(viewContext:PersistenceController.shared.container.viewContext)
    
    //    let container = EventsProvider.shared.container
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
            //                .environment(\.managedObjectContext,
            //                              PersistenceController.shared.container.viewContext)
                .environmentObject(accountState)
                .environmentObject(cm)
            //                .onAppear {
            //                    getCoreDataDBPath()
            //                }
                .environmentObject(eventsProvider)
                .onAppear {
                    //            print("🔴 OnAppear")
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
                    
                    _ = Task {
                        try! await eventsProvider.parseMessagesFromQueue() // Thread 12: EXC_BAD_ACCESS (code=1, address=0x0)
                        print("queue count: \(eventsProvider.messageQueue.count)")
                    }
                    print("🧚🧚🧚 GONNA PARSE YEA 🧚🧚🧚")
                }
                .statusBarHidden(true)
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
    
    //    func didReceiveEvent(text: String) {
    //
    //        do {
    //            PersistenceController.shared.container.performBackgroundTask { context in
    //                if let message = try? RelayMessage.parseRelayMessage(text: text)  {
    //
    //                    switch message.type {
    //                    case .EVENT:
    //                        let event = message.event!
    //                        // skip if event is already in DB
    //                        let request = NSFetchRequest<Event>()
    //                        request.entity = Event.entity()
    //                        request.predicate = NSPredicate(format: "id == %@", event.id)
    //
    //                        guard try context.fetch(request).first == nil else {
    //                            throw "🟠 event.id \(event.id) already in DB. skipped."
    //
    //                        }
    //
    //                        // STORE EVENT
    //                        print("Trying to store event")
    //                        try saveEvent(event: event)
    //                        try saveContact(event: event)
    //
    //                        switch event.kind {
    //
    //                        case .setMetadata:
    //                            // STORE CONTACT
    //                            Contact.handleSetMetadataEvent(event: event, context: context)
    //
    //
    //                        case .custom(3):
    //                            // STORE CONTACT LIST
    //                            print("should handle kind 3")
    //                            _ = Task(priority: .background) {
    //                                let (pubkeys, _) = await Contact.handleContactListEvent(event: event, context: context)
    //                                print("do something with pubkeys: \(pubkeys)")
    //
    //    //                            if accountState.activeAccountPublicKey == event.publicKey {
    //    //                                // add contacts to followed contacts
    //    //
    //    //                                let cr = Contact.fetchRequest()
    //    //                                cr.predicate = NSPredicate(format: "ANY pubkey IN %@", eventPubkeys)
    //    //                                let contacts = try! cr.execute()
    //    //                                print("😡😡😡😡 contacts.count: \(contacts.count)")
    //    //                                accountState.activeAccount()?.addToFollows(NSSet(objects: contacts
    //    //                                                                                ))
    //    //                            }
    //                                // PROBABLY OOPS:
    //                                // SHOULD NOT TRIGGER NEW .REQ FROM didReceiveEvent. (LOOP, RECURSIVE..)
    //            //                        ConnectionManager.shared.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: pubkeys)))
    //                            }
    //
    //                        default:
    //                            print("unhandled event")
    //                        }
    //
    //                    case .EOSE:
    //                        print("🟢 Sending close subscription message")
    //                        cm.sendMessage(ClientMessage(type: .CLOSE, message: ClientMessage.close(subscriptionId: message.subscriptionId!)))
    //                    case .NOTICE:
    //                        print(message.message)
    //
    //                    default:
    //                        print("unhandled relay message type")
    //                    }
    //                }
    //            }
    //
    //
    //
    //        }
    //        catch RelayMessage.error.UNKNOWN_MESSAGE_TYPE {
    //            print("🟠 Unknown message type: \(text)")
    //        }
    //        catch RelayMessage.error.FAILED_TO_PARSE {
    //            print("🟠 Could not parse text received: \(text)")
    //        }
    //        catch RelayMessage.error.FAILED_TO_PARSE_EVENT {
    //            print("🟠 Could not parse EVENT: \(text)")
    //        }
    //        catch {
    //            print(error)
    //        }
    //    }
    
    //    func saveEvent(event:NEvent) throws {
    //        let savedEvent = Event(context: eventsProvider.container.viewContext)
    //        savedEvent.id = event.id
    //        savedEvent.kind = Int16(event.kind.id)
    //        savedEvent.created_at = Int64(event.createdAt.timestamp)
    //        savedEvent.content = event.content
    //        savedEvent.sig = event.signature
    //        savedEvent.pubkey = event.publicKey
    //
    //        let encoder = JSONEncoder()
    //        encoder.outputFormatting = .withoutEscapingSlashes
    //        let tagsSerialized = try? encoder.encode(event.tags)
    //        if (tagsSerialized != nil) {
    //            savedEvent.tagsSerialized = String(data: tagsSerialized!, encoding: .utf8)
    //        }
    //        do {
    //            try eventsProvider.container.viewContext.save()
    //        }
    //        catch let error {
    //            print("🔴🔴 Error saving event 🔴🔴 \(error)")
    //        }
    //
    //    }
    
    //    func saveContact(event:NEvent) throws {
    //
    //        let pubkeys = contacts.map { $0.pubkey }
    //
    //        guard pubkeys.firstIndex(of: event.publicKey) != nil else {
    //            print ("contact.pubkey already exists, new placeholder contact after event not needed")
    //            return
    //        }
    //
    //        let contact = Contact(context: container.viewContext)
    //        contact.pubkey = event.publicKey
    //        contact.updated_at = 0
    //        do {
    //            try container.viewContext.save()
    //        }
    //        catch let error {
    //            print("🔴🔴 Error saving contact (saveContact) 🔴🔴 \(error)")
    //        }
    //    }
    
}

