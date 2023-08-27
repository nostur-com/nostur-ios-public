//
//  PersistentNotification+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/06/2023.
//
//

import Foundation
import CoreData

extension PersistentNotification {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PersistentNotification> {
        return NSFetchRequest<PersistentNotification>(entityName: "PersistentNotification")
    }

    @NSManaged public var id: UUID
    @NSManaged public var createdAt: Date
    @NSManaged public var content: String
    @NSManaged public var pubkey: String
    @NSManaged public var readAt: Date?
    @NSManaged public var type_: String
    
    var type:PersistentNotificationType {
        get { PersistentNotificationType(rawValue: type_) ?? PersistentNotificationType.none }
        set { type_ = newValue.rawValue }
    }

}

extension PersistentNotification : Identifiable {
    static func fetchPersistentNotification(id:String? = nil, type:PersistentNotificationType? = nil, context:NSManagedObjectContext) -> PersistentNotification? {
        let request = NSFetchRequest<PersistentNotification>(entityName: "PersistentNotification")
        if let id {
            request.predicate = NSPredicate(format: "id == %@", id)
        }
        else {
            request.sortDescriptors = [NSSortDescriptor(keyPath: \PersistentNotification.createdAt, ascending: false)]
            if let type = type {
                request.predicate = NSPredicate(format: "type_ == %@", type.rawValue)
            }
            else {
                request.predicate = NSPredicate(value: true)
            }
        }
        request.fetchLimit = 1
        request.fetchBatchSize = 1
        return try? context.fetch(request).first
    }
}
