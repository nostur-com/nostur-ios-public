//
//  Persistence.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import CoreData
import SwiftyJSON

struct PersistenceController {
    static let shared = PersistenceController()
    
    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let cloudContext = result.container.viewContext
//        let localContext = result.localContainer.viewContext
        
        let account = Account(context: cloudContext)
        account.createdAt = Date()
        account.id = UUID()
        account.publicKey = "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"
        account.name = "Testeur"
        account.about = "hi"
        
        let keys = NKeys.newKeys()
        
        let xaccount = Account(context: cloudContext)
        xaccount.createdAt = Date()
        xaccount.id = UUID()
        xaccount.privateKey = "184a90b0cbdf4b4a318d33f6464593d9936430c6793fed82d9b6ec3b8f12804f"
        xaccount.publicKey = "11707ab5c187f4534ea7b4ad67cd9914cd07f7812b5ea2fdd91685ac84c91f5b"
        xaccount.name = "Eltje"
        xaccount.about = "Test"
        
        let relay = Relay(context: cloudContext)
        relay.url = "wss://nostr.bitcoin.sex"
        relay.createdAt = Date()
        relay.id = UUID()
        relay.read = true
        relay.write = false
        
//        let relay2 = Relay(context: cloudContext)
//        relay.url = "wss://relay.damus.io"
//        relay.createdAt = Date()
//        relay.id = UUID()
//        relay.read = true
//        relay.write = false
//        
//        let relay3 = Relay(context: cloudContext)
//        relay.url = "wss://brb.io"
//        relay.createdAt = Date()
//        relay.id = UUID()
//        relay.read = true
//        relay.write = false
        
        
        let contact = Contact(context: cloudContext)
        contact.pubkey = "11707ab5c187f4534ea7b4ad67cd9914cd07f7812b5ea2fdd91685ac84c91f5b"
        contact.about = "test"
        contact.lud16 = ""
        contact.name = "yo"
        contact.nip05 = ""
        contact.updated_at = 0
//        xaccount.addToFollows(contact)
        //        contact.addToFollowedBy(xaccount)
        
        //        let contact = Contact(context: viewContext)
        
        //
        //        xaccount.addToFollowing(contact)
        
        // save some events for testing
        
    
        var events = testKind0Events()
        
        events.append(contentsOf: testKind3Events())
        
//        events.append(contentsOf: testKind1Events())
        
        events.append(contentsOf: testKindMixedOldDunnoEvents())
        
        for text in events {
            
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
                        Contact.handleSetMetadataEvent(event: event, context: cloudContext)
                        //                case .custom(3):
                        
                    default:
                        print("unhandled event")
                    }
                    
                    let savedEvent = Event(context: cloudContext)
                    savedEvent.id = event.id
                    savedEvent.kind = json[2]["kind"].int16Value
                    savedEvent.created_at = json[2]["created_at"].int64Value
                    savedEvent.content = event.content
                    savedEvent.sig = event.signature
                    savedEvent.pubkey = event.publicKey
                    savedEvent.tagsSerialized = json[2]["tags"].rawString()
                    
                    print("Received event: \(json[2]["id"].stringValue)")
                    
                    do {
                        try cloudContext.save()
                    }
                    catch let error {
                        print("🔴🐥🔴 Error storing event 🔴🐥🔴 \(error)")
                    }
                    
                }
            } catch let error {
                print("Problem with event: \(error)")
            }
            
        }
        
        
        do {
//            try localContext.save()
            try cloudContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()
    
    let container: NSPersistentCloudKitContainer
    
    init(inMemory: Bool = false) {
        
        
        container = NSPersistentCloudKitContainer(name: "NosturCloud")
        
        let defaultDirectoryURL = NSPersistentCloudKitContainer.defaultDirectoryURL()
        
        let cloudDescription = NSPersistentStoreDescription(url: defaultDirectoryURL.appendingPathComponent("Nostur-iCloud.sqlite"))
        cloudDescription.configuration = "Default"
        
        let localDescription = NSPersistentStoreDescription(url: defaultDirectoryURL.appendingPathComponent("Nostur-local.sqlite"))
        localDescription.configuration = "Local"
         
        container.viewContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
//        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        container.persistentStoreDescriptions = [cloudDescription, localDescription]
        
        if inMemory {
            for description in container.persistentStoreDescriptions {
                description.url = URL(fileURLWithPath: "/dev/null")
            }
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                print("Unresolved error \(error), \(error.userInfo)")
                //                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
            else {
                print("Store has been loaded \(String(describing: storeDescription.url))")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
        
//        localContainer.loadPersistentStores(completionHandler: { (storeDescription, error) in
//            if let error = error as NSError? {
//                // Replace this implementation with code to handle the error appropriately.
//                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
//
//                /*
//                 Typical reasons for an error here include:
//                 * The parent directory does not exist, cannot be created, or disallows writing.
//                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
//                 * The device is out of space.
//                 * The store could not be migrated to the current model version.
//                 Check the error message to determine what the actual problem was.
//                 */
//                print("Unresolved error \(error), \(error.userInfo)")
//                //                fatalError("Unresolved error \(error), \(error.userInfo)")
//            }
//            else {
//                print("Local Store has been loaded \(String(describing: storeDescription.url))")
//            }
//        })
    
    }
}
