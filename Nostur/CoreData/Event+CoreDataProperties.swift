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
    
    @NSManaged public var liked: Bool // Cache
    @NSManaged public var isRepost: Bool // Cache
    
//    @NSManaged public var repliesCounter: Int64 // Better Cache?
    
    
    // Counters (cached)
    @NSManaged public var likesCount: Int64 // Cache
    @NSManaged public var repliesCount: Int64 // Cache
    @NSManaged public var mentionsCount: Int64 // Cache
    @NSManaged public var zapsCount: Int64 // Cache
    
    @NSManaged public var bookmarkedBy: Set<Account>?
    @NSManaged public var contact: Contact?
    @NSManaged public var personZapping: Contact?
    @NSManaged public var replyTo: Event?
    @NSManaged public var replyToRoot: Event?
    @NSManaged public var firstQuote: Event?
    @NSManaged public var zapTally: Int64

    @NSManaged public var replies: Set<Event>?
    @NSManaged public var tags: NSOrderedSet?

//    // helper
//    var replies_: Set<Event> {
//        get { (replies as? Set<Event>) ?? [] }
//        set { replies = newValue as NSSet }
//    }
    
    // helper
    var replies_: [Event] {
        get { replies?.sorted(by: { $0.created_at < $1.created_at } ) ?? [] }
    }
    
    // helper
    var tags_:[Tag] {
        get { tags?.array as? [Tag] ?? [] }
    }
    
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

// MARK: Generated accessors for tags
extension Event {

   @objc(insertObject:inTagsAtIndex:)
   @NSManaged public func insertIntoTags(_ value: Tag, at idx: Int)

   @objc(removeObjectFromTagsAtIndex:)
   @NSManaged public func removeFromTags(at idx: Int)

   @objc(insertTags:atIndexes:)
   @NSManaged public func insertIntoTags(_ values: [Tag], at indexes: NSIndexSet)

   @objc(removeTagsAtIndexes:)
   @NSManaged public func removeFromTags(at indexes: NSIndexSet)

   @objc(replaceObjectInTagsAtIndex:withObject:)
   @NSManaged public func replaceTags(at idx: Int, with value: Tag)

   @objc(replaceTagsAtIndexes:withTags:)
   @NSManaged public func replaceTags(at indexes: NSIndexSet, with values: [Tag])

   @objc(addTagsObject:)
   @NSManaged public func addToTags(_ value: Tag)

   @objc(removeTagsObject:)
   @NSManaged public func removeFromTags(_ value: Tag)

   @objc(addTags:)
   @NSManaged public func addToTags(_ values: NSOrderedSet)

   @objc(removeTags:)
   @NSManaged public func removeFromTags(_ values: NSOrderedSet)

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
                reactingToEvent.objectWillChange.send()
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
                    reactingToEvent.likesCount = reactingToEvent.likesCount + 1
                    reactingToEvent.objectWillChange.send()
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
    
        if (1 == 2) {
            // Disable for now, because all zaps will be ignored because we havent fetched
            // zapperPubkey for anyone yet
            
            // TODO: Consider valid on import, to immediatly show amounts. Use seperate queue to fetch and verify zapperpubkey, then invalidate if wrong later.
            
        // we need to have contact.zapperPubkey first... ughh
        let pTag = nEvent.tags.first { $0.type == "p" }
        guard pTag != nil else { return false }
        let contact = Contact.fetchByPubkey(pTag!.pubkey, context: context)
        guard contact != nil else { return false }
        
        
            
            guard contact!.zapperPubkey != nil else { return false }
            guard contact!.zapperPubkey! == event.pubkey! else { return false }
        }
        
        
        // bolt11
        let bolt11tag:Tag? = event.tags_.first { $0.type == "bolt11" }
        guard bolt11tag?.index1 != nil else { return false }
        let invoice = Invoice.fromStr(s: bolt11tag!.index1!)
        guard invoice.getValue() != nil else { return false }
        
//        // description, zap request, to get zap from
//        let description:Tag? = event.tags_.first { $0.type == "description" }
//        guard description?.index1 != nil else { return false }
//        let decoder = JSONDecoder()
//        if let innerEvent = try? decoder.decode(NEvent.self, from: description!.index1!.data(using: .utf8, allowLossyConversion: false)!) {
//            if (try! innerEvent.verified()) {
//                
//            }
//        }
//        
        
        // zapped event
        let eventTag = nEvent.tags.first { $0.type == "e" }
        guard eventTag != nil else { return false }
        let request = NSFetchRequest<Event>()
        request.entity = Event.entity()
        request.predicate = NSPredicate(format: "id == %@", eventTag!.id)
        request.fetchLimit = 1
        
