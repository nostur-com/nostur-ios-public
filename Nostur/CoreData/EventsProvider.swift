//
//  NewEventsProvider.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/01/2023.
//

import CoreData
import OSLog

class EventsProvider: ObservableObject {
    
    // MARK: Logging
    
    let logger = Logger(subsystem: "com.nostir.2140.Events", category: "persistence")
    
    // MARK: Core Data
    
    /// A shared quakes provider for use within the main app bundle.
    static let shared = EventsProvider()
    
    /// A quakes provider for use with canvas previews.
    static let preview: EventsProvider = {
        let provider = EventsProvider(inMemory: true)
        let context = provider.container.viewContext
        
        let account = Account(context: context)
        account.createdAt = Date()
        account.id = UUID()
        account.publicKey = "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"
        account.display_name = "bitcoiner_since_2013 ⚡️"
        account.name = "bitcoinerrrrr"
        account.about = "test account"
        
        let account3 = Account(context: context)
        account3.createdAt = Date()
        account3.id = UUID()
        account3.publicKey = "9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e"
        account3.display_name = "Fabian"
        account3.name = "Fabian"
        account3.about = "Author of Nostur.com"
                
        let keys = NKeys.newKeys()
        
        let xaccount = Account(context: context)
        xaccount.createdAt = Date()
        xaccount.id = UUID()
        xaccount.publicKey = "11707ab5c187f4534ea7b4ad67cd9914cd07f7812b5ea2fdd91685ac84c91f5b"
//        xaccount.privateKey = "184a90b0cbdf4b4a318d33f6464593d9936430c6793fed82d9b6ec3b8f12804f"
        xaccount.display_name = "The Ellen"
        xaccount.name = "eltje"
        xaccount.about = "Test"
        
        let relay = Relay(context: context)
        relay.url = "wss://nostr.bitcoin.sex"
        relay.createdAt = Date()
        relay.id = UUID()
        relay.read = true
        relay.write = false
        
        let contact = Contact(context: context)
        contact.pubkey = "11707ab5c187f4534ea7b4ad67cd9914cd07f7812b5ea2fdd91685ac84c91f5b"
        contact.about = "test"
        contact.lud16 = ""
        contact.lud06 = ""
        contact.name = "yo"
        contact.nip05 = ""
        contact.updated_at = 0
        
        var messages:[String] = []
        messages.append(contentsOf: testKind0Events())
        messages.append(contentsOf: testKind3Events())
        messages.append(contentsOf: testKind1Events())
        messages.append(contentsOf: testKindMixedOldDunnoEvents())
        messages.append(contentsOf: testRepliesAndReactions())
        messages.append(contentsOf: testSnowden())
        messages.append(contentsOf: testBadges())
//        messages.append(contentsOf: testMentions())
//        messages.append(contentsOf: testKind6Events())
//        messages.append(contentsOf: testEfilter())
        messages.append(contentsOf: testZaps())
//        messages.append(contentsOf: testSomeFakeAndRealZaps())
        messages.append(contentsOf: testNotifications())
        messages.append(contentsOf: testImages())
//        messages.append(contentsOf: testThread())
        
        var relayMessages:[RelayMessage] = []
        
        for text in messages {
            guard let message = try? RelayMessage.parseRelayMessage(text: text, skipValidation: true) else { continue }
            // just take all:
            relayMessages.append(message)
            // end of just take all.
//            if (message.event?.kind == .badgeDefinition || message.event?.kind == .zapNote || message.event?.kind == .textNote || message.event?.kind == .reaction || message.event?.kind == .setMetadata) {
//
//                if (message.subscriptionId == nil) {
//                    print("WHERE IS SUBSCRIPTION ID BRO")
//                    continue
//                }
//                relayMessages.append(message)
//            }
        }
        
        for relayMessage in relayMessages {
            var event = relayMessage.event!
            
            // no need for preview
//            guard try event.verified() else {
//                print("😡😡 hey invalid sig yo 😡😡")
//                continue
//            }
            
            // ANNOYING FIX FOR KIND 6 WITH JSON STRING OF ANOTHER EVENT IN EVENT.CONTENT. WTF
            if event.kind == .repost && event.content.prefix(2) == #"{""# {
                let decoder = JSONDecoder()
                if let noteInNote = try? decoder.decode(NEvent.self, from: event.content.data(using: .utf8, allowLossyConversion: false)!) {
                    _ = Event.saveEvent(event: noteInNote, context:context)
                    event.content = "#[0]"
                    if let firstTag = event.tags.first {
                        if firstTag.type == "e" {
                            event.tags[0] = NEventTag(type: "e", otherInformation: firstTag.id, "", "mention")
                        }
                    }
                }
            }
            
            let savedEvent = Event.saveEvent(event: event, context:context)
            
            if event.kind == .setMetadata {
                Contact.saveOrUpdateContact(event: event, context: context)
            }
            
            // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REACTIONS)
            if event.kind == .zapNote {
                let _ = Event.updateZapTallyCache(savedEvent, context: context)
            }
            
//            // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REACTIONS)
//            if event.kind == .custom(7) {
//                do { try _ = Event.updateLikeCountCache(event.tags, content:event.content, context: context) } catch {
//                    print("🦋🦋🔴🔴🔴 problem updating Like Count Cache .id \(event.id)")
//                }
//            }
//
//            // UPDATE THINGS THAT THIS EVENT RELATES TO. LIKES CACHE ETC (REPLIES, MENTIONS)
//            if event.kind == .textNote {
//                // NIP-10: Those marked with "mention" denote a quoted or reposted event id.
//                do { try _ = Event.updateMentionsCountCache(event.tags, context: context) } catch {
//                    print("🦋🦋🔴🔴🔴 problem updateMentionsCountCache .id \(event.id)")
//                }
//
//                // NIP-10: Those marked with "reply" denote the id of the reply event being responded to.
//                // NIP-10: Those marked with "root" denote the root id of the reply thread being responded to.
//                do { try _ = Event.updateRepliesCountCache(event.tags, context: context) } catch {
//                    print("🦋🦋🔴🔴🔴 problem updateRepliesCountCache .id \(event.id)")
//                }
//            }
            
        }
        
