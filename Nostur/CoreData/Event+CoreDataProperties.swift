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
import LightningDevKit

extension Event {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Event> {
        let fr = NSFetchRequest<Event>(entityName: "Event")
        fr.sortDescriptors = []
        return fr
    }
    
//    @nonobjc public class func fetchRequest2() -> NSFetchRequest<Event> {
//        let fr = NSFetchRequest<Event>(entityName: "Event")
//        fr.sortDescriptors = []
//        return fr
//    }
    
    @NSManaged public var insertedAt: Date // Needed for correct ordering of events in timeline
    
    @NSManaged public var content: String?
    @NSManaged public var created_at: Int64
    @NSManaged public var id: String?
    @NSManaged public var kind: Int64
    @NSManaged public var pubkey: String?
    @NSManaged public var sig: String?
    @NSManaged public var tagsSerialized: String?
    
    @NSManaged public var replyToRootId: String?
    @NSManaged public var replyToId: String?
    @NSManaged public var firstQuoteId: String?
    @NSManaged public var likes: Int64 // Cache
    @NSManaged public var liked: Bool // Cache
    @NSManaged public var isRepost: Bool // Cache
    @NSManaged public var repliesCount: Int64 // Cache
//    @NSManaged public var repliesCounter: Int64 // Better Cache?
    @NSManaged public var mentions: Int64 // Cache
    
    @NSManaged public var bookmarkedBy: Set<Account>?
    @NSManaged public var contact: Contact?
    @NSManaged public var replyTo: Event?
    @NSManaged public var replyToRoot: Event?
    @NSManaged public var firstQuote: Event?
    @NSManaged public var zapTally: Int64

    @NSManaged public var replies: Set<Event>?
//    // helper
//    var replies_: Set<Event> {
//        get { (replies as? Set<Event>) ?? [] }
//        set { replies = newValue as NSSet }
//    }
    
    var username: String {
        get {
            contact?.username ?? authorKey
        }
    }
    
    var name: String {
        get {
            contact?.display_name ?? contact?.username ?? authorKey
        }
    }
}

// MARK: Generated accessors for bookmarkedBy
extension Event {

    @objc(addBookmarkedByObject:)
    @NSManaged public func addToBookmarkedBy(_ value: Account)

    @objc(removeBookmarkedByObject:)
    @NSManaged public func removeFromBookmarkedBy(_ value: Account)

    @objc(addBookmarkedBy:)
    @NSManaged public func addToBookmarkedBy(_ values: NSSet)

    @objc(removeBookmarkedBy:)
    @NSManaged public func removeFromBookmarkedBy(_ values: NSSet)

}

// MARK: Generated accessors for replies
extension Event {
    
    @objc(addRepliesObject:)
    @NSManaged public func addToReplies(_ value: Event)

    @objc(removeRepliesObject:)
    @NSManaged public func removeFromReplies(_ value: Event)

    @objc(addReplies:)
    @NSManaged public func addToReplies(_ values: NSSet)

    @objc(removeReplies:)
    @NSManaged public func removeFromReplies(_ values: NSSet)

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
    
    var noteId:String {
        get {
            id != nil ? try! NIP19(prefix: "note", hexString: id!).displayString : "?"
        }
    }
    
