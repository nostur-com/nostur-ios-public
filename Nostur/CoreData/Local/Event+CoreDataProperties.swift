//
//  Event+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/01/2023.
//
//

import Foundation
import CoreData


extension Event {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Event> {
        return NSFetchRequest<Event>(entityName: "Event")
    }

    @NSManaged public var content: String?
    @NSManaged public var created_at: Int64
    @NSManaged public var id: String?
    @NSManaged public var kind: Int16
    @NSManaged public var pubkey: String?
    @NSManaged public var sig: String?
    @NSManaged public var tagsSerialized: String?

}

extension Event : Identifiable {

}

extension Event {
    
    static func textNotes(byAuthorPubkey:String? = nil) -> NSFetchRequest<Event> {
        
        let request: NSFetchRequest<Event> = Event.fetchRequest()
        if (byAuthorPubkey != nil) {
            request.predicate = NSPredicate(format: "kind == 1 AND pubkey == %@", byAuthorPubkey!)
        }
        else {
            request.predicate = NSPredicate(format: "kind == 1")
        }
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]

        return request
    }
}
