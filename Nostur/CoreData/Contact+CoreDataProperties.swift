//
//  Contact+CoreDataProperties.swift.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/01/2023.
//
//

import Foundation
import CoreData

typealias ContactPubkey = String

extension Contact {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Contact> {
        let fr = NSFetchRequest<Contact>(entityName: "Contact")
        fr.sortDescriptors = []
        return fr
    }
    
    @NSManaged public var about: String?
    @NSManaged public var lud16: String?
    @NSManaged public var lud06: String?
    @NSManaged public var name: String?
    @NSManaged public var fixedName: String? // When someone renames / deletes account, you can see find out who it was
    @NSManaged public var display_name: String?
    @NSManaged public var nip05: String?
    @NSManaged public var nip05verifiedAt: Date?
    @NSManaged public var picture: String?
    @NSManaged public var banner: String?
    @NSManaged public var pubkey: String
    @NSManaged public var zapperPubkey: String? // used to authorize kind 9735 zap notes. fetch from lud16 endpoint
    @NSManaged public var updated_at: Int64
    @NSManaged public var metadata_created_at: Int64
    @NSManaged public var followedBy: NSSet?
    @NSManaged public var events: Set<Event>?
    @NSManaged public var lists: NSSet?
    @NSManaged public var privateFollow: Bool
    @NSManaged public var couldBeImposter: Int16 // cache (-1 = unchecked, 1/0 = true/false checked)
    
    var pictureUrl:URL? {
        guard let picture = picture else { return nil }
        return URL(string: picture)
    }

    var lists_:[NosturList] {
        get { (lists?.allObjects as? [NosturList]) ?? [] }
        set { lists = NSSet(array: newValue) }
    }
}

// MARK: Generated accessors for lists
extension Contact {

    @objc(addNosturListsObject:)
    @NSManaged public func addToNosturLists(_ value: NosturList)

    @objc(removeNosturListsObject:)
    @NSManaged public func removeFromNosturLists(_ value: NosturList)

    @objc(addNosturLists:)
    @NSManaged public func addToNosturLists(_ values: NSSet)

    @objc(removeNosturLists:)
    @NSManaged public func removeFromNosturLists(_ values: NSSet)

}

// MARK: Generated accessors for events
extension Contact {

    @objc(addEventsObject:)
    @NSManaged public func addToEvents(_ value: Event)

    @objc(removeEventsObject:)
    @NSManaged public func removeFromEvents(_ value: Event)

    @objc(addEvents:)
    @NSManaged public func addToEvents(_ values: NSSet)

    @objc(removeEvents:)
    @NSManaged public func removeFromEvents(_ values: NSSet)

}

// MARK: Generated accessors for followedBy
extension Contact {

    @objc(addFollowedByObject:)
    @NSManaged public func addToFollowedBy(_ value: Account)

    @objc(removeFollowedByObject:)
    @NSManaged public func removeFromFollowedBy(_ value: Account)

    @objc(addFollowedBy:)
    @NSManaged public func addToFollowedBy(_ values: NSSet)

    @objc(removeFollowedBy:)
    @NSManaged public func removeFromFollowedBy(_ values: NSSet)

}

// MARK: Generated accessors for blockedBy
extension Contact {

    @objc(addBlockedByObject:)
    @NSManaged public func addToBlockedBy(_ value: Account)

    @objc(removeBlockedByObject:)
    @NSManaged public func removeFromBlockedBy(_ value: Account)

    @objc(addBlockedBy:)
    @NSManaged public func addToBlockedBy(_ values: NSSet)

    @objc(removeBlockedBy:)
    @NSManaged public func removeFromBlockedBy(_ values: NSSet)

}

extension Contact : Identifiable {
  
//    public var id:String { pubkey } // <--- This gives Core data multithreading errors
    var npub:String {
        try! NIP19(prefix: "npub", hexString: pubkey).displayString
    }
    var authorKey:String { String(pubkey.suffix(11)) }
    
    var handle:String { // for autocomplete: name -> display_name -> authorKey. No nil or ""
        let nameOrNil = name != "" ? name : nil // handle "" as nil
        let displayNameOrNil = display_name != "" ? display_name : nil // handle "" as nil
        return nameOrNil ?? displayNameOrNil ?? npub
    }
    
