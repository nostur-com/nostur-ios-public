//
//  DataProvider.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/01/2023.
//

import CoreData
import OSLog

extension Event {
    func toVPost(plainText:Bool = false) -> VPost? {
        VPostTransformer.shared.toVPost(self, plainText: plainText)
    }
}

extension VPost {
    func toEvent() -> Event {
        self.event
    }
}

class DataProvider: ObservableObject {
    
    private var bgStored:NSManagedObjectContext? // IMPORTING, PREPARING, TRANSFORMING FOR VIEW
//    private var prioStored:NSManagedObjectContext? // FOR POST DETAIL AND "NOW" THINGS
    
    // MARK: Logging
    let logger = Logger(subsystem: "com.nostur.Events", category: "persistence")
    
    // MARK: Core Data
    
    /// A shared data provider for use within the main app bundle.
    static let live = DataProvider()
    
    /// A data provider for use with canvas previews.
    static let preview: DataProvider = {
        let provider = DataProvider(inMemory: true)
        return provider
    }()
    
    private let inMemory: Bool
    private var notificationToken: NSObjectProtocol?
    
    private init(inMemory: Bool = false) {
        self.inMemory = inMemory
    }
    
    var databaseProblem = false
    var databaseProblemDescription:String = ""
    
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
        
        print("🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀 \(description.url?.absoluteString ?? "")")
        
        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        }
        
        description.setOption(FileProtectionType.completeUntilFirstUserAuthentication as NSObject, forKey: NSPersistentStoreFileProtectionKey)
        
        var newError:NSError?
        container.loadPersistentStores { storeDescription, error in
            newError = error as NSError?
        }
        if newError != nil {
            print("Unresolved error \(newError?.description ?? "")")
            self.databaseProblem = true
            self.databaseProblemDescription = newError?.userInfo.description ?? ""
            description.url = URL(fileURLWithPath: "/dev/null")
            container.loadPersistentStores { storeDescription, error in
                if let error = error as NSError? {
                    fatalError("Unresolved error \(error), \(error.userInfo)")
                }
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.undoManager = nil
        
        return container
    }()
    
    lazy var bg: NSManagedObjectContext = {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return container.viewContext
        }
        else {
            if let bgStored {
                return bgStored
            }
            let newBG = container.newBackgroundContext()
            newBG.automaticallyMergesChangesFromParent = true
            newBG.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            newBG.undoManager = nil
            self.bgStored = newBG
            return newBG
        }
    }()
    
//    lazy var prio: NSManagedObjectContext = {
//        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
//            return container.viewContext
//        }
//        else {
//            if let prioStored {
//                return prioStored
//            }
//            let newPrio = container.newBackgroundContext()
//            newPrio.automaticallyMergesChangesFromParent = true
//            newPrio.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
//            newPrio.undoManager = nil
//            self.prioStored = newPrio
//            return newPrio
//        }
//    }()
    
    lazy var viewContext: NSManagedObjectContext = {
        return container.viewContext
    }()
    
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
        
        let fiveDaysAgo = Date.now.addingTimeInterval(-(5 * 86400))
        
        let fr = NSFetchRequest<Event>(entityName: "Event")
        fr.predicate =
        NSPredicate(format: "created_at < %i AND (kind == 0 OR kind == 1 OR kind == 3 OR kind == 7)", Int64(fiveDaysAgo.timeIntervalSince1970))
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
    
    /// Creates and configures a private queue context.
    public func newTaskContext() -> NSManagedObjectContext {
        // Create a private queue context.
        /// - Tag: newBackgroundContext
        let taskContext = container.newBackgroundContext()
        taskContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        // Set unused undoManager to nil for macOS (it is nil by default on iOS)
        // to reduce resource requirements.
        taskContext.undoManager = nil
        return taskContext
    }
    
    func save() { // TODO: replace all viewContext.save() with this save
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return
        }
        #endif
        Task.detached {
            self.container.viewContext.perform {
                if self.container.viewContext.hasChanges {
                    do {
                        try self.container.viewContext.save() // TODO: SHOULD MOVE THIS TO viewContext.perform? or .performAndWait ???
                        print("🟢🟢 viewContext saved")
                    }
                    catch {
                        print("🔴🔴 Could not save viewContext")
                    }
                }
            }
        }
    }
    
    func bgSave() { // TODO: replace all viewContext.save() with this save
        bg.perform {
            if self.bg.hasChanges {
                do {
                    try self.bg.save()
                }
                catch {
                    print("🔴🔴 Could not save bgContext")
                }
            }
        }
    }
    
    static func shared() -> DataProvider {
        // Use an in-memory store for previews
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return DataProvider.preview
        }
        #endif
        return DataProvider.live
    }
}
