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

    @NSManaged public var pubkey: String
    @NSManaged public var listId: String
    @NSManaged public var lastAppearedAtAnchor: String
    @NSManaged public var lastAppearedId: String?
    @NSManaged public var mostRecentAppearedId: String?
    @NSManaged public var updatedAt: Date
    @NSManaged public var unreadCount:Int64

}

extension ListState : Identifiable {

    static func fetchListState(_ pubkey:String, listId:String, context:NSManagedObjectContext) -> ListState? {
        let r = ListState.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \ListState.updatedAt, ascending: false)]
        r.predicate = NSPredicate(format: "pubkey == %@ AND listId = %@", pubkey, listId)
        return try? context.fetch(r).first
    }
}
