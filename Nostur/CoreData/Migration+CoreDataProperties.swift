//
//  Migration+CoreDataProperties.swift.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/07/2023.
//
//

import Foundation
import CoreData

extension Migration {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Migration> {
        return NSFetchRequest<Migration>(entityName: "Migration")
    }

    @NSManaged public var migrationCode: String?
    
    var migrationCode_:String {
        migrationCode ?? ""
    }

}

extension Migration : Identifiable {

}
