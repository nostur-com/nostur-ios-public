//
//  Event+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/01/2023.
//
//

import Foundation
import CoreData
import Compactor


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
    
    @NSManaged public var replyToRootId: String?
    @NSManaged public var replyToId: String?
    @NSManaged public var likes: Int64 // Cache
    @NSManaged public var replies: Int64 // Cache
    @NSManaged public var mentions: Int64 // Cache
}

extension Event : Identifiable {
    
    var date: Date {
        get {
           Date(timeIntervalSince1970: Double(created_at))
        }
    }
    
    var ago: String {
        get {
            let f = TimeCompactor(ifZero: nil, style: .short, roundSmallToWhole: true)
            return f.string(from: Double(Date.now.timeIntervalSince(date)) as NSNumber)!
        }
    }
    
    var authorKey: String {
        get {
            pubkey != nil ? String(pubkey!.prefix(5)) : "?:?"
        }
    }
    
    var noteText: String {
        get {
            content ?? "(empty note)"
        }
    }
    
    static func textNotes(byAuthorPubkey:String? = nil) -> NSFetchRequest<Event> {
        
        let request: NSFetchRequest<Event> = Event.fetchRequest()
        request.includesPendingChanges = false
        if (byAuthorPubkey != nil) {
            request.predicate = NSPredicate(format: "kind == 1 AND pubkey == %@", byAuthorPubkey!)
        }
        else {
            request.predicate = NSPredicate(format: "kind == 1")
        }
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
        
        return request
    }
    
    // GETTER for "setMetaData" Events. !! NOT A SETTER !!
    static func setMetaDataEvents(byAuthorPubkey:String? = nil) -> NSFetchRequest<Event> {
        
        let request: NSFetchRequest<Event> = Event.fetchRequest()
        if (byAuthorPubkey != nil) {
            request.predicate = NSPredicate(format: "kind == 0 AND pubkey == %@", byAuthorPubkey!)
        }
        else {
            request.predicate = NSPredicate(format: "kind == 0")
        }
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
        
        return request
    }
    
    static func contactListEvents(byAuthorPubkey:String? = nil) -> NSFetchRequest<Event> {
        
        let request: NSFetchRequest<Event> = Event.fetchRequest()
        if (byAuthorPubkey != nil) {
            request.predicate = NSPredicate(format: "kind == 3 AND pubkey == %@", byAuthorPubkey!)
        }
        else {
            request.predicate = NSPredicate(format: "kind == 3")
        }
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
        
        return request
    }
    
    @discardableResult
    static func makePreviews(count: Int) -> [Event] {
        var events = [Event]()
        let viewContext = EventsProvider.preview.container.viewContext
        for index in 0..<count {
            let event = Event(context: viewContext)
            event.pubkey = "pubkey\(index)" //rand from preview keys
            event.id = "id\(index)"
            event.created_at = Int64(Date().timeIntervalSinceNow)
            event.content = "Preview event"
            event.kind = 0
            event.sig = "ddd"
            events.append(event)
        }
        return events
    }
    
    // NIP-10: Those marked with "reply" denote the id of the reply event being responded to.
    // NIP-10: Those marked with "root" denote the root id of the reply thread being responded to.
    static func updateRepliesCountCache(_ tags:[NEventTag], context:NSManagedObjectContext) throws {
        // NIP-10: Those marked with "reply" denote the id of the reply event being responded to.
        if let replyEtag = TagsHelpers(tags).replyToEtag() {
            let request = NSFetchRequest<Event>()
            request.entity = Event.entity()
            request.predicate = NSPredicate(format: "id == %@", replyEtag.id)
            
            if let reactingToEvent = try context.fetch(request).first {
                print("updating .replies for .id = \(String(describing: reactingToEvent.id))")
                reactingToEvent.replies = reactingToEvent.replies + 1
            }
        }
        
        // NIP-10: Those marked with "root" denote the root id of the reply thread being responded to.
        if let rootEtag = TagsHelpers(tags).replyToRootEtag() {
            if rootEtag.id != TagsHelpers(tags).replyToEtag()?.id { // dont increase counter if root reply id is same as reply id
                let request = NSFetchRequest<Event>()
                request.entity = Event.entity()
                request.predicate = NSPredicate(format: "id == %@", rootEtag.id)
                
                if let reactingToEvent = try context.fetch(request).first {
                    print("updating .replies for .id = \(String(describing: reactingToEvent.id))")
                    reactingToEvent.replies = reactingToEvent.replies + 1
                }
            }
        }
    }
    
    // NIP-25: The generic reaction, represented by the content set to a + string, SHOULD be interpreted as a "like" or "upvote".
    // NIP-25: The content MAY be an emoji, in this case it MAY be interpreted as a "like" or "dislike", or the client MAY display this emoji reaction on the post.
    static func updateLikeCountCache(_ tags:[NEventTag], content:String, context:NSManagedObjectContext) throws {
        switch content {
        case "+","👍","🤙","❤️","🫂","🤗","😘","😍","💯","🤩":
            // # NIP-25: The last e tag MUST be the id of the note that is being reacted to.
            if let lastEtag = TagsHelpers(tags).eTags().last {
                let request = NSFetchRequest<Event>()
                request.entity = Event.entity()
                request.predicate = NSPredicate(format: "id == %@", lastEtag.id)
                
                if let reactingToEvent = try context.fetch(request).first {
                    print("updating .likes for .id = \(String(describing: reactingToEvent.id))")
                    reactingToEvent.likes = reactingToEvent.likes + 1
//                                            try reactingToEvent.managedObjectContext?.save()
                }
            }
        case "-":
            print("downvote")
        default:
            print("unhandled reaction")
        }
    }
    
    // NIP-10: Those marked with "mention" denote a quoted or reposted event id.
    static func updateMentionsCountCache(_ tags:[NEventTag], context:NSManagedObjectContext) throws {
        // NIP-10: Those marked with "mention" denote a quoted or reposted event id.
        if let mentionEtags = TagsHelpers(tags).mentionEtags() {
            for etag in mentionEtags {
                let request = NSFetchRequest<Event>()
                request.entity = Event.entity()
                request.predicate = NSPredicate(format: "id == %@", etag.id)
                
                if let reactingToEvent = try context.fetch(request).first {
                    print("updating .mentions for .id = \(String(describing: reactingToEvent.id))")
                    reactingToEvent.mentions = reactingToEvent.mentions + 1
                }
            }
        }
    }
}
