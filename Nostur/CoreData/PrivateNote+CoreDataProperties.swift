//
//  PrivateNote+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/03/2023.
//
//

import Foundation
import CoreData

extension PrivateNote {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PrivateNote> {
        return NSFetchRequest<PrivateNote>(entityName: "PrivateNote")
    }

    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var content: String?
    @NSManaged public var by: Account?
    @NSManaged public var post: Event?
    @NSManaged public var contact: Contact?

}

extension PrivateNote : Identifiable {
    
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
    
    static func fetchByAccount(_ account:Account, andPost post:Event, context:NSManagedObjectContext) -> PrivateNote? {
        let fr = PrivateNote.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \PrivateNote.updatedAt, ascending: false)]
        fr.predicate = NSPredicate(format: "by == %@ AND post == %@", account, post)
        return try? context.fetch(fr).first
    }
    
    static func createNewFor(_ account:Account, andPost post:Event, context:NSManagedObjectContext) -> PrivateNote? {
        let privateNote = PrivateNote(context: context)
        privateNote.updatedAt = Date.now
        privateNote.createdAt = Date.now
        privateNote.by = account
        privateNote.post = post
        privateNote.content = ""
        do {
            try context.save()
            return privateNote
        }
        catch {
            L.og.error("Problem saving new private note \(error)")
            return nil
        }
    }
    
    static func createNewFor(_ account:Account, andContact contact:Contact, context:NSManagedObjectContext) -> PrivateNote? {
        let privateNote = PrivateNote(context: context)
        privateNote.updatedAt = Date.now
        privateNote.createdAt = Date.now
        privateNote.by = account
        privateNote.contact = contact
        privateNote.content = ""
        do {
            try context.save()
            return privateNote
        }
        catch {
            L.og.error("Problem saving new private note \(error)")
            return nil
        }
    }
}


struct PN: Identifiable {
    var id:NSManagedObjectID { post.objectID }
    let post:PrivateNote
}
