//
//  EventsProvider.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/01/2023.
//

import SwiftUI
import Foundation
import OSLog
import CoreData
import SwiftyJSON

class EventsProvider: ObservableObject, EventDelegate {
    
    var queue = Queue<RelayMessage>()
    
    var lastTimelineEventTimestamp:NTimestamp? = nil
//    let queue = DispatchQueue(label: "RelayMessageQueue")
//    let queue = DispatchQueue(label: "RelayMessageQueue", qos: .default)
    var cm:ConnectionManager? = nil
    //    var messageQueue:[RelayMessage] = []
//    var messageQueue:Queue<RelayMessage> = Queue<RelayMessage>()
    
    // MARK: Logging
    let logger = Logger(subsystem: "com.nostir.2140.Events", category: "persistence")
    
    // MARK: Core Data
    /// A shared quakes provider for use within the main app bundle.
    static let shared = EventsProvider()
    
    /// A quakes provider for use with canvas previews.
    static let preview: EventsProvider = {
        let provider = EventsProvider(inMemory: true)
        let viewContext = provider.container.viewContext
        
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
                        Contact.handleSetMetadataEvent(event: event, context: viewContext)
//                    case .custom(3):
                        
                    default:
                        print("unhandled event")
                    }
                    
                    try EventsProvider.saveEvent(event: event, context: viewContext)
                    
                }
            } catch let error {
                print("Problem with event: \(error)")
            }
            
        }
        
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return provider
    }()
    
    private let inMemory: Bool
    private var notificationToken: NSObjectProtocol?
    
    private init(inMemory: Bool = false) {
        self.inMemory = inMemory
        
        // Observe Core Data remote change notifications on the queue where the changes were made.
        notificationToken = NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: nil) { note in
            self.logger.debug("Received a persistent store remote change notification.")
            Task {
                await self.fetchPersistentHistory()
            }
        }
    }
    
    deinit {
        if let observer = notificationToken {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    /// A peristent history token used for fetching transactions from the store.
    private var lastToken: NSPersistentHistoryToken?
    
    /// A persistent container to set up the Core Data stack.
    lazy var container: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "NosturCloud")

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve a persistent store description.")
        }
        
        
        let defaultDirectoryURL = NSPersistentContainer.defaultDirectoryURL()
    
        
        description.url = defaultDirectoryURL.appendingPathComponent("Nostur-iCloud.sqlite")
        description.configuration = "Default"

        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        }

        // Enable persistent store remote change notifications
        /// - Tag: persistentStoreRemoteChange
        description.setOption(true as NSNumber,
                              forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        // Enable persistent history tracking
        /// - Tag: persistentHistoryTracking
        description.setOption(true as NSNumber,
                              forKey: NSPersistentHistoryTrackingKey)

        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }

        // This sample refreshes UI by consuming store changes via persistent history tracking.
        /// - Tag: viewContextMergeParentChanges
        container.viewContext.automaticallyMergesChangesFromParent = false
        container.viewContext.name = "viewContext"
        /// - Tag: viewContextMergePolicy
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.undoManager = nil
        container.viewContext.shouldDeleteInaccessibleFaults = true
        return container
        
        
        
