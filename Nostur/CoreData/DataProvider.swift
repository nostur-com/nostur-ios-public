//
//  DataProvider.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/01/2023.
//

import CoreData

class DataProvider: ObservableObject {
    
    public var bgStored:NSManagedObjectContext? // IMPORTING, PREPARING, TRANSFORMING FOR VIEW
    
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
        else {
            L.og.info("🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀🚀 \(description.url?.absoluteString ?? "")")
            description.setOption(FileProtectionType.completeUntilFirstUserAuthentication as NSObject, forKey: NSPersistentStoreFileProtectionKey)
        }
        
        
        
        var newError:NSError?
        container.loadPersistentStores { storeDescription, error in
            newError = error as NSError?
        }
        if newError != nil {
//            print("Unresolved error \(newError?.description ?? "")")
            self.databaseProblem = true
            self.databaseProblemDescription = newError?.userInfo.description ?? ""
            description.url = URL(fileURLWithPath: "/dev/null")
            container.loadPersistentStores { storeDescription, error in
                if let error = error as NSError? {
                    L.og.error("Unresolved error \(error), \(error.userInfo)")
                }
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.undoManager = nil
        
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
        let newBG = container.newBackgroundContext()
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
        
        let bg = self.bgStored ?? self.bg

        bg.perform { [weak self] in
            guard let self = self else { return }
            if bg.hasChanges {
                do {
                    try bg.save()
                }
                catch {
                    L.og.error("🔴🔴 Could not save bgContext \(error)")
                }
                Task {
                    self.container.viewContext.perform {
                        if self.container.viewContext.hasChanges {
                            do {
                                try self.container.viewContext.save() // TODO: SHOULD MOVE THIS TO viewContext.perform? or .performAndWait ???
                                L.og.info("🟢🟢 viewContext saved")
                            }
                            catch {
                                L.og.error("🔴🔴 Could not save viewContext")
                            }
                        }
                    }
                }
            }
        }
    }
    
    func bgSave() { 
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return
        }
        #endif
        
        let bg = self.bgStored ?? self.bg
        
        bg.perform { [weak self] in
            guard let self = self else { return }
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

func bg() -> NSManagedObjectContext {
    (DataProvider.shared().bgStored ?? DataProvider.shared().bg) // .bg lazy computed, so may have thread contention issues when used alot, try to directly access .bgStored here.
}

func bgSave() {
    DataProvider.shared().bgSave()
}
