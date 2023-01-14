//
//  Identity+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/01/2023.
//
//

import Foundation
import CoreData


extension Identity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Identity> {
        return NSFetchRequest<Identity>(entityName: "Identity")
    }

    @NSManaged public var about: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var name: String
    @NSManaged public var lud16: String
    @NSManaged public var nip05: String
    @NSManaged public var picture: String
    @NSManaged public var privateKey: String?
    @NSManaged public var publicKey: String?
    @NSManaged public var id: UUID?
    @NSManaged public var follows: NSSet?

}

// MARK: Generated accessors for follows
extension Identity {

    @objc(addFollowsObject:)
    @NSManaged public func addToFollows(_ value: Contact)

    @objc(removeFollowsObject:)
    @NSManaged public func removeFromFollows(_ value: Contact)

    @objc(addFollows:)
    @NSManaged public func addToFollows(_ values: NSSet)

    @objc(removeFollows:)
    @NSManaged public func removeFromFollows(_ values: NSSet)

}

extension Identity : Identifiable {

}
