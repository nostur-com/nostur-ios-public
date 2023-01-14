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
struct NosturApp: App, EventDelegate {
    let persistenceController = PersistenceController.shared
    let connectionManager = ConnectionManager.shared
    let localContainer = PersistenceController.shared.localContainer
    let cloudContainer = PersistenceController.shared.cloudContainer
    
    var body: some Scene {
        WindowGroup {
            ContentView(cloudContainer:persistenceController.cloudContainer, connectionManager: connectionManager)
                .onAppear {
                    print("onAppear 🍿🍿🍿🍿🍿")
                    getCoreDataDBPath()
                    startNosturing()
                }
                .environment(\.managedObjectContext, persistenceController.localContainer.viewContext)
        }
    }
    
    func startNosturing() {
        let c =  persistenceController.cloudContainer
        let fetchRequest: NSFetchRequest<Relay> = Relay.fetchRequest()

            // Perform Fetch Request
        c.viewContext.perform {
            do {
                // Execute Fetch Request
                let relays = try fetchRequest.execute()

                for relay in relays {
                    let relaySocket = RelaySocket(relay: relay, delegate: self)
                    print("🟣🟣 connecting to \(relay.url ?? "?")")
                    relaySocket.connect()
                    connectionManager.relaySockets.append(relaySocket)
                }
            } catch {
                print("Unable to Execute Fetch Request, \(error)")
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
    
    func didReceiveEvent(text: String) {
        print("🟣\(text)")

        do {
            guard let dataFromString = text.data(using: .utf8, allowLossyConversion: false) else {
                throw "huh?"
            }
            
            guard let json = try? JSON(data: dataFromString) else {
                throw "no json?"
            }
            
            if json[0] == "EVENT" {
            
                let decoder = JSONDecoder()
                let event = try! decoder.decode(NEvent.self, from: Data(json[2].rawData()))
            
                print("🟣\(event)")
                
                guard try event.verified() else {
                    throw "🔴🔴 NO VALID SIG 🔴🔴 "
                }
                print("🟢🟢 VALID SIG 🟢🟢")
                
                switch event.kind {
                case .setMetadata:
                    Contact.handleSetMetadataEvent(event: event, cloudContext: cloudContainer.viewContext)
                    
//                case .custom(3):
                    
                default:
                    print("unhandled event")
                }

                let savedEvent = Event(context: persistenceController.localContainer.viewContext)
                savedEvent.id = json[2]["id"].stringValue
                savedEvent.kind = json[2]["kind"].int16Value
                savedEvent.created_at = json[2]["created_at"].int64Value
                savedEvent.content = event.content
                savedEvent.sig = event.signature
                savedEvent.pubkey = event.publicKey
                savedEvent.tagsSerialized = json[2]["tags"].rawString()

                print("Received event: \(json[2]["id"].stringValue)")
                do {
                    try persistenceController.localContainer.viewContext.save()
                }
                catch let error {
                    print("🔴🐥🔴 Error storing event 🔴🐥🔴 \(error)")
                }
            }
        } catch let error {
            print("🔴🔴🔴 Error storing event 🔴🔴🔴 \(error)")
        }
    }
}

