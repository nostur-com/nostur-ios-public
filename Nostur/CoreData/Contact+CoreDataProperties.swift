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

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Contact> {
        return NSFetchRequest<Contact>(entityName: "Contact")
    }

    @NSManaged public var about: String?
    @NSManaged public var lud16: String?
    @NSManaged public var name: String?
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

    static func handleSetMetadataEvent(event:NEvent, cloudContext:NSManagedObjectContext) {
        
        let decoder = JSONDecoder()
        guard let metaData = try? decoder.decode(NSetMetadata.self, from: event.content.data(using: .utf8, allowLossyConversion: false)!) else {
            return
        }
        
        let request = NSFetchRequest<Contact>()
        request.entity = Contact.entity()
        request.predicate = NSPredicate(format: "pubkey == %@", event.publicKey)
        request.sortDescriptors = [NSSortDescriptor(key: "updated_at", ascending: false)]
        
        if let contact = try! cloudContext.fetch(request).first {
            // check if event is newer
            if contact.updated_at < event.createdAt.timestamp {
                
                // update contact
                contact.name = metaData.name
                contact.about = metaData.about
                contact.pictureFile = nil // todo
                contact.nip05 = metaData.nip05
                contact.lud16 = metaData.lud16
                contact.updated_at = Int64(Date().timeIntervalSince1970)
            }
        }
        else {
            // insert new contact
            
            let contact = Contact(context: cloudContext)
            contact.pubkey = event.publicKey
            contact.name = metaData.name
            contact.about = metaData.about
            contact.pictureFile = nil // todo
            contact.nip05 = metaData.nip05
            contact.lud16 = metaData.lud16
            contact.updated_at = Int64(Date().timeIntervalSince1970)
        }
        do {
            try cloudContext.save()
        }
        catch let error {
            print("🔴🐥🔴 Error storing event 🔴🐥🔴 \(error)")
        }
    }
}
