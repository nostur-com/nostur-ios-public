//
//  DataProvider.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/01/2023.
//

import CoreData

class DataProvider: ObservableObject {
    
    public var bgStored: NSManagedObjectContext? // IMPORTING, PREPARING, TRANSFORMING FOR VIEW
    
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
    
    /// A persistent container to set up the Core Data stack.
    lazy var container: NSPersistentCloudKitContainer = {
        /// - Tag: persistentContainer
        let container = NSPersistentCloudKitContainer(name: "NosturCloud")
        
        let defaultDirectoryURL = NSPersistentContainer.defaultDirectoryURL()
        
        // Create a store description for a local store
        let localStoreLocation = defaultDirectoryURL.appendingPathComponent("Nostur.sqlite")
        let localStoreDescription = NSPersistentStoreDescription(url: localStoreLocation)
        localStoreDescription.configuration = "Local"
            
        // Create a store description for a CloudKit-backed local store
        let cloudStoreLocation = defaultDirectoryURL.appendingPathComponent("NosturCloud.sqlite")
        let cloudStoreDescription = NSPersistentStoreDescription(url: cloudStoreLocation)
        cloudStoreDescription.configuration = "Cloud"
        cloudStoreDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        cloudStoreDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        
        if inMemory {
            localStoreDescription.url = URL(fileURLWithPath: "/dev/null")
            cloudStoreDescription.url = URL(fileURLWithPath: "/dev/null")
        }
        else {
#if DEBUG
            L.og.info("🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀 \(localStoreDescription.url?.absoluteString ?? "") -[LOG]-")
#endif
            localStoreDescription.setOption(FileProtectionType.completeUntilFirstUserAuthentication as NSObject, forKey: NSPersistentStoreFileProtectionKey)
            cloudStoreDescription.setOption(FileProtectionType.completeUntilFirstUserAuthentication as NSObject, forKey: NSPersistentStoreFileProtectionKey)
        }
        
        // Set the container options on the cloud store
        cloudStoreDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.nostur.data")
            
        // Update the container's list of store descriptions
        container.persistentStoreDescriptions = [cloudStoreDescription, localStoreDescription]
            
        // Load both stores
        var newError:NSError?
        container.loadPersistentStores { storeDescription, error in
            newError = error as NSError?
        }
        if newError != nil {
            self.databaseProblem = true
            self.databaseProblemDescription = newError?.userInfo.description ?? ""
            
            localStoreDescription.url = URL(fileURLWithPath: "/dev/null")
            cloudStoreDescription.url = URL(fileURLWithPath: "/dev/null")
            
            container.loadPersistentStores { storeDescription, error in
                if let error = error as NSError? {
                    L.og.error("Unresolved error \(error), \(error.userInfo)")
                }
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.undoManager = nil
        container.viewContext.name = "nostur-viewContext"
        
        return container
    }()
    
    lazy var bg: NSManagedObjectContext = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return container.viewContext
        }
        #endif
        if let bgStored {
            return bgStored
        }
        
        // bg is child of store
        let newBG = container.newBackgroundContext() // 74 MB
        
        // Or: bg is child of viewContext: 100 MB instead of 74 MB
//        let newBG = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
//        newBG.parent = container.viewContext
        
        newBG.automaticallyMergesChangesFromParent = true
        newBG.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        newBG.undoManager = nil
        newBG.name = "nostur-bg-context"
        self.bgStored = newBG
        return newBG
    }()
    
    lazy var viewContext: NSManagedObjectContext = {
        return container.viewContext
    }()
    
    /// Creates and configures a private queue context.
    public func newTaskContext() -> NSManagedObjectContext {
        // Create a private queue context.
        /// - Tag: newBackgroundContext
        let taskContext = container.newBackgroundContext()
        taskContext.automaticallyMergesChangesFromParent = true
        taskContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        // Set unused undoManager to nil for macOS (it is nil by default on iOS)
        // to reduce resource requirements.
        taskContext.undoManager = nil
        return taskContext
    }
    
    func save(_ completion: (() -> Void)? = nil) { // TODO: replace all viewContext.save() with this save
#if DEBUG
        L.og.debug("💾💾 DataProvider.shared().save()")
#endif
        
        let bg = self.bgStored ?? self.bg
     
        
        bg.perform { [weak self] in
            guard let self = self else { return }
#if DEBUG
            L.og.debug("💾💾 BG: Registered objects: \(bg.registeredObjects.count) -[LOG]-")
#endif
            
            if bg.hasChanges {
                try? bg.save()
#if DEBUG
                L.og.debug("💾💾 🟢🟢 bg saved")
#endif
            }
            self.container.viewContext.perform {
#if DEBUG
                L.og.debug("💾💾 VIEWCONTEXT: Registered objects: \(self.container.viewContext.registeredObjects.count)")
#endif
                if self.container.viewContext.hasChanges {
                    try? self.container.viewContext.save()
#if DEBUG
                    L.og.debug("💾💾💾💾 Saved to disk / iCloud 💾💾💾💾")
#endif
                }
                completion?()
            }
        }
    }
    
    func bgSave() {
        let bg = self.bgStored ?? self.bg
        
        if Thread.isMainThread {
            bg.perform {
#if DEBUG
                L.og.debug("💾💾 BG: Registered objects: \(bg.registeredObjects.count)")
#endif
                if bg.hasChanges {
                    do {
                        try bg.save()
                    }
                    catch {
                        L.og.error("🔴🔴 Could not save bgContext \(error)")
                    }
                }
            }
        }
        else {
#if DEBUG
            L.og.debug("💾💾 BG: Registered objects: \(bg.registeredObjects.count) -[LOG]-")
#endif
            if bg.hasChanges {
                do {
                    try bg.save()
                }
                catch {
#if DEBUG
                    L.og.error("🔴🔴 Could not save bgContext \(error)")
#endif
                }
            }
        }
        
        
    }
    
    // 254    468.00 ms    0.9%    254.00 ms                static DataProvider.shared()
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

func viewContext() -> NSManagedObjectContext {
    DataProvider.shared().viewContext
}

func bg() -> NSManagedObjectContext {
    (DataProvider.shared().bgStored ?? DataProvider.shared().bg) // .bg lazy computed, so may have thread contention issues when used a lot, try to directly access .bgStored here.
}

func viewContextSave() { // TODO make this always debounce + throttle latest
    if DataProvider.shared().viewContext.hasChanges {
        do {
            try DataProvider.shared().viewContext.save()
#if DEBUG
            L.og.debug("💾💾💾💾 Saved to disk / iCloud 💾💾💾💾")
#endif
        }
        catch {
#if DEBUG
            L.og.error("🔴🔴 Could not save() context \(error)")
#endif
        }
    }
}

func bgSave() {
    DataProvider.shared().bgSave()
}

func save(context: NSManagedObjectContext = context()) {
    if context.hasChanges {
        do {
            try context.save()
            if Thread.isMainThread {
#if DEBUG
                L.og.debug("💾💾💾💾 Saved to disk / iCloud 💾💾💾💾")
#endif
            }
        }
        catch {
#if DEBUG
            L.og.error("🔴🔴 Could not save() context \(error)")
#endif
        }
    }
}

func context() -> NSManagedObjectContext {
    if Thread.isMainThread {
        return DataProvider.shared().viewContext
    }
    else {
        return (DataProvider.shared().bgStored ?? DataProvider.shared().bg)
    }
}