    // Display name, with fallbacks: (User)name, pubkey (prefix), or "?:?"
    var authorName: String { anyName }
    var anyName: String {
        let displayName = display_name != nil && display_name != "" ? display_name : nil
        let name = name != nil && name != "" ? name : nil
        let theName = (displayName ?? name) ?? nip05nameOnly
        
        if theName.isEmpty { return authorKey }
        let spamFixedName = String(theName.prefix(255)) // 255 SPAM LIMIT
        
        return spamFixedName.trimmingCharacters(in: .whitespacesAndNewlines)
        
//        if (SettingsStore.shared.hideEmojisInNames) {
//            return (spamFixedName.unicodeScalars.filter {
//                !($0.value >= 0x13000 && $0.value <= 0x1342E) && // EGYPTIAN HIEROGLYPHS
//                !$0.properties.isEmoji  // EMOJIS
//                
//            }.reduce("") { $0 + String($1) })
//        }
//        else {
//            return spamFixedName
//        }
    }
    
    var nip05nameOnly:String {
        guard nip05veried else { return "" }
        guard let parts = nip05?.split(separator: "@"), parts.count >= 2 else { return "" }
        guard let name = parts[safe: 0] else { return "" }
        guard !name.isEmpty else { return "" }
        return String(name)
    }
    
    var nip05veried:Bool {
        get {
            let fourWeeksAgo = Date.now.addingTimeInterval(-(28 * 86400))
            if nip05verifiedAt != nil && nip05verifiedAt! > fourWeeksAgo {
                return true
            }
            return false
        }
    }
    
