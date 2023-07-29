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
    
    // default (nil) or "pubkeys" = feed of posts from selected pubkeys
    // "relays" = Relays feed. Any post from selected relays
    // "hashtags" = Feed of posts with selected hashtag(s) (TODO)
    // "..more??" = ...
    @NSManaged public var type: String? // Use LVM.ListType enum
    @NSManaged public var contacts: NSSet?
    @NSManaged public var relays: Set<Relay>?
    @NSManaged public var showAsTab: Bool
    @NSManaged public var hideReplies: Bool
    
    var contacts_:[Contact] {
        get { contacts?.allObjects as! [Contact] }
        set { contacts = NSSet(array: newValue) }
    }
    
    var relays_:Set<Relay> {
        get { relays ?? [] }
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

// MARK: Generated accessors for relays
extension NosturList {

    @objc(addRelaysObject:)
    @NSManaged public func addToRelays(_ value: Relay)

    @objc(removeRelaysObject:)
    @NSManaged public func removeFromRelays(_ value: Relay)

    @objc(addRelays:)
    @NSManaged public func addToRelays(_ values: NSSet)

    @objc(removeRelays:)
    @NSManaged public func removeFromRelays(_ values: NSSet)

}

extension NosturList : Identifiable {

}