    static func textNotes(byAuthorPubkey:String? = nil) -> NSFetchRequest<Event> {
        
        let request: NSFetchRequest<Event> = Event.fetchRequest()
        request.entity = Event.entity()
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
    static func setMetaDataEvents(byAuthorPubkey:String? = nil, context:NSManagedObjectContext) -> [Event]? {
        
        let request: NSFetchRequest<Event> = Event.fetchRequest()
        if (byAuthorPubkey != nil) {
            request.predicate = NSPredicate(format: "kind == 0 AND pubkey == %@", byAuthorPubkey!)
        }
        else {
            request.predicate = NSPredicate(format: "kind == 0")
        }
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
        
        return try? context.fetch(request)
    }
    
    static func contactListEvents(byAuthorPubkey:String? = nil, context:NSManagedObjectContext) -> [Event]? {
        
        let request: NSFetchRequest<Event> = Event.fetchRequest()
        if (byAuthorPubkey != nil) {
            request.predicate = NSPredicate(format: "kind == 3 AND pubkey == %@", byAuthorPubkey!)
        }
        else {
            request.predicate = NSPredicate(format: "kind == 3")
        }
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
        
        return try? context.fetch(request)
    }
    
    @discardableResult
    static func makePreviews(count: Int) -> [Event] {
        var events = [Event]()
        let viewContext = EventsProvider.preview.container.viewContext
        for index in 0..<count {
            let event = Event(context: viewContext)
            event.insertedAt = Date.now
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
    static func updateRepliesCountCache(_ tags:[NEventTag], context:NSManagedObjectContext) throws -> Bool {
        // NIP-10: Those marked with "reply" denote the id of the reply event being responded to.
        if let replyEtag = TagsHelpers(tags).replyToEtag() {
            let request = NSFetchRequest<Event>()
            request.entity = Event.entity()
            request.predicate = NSPredicate(format: "id == %@", replyEtag.id)
            request.fetchLimit = 1
            
            if let reactingToEvent = try context.fetch(request).first {
//                print("updating .replies for .id = \(String(describing: reactingToEvent.id))")
                reactingToEvent.repliesCount = reactingToEvent.repliesCount + 1
            }
        }
        
        // NIP-10: Those marked with "root" denote the root id of the reply thread being responded to.
//        if let rootEtag = TagsHelpers(tags).replyToRootEtag() {
//            if rootEtag.id != TagsHelpers(tags).replyToEtag()?.id { // dont increase counter if root reply id is same as reply id
//                let request = NSFetchRequest<Event>()
//                request.entity = Event.entity()
//                request.predicate = NSPredicate(format: "id == %@", rootEtag.id)
//                
//                if let reactingToEvent = try context.fetch(request).first {
////                    print("updating .replies for .id = \(String(describing: reactingToEvent.id))")
//                    reactingToEvent.replies = reactingToEvent.replies + 1
//                }
//            }
//        }
        return true
    }
    
    // NIP-25: The generic reaction, represented by the content set to a + string, SHOULD be interpreted as a "like" or "upvote".
    // NIP-25: The content MAY be an emoji, in this case it MAY be interpreted as a "like" or "dislike", or the client MAY display this emoji reaction on the post.
    static func updateLikeCountCache(_ tags:[NEventTag], content:String, context:NSManagedObjectContext) throws -> Bool {
        switch content {
        case "+","👍","🤙","❤️","🫂","🤗","😘","😍","💯","🤩":
            // # NIP-25: The last e tag MUST be the id of the note that is being reacted to.
            if let lastEtag = TagsHelpers(tags).eTags().last {
                let request = NSFetchRequest<Event>()
                request.entity = Event.entity()
                request.predicate = NSPredicate(format: "id == %@", lastEtag.id)
                request.fetchLimit = 1
                
                if let reactingToEvent = try context.fetch(request).first {
//                    print("updating .likes for .id = \(String(describing: reactingToEvent.id))")
                    reactingToEvent.likes = reactingToEvent.likes + 1
//                                            try reactingToEvent.managedObjectContext?.save()
                }
            }
        case "-":
            print("downvote")
        default:
            break
        }
        return true
    }
    
    
    static func updateZapTallyCache(_ event:Event, context:NSManagedObjectContext) -> Bool {
        let nEvent = event.toNEvent()
        
        // we need to have contact.zapperPubkey first... ughh
        let pTag = nEvent.tags.first { $0.type == "p" }
        guard pTag != nil else { return false }
        let contact = Contact.fetchByPubkey(pTag!.pubkey, context: context)
        guard contact != nil else { return false }
        guard contact!.zapperPubkey != nil else { return false }
        guard contact!.zapperPubkey! == event.pubkey! else { return false }
        
        
        // bolt11
        let bolt11tag = nEvent.tags.first { $0.type == "bolt11" }
        guard bolt11tag != nil else { return false }
        let invoice = Invoice.fromStr(s: bolt11tag!.otherInformation[0])
        guard invoice.getValue() != nil else { return false }
        
        // zapped event
        let eventTag = nEvent.tags.first { $0.type == "e" }
        guard eventTag != nil else { return false }
        let request = NSFetchRequest<Event>()
        request.entity = Event.entity()
        request.predicate = NSPredicate(format: "id == %@", eventTag!.id)
        request.fetchLimit = 1
        
        if let zappedEvent = try! context.fetch(request).first {
            zappedEvent.zapTally = zappedEvent.zapTally + Int64(((invoice.getValue()!.amountMilliSatoshis() ?? 0) / 1000))
        }
        return true
    }
    
    // NIP-10: Those marked with "mention" denote a quoted or reposted event id.
    static func updateMentionsCountCache(_ tags:[NEventTag], context:NSManagedObjectContext) throws -> Bool {
        // NIP-10: Those marked with "mention" denote a quoted or reposted event id.
        if let mentionEtags = TagsHelpers(tags).mentionEtags() {
            for etag in mentionEtags {
                let request = NSFetchRequest<Event>()
                request.entity = Event.entity()
                request.predicate = NSPredicate(format: "id == %@", etag.id)
                request.fetchLimit = 1
                
                if let reactingToEvent = try context.fetch(request).first {
//                    print("updating .mentions for .id = \(String(describing: reactingToEvent.id))")
                    reactingToEvent.mentions = reactingToEvent.mentions + 1
                }
            }
        }
        return true
    }
    
    
    func tags() -> [NEventTag]? {
        let decoder = JSONDecoder()
        
        if (tagsSerialized != nil) {
            guard let tags = try? decoder.decode([NEventTag].self, from: Data(tagsSerialized!.utf8)) else {
                return nil
            }
            
            return tags
        }
        else {
            return nil
        }
    }
    
    func contactPubkeys() -> [String]? {
        let decoder = JSONDecoder()
        
        if (tagsSerialized != nil) {
            guard let tags = try? decoder.decode([NEventTag].self, from: Data(tagsSerialized!.utf8)) else {
                return nil
            }
            
            return tags.filter { $0.type == "p" } .map { $0.pubkey }
        }
        else {
            return nil
        }
    }
    
    static func fetchEvent(id:String, context:NSManagedObjectContext) throws -> Event? {
        let request = NSFetchRequest<Event>()
        request.entity = Event.entity()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        request.fetchBatchSize = 1
        return try context.fetch(request).first
    }
    
    static func saveEvent(event:NEvent, context:NSManagedObjectContext) -> Event {
        let savedEvent = Event(context: context)
        savedEvent.insertedAt = Date.now
        savedEvent.id = event.id
        savedEvent.kind = Int64(event.kind.id)
        savedEvent.created_at = Int64(event.createdAt.timestamp)
        savedEvent.content = event.content
        savedEvent.sig = event.signature
        savedEvent.pubkey = event.publicKey
        savedEvent.likes = 0
        savedEvent.liked = false
        
        if (event.kind == .textNote && TagsHelpers(event.tags).replyToRootEtag() != nil) {
            savedEvent.replyToRootId = TagsHelpers(event.tags).replyToRootEtag()!.id
            
            let er = NSFetchRequest<Event>(entityName: "Event")
            er.predicate = NSPredicate(format: "id == %@", savedEvent.replyToRootId!)
            er.fetchLimit = 1
            er.sortDescriptors = []
            if let rootReply = try? context.fetch(er).first {
                savedEvent.replyToRoot = rootReply
//                rootReply.objectWillChange.send()
                // root heeft geen inverse
            }
        }
        if (event.kind == .textNote && TagsHelpers(event.tags).replyToEtag() != nil) {
            savedEvent.replyToId = TagsHelpers(event.tags).replyToEtag()!.id
            
            let er = NSFetchRequest<Event>(entityName: "Event")
            er.predicate = NSPredicate(format: "id == %@", savedEvent.replyToId!)
            er.fetchLimit = 1
            er.sortDescriptors = []
            if let reply = try? context.fetch(er).first {
                savedEvent.replyTo = reply
//                reply.objectWillChange.send()
                // TODO: inverse hier erbij of neit?
            }
        }
        
        if (event.kind == .repost) {
            savedEvent.isRepost = true
        }
        
        if (event.kind == .textNote && event.content == "#[0]") {
            if event.tags.count > 0 && event.tags[0].type == "e" {
                savedEvent.isRepost = true
            }
        }
        
        if ((event.kind == .repost || event.kind == .textNote) && TagsHelpers(event.tags).mentionEtags() != nil) {
            savedEvent.firstQuoteId = TagsHelpers(event.tags).mentionEtags()!.first!.id
            
            let er = NSFetchRequest<Event>(entityName: "Event")
            er.predicate = NSPredicate(format: "id == %@", savedEvent.firstQuoteId!)
            er.fetchLimit = 1
            er.sortDescriptors = []
            if let mentionedEvent = try? context.fetch(er).first {
                savedEvent.firstQuote = mentionedEvent
            }
        }
        
        // if other existing messages were replying, mentioning, reposting (to) this, fix the relation
        let pointingToEventReq = NSFetchRequest<Event>(entityName: "Event")
        pointingToEventReq.predicate = NSPredicate(format: "(kind == 1 OR kind == 6) AND (replyToId == %@ OR replyToRootId == %@ OR firstQuoteId == %@)", savedEvent.id!, savedEvent.id!, savedEvent.id!)
        pointingToEventReq.sortDescriptors = []
        if let pointingToEvents = try? context.fetch(pointingToEventReq) {
            for event in pointingToEvents {
                if (event.replyToId != nil) && (event.replyToId == savedEvent.id!) {
                    event.replyTo = savedEvent
                    event.objectWillChange.send()
                }
                if (event.replyToRootId != nil) && (event.replyToRootId == savedEvent.id!) {
                    event.replyToRoot = savedEvent
                    event.objectWillChange.send()
                }
                if (event.firstQuoteId != nil) && (event.firstQuoteId == savedEvent.id!) {
                    event.firstQuote = savedEvent
                    event.objectWillChange.send()
                }
            }
        }
        
        // set relation to Contact
        let cr = NSFetchRequest<Contact>(entityName: "Contact")
        cr.predicate = NSPredicate(format: "pubkey == %@", event.publicKey)
        cr.sortDescriptors = [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)]
        if let contact = try? context.fetch(cr).first {
            savedEvent.contact = contact
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let tagsSerialized = try? encoder.encode(event.tags)
        if (tagsSerialized != nil) {
            savedEvent.tagsSerialized = String(data: tagsSerialized!, encoding: .utf8)
        }
        
        return savedEvent
    }
    
    // TODO: Maybe [EVENT..] to Core Data ... to NEvent will not give a valid id or sig, because
    // data not exactly the same.
    func toNEvent() -> NEvent {
        var nEvent = NEvent(content: content!)
        nEvent.id = id!
        nEvent.publicKey = pubkey!
        nEvent.createdAt = NTimestamp(timestamp: Int(created_at))
        nEvent.kind = NEventKind(id: Int(kind))
        nEvent.tags = tags() ?? []
        nEvent.signature = sig!
        return nEvent
    }
    
    func getMetadataContent() throws -> NSetMetadata? {
        if kind != NEventKind.setMetadata.id {
            throw "Event is not kind 7"
        }
        let decoder = JSONDecoder()
        
        if (content != nil) {
            guard let setMetadata = try? decoder.decode(NSetMetadata.self, from: Data(content!.utf8)) else {
                return nil
            }
            
            return setMetadata
        }
        else {
            return nil
        }
    }
}