    var nip05domain:String {
        get {
            guard nip05 != nil else { return "" }
            let nip05 = nip05!.trimmingCharacters(in: .whitespacesAndNewlines)
            let nip05parts = nip05.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true)
            
            guard nip05parts.count == 2 else { return "" }
            return String(nip05parts[1])
        }
    }
    
    var clEvent:Event? {
        get {
            let fr = Event.fetchRequest()
            fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
            fr.predicate = NSPredicate(format: "kind == 3 AND pubkey == %@", self.pubkey)
            return try? self.managedObjectContext?.fetch(fr).first
        }
    }
    
    var clNEvent:NEvent? {
        get {
            if let clEvent = self.clEvent {
                return clEvent.toNEvent()
            }
            return nil
        }
    }
    
    var followingPubkeys:[String] {
        get {
            if let nEvent = self.clNEvent {
                return TagsHelpers(nEvent.tags).pTags().map { $0.pubkey }
            }
            return []
        }
    }
    
    // [Contact] <-- NEvent.tags (clNEvent.tags) <-- Event (.clEvent)
    var followingContacts:[Contact] {
        get {
            guard !self.followingPubkeys.isEmpty else { return [] }
            let fr = Contact.fetchRequest()
            fr.predicate = NSPredicate(format: "pubkey IN %@", self.followingPubkeys)
            return (try? self.managedObjectContext?.fetch(fr)) ?? []
        }
    }

    static func saveOrUpdateContact(event:NEvent) {
        let context = DataProvider.shared().bg
                
        context.perform {
            let decoder = JSONDecoder()
            guard let metaData = try? decoder.decode(NSetMetadata.self, from: event.content.data(using: .utf8, allowLossyConversion: false)!) else {
                return
            }
            
            let awaitingContacts = EventRelationsQueue.shared.getAwaitingBgContacts()
            var contact:Contact?
            
            contact = awaitingContacts.first(where: { $0.pubkey == event.publicKey })
            
            if contact == nil {
                let request = NSFetchRequest<Contact>(entityName: "Contact")
                request.predicate = NSPredicate(format: "pubkey == %@", event.publicKey)
                request.sortDescriptors = [NSSortDescriptor(key: "updated_at", ascending: false)]
                request.fetchLimit = 1
                contact = try? context.fetch(request).first
            }
            
            if let contact {
                
                // Received metadata is newer than stored Contact
                if contact.metadata_created_at < event.createdAt.timestamp {
                    
                    // Needs imposter recheck?
                    if contact.couldBeImposter == 0 && !isFollowing(contact.pubkey) { // only if wasnt imposter before and is not following
                        if (contact.name != metaData.name) {
                            contact.couldBeImposter = -1
                        }
                        else if (contact.display_name != metaData.display_name) {
                            contact.couldBeImposter = -1
                        }
                        else if (contact.picture != metaData.picture) {
                            contact.couldBeImposter = -1
                        }
                    }
                    
                    // update contact
                    contact.objectWillChange.send()
                    contact.name = metaData.name
                    contact.display_name = metaData.display_name
                    contact.about = metaData.about
                    contact.picture = metaData.picture
                    contact.banner = metaData.banner
                    contact.nip05 = metaData.nip05
                    contact.lud16 = metaData.lud16
                    contact.lud06 = metaData.lud06
                    contact.metadata_created_at = Int64(event.createdAt.timestamp) // By Author (kind 0)
                    contact.updated_at = Int64(Date().timeIntervalSince1970) // By Nostur
                    contact.contactUpdated.send(contact)
                    Kind0Processor.shared.receive.send(Profile(pubkey: contact.pubkey, name: contact.anyName, pictureUrl: contact.pictureUrl))
                    
                    
                    updateRelatedEvents(contact)
                    updateRelatedAccounts(contact)
                }
                else {
                    // Received metadata is older than stored Contact
    //                print("🟠🟠 Already have newer info stored in Contact. Skipped update.")
                }
            }
            else {
                // Received metadata is not in any Contact
                // insert new contact
                let contact = Contact(context: context)
                contact.pubkey = event.publicKey
                contact.name = metaData.name
                contact.display_name = metaData.display_name
                contact.about = metaData.about
                contact.picture = metaData.picture
                contact.banner = metaData.banner
                contact.nip05 = metaData.nip05
                contact.lud16 = metaData.lud16
                contact.lud06 = metaData.lud06
                contact.metadata_created_at = Int64(event.createdAt.timestamp) // by author kind 0
                contact.updated_at = Int64(Date.now.timeIntervalSince1970) // by Nostur
                
                if contact.anyName != contact.authorKey { // For showing "Previously known as"
                    contact.fixedName = contact.anyName
                }
                Kind0Processor.shared.receive.send(Profile(pubkey: contact.pubkey, name: contact.anyName, pictureUrl: contact.pictureUrl))
                EventRelationsQueue.shared.addAwaitingContact(contact)
                updateRelatedEvents(contact)
                updateRelatedAccounts(contact)
            }
        }
    }
    
    static func updateRelatedEvents(_ contact:Contact) {
//        if contact.nip05 != nil && !contact.nip05veried {
//            NIP05Verifier.shared.verify(contact)
//        }
        
        let name = (contact.display_name ?? "") != "" ? contact.display_name : contact.name
        PubkeyUsernameCache.shared.setObject(for: contact.pubkey, value: name)
        
        let awaitingEvents = EventRelationsQueue.shared.getAwaitingBgEvents()
        
        for waitingEvent in awaitingEvents {
            if (waitingEvent.pubkey == contact.pubkey) {
                waitingEvent.objectWillChange.send() // Needed for zaps on notification screen
                if waitingEvent.contact == nil {
                    waitingEvent.contact = contact
                    waitingEvent.contactUpdated.send(contact)
                }
            }
            if let tagsSerialized = waitingEvent.tagsSerialized, tagsSerialized.contains(serializedP(contact.pubkey)) {
                waitingEvent.objectWillChange.send()
                if !waitingEvent.contacts_.contains(contact) {
                    waitingEvent.addToContacts(contact)
                    waitingEvent.contactsUpdated.send(waitingEvent.contacts_)
                }
            }
        }
        
        let awaitingZaps = ZapperPubkeyVerificationQueue.shared.getQueuedZaps()
        awaitingZaps.forEach { zap in
            if (zap.otherPubkey == contact.pubkey) {
                zap.objectWillChange.send() // Needed for zaps on notification screen
                if zap.zappedContact == nil {
                    zap.zappedContact = contact
                }
                if let zapperPubkey = contact.zapperPubkey,
                    zapperPubkey == zap.pubkey,
                    let zappedEvent = zap.zappedEvent {
                    zappedEvent.zapTally = (zappedEvent.zapTally + Int64(zap.naiveSats))
                    zappedEvent.zapsCount = (zappedEvent.zapsCount + 1)
                    zappedEvent.zapsDidChange.send((zappedEvent.zapsCount, zappedEvent.zapTally))
                    L.og.info("⚡️👍 zap \(zap.id) verified after fetching contact \(contact.pubkey)")
                }
            }
        }
        
        let pubkey = contact.pubkey
        Importer.shared.contactSaved.send(pubkey)
    }
    
    static func updateRelatedAccounts(_ contact:Contact) {
        #if DEBUG
            if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                fatalError("Should only be called from bg()")
            }
        #endif

        guard NRState.shared.accountPubkeys.contains(contact.pubkey) else { return }
        guard let account = try? Account.fetchAccount(publicKey: contact.pubkey, context: bg()) else { return }
        
        account.name = contact.name ?? ""
        account.about = contact.about ?? ""
        account.picture = contact.picture ?? ""
        account.banner = contact.banner ?? ""
        account.nip05 = contact.nip05 ?? ""
        account.lud16 = contact.lud16 ?? ""
        account.lud06 = contact.lud06 ?? ""
        
        bgSave()
        L.og.info("Updated account from new kind 0 from relay. pubkey: \(contact.pubkey)")
    }

    // Create dummy Contact if not already exists.
    static func ensureContactsCreated(event:NEvent, context:NSManagedObjectContext, limit:Int = 25) -> [Contact] {
        var contactsInThisEvent:[Contact] = []
        for pTag in event.pTags().prefix(limit) { // sanity... limit 25
            let contact = Contact.fetchByPubkey(pTag, context: context)
            guard contact == nil else {
                contactsInThisEvent.append(contact!)
                continue
            }
            let newContact = Contact(context: context)
            newContact.pubkey = pTag
            newContact.metadata_created_at = 0
            newContact.updated_at = 0
            contactsInThisEvent.append(newContact)
        }
        
        return contactsInThisEvent
    }
    
    
    static func allContactPubkeys(context:NSManagedObjectContext) async -> [String] {
        return await context.perform {
            let r = NSFetchRequest<Contact>(entityName: "Contact")
            r.entity = Contact.entity()
            let allContacts = try! r.execute()

            return allContacts.map { $0.pubkey }
        }
    }
    
    static func contactBy(pubkey:String, context:NSManagedObjectContext) -> Contact? {
        
        let request = NSFetchRequest<Contact>(entityName: "Contact")
        request.entity = Contact.entity()
        request.predicate = NSPredicate(format: "pubkey == %@", pubkey)
        request.sortDescriptors = [NSSortDescriptor(key: "updated_at", ascending: false)]
        
        return try? context.fetch(request).first    
    }
    
    static func npub(_ pubkey:String) -> String {
        return try! NIP19(prefix: "npub", hexString: pubkey).displayString
    }
    
    static func updateMetadata(_ metaData:NSetMetadata, event:Event, context:NSManagedObjectContext) throws {
        
        let request = NSFetchRequest<Contact>(entityName: "Contact")
        request.entity = Contact.entity()
        request.predicate = NSPredicate(format: "pubkey == %@", event.pubkey)
        
        if let contactToUpdate = try context.fetch(request).first {
            contactToUpdate.about = metaData.about
            contactToUpdate.lud16 = metaData.lud16
            contactToUpdate.lud06 = metaData.lud06
            contactToUpdate.name = metaData.name
            contactToUpdate.display_name = metaData.display_name
            contactToUpdate.picture = metaData.picture
            contactToUpdate.banner = metaData.banner
            if (metaData.nip05 != contactToUpdate.nip05) {
                contactToUpdate.nip05verifiedAt = nil // WHEN SET
            }
            contactToUpdate.nip05 = metaData.nip05
            contactToUpdate.metadata_created_at = event.created_at
            contactToUpdate.updated_at = Int64(Date().timeIntervalSince1970)
        }
        else {
            let contact = Contact(context: context)
            contact.pubkey = event.pubkey
            contact.about = metaData.about
            contact.lud16 = metaData.lud16
            contact.lud06 = metaData.lud06
            contact.name = metaData.name
            contact.display_name = metaData.display_name
            contact.picture = metaData.picture
            contact.banner = metaData.banner
            contact.nip05verifiedAt = nil // WHEN SET
            contact.nip05 = metaData.nip05
            contact.metadata_created_at = event.created_at
            contact.updated_at = Int64(Date().timeIntervalSince1970)
        }
    }
    
    
    static func fetchByPubkey(_ pubkey:String, context:NSManagedObjectContext) -> Contact? {
        let r = Contact.fetchRequest()
        r.predicate = NSPredicate(format: "pubkey == %@", pubkey)
        r.fetchLimit = 1
        r.fetchBatchSize = 1
        return try? context.fetch(r).first
    }
    
    static func fetchByPubkeys(_ pubkeys:[String], context:NSManagedObjectContext) -> [Contact] {
        let r = Contact.fetchRequest()
        r.predicate = NSPredicate(format: "pubkey IN %@", pubkeys)
        return (try? context.fetch(r)) ?? []
    }
}


extension DataProvider {
    func newContact(pubkey:String, context:NSManagedObjectContext? = nil, dontSave:Bool = false) -> Contact {
        let ctx = context ?? viewContext
        let newContact = Contact(context: ctx)
        newContact.pubkey = pubkey
        newContact.updated_at = 0
        newContact.metadata_created_at = 0
        if (!dontSave) {
            try? ctx.save()
        }
        return newContact
    }
}
