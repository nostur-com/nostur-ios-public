//
//  NosturList+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/04/2023.
//
//

import Foundation
import CoreData

extension NosturList {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<NosturList> {
        return NSFetchRequest<NosturList>(entityName: "NosturList")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var createdAt: Date?
    @NSManaged public var name: String?
    @NSManaged public var refreshedAt: Date?
    @NSManaged public var type: String?
    @NSManaged public var contacts: NSSet?
    @NSManaged public var showAsTab: Bool
    @NSManaged public var hideReplies: Bool
    
    var contacts_:[Contact] {
        get { contacts?.allObjects as! [Contact] }
        set { contacts = NSSet(array: newValue) }
    }
    
    var name_:String {
        get { name ?? "" }
        set { name = newValue }
    }
    
    var subscriptionId:String {
        let id = id?.uuidString ?? "UNKNOWN"
        let idLength = id.count
        return "List-" + String(id.prefix(min(idLength,18)))
    }
}

// MARK: Generated accessors for contacts
extension NosturList {

    @objc(addContactsObject:)
    @NSManaged public func addToContacts(_ value: Contact)

    @objc(removeContactsObject:)
    @NSManaged public func removeFromContacts(_ value: Contact)

    @objc(addContacts:)
    @NSManaged public func addToContacts(_ values: NSSet)

    @objc(removeContacts:)
    @NSManaged public func removeFromContacts(_ values: NSSet)

}

extension NosturList : Identifiable {

}
