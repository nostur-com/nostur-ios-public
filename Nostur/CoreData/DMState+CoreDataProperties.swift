//
//  DMState+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/09/2023.
//
//

import Foundation
import CoreData

extension DMState {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<DMState> {
        let fr = NSFetchRequest<DMState>(entityName: "DMState")
        fr.sortDescriptors = []
        return fr
    }

    @NSManaged public var accountPubkey: String?
    @NSManaged public var contactPubkey: String?
    @NSManaged public var markedReadAt: Date?
    @NSManaged public var accepted: Bool

    static func fetchByAccount(_ accountPubkey:String, context: NSManagedObjectContext) -> [DMState] {
        let fr = DMState.fetchRequest()
        fr.predicate = NSPredicate(format: "accountPubkey == %@", accountPubkey)
        return (try? context.fetch(fr)) ?? []
    }
    
    static func fetchExisting(_ accountPubkey:String, contactPubkey:String, context: NSManagedObjectContext) -> DMState? {
        let fr = DMState.fetchRequest()
        fr.predicate = NSPredicate(format: "accountPubkey == %@ AND contactPubkey == %@", accountPubkey, contactPubkey)
        return try? context.fetch(fr).first
    }
    
    var unread:Int {
        guard let contactPubkey else { return 0 }
        guard let managedObjectContext else { return 0 }
        let allReceived = Event.fetchEventsBy(pubkey: contactPubkey, andKind: 4, context: managedObjectContext)
        let unreadSince = markedReadAt ?? Date(timeIntervalSince1970: 0)
        
        return allReceived.filter { $0.date > unreadSince }.count
    }
    
}

extension DMState : Identifiable {

}
