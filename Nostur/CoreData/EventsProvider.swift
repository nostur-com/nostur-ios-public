//
//  NewEventsProvider.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/01/2023.
//

import CoreData
import OSLog
import SwiftyJSON // nodig voor preview, maar preview is rommel. TODO: fixen

class EventsProvider: ObservableObject {
    
    // MARK: Logging
    
    let logger = Logger(subsystem: "com.nostir.2140.Events", category: "persistence")
    
    // MARK: Core Data
    
    /// A shared quakes provider for use within the main app bundle.
    static let shared = EventsProvider()
    
    /// A quakes provider for use with canvas previews.
    static let preview: EventsProvider = {
        let provider = EventsProvider(inMemory: true)
        let viewContext = provider.container.viewContext
        //TODO:Quake.makePreviews(count: 10)
        
        let account = Account(context: viewContext)
        account.createdAt = Date()
        account.id = UUID()
        account.publicKey = "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"
        account.name = "Testeur"
        account.about = "hi"
        
        let keys = NKeys.newKeys()
        
        let xaccount = Account(context: viewContext)
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
        contact.about = "test"
        contact.lud16 = ""
        contact.name = "yo"
        contact.nip05 = ""
        contact.updated_at = 0
        
        var events = [String]()
        events.append(contentsOf: testKind0Events())
        events.append(contentsOf: testKind3Events())
        events.append(contentsOf: testKind1Events())
        events.append(contentsOf: testKindMixedOldDunnoEvents())
        events.append(contentsOf: testRepliesAndReactions())
        events.append(contentsOf: testSnowden())
        
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
                    
                    guard try event.verified() else {
                        throw "🔴🔴 NO VALID SIG 🔴🔴 "
                    }
                    
                    switch event.kind {
                    case .setMetadata:
                        let _ = Contact.handleSetMetadataEvent(event: event, context: viewContext)
                        //                    case .custom(3):
                        
                    default:
                        print("unhandled event")
                    }
                    
                    _ = Event.saveEvent(event: event, context: viewContext)
                    
                }
            } catch let error {
                print("Problem with event: \(error)")
            }
            
        }
        
        var someEvent = PreviewFetcher.fetchEvent(
            "b9b337e5730eb83af2f6ae71b65295db8fe241aec7beb7fd8b6c0b88cc3d05d1", context: viewContext)!
        
        let contact1 = PreviewFetcher.fetchContact(
            "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0", context: viewContext)
        account.addToFollows(contact1!)
        
        let contact2 = PreviewFetcher.fetchContact(
            "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240", context: viewContext)
        account.addToFollows(contact2!)
        contact2!.nip05 = "snowden@citizenfour.com"
        contact2!.nip05verifiedAt = Date.now
        
        let contact3 = PreviewFetcher.fetchContact(
            "df8efff2bfc02d81f93c7ff6ae111541637e0b3a4caff9ad48939a2f2f283be2", context: viewContext)
        
        account.addToBookmarks(someEvent)
        account.addToBlockedContacts(contact3!)
        someEvent.addToBookmarkedBy(account)
        
        
        return provider
    }()
    
    private let inMemory: Bool
    private var notificationToken: NSObjectProtocol?
    
    private init(inMemory: Bool = false) {
        self.inMemory = inMemory
    }
    
    /// A peristent history token used for fetching transactions from the store.
    private var lastToken: NSPersistentHistoryToken?
    
    /// A persistent container to set up the Core Data stack.
    lazy var container: NSPersistentContainer = {
        /// - Tag: persistentContainer
        let container = NSPersistentContainer(name: "NosturCloud")
        
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve a persistent store description.")
        }
        
        let defaultDirectoryURL = NSPersistentContainer.defaultDirectoryURL()
        //        description.url = defaultDirectoryURL.appendingPathComponent("Nostur-iCloud.sqlite")
        description.url = defaultDirectoryURL.appendingPathComponent("Nostur.sqlite") // ("Nostur-iCloud.sqlite")
        description.configuration = "Default"
        
        
        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        }
        
        //        // Enable persistent store remote change notifications
        //        /// - Tag: persistentStoreRemoteChange
        //        description.setOption(true as NSNumber,
        //                              forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        //
        //        // Enable persistent history tracking
        //        /// - Tag: persistentHistoryTracking
        //        description.setOption(true as NSNumber,
        //                              forKey: NSPersistentHistoryTrackingKey)
        
        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.undoManager = nil
        
        return container
    }()
    
    
    
    /// Creates and configures a private queue context.
    private func newTaskContext() -> NSManagedObjectContext {
        // Create a private queue context.
        /// - Tag: newBackgroundContext
        let taskContext = container.newBackgroundContext()
        taskContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        // Set unused undoManager to nil for macOS (it is nil by default on iOS)
        // to reduce resource requirements.
        taskContext.undoManager = nil
        return taskContext
    }
    
    /// Synchronously deletes given records in the Core Data store with the specified object IDs.
    func deleteEvents(identifiedBy objectIDs: [NSManagedObjectID]) {
        let viewContext = container.viewContext
        logger.debug("Start deleting data from the store...")
        
        viewContext.perform {
            objectIDs.forEach { objectID in
                let event = viewContext.object(with: objectID)
                viewContext.delete(event)
            }
        }
        
        logger.debug("Successfully deleted data.")
    }
    
    func removeOldEvents() {
        
        let threeDaysAgo = Date.now.addingTimeInterval(-(3 * 86400))
        
        let fr = NSFetchRequest<Event>(entityName: "Event")
        fr.predicate =
        NSPredicate(format: "created_at < %i AND (kind == 0 OR kind == 1 OR kind == 3 OR kind == 7)", Int64(threeDaysAgo.timeIntervalSince1970))
        //        fr.resultType = .managedObjectIDResultType
        
        do {
            let events = try container.viewContext.fetch(fr)
            
            print("found \(events.count) to delete")
            
            for event in events {
                container.viewContext.delete(event)
            }
            
            try container.viewContext.save()
        }
        catch {
            print(error)
        }
        
    }
}
