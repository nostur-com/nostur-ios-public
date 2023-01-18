//
//  ContentView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI
import CoreData

struct ContentView: View, EventDelegate {
    
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var accountState:AccountState
    @AppStorage("activeAccountPublicKey") var activeAccountPublicKey: String = ""
    @State var path = NavigationPath()
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)],
        animation: .none)
    var contacts:FetchedResults<Contact>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
        predicate: NSPredicate(format: "kind == 1"),
        animation: .none)
    var events: FetchedResults<Event>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
        animation: .none)
    var eventsAll: FetchedResults<Event>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
        predicate: NSPredicate(format: "kind == 0"),
        animation: .none)
    var eventsMeta: FetchedResults<Event>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
        predicate: NSPredicate(format: "kind == 3"),
        animation: .none)
    var eventsCL: FetchedResults<Event>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
        predicate: NSPredicate(format: "kind == 7"),
        animation: .none)
    var eventsR: FetchedResults<Event>
    
    
    let connectionManager = ConnectionManager.shared
    
    var body: some View {
        VStack {
            HStack {
                Text("C: \(contacts.count) N:\(events.count) M:\(eventsMeta.count) CL:\(eventsCL.count) R:\(eventsR.count) ALL: \(eventsAll.count)")
            }
            TabView {
            NavigationStack {
                TestTimeline(contacts: contacts, events: events)
                    .navigationDestination(for: Note.self) { note in
                        NoteDetailView(note)
                    }
                    .navigationDestination(for: ContactProfile.self) { contactProfile in
                        ContactProfileView(pubkey: contactProfile.publicKey)
                    }
            }
            .tabItem { Image(systemName: "figure.fall") }
            NavigationStack {
                Playground()
                    .navigationDestination(for: Note.self) { note in
                        NoteDetailView(note)
                    }
                    .navigationDestination(for: ContactProfile.self) { contactProfile in
                        ContactProfileView(pubkey: contactProfile.publicKey)
                    }
                ////                        }
            }
            .tabItem { Image(systemName: "lightbulb.fill") }
            //                NavigationStack {
            ////                    TimelineView(tweets:DummyTweets().tweets())
            //                    Spacer()
            //                }
            .tabItem { Image(systemName: "house.fill") }
            
            //                Text("Notifications")
            //                    .badge(2)
            //                    .tabItem { Image(systemName: "bell.fill") }
            
            NavigationStack {
                AccountListView()
                Spacer()
            }
            .tabItem {
                Image(systemName: "person.badge.key.fill")
            }
            NavigationStack {
                RelaysView()
                Spacer()
            }
            .tabItem { Image(systemName: "server.rack") }
        }
        }
        .onAppear {
            print("🔴 OnAppear")
            startNosturing()
        }
        .onDisappear { print("🔴 OnDisappear") }
    }
    
    func repairDb() {
        viewContext.perform {
            do {
                let r = NSFetchRequest<Contact>()
                r.entity = Contact.entity()
                r.sortDescriptors = [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)]
                
                guard let allContacts = try? r.execute() else {
                    print("😢 XX")
                    return
                }
                
                for contact in allContacts {
                    viewContext.delete(contact)
                }
                
                try viewContext.save()
            } catch let error as NSError {
                // TODO: handle the error
                print("😢😢😢 XX \(error)")
            }
        }
    }
    
    func startNosturing() {
        // One time fix
//        repairDb()

        let delegate = self
        
        // Perform Fetch Request
        viewContext.perform {
            do {
                
                // Fetch RELAYS
                let fetchRequest: NSFetchRequest<Relay> = Relay.fetchRequest()
                let relays = try fetchRequest.execute()
                
                // CONNECT TO RELAYS
                for relay in relays {
                    let relaySocket = RelaySocket(relay: relay, delegate: delegate)
                    print("🟣🟣 connecting to \(relay.url ?? "?")")
                    relaySocket.connect()
                    connectionManager.relaySockets.append(relaySocket)
                    connectionManager.eventReceivingDelegate = delegate
                }
            } catch {
                print("Unable to Execute Fetch Request, \(error)")
            }
        }
    }
    
    func saveEvent(event:NEvent) throws {
        let savedEvent = Event(context: viewContext)
        savedEvent.id = event.id
        savedEvent.kind = Int16(event.kind.id)
        savedEvent.created_at = Int64(event.createdAt.timestamp)
        savedEvent.content = event.content
        savedEvent.sig = event.signature
        savedEvent.pubkey = event.publicKey
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let tagsSerialized = try? encoder.encode(event.tags)
        if (tagsSerialized != nil) {
            savedEvent.tagsSerialized = String(data: tagsSerialized!, encoding: .utf8)
        }
        do {
            try viewContext.save()
        }
        catch let error {
            print("🔴🔴 Error saving event 🔴🔴 \(error)")
        }
        
    }
    
    func saveContact(event:NEvent) throws {
        
        let pubkeys = contacts.map { $0.pubkey }
        
        guard pubkeys.firstIndex(of: event.publicKey) != nil else {
            print ("contact.pubkey already exists, new placeholder contact after event not needed")
            return
        }
        
        let contact = Contact(context: viewContext)
        contact.pubkey = event.publicKey
        contact.updated_at = 0
        do {
            try viewContext.save()
        }
        catch let error {
            print("🔴🔴 Error saving contact (saveContact) 🔴🔴 \(error)")
        }
    }
    
    func didReceiveEvent(text: String) {
        
        do {
            if let message = try? RelayMessage.parseRelayMessage(text: text)  {
                
                switch message.type {
                case .EVENT:
                    let event = message.event!
                    // skip if event is already in DB
                    let request = NSFetchRequest<Event>()
                    request.entity = Event.entity()
                    request.predicate = NSPredicate(format: "id == %@", event.id)
                      
                    guard try viewContext.fetch(request).first == nil else {
                        throw "🟠 event.id \(event.id) already in DB. skipped."
                        
                    }
                    
                    // STORE EVENT
                    print("Trying to store event")
                    try saveEvent(event: event)
                    try saveContact(event: event)
                    
                    switch event.kind {
                        
                    case .setMetadata:
                        // STORE CONTACT
                        Contact.handleSetMetadataEvent(event: event, context: viewContext)
                        
                        
                    case .custom(3):
                        // STORE CONTACT LIST
                        print("should handle kind 3")
                        _ = Task {
                            let pubkeys = await Contact.handleContactListEvent(event: event, context: viewContext)
                            print("do something with pubkeys: \(pubkeys)")
                            
                            // PROBABLY OOPS:
                            // SHOULD NOT TRIGGER NEW .REQ FROM didReceiveEvent. (LOOP, RECURSIVE..)
        //                        ConnectionManager.shared.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: pubkeys)))
                        }

                    default:
                        print("unhandled event")
                    }
                    
                case .EOSE:
                    print("🟢 Sending close subscription message")
                    connectionManager.sendMessage(ClientMessage(type: .CLOSE, message: ClientMessage.close(subscriptionId: message.subscriptionId!)))
                case .NOTICE:
                    print(message.message)
                    
                default:
                    print("unhandled relay message type")
                }
            }
        }
        catch RelayMessage.error.UNKNOWN_MESSAGE_TYPE {
            print("🟠 Unknown message type: \(text)")
        }
        catch RelayMessage.error.FAILED_TO_PARSE {
            print("🟠 Could not parse text received: \(text)")
        }
        catch RelayMessage.error.FAILED_TO_PARSE_EVENT {
            print("🟠 Could not parse EVENT: \(text)")
        }
        catch {
            print(error)
        }
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

struct ContentView_Previews: PreviewProvider {
    
    static var previewUserDefaults: UserDefaults = {
                let d = UserDefaults(suiteName: "preview_user_defaults")!
                
        d.set("5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0", forKey: "activeAccountPublicKey")
                
        return d
            }()
    
    static var previews: some View {
        
        let accountState = AccountState(viewContext: PersistenceController.preview.container.viewContext)
        
        ContentView()
            .defaultAppStorage(previewUserDefaults)
            .environment(\.managedObjectContext,
                          PersistenceController.preview.container.viewContext)
            .environmentObject(accountState)
    }
}
