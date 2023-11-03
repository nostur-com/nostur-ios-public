//
//  Bookmark+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/11/2023.
//
//

import Foundation
import CoreData


extension Bookmark {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Bookmark> {
        return NSFetchRequest<Bookmark>(entityName: "Bookmark")
    }

    // -- MARK: iCloud fields --
    @NSManaged public var eventId: String?
    @NSManaged public var json: String?
    @NSManaged public var createdAt: Date?

}

extension Bookmark : Identifiable {

}
