//
//  Contact+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/01/2023.
//
//

import Foundation
import CoreData


extension Contact {

//    @nonobjc public class func fetchRequest() -> NSFetchRequest<Contact> {
//        let request: NSFetchRequest<Contact> = Contact.fetchRequest()
//        let sortDescriptor = NSSortDescriptor(key: "updated_at", ascending: false)
//        return request
//        return NSFetchRequest<Contact>(entityName: "Contact")
//    }
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Contact> {
        return NSFetchRequest<Contact>(entityName: "Contact")
    }

    @NSManaged public var about: String?
    @NSManaged public var lud16: String?
    @NSManaged public var name: String?
    @NSManaged public var display_name: String?
    @NSManaged public var nip05: String?
    @NSManaged public var nip05verifiedAt: Date?
    @NSManaged public var picture: String?
    @NSManaged public var pictureFile: Data?
    @NSManaged public var pubkey: String?
    @NSManaged public var updated_at: Int64
    @NSManaged public var followedBy: NSSet?

}

// MARK: Generated accessors for followedBy
extension Contact {

    @objc(addFollowedByObject:)
    @NSManaged public func addToFollowedBy(_ value: Identity)

    @objc(removeFollowedByObject:)
    @NSManaged public func removeFromFollowedBy(_ value: Identity)

    @objc(addFollowedBy:)
    @NSManaged public func addToFollowedBy(_ values: NSSet)

    @objc(removeFollowedBy:)
    @NSManaged public func removeFromFollowedBy(_ values: NSSet)

}

extension Contact : Identifiable {
    
//    static func allContacts() -> NSFetchRequest<Contact> {
//        
//        let request: NSFetchRequest<Contact> = Contact.fetchRequest()
//        let sortDescriptor = NSSortDescriptor(key: "updated_at", ascending: false)
//        return request
//    }
    
    //
    var authorKey: String {
        get {
            pubkey != nil ? String(pubkey!.prefix(5)) : "?:?"
        }
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

    static func handleSetMetadataEvent(event:NEvent, context:NSManagedObjectContext) {
        
        let decoder = JSONDecoder()
        guard let metaData = try? decoder.decode(NSetMetadata.self, from: event.content.data(using: .utf8, allowLossyConversion: false)!) else {
            return
        }
        
        let request = NSFetchRequest<Contact>()
        request.entity = Contact.entity()
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
                contact.pictureFile = nil // todo
                contact.nip05 = metaData.nip05
                contact.lud16 = metaData.lud16
                contact.updated_at = Int64(Date().timeIntervalSince1970)
                print("🟢🟢 Existing Contact metadata updated")
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
            contact.pictureFile = nil // todo
            contact.nip05 = metaData.nip05
            contact.lud16 = metaData.lud16
            contact.updated_at = Int64(Date().timeIntervalSince1970)
            print("🟢🟢 New contact stored ")
        }
        do {
            try context.save()
        }
        catch let error {
            print("🔴🐥🔴 Error storing event 🔴🐥🔴 \(error)")
        }
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
    
    static func handleContactListEvent(event:NEvent, context:NSManagedObjectContext) async -> [String] {
        print("how to handle?? \(event.eventJson())")
        
        let newPubkeys = await context.perform {
            
            // check existing to prevent duplicates (because iCloud database doesn't support unique id contraints)
            let r = NSFetchRequest<Contact>()
            r.entity = Contact.entity()
            r.sortDescriptors = [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)]
            let allContacts = try! r.execute()
            print(allContacts)
            let allContactPubkeys = allContacts.map { $0.pubkey! }
            var newPubkeys = [String]()
            
            // create contacts from "p" tags
            for tag in event.tags {
                if tag.id == "p" {
                    let pubkey = tag.otherInformation[0]
            
                    if allContactPubkeys.contains(where: { $0 == pubkey }) {
                        print("Already have \(pubkey) in contacts. Skipped")
                        continue
                    }
                    print("🩸🩸🩸 new contact tag.id \(tag.id), tag.otherinf \(tag.otherInformation[0]), pubkey \(pubkey)")
                    let newContact = Contact(context: context)
                    newContact.pubkey = pubkey
                    newContact.updated_at = 0
                    newPubkeys.append(pubkey)
                    try! context.save()
                }
            }
            
            // return all new pubkeys
            return newPubkeys
        }
        return newPubkeys
    }
    
    static func contactBy(pubkey:String, context:NSManagedObjectContext) -> Contact? {
        
        let request = NSFetchRequest<Contact>()
        request.entity = Contact.entity()
        request.predicate = NSPredicate(format: "pubkey == %@", pubkey)
        request.sortDescriptors = [NSSortDescriptor(key: "updated_at", ascending: false)]
        
        return try? context.fetch(request).first    
    }
}
