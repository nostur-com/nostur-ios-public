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
    
    // account pubkey! not contact pubkey
    @NSManaged public var pubkey: String
    @NSManaged public var readAt: Date?
    @NSManaged public var type_: String
    @NSManaged public var since: Int64 // New Post notifications "since"
    
    var type:PersistentNotificationType {
        get { PersistentNotificationType(rawValue: type_) ?? PersistentNotificationType.none }
        set { type_ = newValue.rawValue }
    }
    
    var contactsInfo: [ContactInfo] {
        guard type == .newPosts, !content.isEmpty, let contentData = content.data(using: .utf8) else { return [] }
        guard let contactsInfo = try? JSONDecoder().decode([ContactInfo].self, from: contentData) else { return [] }
        return contactsInfo
    }

}

extension PersistentNotification : Identifiable {
    static func fetchPersistentNotification(byPubkey pubkey: String? = nil, id: String? = nil, type: PersistentNotificationType? = nil, context: NSManagedObjectContext = context()) -> PersistentNotification? {
        let request = NSFetchRequest<PersistentNotification>(entityName: "PersistentNotification")
        
        if let id {
            request.predicate = NSPredicate(format: "id == %@ AND NOT id == nil", id)
        }
        else if let pubkey, let type {
            request.predicate = NSPredicate(format: "pubkey == %@ AND type_ == %@ AND NOT id == nil", pubkey, type.rawValue)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \PersistentNotification.createdAt, ascending: false)]
        }
        else {
            request.sortDescriptors = [NSSortDescriptor(keyPath: \PersistentNotification.createdAt, ascending: false)]
            if let type = type {
                request.predicate = NSPredicate(format: "type_ == %@ AND NOT id == nil", type.rawValue)
            }
            else {
                request.predicate = NSPredicate(format: "id != nil")
            }
        }
        request.fetchLimit = 1
        request.fetchBatchSize = 1
        return try? context.fetch(request).first
    }
}
