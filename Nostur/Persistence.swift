//
//  Persistence.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
    
        let account = Identity(context: viewContext)
        account.createdAt = Date()
        account.id = UUID()
        account.publicKey = "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"
        account.name = "Testeur"
        account.about = "hi"
        
        let keys = NKeys.newKeys()
        
        let xaccount = Identity(context: viewContext)
        xaccount.createdAt = Date()
        xaccount.id = UUID()
        xaccount.privateKey = "184a90b0cbdf4b4a318d33f6464593d9936430c6793fed82d9b6ec3b8f12804f"
        xaccount.publicKey = "11707ab5c187f4534ea7b4ad67cd9914cd07f7812b5ea2fdd91685ac84c91f5b"
        xaccount.name = "Eltje"
        xaccount.about = "Test"
    
        let relay = Relay(context: viewContext)
        relay.url = "wss://nostr.bitcoin.sex"
        relay.createdAt = Date()
        relay.id = UUID()
        relay.read = true
        relay.write = false
        
        
        let contact = Contact(context: viewContext)
        contact.pubkey = "11707ab5c187f4534ea7b4ad67cd9914cd07f7812b5ea2fdd91685ac84c91f5b"
        xaccount.addToFollows(contact)
//        contact.addToFollowedBy(xaccount)
        
//        let contact = Contact(context: viewContext)
        
//        
//        xaccount.addToFollowing(contact)
    
        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()
    
    let container: NSPersistentCloudKitContainer
    let containerLocal: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "NosturCloud")
        containerLocal = NSPersistentContainer(name:"NosturLocal")
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
            containerLocal.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
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
        
        containerLocal.loadPersistentStores(completionHandler: { (storeDescription, error) in
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
                print("Local Store has been loaded \(String(describing: storeDescription.url))")
            }
        })
    }
}
