//
//  Contact+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/01/2023.
//
//

import Foundation
import CoreData

typealias ContactPubkey = String

extension Contact {

//    @nonobjc public class func fetchRequest() -> NSFetchRequest<Contact> {
//        let request: NSFetchRequest<Contact> = Contact.fetchRequest()
//        let sortDescriptor = NSSortDescriptor(key: "updated_at", ascending: false)
//        return request
//        return NSFetchRequest<Contact>(entityName: "Contact")
//    }
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Contact> {
        let fr = NSFetchRequest<Contact>(entityName: "Contact")
        fr.sortDescriptors = []
        return fr
    }
    
//    @nonobjc public class func fetchRequest2() -> NSFetchRequest<Contact> { // SOMEHOW THIS FIXES PREVIEW CANVAS BUG JEEZ
//        let fr = NSFetchRequest<Contact>(entityName: "Contact")
//        fr.sortDescriptors = []
//        return fr
//    }

    @NSManaged public var about: String?
    @NSManaged public var lud16: String?
    @NSManaged public var name: String?
    @NSManaged public var display_name: String?
    @NSManaged public var nip05: String?
    @NSManaged public var nip05verifiedAt: Date?
    @NSManaged public var picture: String?
    @NSManaged public var banner: String?
    @NSManaged public var pubkey: String?
    @NSManaged public var zapperPubkey: String? // used to authorize kind 9735 zap notes. fetch from lud16 endpoint
    @NSManaged public var updated_at: Int64
    @NSManaged public var followedBy: NSSet?
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
        
    var authorKey: String {
        get { pubkey != nil ? String(npub.prefix(9)) : "⏤⏤" }
    }
    
    // Display name, with fallbacks: (User)name, pubkey (prefix), or "?:?"
    var authorName: String {
        get {
            display_name != nil
            ? display_name!
            : name != nil
                ? name!
                : authorKey
        }
    }
    
    var username:String { get { name ?? authorKey } }
    
    var npub:String { get { pubkey != nil ? try! NIP19(prefix: "npub", hexString: pubkey!).displayString : "⏤⏤" } }
    
