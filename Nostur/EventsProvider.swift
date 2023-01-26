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
    var cm:ConnectionManager? = nil
    
    // MARK: Logging
    let logger = Logger(subsystem: "com.nostir.2140.Events", category: "persistence")
    
    // MARK: Core Data
    static let shared = EventsProvider()
    
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
                    
                    try EventsProvider.saveEvent(event: event, context: viewContext)
                    
                }
            } catch let error {
                print("Problem with event: \(error)")
            }
            
        }
        
        var someEvent = PreviewFetcher.fetchEvent("b9b337e5730eb83af2f6ae71b65295db8fe241aec7beb7fd8b6c0b88cc3d05d1", context: viewContext)!
        account.addToBookmarks(someEvent)
        someEvent.addToBookmarkedBy(account)
        
//        do {
//            try viewContext.save()
//        } catch {
//            let nsError = error as NSError
//            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
//        }
        return provider
    }()
    
    private let inMemory: Bool
    private var notificationToken: NSObjectProtocol?
    
    init(inMemory: Bool = false) {
        self.inMemory = inMemory
        
        container = NSPersistentContainer(name: "NosturCloud")
        
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
    
    
    
    let container: NSPersistentContainer
    
    /// Creates and configures a private queue context.
    func newTaskContext() -> NSManagedObjectContext {
        // Create a private queue context.
        /// - Tag: newBackgroundContext
        let taskContext = container.newBackgroundContext()
        taskContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        // Set unused undoManager to nil for macOS (it is nil by default on iOS)
        // to reduce resource requirements.
        taskContext.undoManager = nil
        return taskContext
    }
    
    /// Handle messages received from relay
    /// takes message and adds it to queue
    func didReceiveMessage(text: String) async throws { // didReceive...? --> add to in memory array..?
        do {
            guard let message = try? RelayMessage.parseRelayMessage(text: text) else {
                throw "could not parse message"
            }
            
            switch message.type {
            case .NOTICE:
                print(message.message)
            case .EOSE:
//                print("🟢 Sending close subscription message")
                self.cm!.sendMessage(ClientMessage(type: .CLOSE, message: ClientMessage.close(subscriptionId: message.subscriptionId!)))
            default:
                
                // TODO: CHECK IF NOT ALREADY IN QUEUE (BECAUSE FROM OTHER RELAYS) BEFORE ADDING
                await queue.enqueue(message) // Wrap in _ = Task {}?
                //                EventsProvider.shared.messageQueue.enqueue(message) // Thread 30: signal SIGABRT
                
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
    
    // Parse messages from queue
    func startParsing() {
        Task {
            let before = await queue.count
            do {
                try await parseMessagesFromQueue() // Thread 12: EXC_BAD_ACCESS (code=1, address=0x0)
            }
            catch {
                print("oops::: \(error)")
            }
            let after = await queue.count
        }
        
    }
    
    func parseMessagesFromQueue(amount:Int? = nil) async throws { // import from in memory array

        await queue.incrementCounter()
        let taskContext = newTaskContext()
        // Add name and author to identify source of persistent history changes.
        taskContext.name = "parseContext\(await queue.backgroundTaskCounter)"
        taskContext.transactionAuthor = "parseMessagesFromQueue"
        
        /// - Tag: performAndWait
        _ = taskContext.performAndWait {
            Task(priority:.background) {
                let amountOfMessagesToParse = await queue.count
                
                var messagesToParse:[RelayMessage] = []
                
                for _ in 0..<amountOfMessagesToParse {
                    if amountOfMessagesToParse == 0 { break; }
                    if let message = await queue.dequeue() {
                        messagesToParse.append(message)
                    }
                }
                
                for index in 0..<messagesToParse.count {
                    let message = messagesToParse.reversed()[index] // FIFO
                    
                    do {
                        switch message.type {
                        case .EVENT:
                            let event = message.event!
                            
                            // skip if event is already in DB
                            // TODO: Maybe create LRU cache here??
                             
                            
                            if SavedEventsCache.shared.retrieveObject(at: event.id) == nil {
                                let request = NSFetchRequest<Event>()
                                request.entity = Event.entity()
                                request.predicate = NSPredicate(format: "id == %@", event.id)
                                
                                // remember recent .created_at timestamp from timeline events
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
                                
    //                            guard try container.viewContext.fetch(request).first == nil else {
                                guard try taskContext.fetch(request).first == nil else {
                                    throw "🟠 event.id \(event.id) already in DB. skipped."
                                    
                                }
                                
                                // STORE EVENT
                                print("Trying to store event")
                                try EventsProvider.saveEvent(event: event, context:taskContext) // Thread 12: EXC_BAD_ACCESS (code=1, address=0x0)
                                
                                
                                
                                // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REACTIONS)
                                if event.kind == .custom(7) {
                                    try Event.updateLikeCountCache(event.tags, content:event.content, context: taskContext)
                                }
                                
                                SavedEventsCache.shared.setObject(for: event.id, value: event.createdAt)
                               
                                // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REPLIES, MENTIONS)
                                if event.kind == .textNote {
                                    // NIP-10: Those marked with "mention" denote a quoted or reposted event id.
                                    try Event.updateMentionsCountCache(event.tags, context: taskContext)
                                    
                                    // NIP-10: Those marked with "reply" denote the id of the reply event being responded to.
                                    // NIP-10: Those marked with "root" denote the root id of the reply thread being responded to.
                                    try Event.updateRepliesCountCache(event.tags, context: taskContext)
                                }
                                
                                switch event.kind {
                                    
                                case .setMetadata:
                                    // STORE CONTACT
                                    Contact.handleSetMetadataEvent(event: event, context: taskContext)
                                    
                                    
                                case .custom(3):
                                    // STORE CONTACT LIST
                                    print("should handle kind 3")
                                default:
                                    print("unhandled event \(event.kind)")
                                }
                            }
                            else {
                                print("🤙🤙 Already in LRU cache, skipped :) event.id: \(event.id)")
                            }
                            
                        default:
                            print("unhandled relay message type")
                        }
                    }
                    catch {
                        print(error)
                    }
                }
                do {
                    try taskContext.save() // SHOULD ONLY SAVE HERE! NO WHERE ELSE!!!
                }
                catch {
                    print ("error taskContext.save(): \(error)")
                }
            }
        }
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
            let changeRequest = NSPersistentHistoryChangeRequest.fetchHistory(after: self.lastToken) // Thread 62: EXC_BAD_ACCESS (code=1, address=0x5dc91bc00)
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
                viewContext.mergeChanges(fromContextDidSave: transaction.objectIDNotification()) // Thread 1: signal SIGABRT
                self.lastToken = transaction.token
            }
        }
    }
    
    static func saveEvent(event:NEvent, context:NSManagedObjectContext) throws {
        let savedEvent = Event(context: context)
        savedEvent.id = event.id
        savedEvent.kind = Int64(event.kind.id)
        savedEvent.created_at = Int64(event.createdAt.timestamp)
        savedEvent.content = event.content
        savedEvent.sig = event.signature
        savedEvent.pubkey = event.publicKey
        savedEvent.likes = 0
        
        if (event.kind == .textNote && TagsHelpers(event.tags).replyToRootEtag() != nil) {
            savedEvent.replyToRootId = TagsHelpers(event.tags).replyToRootEtag()!.id
            
            let er = NSFetchRequest<Event>(entityName: "Event")
            er.predicate = NSPredicate(format: "id == %@", savedEvent.replyToRootId!)
            er.sortDescriptors = []
            if let rootReply = try? context.fetch(er).first {
                savedEvent.replyToRoot = rootReply
                // root heeft geen inverse
            }
        }
        if (event.kind == .textNote && TagsHelpers(event.tags).replyToEtag() != nil) {
            savedEvent.replyToId = TagsHelpers(event.tags).replyToEtag()!.id
            
            let er = NSFetchRequest<Event>(entityName: "Event")
            er.predicate = NSPredicate(format: "id == %@", savedEvent.replyToId!)
            er.sortDescriptors = []
            if let reply = try? context.fetch(er).first {
                savedEvent.replyTo = reply
                // TODO: inverse hier erbij of neit?
            }
        }
        
        // if other existing messages were replying to this, fix the relation
        let pointingToEventReq = NSFetchRequest<Event>(entityName: "Event")
        pointingToEventReq.predicate = NSPredicate(format: "kind == 1 AND (replyToId == %@ OR replyToRootId == %@)", savedEvent.id!, savedEvent.id!)
        pointingToEventReq.sortDescriptors = []
        if let pointingToEvents = try? context.fetch(pointingToEventReq) {
            for event in pointingToEvents {
                if (event.replyToId != nil) && (event.replyToId == savedEvent.id!) {
                    event.replyTo = savedEvent
                }
                if (event.replyToRootId != nil) && (event.replyToRootId == savedEvent.id!) {
                    event.replyToRoot = savedEvent
                }
            }
        }
        
        // set relation to Contact
        let cr = NSFetchRequest<Contact>(entityName: "Contact")
        cr.predicate = NSPredicate(format: "pubkey == %@", event.publicKey)
        cr.sortDescriptors = [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)]
        if let contact = try? context.fetch(cr).first {
            savedEvent.contact = contact
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let tagsSerialized = try? encoder.encode(event.tags)
        if (tagsSerialized != nil) {
            savedEvent.tagsSerialized = String(data: tagsSerialized!, encoding: .utf8)
        }
    }
}



