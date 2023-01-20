//
//  Relay+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 18/01/2023.
//
//

import Foundation
import CoreData


extension Relay {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Relay> {
        return NSFetchRequest<Relay>(entityName: "Relay")
    }

    @NSManaged public var createdAt: Date?
    @NSManaged public var id: UUID?
    @NSManaged public var read: Bool
    @NSManaged public var url: String?
    @NSManaged public var write: Bool

}

extension Relay : Identifiable {
    
}
