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
    
    // old dms: contactPubkey_: single key (length 64)
    // new dms: participantPubkeys_: concat(pubkey,pubkey,pubkey,...) including sender!
    @NSManaged public var contactPubkey_: String? // old: just receiver pubkey
    @NSManaged public var participantPubkeys_: String? // NEW: Who is part of this conversation  (.pubkey + p tags) (NIP-17 chat room)
    @NSManaged public var initiatorPubkey_: String? // sender of first received message,e for WoT filtering
    @NSManaged public var blurb_: String? // cache last message text for preview
    @NSManaged public var markedReadAt_: Date?
    @NSManaged public var lastMessageTimestamp_: Date?
    @NSManaged public var isPinned: Bool
    @NSManaged public var isHidden: Bool
    @NSManaged public var version: Int
    
    public var conversationId: String {
        return Self.getConversationId(for: self.participantPubkeys)
    }
    
    static public func getConversationId(for participants: Set<String>) -> String {
        return participants.sorted().joined(separator: "")
    }
    
    // Should include sender pubkey, not just receivers
    var participantPubkeys: Set<String> {
        get {
            if let participantPubkeys = participantPubkeys_, participantPubkeys.count % 64 == 0 {
                // split every 64 characters
                var result = Set<String>()
                var start = participantPubkeys.startIndex

                while start < participantPubkeys.endIndex {
                    let end = participantPubkeys.index(start, offsetBy: 64)
                    let chunk = String(participantPubkeys[start..<end])
                    if isValidPubkey(chunk) {
                        result.insert(chunk)
                    }
                    start = end
                }

                return result
            }
            else if let contactPubkey = contactPubkey_, isValidPubkey(contactPubkey) {
                return Set([accountPubkey_,contactPubkey].compactMap { $0 })
            }
            return []
        }
        set {
            participantPubkeys_ = newValue.sorted().joined(separator: "")
        }
    }
    
    var senderPubkey: String {
        accountPubkey_ ?? ""
    }
    
    var receiverPubkeys: Set<String> {
        participantPubkeys.subtracting([senderPubkey])
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
        fr.predicate = NSPredicate(format: "accountPubkey_ = %@ AND NOT contactPubkey_ = nil AND NOT contactPubkey_ = %@", accountPubkey, accountPubkey)
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \CloudDMState.lastMessageTimestamp_, ascending: false)]
        return (try? context.fetch(fr)) ?? []
    }
    
    static func fetchByParticipants(participants: Set<String>, context: NSManagedObjectContext) -> [CloudDMState] {
        let fr = CloudDMState.fetchRequest()
        fr.predicate = NSPredicate(format: "participantPubkeys_ == %@", participants.sorted().joined(separator: ""))
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \CloudDMState.lastMessageTimestamp_, ascending: false)]
        return (try? context.fetch(fr)) ?? []
    }
    
    static func fetchByParticipants(participants: Set<String>, andAccountPubkey accountPubkey: String, context: NSManagedObjectContext) -> CloudDMState? {
        let fr = CloudDMState.fetchRequest()
        fr.predicate = NSPredicate(format: "accountPubkey_ == %@ AND participantPubkeys_ == %@", accountPubkey, CloudDMState.getConversationId(for: participants))
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \CloudDMState.lastMessageTimestamp_, ascending: false)]
        return try? context.fetch(fr).first
    }
    
    static func create(accountPubkey: String, participants: Set<String>, context: NSManagedObjectContext) -> CloudDMState {
        let newGroupDMSstate = CloudDMState(context: context)
        newGroupDMSstate.accountPubkey_ = accountPubkey
        newGroupDMSstate.participantPubkeys = participants
        newGroupDMSstate.contactPubkey_ = participants.subtracting([accountPubkey]).first
        return newGroupDMSstate
    }
    
    var unread: Int {
        guard contactPubkey_ != nil || participantPubkeys_ != nil else { return 0 }
        guard let managedObjectContext else { return 0 }

        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        fr.predicate = NSPredicate(format: "kind IN %@ AND groupId == %@", [4,14], self.conversationId)
        let allReceived = (try? managedObjectContext.fetch(fr)) ?? []
        
        
        let unreadSince = markedReadAt_ ?? Date.distantPast
        
        return allReceived.count { $0.date > unreadSince }
    }
    
    func unread(for accountPubkey: String) -> Int {
        guard contactPubkey_ != nil || participantPubkeys_ != nil else { return 0 }
        guard let managedObjectContext else { return 0 }

        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        fr.predicate = NSPredicate(format: "kind IN %@ AND groupId == %@ AND NOT pubkey = %@", [4,14], self.conversationId, accountPubkey)
        let allReceived = (try? managedObjectContext.fetch(fr)) ?? []
        
        
        let unreadSince = markedReadAt_ ?? Date.distantPast
        
        return allReceived.count { $0.date > unreadSince }
    }
}
