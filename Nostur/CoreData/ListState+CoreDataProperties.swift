//
//  ListState+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/03/2023.
//
//

import Foundation
import CoreData

extension ListState {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ListState> {
        return NSFetchRequest<ListState>(entityName: "ListState")
    }

    @NSManaged public var pubkey: String?
    @NSManaged public var listId: String
    @NSManaged public var lastAppearedAtAnchor: String
    @NSManaged public var lastAppearedId: String?
    @NSManaged public var mostRecentAppearedId: String?
    @NSManaged public var updatedAt: Date
    @NSManaged public var unreadCount:Int64
    @NSManaged public var leafs: String?
    @NSManaged public var hideReplies: Bool

}

extension ListState : Identifiable {
    
    var leafIds:[String] {
        if let leafs = self.leafs {
            return leafs.split(separator: ",").map { String($0) }
        }
        return []
    }

    static func fetchListState(_ pubkey:String? = nil, listId:String, context:NSManagedObjectContext) -> ListState? {
        let r = ListState.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \ListState.updatedAt, ascending: false)]
        if let pubkey {
            r.predicate = NSPredicate(format: "pubkey == %@ AND listId = %@", pubkey, listId)
        }
        else {
            r.predicate = NSPredicate(format: "listId = %@", listId)
        }
        return try? context.fetch(r).first
    }
}
