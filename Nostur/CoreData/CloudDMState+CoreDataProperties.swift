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
    @NSManaged public var accountPubkey_: String? // Who is viewing this conversation
    
    // old dms: single key (length 64) (after migrations should always be minimum 64+64)
    // new dms: concat(pubkey,pubkey,pubkey,...) including sender!
    @NSManaged public var contactPubkey_: String? // Who is part of this conversation (old: just receiver pubkey, new: .pubkey + p tags) (NIP-17 chat room)
    @NSManaged public var initiatorPubkey_: String? // sender of first received message,e for WoT filtering
    @NSManaged public var blurb_: String? // cache last message text for preview
    @NSManaged public var markedReadAt_: Date?
    @NSManaged public var isPinned: Bool
    @NSManaged public var isHidden: Bool
    
    public var conversationId: String {
        return Self.getConversationId(for: self.participantPubkeys)
    }
    
    static public func getConversationId(for participants: Set<String>) -> String {
        return participants.sorted().joined(separator: "")
    }
    
    // Should include sender pubkey, not just receivers
    var participantPubkeys: Set<String> {
        get {
            if let contactPubkey = contactPubkey_ {
                if contactPubkey.count == 64 {
                    return [contactPubkey]
                }
                if contactPubkey.count % 64 == 0 {
                    // split every 64 characters
                    var result = Set<String>()
                    var start = contactPubkey.startIndex

                    while start < contactPubkey.endIndex {
                        let end = contactPubkey.index(start, offsetBy: 64)
                        let chunk = String(contactPubkey[start..<end])
                        if isValidPubkey(chunk) {
                            result.insert(chunk)
                        }
                        start = end
                    }

                    return result
                }
            }
            return []
        }
        set {
            contactPubkey_ = newValue.sorted().joined(separator: "")
        }
    }
    
    var blurb: String {
        get {
            blurb_ ?? ""
        }
        set {
            blurb_ = newValue
        }
    }
}

extension CloudDMState: Identifiable {
    static func fetchByAccount(_ accountPubkey: String, context: NSManagedObjectContext) -> [CloudDMState] {
        let fr = CloudDMState.fetchRequest()
        fr.predicate = NSPredicate(format: "accountPubkey_ == %@", accountPubkey)
        return (try? context.fetch(fr)) ?? []
    }
    
    static func fetchByParticipants(participants: Set<String>, context: NSManagedObjectContext) -> [CloudDMState] {
        let fr = CloudDMState.fetchRequest()
        fr.predicate = NSPredicate(format: "contactPubkey_ == %@", participants.sorted().joined(separator: ""))
        return (try? context.fetch(fr)) ?? []
    }
    
    static func fetchByParticipants(participants: Set<String>, andAccountPubkey accountPubkey: String, context: NSManagedObjectContext) -> CloudDMState? {
        let fr = CloudDMState.fetchRequest()
        fr.predicate = NSPredicate(format: "accountPubkey_ == %@ AND contactPubkey_ == %@", accountPubkey, CloudDMState.getConversationId(for: participants))
        return try? context.fetch(fr).first
    }

//    static func fetchExisting(_ accountPubkey: String, participants: Set<String>, context: NSManagedObjectContext) -> CloudDMState? {
//        let fr = CloudDMState.fetchRequest()
//        fr.predicate = NSPredicate(format: "accountPubkey_ == %@ AND contactPubkey_ == %@", accountPubkey, participants.sorted().joined(separator: ""))
//        return try? context.fetch(fr).first
//    }
    
    static func create(accountPubkey: String, participants: Set<String>, context: NSManagedObjectContext) -> CloudDMState {
        let newGroupDMSstate = CloudDMState(context: context)
        newGroupDMSstate.accountPubkey_ = accountPubkey
        newGroupDMSstate.contactPubkey_ = participants.sorted().joined(separator: "")
        return newGroupDMSstate
    }
    
    var unread: Int {
        guard let contactPubkey_ else { return 0 }
        guard let managedObjectContext else { return 0 }
        let allReceived = Event.fetchEventsBy(pubkey: contactPubkey_, andKinds: [1,14], context: managedObjectContext)
        let unreadSince = markedReadAt_ ?? Date.distantPast
        
        return allReceived.count { $0.date > unreadSince }
    }
}
