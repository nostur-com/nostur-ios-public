//
//  CloudBlocked+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/11/2023.
//
//

import Foundation
import CoreData


extension CloudBlocked {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CloudBlocked> {
        return NSFetchRequest<CloudBlocked>(entityName: "CloudBlocked")
    }

    @NSManaged public var eventId_: String?
    @NSManaged public var pubkey_: String?
    @NSManaged public var word_: String?
    @NSManaged public var fixedName_: String?
    @NSManaged public var type_: String? // enum BlockType.rawValue. nil is "CONTACT"
    @NSManaged public var createdAt_: Date?

    public enum BlockType: String {
        case contact = "CONTACT"
        case post = "POST"
        case mutedWord = "WORD"
    }
}

extension CloudBlocked : Identifiable {
    
    public var eventId: String {
        get { eventId_ ?? "5370b27a59d88295ea5ce3bcbfbc977f4aafc36f368d2f0a1d72f0ae7d10af6f" }
        set { eventId_ = newValue }
    }
    
    public var pubkey: String {
        get { pubkey_ ?? "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798" }
        set { pubkey_ = newValue }
    }
    
    public var word: String {
        get { word_ ?? "" }
        set { word_ = newValue }
    }
    
    public var fixedName: String {
        get { fixedName_ ?? "" }
        set { fixedName_ = newValue }
    }
    
    public var type: BlockType {
        get {
            guard let type = type_ else { return .contact }
            if type == BlockType.post.rawValue {
                return .post
            }
            else if type == BlockType.mutedWord.rawValue {
                return .mutedWord
            }
            else if type == BlockType.contact.rawValue {
                return .contact
            }
            else {
                return .contact
            }
        }
        set { type_ = newValue.rawValue }
    }
    
    
    static func addBlock(pubkey: String, fixedName: String? = nil) {
        let block = CloudBlocked(context: Thread.isMainThread ? DataProvider.shared().viewContext : bg())
        block.createdAt_ = .now
        block.type = .contact
        block.pubkey = pubkey
        block.fixedName = fixedName ?? ""
    }
    
    static func addBlock(eventId: String, replyToRootId:String? = nil, replyToId: String? = nil) {
        let block = CloudBlocked(context: Thread.isMainThread ? DataProvider.shared().viewContext : bg())
        block.createdAt_ = .now
        block.type = .post
        block.eventId_ = eventId
        
        if let replyToRootId = replyToRootId, eventId != replyToRootId {
            let block = CloudBlocked(context: Thread.isMainThread ? DataProvider.shared().viewContext : bg())
            block.createdAt_ = .now
            block.type = .post
            block.eventId_ = replyToRootId
        }
        
        if let replyToId = replyToId, replyToId != replyToRootId {
            let block = CloudBlocked(context: Thread.isMainThread ? DataProvider.shared().viewContext : bg())
            block.createdAt_ = .now
            block.type = .post
            block.eventId_ = replyToId
        }
        
        DispatchQueue.main.async {
            sendNotification(.muteListUpdated)
        }
    }
    
    static func addBlock(word: String) {
        let block = CloudBlocked(context: Thread.isMainThread ? DataProvider.shared().viewContext : bg())
        block.createdAt_ = .now
        block.type = .mutedWord
        block.word_ = word
    }
    
    static func blockedPubkeys() -> Set<String> {
        let fr = CloudBlocked.fetchRequest()
        fr.predicate = NSPredicate(format: "type_ == %@", CloudBlocked.BlockType.contact.rawValue)
        return Set(((try? (Thread.isMainThread ? DataProvider.shared().viewContext : bg()).fetch(fr)) ?? []).compactMap { $0.pubkey_ })
    }
    
    static func fetchBlock(byPubkey pubkey: String, context: NSManagedObjectContext = context()) -> CloudBlocked? {
        let fr = CloudBlocked.fetchRequest()
        fr.predicate = NSPredicate(format: "type_ == %@ AND pubkey_ == %@", CloudBlocked.BlockType.contact.rawValue, pubkey)
        fr.fetchLimit = 1
        return try? context.fetch(fr).first
    }
    
    static func mutedRootIds() -> Set<String> {
        let fr = CloudBlocked.fetchRequest()
        fr.predicate = NSPredicate(format: "type_ == %@", CloudBlocked.BlockType.post.rawValue)
        return Set(((try? (Thread.isMainThread ? DataProvider.shared().viewContext : bg()).fetch(fr)) ?? []).compactMap { $0.eventId_ })
    }
}

// on iCloud all fields must be optional
// if for whatever reason we must return something, use this dummy event (should never happen):
/*
 {
   "content": "hello world",
   "created_at": 1699401137,
   "id": "5370b27a59d88295ea5ce3bcbfbc977f4aafc36f368d2f0a1d72f0ae7d10af6f",
   "kind": 1,
   "pubkey": "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
   "sig": "7b1abab9e617f4ef4252d47eb2a2fc6c2b5ad6c6ddb53f8d33647f4ad9a40ea9a96cead8b2ab8179816717e2c7abd6083a553fd3d51b4c7a30c0225bfe72214b",
   "tags": []
 }
 */