//        /// - Tag: persistentContainer
//        //        let container = NSPersistentCloudKitContainer(name: "Events")
//        container = NSPersistentCloudKitContainer(name: "NosturCloud")
//        
//        let defaultDirectoryURL = NSPersistentCloudKitContainer.defaultDirectoryURL()
//        
//        let cloudDescription = NSPersistentStoreDescription(url: defaultDirectoryURL.appendingPathComponent("Nostur-iCloud.sqlite"))
//        cloudDescription.configuration = "Default"
//        
////        let localDescription = NSPersistentStoreDescription(url: defaultDirectoryURL.appendingPathComponent("Nostur-local.sqlite"))
////        localDescription.configuration = "Local"
//        
//        
//        
//        container.viewContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
//        //        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
//        
//        container.persistentStoreDescriptions = [cloudDescription]
////        container.persistentStoreDescriptions = [cloudDescription, localDescription]
//        
//        guard let description = container.persistentStoreDescriptions.first else {
//            fatalError("Failed to retrieve a persistent store description.")
//        }
//        
//        if inMemory {
//            for descripton in container.persistentStoreDescriptions {
//                description.url = URL(fileURLWithPath: "/dev/null")
//            }
//        }
//        
//        for descripton in container.persistentStoreDescriptions {
//            // Enable persistent store remote change notifications
//            /// - Tag: persistentStoreRemoteChange
//            description.setOption(true as NSNumber,
//                                  forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
//            
//            // Enable persistent history tracking
//            /// - Tag: persistentHistoryTracking
//            description.setOption(true as NSNumber,
//                                  forKey: NSPersistentHistoryTrackingKey)
//        }
//        
//        
////        guard let description = container.persistentStoreDescriptions.first else {
////            fatalError("Failed to retrieve a persistent store description.")
////        }
//        
//        container.loadPersistentStores { storeDescription, error in
//            if let error = error as NSError? {
//                fatalError("Unresolved error \(error), \(error.userInfo)")
//            }
//        }
//        
//        //        if (!inMemory) {
//        // This sample refreshes UI by consuming store changes via persistent history tracking.
//        /// - Tag: viewContextMergeParentChanges
//        container.viewContext.automaticallyMergesChangesFromParent = false
//        container.viewContext.name = "viewContext"
//        /// - Tag: viewContextMergePolicy
//        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
//        container.viewContext.undoManager = nil
//        container.viewContext.shouldDeleteInaccessibleFaults = true
//        //        }
//        return container
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
    
    /// Fetches the earthquake feed from the remote server, and imports it into Core Data.
    func fetchEventsIsNowDidReceive(text: String) async throws { // didReceive...? --> add to in memory array..?
        do {
            guard let message = try? RelayMessage.parseRelayMessage(text: text) else {
                throw "couild not parse message"
            }
            
            switch message.type {
            case .NOTICE:
                print(message.message)
            case .EOSE:
                print("🟢 Sending close subscription message")
                self.cm!.sendMessage(ClientMessage(type: .CLOSE, message: ClientMessage.close(subscriptionId: message.subscriptionId!)))
            default:
                
                await queue.enqueue(message) // Wrap in _ = Task {}?
//                EventsProvider.shared.messageQueue.enqueue(message) // Thread 30: signal SIGABRT
                
                // remember recent .created_at timestamp from timeline events
                if message.type == .EVENT && message.event?.kind == .textNote {
                    // don't remember if timestamp is in the future
                    if message.event!.createdAt.timestamp > Int(Date().timeIntervalSince1970) {
                        return
                    }
                    
                    // remember timestamp if its the first one
                    if (self.lastTimelineEventTimestamp == nil) {
                        self.lastTimelineEventTimestamp = message.event?.createdAt
                    }
                    else {
                        // only remember if timestamp is newer than already remembered timestamp
                        if ((message.event?.createdAt.timestamp)! > self.lastTimelineEventTimestamp!.timestamp) {
                            self.lastTimelineEventTimestamp = message.event?.createdAt
                        }
                    }
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
    
    func parseMessagesFromQueue(amount:Int? = nil) async throws {
//        let amountOfMessagesToParse = amount ?? EventsProvider.shared.messageQueue.count
        let amountOfMessagesToParse = await queue.count
        
        var messagesToParse:[RelayMessage] = []
        
        for _ in 0..<amountOfMessagesToParse {
            if amountOfMessagesToParse == 0 {
                break;
            }
            messagesToParse.append(await queue.dequeue()!)
        }
        
//        queue.sync() { // Thread 12: EXC_BAD_ACCESS (code=1, address=0x0)
            // Read array here
            
            for index in 0..<messagesToParse.count {
                let message = messagesToParse.reversed()[index]
                
                do {
                    switch message.type {
                    case .EVENT:
                        let event = message.event!
                        // skip if event is already in DB
                        let request = NSFetchRequest<Event>()
                        request.entity = Event.entity()
                        request.predicate = NSPredicate(format: "id == %@", event.id)
                        
                        // remember recent .created_at timestamp from timeline events
                        if event.kind == .textNote {
                            // don't remember if timestamp is in the future
                            if event.createdAt.timestamp > Int(Date().timeIntervalSince1970) {
                                return
                            }
                            
                            // remember timestamp if its the first one
                            if (self.lastTimelineEventTimestamp == nil) {
                                self.lastTimelineEventTimestamp = event.createdAt
                            }
                            else {
                                // only remember if timestamp is newer than already remembered timestamp
                                if (event.createdAt.timestamp > self.lastTimelineEventTimestamp!.timestamp) {
                                    self.lastTimelineEventTimestamp = event.createdAt
                                }
                            }
                        }
                        
                        guard try container.viewContext.fetch(request).first == nil else {
                            throw "🟠 event.id \(event.id) already in DB. skipped."
                            
                        }
                        
                        // STORE EVENT
                        print("Trying to store event")
                        try EventsProvider.saveEvent(event: event, context:container.viewContext) // Thread 12: EXC_BAD_ACCESS (code=1, address=0x0)
                        
                        // STORE CONTACT
                        
                        do {
                            // skip if contact is already in DB
                            let crequest = NSFetchRequest<Contact>()
                            crequest.entity = Contact.entity()
                            crequest.predicate = NSPredicate(format: "pubkey == %@", event.publicKey)
                            
                            guard try container.viewContext.fetch(crequest).first == nil else {
                                throw "🟠 Contact.pubkey \(event.publicKey) already in DB. skipped."
                            }
                            
                            try EventsProvider.saveContact(event: event, context: container.viewContext)
                        }
                        catch {
                            print(error)
                            
                        }
                        
                        
                        
                        
                        
                        switch event.kind {
                            
                        case .setMetadata:
                            // STORE CONTACT
                            Contact.handleSetMetadataEvent(event: event, context: container.viewContext)
                            
                            
                        case .custom(3):
                            // STORE CONTACT LIST
                            print("should handle kind 3")
                            _ = Task(priority: .background) {
                                //                            let (pubkeys, _) = await Contact.handleContactListEvent(event: event, context: container.viewContext)
                                //                            print("do something with pubkeys: \(pubkeys)")
                                
                                //                            if accountState.activeAccountPublicKey == event.publicKey {
                                //                                // add contacts to followed contacts
                                //
                                //                                let cr = Contact.fetchRequest()
                                //                                cr.predicate = NSPredicate(format: "ANY pubkey IN %@", eventPubkeys)
                                //                                let contacts = try! cr.execute()
                                //                                print("😡😡😡😡 contacts.count: \(contacts.count)")
                                //                                accountState.activeAccount()?.addToFollows(NSSet(objects: contacts
                                //                                                                                ))
                                //                            }
                                // PROBABLY OOPS:
                                // SHOULD NOT TRIGGER NEW .REQ FROM didReceiveEvent. (LOOP, RECURSIVE..)
                                //                        ConnectionManager.shared.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: pubkeys)))
                            }
                            
                        default:
                            print("unhandled event")
                        }
                        
                        
                    default:
                        print("unhandled relay message type")
                    }
                }
                catch {
                    print(error)
                }
                
            }
        
            print("🐥🐥🐥🐥 Events in queue? \(await queue.count) 🐥🐥🐥🐥")
//        }
        
        
    }
    
    /// Uses `NSBatchInsertRequest` (BIR) to import a JSON dictionary into the Core Data store on a private queue.
    private func importQuakes(from propertiesList: [EventProperties]) async throws { // import from in memory array
        //        guard !propertiesList.isEmpty else { return }
        //
        //        let taskContext = newTaskContext()
        //        // Add name and author to identify source of persistent history changes.
        //        taskContext.name = "importContext"
        //        taskContext.transactionAuthor = "importQuakes"
        //
        //        /// - Tag: performAndWait
        //        try await taskContext.perform {
        //            // Execute the batch insert.
        //            /// - Tag: batchInsertRequest
        //            let batchInsertRequest = self.newBatchInsertRequest(with: propertiesList)
        //            if let fetchResult = try? taskContext.execute(batchInsertRequest),
        //               let batchInsertResult = fetchResult as? NSBatchInsertResult,
        //               let success = batchInsertResult.result as? Bool, success {
        //                return
        //            }
        //            self.logger.debug("Failed to execute batch insert request.")
        //            throw EventError.batchInsertError
        //        }
        //
        //        logger.debug("Successfully inserted data.")
    }
    
    private func newBatchInsertRequest(with propertyList: [EventProperties]) -> NSBatchInsertRequest {
        var index = 0
        let total = propertyList.count
        
        // Provide one dictionary at a time when the closure is called.
        let batchInsertRequest = NSBatchInsertRequest(entity: Event.entity(), dictionaryHandler: { dictionary in
            guard index < total else { return true }
            dictionary.addEntries(from: propertyList[index].dictionaryValue)
            index += 1
            return false
        })
        return batchInsertRequest
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
    
    /// Asynchronously deletes records in the Core Data store with the specified `Quake` managed objects.
    func deleteEvents(_ events: [Event]) async throws {
        let objectIDs = events.map { $0.objectID }
        let taskContext = newTaskContext()
        // Add name and author to identify source of persistent history changes.
        taskContext.name = "deleteContext"
        taskContext.transactionAuthor = "deleteEvents"
        logger.debug("Start deleting data from the store...")
        
        try await taskContext.perform {
            // Execute the batch delete.
            let batchDeleteRequest = NSBatchDeleteRequest(objectIDs: objectIDs)
            guard let fetchResult = try? taskContext.execute(batchDeleteRequest),
                  let batchDeleteResult = fetchResult as? NSBatchDeleteResult,
                  let success = batchDeleteResult.result as? Bool, success
            else {
                self.logger.debug("Failed to execute batch delete request.")
                throw EventError.batchDeleteError
            }
        }
        
        logger.debug("Successfully deleted data.")
    }
    
    func fetchPersistentHistory() async {
        do {
            try await fetchPersistentHistoryTransactionsAndChanges()
        } catch {
            logger.debug("\(error.localizedDescription)")
        }
    }
    
    private func fetchPersistentHistoryTransactionsAndChanges() async throws {
        let taskContext = newTaskContext()
        taskContext.name = "persistentHistoryContext"
        logger.debug("Start fetching persistent history changes from the store...")
        
        try await taskContext.perform {
            // Execute the persistent history change since the last transaction.
            /// - Tag: fetchHistory
            let changeRequest = NSPersistentHistoryChangeRequest.fetchHistory(after: self.lastToken)
            let historyResult = try taskContext.execute(changeRequest) as? NSPersistentHistoryResult
            if let history = historyResult?.result as? [NSPersistentHistoryTransaction],
               !history.isEmpty {
                self.mergePersistentHistoryChanges(from: history)
                return
            }
            
            self.logger.debug("No persistent history transactions found.")
            throw EventError.persistentHistoryChangeError
        }
        
        logger.debug("Finished merging history changes.")
    }
    
    private func mergePersistentHistoryChanges(from history: [NSPersistentHistoryTransaction]) {
        self.logger.debug("Received \(history.count) persistent history transactions.")
        // Update view context with objectIDs from history change request.
        /// - Tag: mergeChanges
        let viewContext = container.viewContext
        viewContext.perform {
            for transaction in history {
                viewContext.mergeChanges(fromContextDidSave: transaction.objectIDNotification())
                self.lastToken = transaction.token
            }
        }
    }
    
    static func saveEvent(event:NEvent, context:NSManagedObjectContext) throws {
        let savedEvent = Event(context: context)
        savedEvent.id = event.id
        savedEvent.kind = Int16(event.kind.id)
        savedEvent.created_at = Int64(event.createdAt.timestamp)
        savedEvent.content = event.content
        savedEvent.sig = event.signature
        savedEvent.pubkey = event.publicKey
        if (event.kind == .textNote && event.replyToRootEtag() != nil) {
            savedEvent.replyToRootId = event.replyToRootEtag()!.id
        }
        if (event.kind == .textNote && event.replyToEtag() != nil) {
            savedEvent.replyToId = event.replyToEtag()!.id
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let tagsSerialized = try? encoder.encode(event.tags)
        if (tagsSerialized != nil) {
            savedEvent.tagsSerialized = String(data: tagsSerialized!, encoding: .utf8)
        }
        do {
            try context.save() // Thread 12: EXC_BAD_ACCESS (code=1, address=0x0)
        }
        catch let error {
            print("🔴🔴 Error saving event 🔴🔴 \(error)")
        }
        
    }
    
    static func saveContact(event:NEvent, context:NSManagedObjectContext) throws {
        let contact = Contact(context: context)
        contact.pubkey = event.publicKey
        contact.updated_at = 0
        do {
            try context.save()
        }
        catch let error {
            print("🔴🔴 Error saving contact (saveContact) 🔴🔴 \(error)")
        }
    }
}