        if let zappedEvent = try! context.fetch(request).first {
            zappedEvent.zapTally = zappedEvent.zapTally + Int64(((invoice.getValue()!.amountMilliSatoshis() ?? 0) / 1000))
            zappedEvent.zapsCount = zappedEvent.zapsCount + 1
            zappedEvent.objectWillChange.send()
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
                    reactingToEvent.mentionsCount = reactingToEvent.mentionsCount + 1
                    reactingToEvent.objectWillChange.send()
                }
            }
        }
        return true
    }
    
    
    func oldTags() -> [NEventTag]? {
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
    
    
    static func extractAndSaveZapRequest(event:NEvent, context:NSManagedObjectContext) -> Event? {
        
        let description:NEventTag? = event.tags.first(where: { $0.type == "description" })
        guard description?.otherInformation[safe: 0] != nil else { return nil }
        
        let decoder = JSONDecoder()
        if let zapReqNEvent = try? decoder.decode(NEvent.self, from: description!.otherInformation[0].data(using: .utf8, allowLossyConversion: false)!) {
            
            if let existingZapReq = try! Event.fetchEvent(id: zapReqNEvent.id, context: context) {
                print("🔴 zap req already in db");
                return existingZapReq
            }
            
            do {
                guard try zapReqNEvent.verified() else { return nil }
                
                
                // CREATE ZAP REQUEST EVENT
                let zapRequest = Event(context: context)
                zapRequest.insertedAt = Date.now
                
                zapRequest.id = zapReqNEvent.id
                zapRequest.kind = Int64(zapReqNEvent.kind.id)
                zapRequest.created_at = Int64(zapReqNEvent.createdAt.timestamp)
                zapRequest.content = zapReqNEvent.content
                zapRequest.sig = zapReqNEvent.signature
                zapRequest.pubkey = zapReqNEvent.publicKey
                zapRequest.likesCount = 0
                zapRequest.liked = false
                
                // set relation to Contact
                let cr = NSFetchRequest<Contact>(entityName: "Contact")
                cr.predicate = NSPredicate(format: "pubkey == %@", zapReqNEvent.publicKey)
                cr.sortDescriptors = [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)]
                if let contact = try? context.fetch(cr).first {
                    zapRequest.contact = contact
                }
                
                let encoder = JSONEncoder()
                encoder.outputFormatting = .withoutEscapingSlashes
                let tagsSerialized = try? encoder.encode(zapReqNEvent.tags)
                if (tagsSerialized != nil) {
                    zapRequest.tagsSerialized = String(data: tagsSerialized!, encoding: .utf8)
                }
                
                return zapRequest
            }
            catch {
                print(error)
                return nil
            }
        }
        return nil
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
        savedEvent.likesCount = 0
        savedEvent.liked = false
        
        var zapRequest:Event?
        if event.kind == .zapNote {
            // save 9734 seperate
            // so later we can do --> event(9735).tags[type=description].event(9734).contact
            zapRequest = Event.extractAndSaveZapRequest(event: event, context:context)
        }
        
        // TAGS: do tags, for just .textNote? or all? or..?
        savedEvent.tags = NSOrderedSet(array:
        event.tags.map({ nTag in
            let tag = Tag(context: context)
            tag.type = nTag.type
            if (tag.type == "e") {
                tag.event = try? Event.fetchEvent(id: nTag.id, context: context)
            }
            else if (tag.type == "description" && zapRequest != nil) {
                tag.event = zapRequest
            }
            else if (tag.type == "p") {
                tag.contact = Contact.fetchByPubkey(nTag.pubkey, context: context)
            }
            tag.index1 = nTag.otherInformation[safe: 0]
            tag.index2 = nTag.otherInformation[safe: 1]
            tag.index3 = nTag.otherInformation[safe: 2]
            tag.index4 = nTag.otherInformation[safe: 3]
            
            return tag
        }))
        
        // TAGS INVERSE:
        let er = NSFetchRequest<Tag>(entityName: "Tag")
        er.predicate = NSPredicate(format: "type == 'e' AND index1 == %@", savedEvent.id!)
        if let tags = try? context.fetch(er) {
            for tag in tags {
                tag.event = savedEvent
                tag.objectWillChange.send()
            }
        }
        
        
        
        
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
        nEvent.tags = oldTags() ?? []
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
    
    static func zapsForEvent(_ id:String, context:NSManagedObjectContext) -> [Event] {
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        fr.predicate = NSPredicate(format: "kind == 9735 AND ANY tags.index1 == %@", id)
        
        return (try? context.fetch(fr)) ?? []
    }
}
