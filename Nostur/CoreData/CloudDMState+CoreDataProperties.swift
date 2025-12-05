//
//  CloudDMState+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/11/2023.
//
//

import Foundation
import CoreData


extension CloudDMState {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CloudDMState> {
        return NSFetchRequest<CloudDMState>(entityName: "CloudDMState")
    }

    @NSManaged public var accepted: Bool
    @NSManaged public var accountPubkey_: String?
    @NSManaged public var contactPubkey_: String?
    @NSManaged public var markedReadAt_: Date?
    @NSManaged public var isPinned: Bool
    @NSManaged public var isHidden: Bool
    
    public var conversationId: String {
        return ((accountPubkey_ ?? "") + "-" + (contactPubkey_ ?? ""))
    }
    
    static public func getConversationId(from pubkeys: Set<String>) -> String {
        return ("-" + (pubkeys.sorted().joined(separator: "")))
    }
}

extension CloudDMState: Identifiable {
    static func fetchByAccount(_ accountPubkey: String, context: NSManagedObjectContext) -> [CloudDMState] {
        let fr = CloudDMState.fetchRequest()
        fr.predicate = NSPredicate(format: "accountPubkey_ == %@", accountPubkey)
        return (try? context.fetch(fr)) ?? []
    }
    
    static func fetchExisting(_ accountPubkey: String, contactPubkey: String, context: NSManagedObjectContext) -> CloudDMState? {
        let fr = CloudDMState.fetchRequest()
        fr.predicate = NSPredicate(format: "accountPubkey_ == %@ AND contactPubkey_ == %@", accountPubkey, contactPubkey)
        return try? context.fetch(fr).first
    }
    
    static func fetchGroup(pubkeys: Set<String>, context: NSManagedObjectContext) -> CloudDMState? {
        let groupPubkeys = pubkeys.sorted().joined(separator: "")
        let fr = CloudDMState.fetchRequest()
        fr.predicate = NSPredicate(format: "accountPubkey_ = nil AND contactPubkey_ == %@", groupPubkeys)
        return try? context.fetch(fr).first
    }
    
    static func create(pubkeys: Set<String>, context: NSManagedObjectContext) -> CloudDMState {
        let newGroupDMSstate = CloudDMState(context: context)
        let groupPubkeys = pubkeys.sorted().joined(separator: "")
        newGroupDMSstate.contactPubkey_ = groupPubkeys
        return newGroupDMSstate
    }
    
    var unread: Int {
        guard let contactPubkey_ else { return 0 }
        guard let managedObjectContext else { return 0 }
        let allReceived = Event.fetchEventsBy(pubkey: contactPubkey_, andKind: 4, context: managedObjectContext)
        let unreadSince = markedReadAt_ ?? Date.distantPast
        
        return allReceived.count { $0.date > unreadSince }
    }
}
