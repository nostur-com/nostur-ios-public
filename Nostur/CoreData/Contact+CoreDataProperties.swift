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
    @NSManaged public var fixedName: String? // When someone renames / deletes account, you can find out who it was
    @NSManaged public var fixedPfp: String? // When someone renames / deletes account, you can find out who it was
    @NSManaged public var display_name: String?
    @NSManaged public var nip05: String?
    @NSManaged public var nip05verifiedAt: Date?
    @NSManaged public var picture: String?
    @NSManaged public var banner: String?
    @NSManaged public var pubkey: String
    @NSManaged public var zapperPubkey: String? // used to authorize kind 9735 zap notes. fetch from lud16 endpoint. updated to contain Set
    @NSManaged public var updated_at: Int64
    @NSManaged public var metadata_created_at: Int64

    @NSManaged public var events: Set<Event>?
    @NSManaged public var lists: NSSet?
    @NSManaged public var privateFollow: Bool // Need to keep for old DB migration
    @NSManaged public var couldBeImposter: Int16 // cache (-1 = unchecked, 1/0 = true/false checked)
    @NSManaged public var similarToPubkey: String? // If possible imposter, pubkey of similar profile already following
    
    var pictureUrl:URL? {
        guard let picture = picture else { return nil }
        return URL(string: picture)
    }

    var lists_:[CloudFeed] {
        get {
            CloudFeed.fetchAll(context: DataProvider.shared().viewContext)
                .filter({
                    ($0.pubkeys?.components(separatedBy: " ") ?? []).contains(where: { $0 == self.pubkey })
                })
        }
        set {
            for feed in newValue {
                feed.contacts_.append(self)
            }
        }
    }
    
    // Repurpose zapperPubkey single field to track multiple pubkeys for when user changes zapper (wallet)
    var zapperPubkeys: Set<String> {
        get {
            guard let zapperPubkey else { return [] }
            return Set(zapperPubkey.split(separator: " ").map { String($0) })
        }
        set {
            zapperPubkey = newValue.joined(separator: " ")
        }
    }
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
    
    var nip05nameOnly: String {
        guard nip05veried else { return "..." }
        guard let parts = nip05?.split(separator: "@"), parts.count >= 2 else { return "" }
        guard let name = parts[safe: 0] else { return "" }
        guard !name.isEmpty else { return "" }
        return String(name)
    }
    
    var nip05veried:Bool {
        get {
            let fourWeeksAgo = Date.now.addingTimeInterval(-(2419200))
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

    static func saveOrUpdateContact(event: NEvent, context: NSManagedObjectContext) {
        #if DEBUG
        shouldBeBg()
        #endif
        let decoder = JSONDecoder()
        guard let metaData = try? decoder.decode(NSetMetadata.self, from: event.content.data(using: .utf8, allowLossyConversion: false)!) else {
            return
        }
        
        let awaitingContacts = EventRelationsQueue.shared.getAwaitingBgContacts()
        var contact: Contact?
        
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
                        contact.similarToPubkey = nil
                    }
                    else if (contact.display_name != metaData.display_name) {
                        contact.couldBeImposter = -1
                        contact.similarToPubkey = nil
                    }
                    else if (contact.picture != metaData.picture) {
                        contact.couldBeImposter = -1
                        contact.similarToPubkey = nil
                    }
                }
                
                if (contact.fixedName ?? "").isEmpty && contact.anyName != contact.authorKey { // Store previous name
                    contact.fixedName = contact.anyName
                }
                
                if (contact.fixedPfp ?? "").isEmpty { // Store previous name
                    contact.fixedPfp = contact.picture
                }
                // update contact
//                    contact.objectWillChange.send()
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
                
                PubkeyUsernameCache.shared.setObject(for: event.publicKey, value: contact.anyName)
                
                // TODO: Should use this more?:
                Kind0Processor.shared.receive.send(Profile(pubkey: contact.pubkey, name: contact.anyName, pictureUrl: contact.pictureUrl))
                
                
                updateRelatedEvents(contact)
                updateRelatedAccounts(contact)
                ViewUpdates.shared.contactUpdated.send((event.publicKey, contact))
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
            contact.fixedPfp = contact.picture // For showing "Previously known as"
            
            PubkeyUsernameCache.shared.setObject(for: event.publicKey, value: contact.anyName)
            
            Kind0Processor.shared.receive.send(Profile(pubkey: contact.pubkey, name: contact.anyName, pictureUrl: contact.pictureUrl))
            EventRelationsQueue.shared.addAwaitingContact(contact, debugInfo: "saveOrUpdateContact")
            updateRelatedEvents(contact)
            updateRelatedAccounts(contact)
            ViewUpdates.shared.contactUpdated.send((event.publicKey, contact))
        }
    }
    
    static func updateRelatedEvents(_ contact: Contact) {
//        if contact.nip05 != nil && !contact.nip05veried {
//            NIP05Verifier.shared.verify(contact)
//        }
        
//        let name = (contact.display_name ?? "") != "" ? contact.display_name : contact.name
        PubkeyUsernameCache.shared.setObject(for: contact.pubkey, value: contact.anyName)
        
        let awaitingZaps = ZapperPubkeyVerificationQueue.shared.getQueuedZaps()
        awaitingZaps.forEach { zap in
            if (zap.otherPubkey == contact.pubkey) {
                zap.objectWillChange.send() // Needed for zaps on notification screen
                if zap.zappedContact == nil {
                    zap.zappedContact = contact
                }
                if let zappedEvent = zap.zappedEvent, contact.zapperPubkeys.contains(zap.pubkey) {
                    zappedEvent.zapTally = (zappedEvent.zapTally + Int64(zap.naiveSats))
                    zappedEvent.zapsCount = (zappedEvent.zapsCount + 1)
//                    zappedEvent.zapsDidChange.send((zappedEvent.zapsCount, zappedEvent.zapTally))
                    ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: zappedEvent.id, zaps: zappedEvent.zapsCount, zapTally: zappedEvent.zapTally))
                    L.og.debug("⚡️👍 zap \(zap.id) verified after fetching contact \(contact.pubkey)")
                }
            }
        }
    }
    
    static func updateRelatedAccounts(_ contact:Contact) {
        #if DEBUG
            if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                fatalError("Should only be called from bg()")
            }
        #endif

        guard AccountsState.shared.bgAccountPubkeys.contains(contact.pubkey) else { return }
        guard let account = try? CloudAccount.fetchAccount(publicKey: contact.pubkey, context: bg()) else { return }
        
        account.name = contact.name ?? ""
        account.about = contact.about ?? ""
        account.picture = contact.picture ?? ""
        account.banner = contact.banner ?? ""
        account.nip05 = contact.nip05 ?? ""
        account.lud16 = contact.lud16 ?? ""
        account.lud06 = contact.lud06 ?? ""
        
        bgSave()
        L.og.debug("Updated account from new kind 0 from relay. pubkey: \(contact.pubkey)")
    }

    // Create dummy Contact if not already exists.
    static func ensureContactsCreated(event: NEvent, context: NSManagedObjectContext, limit: Int = 75) -> [Contact] {
        var contactsInThisEvent: [Contact] = []
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
    
    static func fetchByPubkey(_ pubkey: String, context: NSManagedObjectContext) -> Contact? {
        if !Thread.isMainThread { // Try to get from following cache first (bg only for now)
            if let contact = AccountsState.shared.loggedInAccount?.followingCache[pubkey]?.bgContact {
                return contact
            }
        }
        let r = Contact.fetchRequest()
        r.predicate = NSPredicate(format: "pubkey == %@", pubkey)
        r.sortDescriptors = [NSSortDescriptor(key: "updated_at", ascending: false)]
        r.fetchLimit = 1
        r.fetchBatchSize = 1
        return try? context.fetch(r).first
    }
    
    static func fetchByPubkeys(_ pubkeys: [String], context: NSManagedObjectContext = context()) -> [Contact] {
        let r = Contact.fetchRequest()
        r.predicate = NSPredicate(format: "pubkey IN %@", pubkeys)
        return (try? context.fetch(r)) ?? []
    }
    
    static func fetchByPubkeys(_ pubkeys: Set<String>, context: NSManagedObjectContext = context()) -> [Contact] {
        let r = Contact.fetchRequest()
        r.predicate = NSPredicate(format: "pubkey IN %@", pubkeys)
        return (try? context.fetch(r)) ?? []
    }
    
    static func addZapperPubkey(contactPubkey: String, zapperPubkey: String) {
        shouldBeBg()
        guard let contact = Self.fetchByPubkey(contactPubkey, context: bg()) else { return }
        contact.zapperPubkeys.insert(zapperPubkey)
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
