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
    
    var body: some Scene {
        WindowGroup {
            ContentView(connectionManager: connectionManager)
                .onAppear {
                    print("onAppear 🍿🍿🍿🍿🍿")
                    getCoreDataDBPath()
                    startNosturing()
                }
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
    
    func startNosturing() {
        let c =  persistenceController.container
        let fetchRequest: NSFetchRequest<Relay> = Relay.fetchRequest()

            // Perform Fetch Request
        c.viewContext.perform {
            do {
                // Execute Fetch Request
                let relays = try fetchRequest.execute()

                for relay in relays {
                    let relaySocket = RelaySocket(relay: relay, delegate: self)
                    print("🟣🟣 connecting to \(relay.url)")
                    relaySocket.connect()
                    connectionManager.relaySockets.append(relaySocket)
                }
                
//                connectionManager.sendMessage(text: "Heeee")
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
                    let metaData = try! decoder.decode(NSetMetadata.self, from: event.content.data(using: .utf8, allowLossyConversion: false)!)
                    print (metaData)
//                    let content = JSON(event.content)
//                    if let dataFromString = content.stringValue {
//                        let json = try! JSON(data: dataFromString)
//                        print(json["nip05"].stringValue)
//
//                        identity.name = json["name"].stringValue
//                        identity.bio = json["about"].stringValue
//                        identity.picture = json["picture"].stringValue
//                        identity.nip05identifier = json["nip05"].stringValue
//                        identity.lightningAddress = json["lud16"].stringValue
//
//                        do {
//                            try viewContext.save()
//                        } catch {
//                            // Replace this implementation with code to handle the error appropriately.
//                            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
//                            let nsError = error as NSError
//                            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
//                        }
//                    }
                    
//                case .custom(3):
                    
                default:
                    print("unhandled even")
                }

                let savedEvent = Event(context: persistenceController.containerLocal.viewContext)
                savedEvent.id = event.id
                savedEvent.kind = json[2]["kind"].int16Value
                savedEvent.created_at = json[2]["created_at"].int16Value
                savedEvent.content = event.content
                savedEvent.sig = event.signature
                savedEvent.pubkey = event.publicKey
                savedEvent.tagsSerialized = json[2]["tags"].rawString()

                print("Received event: \(json[2]["id"].stringValue)")
                try persistenceController.containerLocal.viewContext.save()

            }
        } catch let error {
            print("Problem with event: \(error)")
        }

        if let dataFromString = text.data(using: .utf8, allowLossyConversion: false) {
            if let json = try? JSON(data: dataFromString) {
                if json[0] == "EVENT" {
//                    print(json[2]["tags"].map { $0.1[1] })
//                    print("created_at: \(json[2]["created_at"].intValue)")
//                    print(type(of:json[2]["created_at"].intValue))
                    
                    // @TODO SHOULD VERIFY SIG BEFORE STORING EVENT
                    
                    let event = Event(context: persistenceController.containerLocal.viewContext)
                    event.id = json[2]["id"].stringValue
                    event.kind = json[2]["kind"].int16Value
                    event.created_at = json[2]["created_at"].int16Value
                    event.content = json[2]["content"].stringValue
                    event.sig = json[2]["sig"].stringValue
                    event.pubkey = json[2]["pubkey"].stringValue
                    event.tagsSerialized = json[2]["tags"].rawString()
                    
                    print("Received event: \(json[2]["id"].stringValue)")
                    
//                    getCoreDataDBPath()
                    // To save the new entity to the persistent store, call
                    // save on the context
                    do {
                        try persistenceController.containerLocal.viewContext.save()
                    }
                    catch {
                        // Handle Error
                        print("🔴🔴🔴 Error storing event.id \(event.id) 🔴🔴🔴 \(error)")
                        getCoreDataDBPath()
                    }
                    
                }
            }
        }
    }
}