        var someEvent = PreviewFetcher.fetchEvent(
            "b9b337e5730eb83af2f6ae71b65295db8fe241aec7beb7fd8b6c0b88cc3d05d1", context: context)
    
        let contact1 = PreviewFetcher.fetchContact(
            "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0", context: context)
        account.addToFollows(contact1!)
        
        
        let contact2 = PreviewFetcher.fetchContact(
            "84dee6e676e5bb67b4ad4e042cf70cbd8681155db535942fcc6a0533858a7240", context: context)
        account.addToFollows(contact2!)
        contact2!.nip05 = "snowden@citizenfour.com"
        contact2!.nip05verifiedAt = Date.now
        
        
        let contact3 = PreviewFetcher.fetchContact(
            "df8efff2bfc02d81f93c7ff6ae111541637e0b3a4caff9ad48939a2f2f283be2", context: context)
        
        if (someEvent != nil) {
            account.addToBookmarks(someEvent!)
            someEvent!.addToBookmarkedBy(account)
        }
        if (contact3 != nil) {
            account.blockedPubkeys_ = account.blockedPubkeys_ + [contact3!.pubkey]
        }
        if (contact1 != nil) {
            account.blockedPubkeys_ = account.blockedPubkeys_ + [contact1!.pubkey]
        }
        
        if (contact2 != nil) {
            account.addToFollows(contact2!)
        }
        if (contact3 != nil) {
            account.addToFollows(contact3!)
        }
        
        if (contact1 != nil) {
            xaccount.addToFollows(contact1!)
        }
        
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
        
//        print("🎃🎃🎃🎃🎃🎃🎃🎃🎃🎃 \(description.url)")
        
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
}
