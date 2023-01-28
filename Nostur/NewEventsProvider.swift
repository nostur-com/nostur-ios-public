//
//  NewEventsProvider.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/01/2023.
//

import CoreData
import OSLog
import SwiftyJSON // nodig voor preview, maar preview is rommel. TODO: fixen

class EventsProvider: ObservableObject, EventDelegate {

    var lastTimelineEventTimestamp:NTimestamp? = nil
    var cm:ConnectionManager? = nil
    var queue = Queue<RelayMessage>()
    
    // Received messages from connected websockets and puts the in .queue
    func didReceiveMessage(text: String) async throws { // didReceive...? --> add to in memory array..?
        do {
            guard let message = try? RelayMessage.parseRelayMessage(text: text) else {
                throw "could not parse message"
            }

            switch message.type {
            case .NOTICE:
                print(message.message)
            case .EOSE:
                self.cm!.sendMessage(ClientMessage(type: .CLOSE, message: ClientMessage.close(subscriptionId: message.subscriptionId!)))
            default:
                
                // TODO: CHECK IF NOT ALREADY IN QUEUE (BECAUSE FROM OTHER RELAYS) BEFORE ADDING
                await queue.enqueue(message) // Wrap in _ = Task {}?
                
                // remember recent .created_at timestamp from timeline events
                if message.type == .EVENT && (message.event?.kind == .textNote || message.event?.kind == .custom(7)) {
                    
                    
                    if (message.subscriptionId == nil) {
                        print("WHERE IS SUBSCRIPTION ID BRO")
                        return
                    }
                    
                    // TIMESTAMP TRACKING NOT COULD ENOUGH, BECAUSe NEED TO FETCH OLDER EVENTS SOMETIMES
                    // MAYBE EXCLUDE FROM TRACKING BY SUBSCRIPTION ID.
                    // DISABLE FOR NOW...
                    // ----
                    // don't remember if timestamp is in the future:
                    if message.subscriptionId!.prefix(3) == "TL-" && message.event!.createdAt.timestamp > Int(Date().timeIntervalSince1970) {
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
                                Contact.handleSetMetadataEvent(event: event, context: viewContext)
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
                
                var someEvent = PreviewFetcher.fetchEvent("b9b337e5730eb83af2f6ae71b65295db8fe241aec7beb7fd8b6c0b88cc3d05d1", context: viewContext)!
                account.addToBookmarks(someEvent)
                someEvent.addToBookmarkedBy(account)
        
        
        return provider
    }()

    private let inMemory: Bool
    private var notificationToken: NSObjectProtocol?

    private init(inMemory: Bool = false) {
        self.inMemory = inMemory

//        // Observe Core Data remote change notifications on the queue where the changes were made.
//        notificationToken = NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: nil) { note in
//            self.logger.debug("Received a persistent store remote change notification.")
//            Task {
//                await self.fetchPersistentHistory()
//            }
//        }
    }

    deinit {
//        if let observer = notificationToken {
//            NotificationCenter.default.removeObserver(observer)
//        }
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
//        container.viewContext.automaticallyMergesChangesFromParent = false
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.name = "viewContext"
        /// - Tag: viewContextMergePolicy
//        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.undoManager = nil
//        container.viewContext.shouldDeleteInaccessibleFaults = true
        return container
    }()

//    /// Creates and configures a private queue context.
//    private func newTaskContext() -> NSManagedObjectContext {
//        // Create a private queue context.
//        /// - Tag: newBackgroundContext
//        let taskContext = container.newBackgroundContext()
//        taskContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
//        // Set unused undoManager to nil for macOS (it is nil by default on iOS)
//        // to reduce resource requirements.
//        taskContext.undoManager = nil
//        return taskContext
//    }
    
    func rememberTimestamp(event: NEvent) {
        if event.kind == .textNote || event.kind == .custom(7) {
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
    }
    
    // Takes parsed events and imports them into core data
    public func importEvents() async throws {
//        print("🦋🦋 calling importEvents with \(await queue.count) messages in queue.")
        guard await queue.count != 0 else { return }

//        let taskContext = newTaskContext()
//        // Add name and author to identify source of persistent history changes.
//        taskContext.name = "importContext"
//        taskContext.transactionAuthor = "importEvents"
        
        var importQueue = [RelayMessage]()
        while let message = await self.queue.dequeue() {
            importQueue.append(message)
        }
        
        let taskContext = container.viewContext

        /// - Tag: performAndWait
        do {
            try await container.viewContext.perform {
                
//                print("🦋🦋 \(importQueue.count) messages ready to import")
                for message in importQueue.reversed() {
                    let event = message.event!
                    self.rememberTimestamp(event:event)
                    
                    guard SavedEventsCache.shared.retrieveObject(at: event.id) == nil else {
//                        print("🦋🦋 Already in LRU cache, skipped :) event.id: \(event.id)")
                        continue
                    }
                    
                    guard try Event.fetchEvent(id: event.id, context: taskContext) == nil else {
//                        print("🦋🦋 event.id \(event.id) already in DB. skipped.")
                        continue
                    }
                    
                    _ = Event.saveEvent(event: event, context:taskContext)
                    
                    // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REACTIONS)
                    if event.kind == .custom(7) && 1 == 2 {
                        do { try _ = Event.updateLikeCountCache(event.tags, content:event.content, context: taskContext) } catch {
                            print("🦋🦋🔴🔴🔴 problem updating Like Count Cache .id \(event.id)")
                        }
                    }
                    
                    // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REPLIES, MENTIONS)
                    if event.kind == .textNote && 1 == 2 {
                        // NIP-10: Those marked with "mention" denote a quoted or reposted event id.
                        do { try _ = Event.updateMentionsCountCache(event.tags, context: taskContext) } catch {
                            print("🦋🦋🔴🔴🔴 problem updateMentionsCountCache .id \(event.id)")
                        }

                        // NIP-10: Those marked with "reply" denote the id of the reply event being responded to.
                        // NIP-10: Those marked with "root" denote the root id of the reply thread being responded to.
                        do { try _ = Event.updateRepliesCountCache(event.tags, context: taskContext) } catch {
                            print("🦋🦋🔴🔴🔴 problem updateRepliesCountCache .id \(event.id)")
                        }
                    }
                    
                    if event.kind == .setMetadata {
                        Contact.handleSetMetadataEvent(event: event, context: taskContext)
                    }
                    
                    if event.kind == .custom(3) {
                        print("kind 3 event \(event.id) saved, but no further handling done yet...")
                    }
                    
                    SavedEventsCache.shared.setObject(for: event.id, value: event.createdAt)
                }
                
                print("🦋🦋 taskContext.save() makes app hang for a while!!")
                // can do in background?
                Task(priority: .background) {
                    try taskContext.save()
                }
                        
    //            // Execute the batch insert.
    //            /// - Tag: batchInsertRequest
    //            let batchInsertRequest = self.newBatchInsertRequest(with: events)
    //            if let fetchResult = try? taskContext.execute(batchInsertRequest),
    //               let batchInsertResult = fetchResult as? NSBatchInsertResult,
    //               let success = batchInsertResult.result as? Bool, success {
    //                return
    //            }
    //            self.logger.debug("Failed to execute batch insert request.")
    //            throw EventError.batchInsertError
            }
        }
        catch {
            print("🦋🦋 we failed to import because:")
            print("🦋🦋 \(error)")
        }
        logger.debug("Successfully inserted data.")
    }
    
//    private func newBatchInsertRequest(with events: [Event]) -> NSBatchInsertRequest {
//        let batchInsertRequest = NSBatchInsertRequest(entity: Event.entity(), objects: events)
//        return batchInsertRequest
//    }

    
    // ORIGINAL, CHANGED TO ABOVE
//    private func newBatchInsertRequest(with propertyList: [EventProperties]) -> NSBatchInsertRequest {
//        var index = 0
//        let total = propertyList.count
//
//        // Provide one dictionary at a time when the closure is called.
//        let batchInsertRequest = NSBatchInsertRequest(entity: Event.entity(), dictionaryHandler: { dictionary in
//            guard index < total else { return true }
//            dictionary.addEntries(from: propertyList[index].dictionaryValue)
//            index += 1
//            return false
//        })
//        return batchInsertRequest
//    }

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
//    func deleteEvents(_ events: [Event]) async throws {
//        let objectIDs = events.map { $0.objectID }
//        let taskContext = newTaskContext()
//        // Add name and author to identify source of persistent history changes.
//        taskContext.name = "deleteContext"
//        taskContext.transactionAuthor = "deleteEvents"
//        logger.debug("Start deleting data from the store...")
//
//        try await taskContext.perform {
//            // Execute the batch delete.
//            let batchDeleteRequest = NSBatchDeleteRequest(objectIDs: objectIDs)
//            guard let fetchResult = try? taskContext.execute(batchDeleteRequest),
//                  let batchDeleteResult = fetchResult as? NSBatchDeleteResult,
//                  let success = batchDeleteResult.result as? Bool, success
//            else {
//                self.logger.debug("Failed to execute batch delete request.")
//                throw EventError.batchDeleteError
//            }
//        }
//
//        logger.debug("Successfully deleted data.")
//    }

//    func fetchPersistentHistory() async {
//        do {
//            try await fetchPersistentHistoryTransactionsAndChanges()
//        } catch {
//            logger.debug("\(error.localizedDescription)")
//        }
//    }

//    private func fetchPersistentHistoryTransactionsAndChanges() async throws {
//        let taskContext = newTaskContext()
//        taskContext.name = "persistentHistoryContext"
//        logger.debug("Start fetching persistent history changes from the store...")
//
//        try await taskContext.perform {
//            // Execute the persistent history change since the last transaction.
//            /// - Tag: fetchHistory
//            let changeRequest = NSPersistentHistoryChangeRequest.fetchHistory(after: self.lastToken)
//            let historyResult = try taskContext.execute(changeRequest) as? NSPersistentHistoryResult
//            if let history = historyResult?.result as? [NSPersistentHistoryTransaction],
//               !history.isEmpty {
//                self.mergePersistentHistoryChanges(from: history)
//                return
//            }
//
//            self.logger.debug("No persistent history transactions found.")
//            throw EventError.persistentHistoryChangeError
//        }
//
//        logger.debug("Finished merging history changes.")
//    }

//    private func mergePersistentHistoryChanges(from history: [NSPersistentHistoryTransaction]) {
//        self.logger.debug("Received \(history.count) persistent history transactions.")
//        // Update view context with objectIDs from history change request.
//        /// - Tag: mergeChanges
//        let viewContext = container.viewContext
//        viewContext.perform {
//            for transaction in history {
//                viewContext.mergeChanges(fromContextDidSave: transaction.objectIDNotification())
//                self.lastToken = transaction.token
//            }
//        }
//    }
    
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