    var nip05veried:Bool {
        get {
            let twoWeeksAgo = Date.now.addingTimeInterval(-(14 * 86400))
            if nip05verifiedAt != nil && nip05verifiedAt! > twoWeeksAgo {
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
            fr.predicate = NSPredicate(format: "kind == 3 AND pubkey == %@", self.pubkey!)
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
            guard self.followingPubkeys.count != 0 else { return [] }
            let fr = Contact.fetchRequest()
            fr.predicate = NSPredicate(format: "pubkey IN %@", self.followingPubkeys)
            return (try? self.managedObjectContext?.fetch(fr)) ?? []
        }
    }

    static func saveOrUpdateContact(event:NEvent, context:NSManagedObjectContext) {
        
        let decoder = JSONDecoder()
        guard let metaData = try? decoder.decode(NSetMetadata.self, from: event.content.data(using: .utf8, allowLossyConversion: false)!) else {
            return
        }
        
        let request = NSFetchRequest<Contact>(entityName: "Contact")
        request.predicate = NSPredicate(format: "pubkey == %@", event.publicKey)
        request.sortDescriptors = [NSSortDescriptor(key: "updated_at", ascending: false)]
        
        if let contact = try! context.fetch(request).first {
            
            // Received metadata is newer than stored Contact
            if contact.updated_at < event.createdAt.timestamp {
                
                // update contact
                contact.name = metaData.name
                contact.display_name = metaData.display_name
                contact.about = metaData.about
                contact.picture = metaData.picture
                contact.banner = metaData.banner
                contact.nip05 = metaData.nip05
                contact.lud16 = metaData.lud16
                contact.updated_at = Int64(Date().timeIntervalSince1970)
                print("🟢🟢 Existing Contact metadata updated")
                // TODO: Maybe some event.objectWillChange.send() to relations in active views? Performance?
                let er = Event.fetchRequest()
                er.sortDescriptors = []
                er.predicate = NSPredicate(format: "kind IN {1,6,9734} && pubkey == %@", event.publicKey)
                let contactEvents = Array(try! context.fetch(er))
                for event in contactEvents {
                    event.contact = contact
                    event.objectWillChange.send()
                }
            }
            else {
                // Received metadata is older than stored Contact
                print("🟠🟠 Already have newer info stored in Contact. Skipped update.")
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
            contact.updated_at = Int64(Date().timeIntervalSince1970)
            print("🟢🟢 New contact stored ")
            
            // Update relation on already existing events
            let er = Event.fetchRequest()
            er.sortDescriptors = []
            er.predicate = NSPredicate(format: "kind IN {1,6,9734} && pubkey == %@", event.publicKey)
            let contactEvents = Array(try! context.fetch(er))
            for event in contactEvents {
                event.contact = contact
                event.objectWillChange.send()
            }
            
            // TAGS INVERSE:
            let tr = NSFetchRequest<Tag>(entityName: "Tag")
            tr.predicate = NSPredicate(format: "type == 'p' AND index1 == %@", event.publicKey)
            if let tags = try? context.fetch(tr) {
                for tag in tags {
                    tag.contact = contact
                    tag.objectWillChange.send()
                }
            }
        }
    }

    // Create dummy Contact if not already exists.
    static func ensureContactsCreated(event:NEvent, context:NSManagedObjectContext) -> [Contact] {
        var contactsInThisEvent:[Contact] = []
        let pTags = TagsHelpers(event.tags).pTags()
        for pTag in pTags {
            let contact = Contact.fetchByPubkey(pTag.pubkey, context: context)
            guard contact == nil else {
                contactsInThisEvent.append(contact!)
                continue
            }
            let newContact = Contact(context: context)
            newContact.pubkey = pTag.pubkey
            newContact.updated_at = 0
            contactsInThisEvent.append(newContact)
        }
        
        return contactsInThisEvent
    }
    
    
    static func allContactPubkeys(context:NSManagedObjectContext) async -> [String] {
        return await context.perform {
            let r = NSFetchRequest<Contact>()
            r.entity = Contact.entity()
    //        r.sortDescriptors = [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)]
            let allContacts = try! r.execute()
    //        print(allContacts)
            return allContacts.map { $0.pubkey! }
        }
    }
//    
//    static func handleContactListEvent(event:NEvent, context:NSManagedObjectContext) async -> ([String], [String]) {
//        // DONT NEED THIS ENTIRE FUNC ACTUALLY
//        print("how to handle?? \(event.eventJson())")
//        
//        let newPubkeys = await context.perform {
//            
//            // check existing to prevent duplicates (because iCloud database doesn't support unique id contraints)
//            let r = NSFetchRequest<Contact>()
//            r.entity = Contact.entity()
//            r.sortDescriptors = [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)]
//            let allContacts = try! r.execute()
//            print(allContacts)
//            let allContactPubkeys = allContacts.map { $0.pubkey! }
//            var newPubkeys = [String]()
//            var eventPubkeys = [String]()
//            
//            // create contacts from "p" tags
//            for tag in event.tags {
//                if tag.id == "p" {
//                    let pubkey = tag.otherInformation[0]
//                    eventPubkeys.append(pubkey)
//            
//                    if allContactPubkeys.contains(where: { $0 == pubkey }) {
//                        print("Already have \(pubkey) in contacts. Skipped")
//                        continue
//                    }
//                    print("🩸🩸🩸 new contact tag.id \(tag.id), tag.otherinf \(tag.otherInformation[0]), pubkey \(pubkey)")
//                    let newContact = Contact(context: context)
//                    newContact.pubkey = pubkey
//                    newContact.updated_at = 0
//                    newPubkeys.append(pubkey)
//                    try! context.save()
//                }
//            }
//            
//            // return all new pubkeys
//            return (newPubkeys, eventPubkeys)
//        }
//        return newPubkeys
//    }
    
    static func contactBy(pubkey:String, context:NSManagedObjectContext) -> Contact? {
        
        let request = NSFetchRequest<Contact>()
        request.entity = Contact.entity()
        request.predicate = NSPredicate(format: "pubkey == %@", pubkey)
        request.sortDescriptors = [NSSortDescriptor(key: "updated_at", ascending: false)]
        
        return try? context.fetch(request).first    
    }
    
    static func npub(_ pubkey:String) -> String {
        return try! NIP19(prefix: "npub", hexString: pubkey).displayString
    }
    
    static func updateMetadata(_ metaData:NSetMetadata, pubkey:String, context:NSManagedObjectContext) throws {
        
        let request = NSFetchRequest<Contact>()
        request.entity = Contact.entity()
        request.predicate = NSPredicate(format: "pubkey == %@", pubkey)
        
        if let contactToUpdate = try context.fetch(request).first {
            contactToUpdate.about = metaData.about
            contactToUpdate.lud16 = metaData.lud16
            contactToUpdate.name = metaData.name
            contactToUpdate.display_name = metaData.display_name
            contactToUpdate.picture = metaData.picture
            contactToUpdate.banner = metaData.banner
            if (metaData.nip05 != contactToUpdate.nip05) {
                contactToUpdate.nip05verifiedAt = nil // WHEN SET
            }
            contactToUpdate.nip05 = metaData.nip05
            contactToUpdate.updated_at = Int64(Date().timeIntervalSinceNow)
        }
        else {
            let contact = Contact(context: context)
            contact.pubkey = pubkey
            contact.about = metaData.about
            contact.lud16 = metaData.lud16
            contact.name = metaData.name
            contact.display_name = metaData.display_name
            contact.picture = metaData.picture
            contact.banner = metaData.banner
            contact.nip05verifiedAt = nil // WHEN SET
            contact.nip05 = metaData.nip05
            contact.updated_at = Int64(Date().timeIntervalSinceNow)
        }
    }
    
    
    static func fetchByPubkey(_ pubkey:String, context:NSManagedObjectContext) -> Contact? {
        let r = Contact.fetchRequest()
        r.predicate = NSPredicate(format: "pubkey == %@", pubkey)
        return try? context.fetch(r).first
    }
    
    static func fetchByPubkeys(_ pubkeys:[String], context:NSManagedObjectContext) -> [Contact] {
        let r = Contact.fetchRequest()
        r.predicate = NSPredicate(format: "pubkey IN %@", pubkeys)
        return (try? context.fetch(r)) ?? []
    }
}
