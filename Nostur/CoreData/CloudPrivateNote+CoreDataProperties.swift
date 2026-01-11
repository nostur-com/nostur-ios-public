//
//  CloudPrivateNote+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/11/2023.
//
//

import Foundation
import CoreData


extension CloudPrivateNote {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CloudPrivateNote> {
        return NSFetchRequest<CloudPrivateNote>(entityName: "CloudPrivateNote")
    }

    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var json: String?
    @NSManaged public var type: String?
    @NSManaged public var eventId: String?
    @NSManaged public var pubkey: String?
    @NSManaged public var content: String? // Will be encrypted on iCloud
        
    enum PrivateNoteType: String {
        case post = "POST"
        case contact = "CONTACT"
    }
}

extension CloudPrivateNote : Identifiable {
    var createdAt_:Date {
        get { createdAt ?? Date.init(timeIntervalSince1970: 0.0) }
        set { createdAt = newValue }
    }
    
    var updatedAt_:Date {
        get { updatedAt ?? Date.init(timeIntervalSince1970: 0.0) }
        set { updatedAt = newValue }
    }
    
    var content_:String {
        get { content ?? "" }
        set { content = newValue }
    }
        
    var ago: String { createdAt_.agoString }
    
    // MARK: DB functions
    static func fetchAll(context: NSManagedObjectContext) -> [CloudPrivateNote] {
        let fr = CloudPrivateNote.fetchRequest()
        return (try? context.fetch(fr)) ?? []
    }
    
    
    static func createNewFor(_ post: Event, context:NSManagedObjectContext) -> CloudPrivateNote? {
        let privateNote = CloudPrivateNote(context: context)
        privateNote.type = CloudPrivateNote.PrivateNoteType.post.rawValue
        privateNote.updatedAt = Date.now
        privateNote.createdAt = Date.now
        privateNote.eventId = post.id
        privateNote.json = post.toNEvent().eventJson()
        privateNote.content = ""
        let postId = post.id
        do {
            try context.save()
            Task { @MainActor in
                AppState.shared.bgAppState.hasPrivateNoteEventIds.insert(postId)
            }
            return privateNote
        }
        catch {
            L.og.error("Problem saving new private note \(error)")
            return nil
        }
    }
    
    static func createNewFor(_ contact: Contact, context:NSManagedObjectContext) -> CloudPrivateNote? {
        let privateNote = CloudPrivateNote(context: context)
        privateNote.type = CloudPrivateNote.PrivateNoteType.contact.rawValue
        privateNote.updatedAt = Date.now
        privateNote.createdAt = Date.now
        privateNote.pubkey = contact.pubkey
        privateNote.json = Event.fetchReplacableEvent(0, pubkey: contact.pubkey, context: context)?.toNEvent().eventJson()
        privateNote.content = ""
        let contactPubkey = contact.pubkey
        do {
            try context.save()
            Task { @MainActor in
                AppState.shared.bgAppState.hasPrivateNoteContactPubkeys.insert(contactPubkey)

            }
            return privateNote
        }
        catch {
            L.og.error("Problem saving new private note \(error)")
            return nil
        }
    }
}
