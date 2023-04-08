//
//  Even+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/01/2023.
//
//

import Foundation
import CoreData
import Compactor
//import LightningDevKit

extension Event {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Event> {
        let fr = NSFetchRequest<Event>(entityName: "Event")
        fr.sortDescriptors = []
        return fr
    }
    
    @NSManaged public var insertedAt: Date // Needed for correct ordering of events in timeline
    
    @NSManaged public var content: String?
    @NSManaged public var created_at: Int64
    @NSManaged public var id: String
    @NSManaged public var kind: Int64
    @NSManaged public var pubkey: String
    @NSManaged public var sig: String?
    @NSManaged public var tagsSerialized: String?
    @NSManaged public var relays: String
    
    @NSManaged public var replyToRootId: String?
    @NSManaged public var replyToId: String?
    @NSManaged public var firstQuoteId: String?
    
    @NSManaged public var liked: Bool // Cache
    @NSManaged public var reposted: Bool // Cache
    @NSManaged public var isRepost: Bool // Cache
    
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
    
    @NSManaged public var contacts: Set<Contact>?
    
    @NSManaged public var deletedById: String?


//    // helper
//    var replies_: Set<Event> {
//        get { (replies as? Set<Event>) ?? [] }
//        set { replies = newValue as NSSet }
//    }
    
    // helper
    var replies_: [Event] { replies?.sorted(by: { $0.created_at < $1.created_at } ) ?? [] }
    var username: String { contact?.username ?? authorKey }
    var name: String { contact?.authorName ?? authorKey }
    
    static func getParentEvents(_ event:Event) -> [Event] {
        let RECURSION_LIMIT = 35 // PREVENT SPAM THREADS
        var parentEvents = [Event]()
        var currentEvent:Event? = event
        var i = 0
        while (currentEvent != nil) {
            if i > RECURSION_LIMIT {
                break
            }
            if let replyTo = currentEvent?.replyTo {
                parentEvents.append(replyTo)
                currentEvent = replyTo
                i = i + 1
            }
            else {
                currentEvent = nil
            }
        }
        return parentEvents
            .sorted(by: { $0.created_at < $1.created_at })
    }
}

// MARK: Generated accessors for contacts
extension Event {

    @objc(addContactsObject:)
    @NSManaged public func addToContacts(_ value: Contact)

    @objc(removeContactsObject:)
    @NSManaged public func removeFromContacts(_ value: Contact)

    @objc(addContacts:)
    @NSManaged public func addToContacts(_ values: NSSet)

    @objc(removeContacts:)
    @NSManaged public func removeFromContacts(_ values: NSSet)

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
    
    var bookmarkedBy_:Set<Account> {
        get { bookmarkedBy ?? [] }
    }

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

// MARK: Generated accessors for zaps
extension Event {
//    @NSManaged public var zapFromRequestId: String? // We ALWAYS have zapFromRequest (it is IN the 9735, so not needed)
    @NSManaged public var zappedEventId: String?
    @NSManaged public var zappedContactPubkey: String?
    
    @NSManaged public var zapFromRequest: Event?
    @NSManaged public var zappedEvent: Event?
    @NSManaged public var zappedContact: Contact?
}

// MARK: Generated accessors for reactions
extension Event {
    @NSManaged public var reactionToId: String?
    @NSManaged public var reactionTo: Event?
}


// MARK: HELPERS FOR KIND 9735 (ZAPS)
extension Event {
    
//    // THE ZAP REQUEST (CREATED BY SENDER OF SATS)
//    var zapReq:Event? { // TODO: Fix somewhere, this cant be nil or zap is invalid, put where to properly fix this so we never have to "if zapReq != nil..."
//        get {
//            tags_.first(where: { $0.type == "description" })?.event
//        }
//    }
//
//    // THE NOTE THAT RECEIVED THE ZAP
//    // NIP-57: It MUST have either 0 or 1 e-tag
//    var zappedEvent:Event? {
//        tags_.filter { $0.type == "e" }.first?.event
//    }
//
//    // For when we dont have the zappedEvent yet, we should at least have the id
//    var zappedEventId:String? {
//        tags_.filter { $0.type == "e" }.first?.index1
//    }
//
//    // THE PERSON THAT RECEIVED THE ZAP
//    // NIP-57: It MUST have at least one p-tag
//    var zappedContact:Contact? {
//        get {
//            tags_.filter { $0.type == "p" }.first?.contact
//        }
//    }
//
//    // For when we dont have the zappedContact yet, we should at least have the id
//    var zappedContactId:String? {
//        tags_.filter { $0.type == "p" }.first?.index1
//    }
    
}

extension Event {
    
    var plainText:String {
        let textRenderer = TextRenderer(managedObjectContext, event: self)
        return textRenderer.copyPasteText(self, text: self.noteText)
    }
    
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
        String(pubkey.prefix(5))
    }
    
    var noteText: String {
        if kind == 4 {
            guard let account = NosturState.shared.account, let pk = account.privateKey, let encrypted = content else {
                return convertToHieroglyphs(text: "(Encrypted content)")
            }
            if pubkey == account.publicKey, let firstP = self.firstP() {
                return NKeys.decryptDirectMessageContent(withPrivateKey: pk, pubkey: firstP, content: encrypted) ?? "(Encrypted content)"
            }
            else {
                return NKeys.decryptDirectMessageContent(withPrivateKey: pk, pubkey: pubkey, content: encrypted) ?? "(Encrypted content)"
            }
        }
        else {
            return content ?? "(empty note)"
        }
    }
    
    var noteTextPrepared: String {
        let tags = fastTags
        guard tags.count > 0 else { return content ?? "" }
        
        var newText = content ?? ""
        for index in tags.indices {
            if (tags[index].0 == "e") {
                newText = newText.replacingOccurrences(of: String("#[\(index)]"), with: "nostr:\(note1(tags[index].1))")

            }
        }
        return newText
    }
    
    var noteId:String {
        try! NIP19(prefix: "note", hexString: id).displayString
    }
    
    var npub:String { try! NIP19(prefix: "npub", hexString: pubkey).displayString }
    
    
    static func textNotes(byAuthorPubkey:String? = nil) -> NSFetchRequest<Event> {
        
        let request: NSFetchRequest<Event> = Event.fetchRequest()
        request.entity = Event.entity()
        request.includesPendingChanges = false
        if (byAuthorPubkey != nil) {
            request.predicate = NSPredicate(format: "pubkey == %@ AND kind == 1", byAuthorPubkey!)
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
            request.predicate = NSPredicate(format: "pubkey == %@ AND kind == 0", byAuthorPubkey!)
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
    
    static func metadataEvent(byAuthorPubkey:String? = nil, context:NSManagedObjectContext) -> [Event]? {
        
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
    
    @discardableResult
    static func makePreviews(count: Int) -> [Event] {
        var events = [Event]()
        let viewContext = EventsProvider.preview.container.viewContext
        for index in 0..<count {
            let event = Event(context: viewContext)
            event.insertedAt = Date.now
            event.pubkey = "pubkey\(index)" //rand from preview keys
            event.id = "id\(index)"
            event.created_at = Int64(Date().timeIntervalSince1970)
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
        
        let replyEtag = TagsHelpers(tags).replyToEtag()
        
        if (replyEtag != nil) {
            let request = NSFetchRequest<Event>(entityName: "Event")
            request.entity = Event.entity()
            request.predicate = NSPredicate(format: "id == %@", replyEtag!.id)
            request.fetchLimit = 1
            
            if let reactingToEvent = try context.fetch(request).first {
//                print("updating .replies for .id = \(String(describing: reactingToEvent.id))")
                reactingToEvent.objectWillChange.send()
                reactingToEvent.repliesCount = reactingToEvent.repliesCount + 1
            }
        }
        let replyToRootEtag = TagsHelpers(tags).replyToRootEtag()
        
        // There is already a replyToRoot and not a replyToId, then replyToRootId should be counted
        if (replyToRootEtag != nil && replyEtag == nil) {
            let request = NSFetchRequest<Event>(entityName: "Event")
            request.entity = Event.entity()
            request.predicate = NSPredicate(format: "id == %@", replyToRootEtag!.id)
            request.fetchLimit = 1
            
            if let reactingToEvent = try context.fetch(request).first {
//                print("updating .replies for .id = \(String(describing: reactingToEvent.id))")
                reactingToEvent.objectWillChange.send()
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
    static func updateLikeCountCache(_ event:Event, content:String, context:NSManagedObjectContext) throws -> Bool {
        switch content {
        case "+","👍","🤙","❤️","🫂","🤗","😘","😍","💯","🤩","⚡️","🔥","💥","🚀":
            // # NIP-25: The last e tag MUST be the id of the note that is being reacted to.
                if let lastEtag = event.lastE() {
                let request = NSFetchRequest<Event>(entityName: "Event")
                request.entity = Event.entity()
                request.predicate = NSPredicate(format: "id == %@", lastEtag)
                request.fetchLimit = 1
                
                if let reactingToEvent = try context.fetch(request).first {
//                    print("updating .likes for .id = \(String(describing: reactingToEvent.id))")
                    reactingToEvent.objectWillChange.send()
                    reactingToEvent.likesCount = reactingToEvent.likesCount + 1
                    event.reactionTo = reactingToEvent
                    event.reactionToId = reactingToEvent.id
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
    
//        if (1 == 2) {
//            /*
//             TODO: Disabled for now, because all zaps will be ignored because we havent fetched zapperPubkey for anyone yet Consider valid on import, to immediatly show amounts. Use seperate queue to fetch and verify zapperpubkey, then invalidate if wrong later.
//             */
//            // we need to have contact.zapperPubkey first... ughh
//            let pTag = nEvent.tags.first { $0.type == "p" }
//            guard pTag != nil else { return false }
//            let contact = Contact.fetchByPubkey(pTag!.pubkey, context: context)
//            guard contact != nil else { return false }
//
//            guard contact!.zapperPubkey != nil else { return false }
//            guard contact!.zapperPubkey! == event.pubkey else { return false }
//        }
                
        // zapped event
        guard let firstE = nEvent.firstE() else { return false }
        let request = NSFetchRequest<Event>(entityName: "Event")
        request.entity = Event.entity()
        request.predicate = NSPredicate(format: "id == %@", firstE)
        request.fetchLimit = 1
        
        if let zappedEvent = try! context.fetch(request).first {
            zappedEvent.objectWillChange.send()
            zappedEvent.zapTally = zappedEvent.zapTally + Int64(event.naiveSats)
            zappedEvent.zapsCount = zappedEvent.zapsCount + 1
        }
        return true
    }
    
    // NIP-10: Those marked with "mention" denote a quoted or reposted event id.
    static func updateMentionsCountCache(_ tags:[NEventTag], context:NSManagedObjectContext) throws -> Bool {
        // NIP-10: Those marked with "mention" denote a quoted or reposted event id.
        if let mentionEtags = TagsHelpers(tags).mentionEtags() {
            for etag in mentionEtags {
                let request = NSFetchRequest<Event>(entityName: "Event")
                request.entity = Event.entity()
                request.predicate = NSPredicate(format: "id == %@", etag.id)
                request.fetchLimit = 1
                
                if let reactingToEvent = try context.fetch(request).first {
                    reactingToEvent.objectWillChange.send()
//                    print("updating .mentions for .id = \(String(describing: reactingToEvent.id))")
                    reactingToEvent.mentionsCount = reactingToEvent.mentionsCount + 1
                    
                }
            }
        }
        return true
    }
    
    var fastTags:[(String, String, String?)] {
        guard let tagsSerialized = tagsSerialized else { return [] }
        guard let jsonData = tagsSerialized.data(using: .utf8) else {
            return []
        }

        guard let jsonArray = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String]] else {
            return []
        }
        
        return jsonArray
//            .filter { $0.count >= 2 }
            .map { ($0[0], $0[safe: 1] ?? "WTF", $0[safe: 2]) }
    }
    
    
    func tags() -> [NEventTag] {
        let decoder = JSONDecoder()
        
        if (tagsSerialized != nil) {
            guard let tags = try? decoder.decode([NEventTag].self, from: Data(tagsSerialized!.utf8)) else {
                return []
            }
            
            return tags
        }
        else {
            return []
        }
    }
    
    func naiveBolt11() -> String? {
        let prefix = ###"["bolt11",""###
        let suffix = ###""]"###

        if let rangeStart = tagsSerialized!.range(of: prefix)?.upperBound,
           let rangeEnd = tagsSerialized!.range(of: suffix, range: rangeStart..<tagsSerialized!.endIndex)?.lowerBound {
            let extractedString = String(tagsSerialized![rangeStart..<rangeEnd])

            return extractedString
        }
        return nil
    }
    
    func bolt11() -> String? {
        tags().first(where: { $0.type == "bolt11" })?.otherInformation[safe: 0]
    }
    
    func firstP() -> String? {
        tags().first(where: { $0.type == "p" })?.pubkey
    }
    
    func firstE() -> String? {
        tags().first(where: { $0.type == "e" })?.id
    }
    
    func lastE() -> String? {
        tags().last(where: { $0.type == "e" })?.id
    }
    
    func lastP() -> String? {
        tags().last(where: { $0.type == "p" })?.pubkey
    }
    
    func pTags() -> [String] {
        tags().filter { $0.type == "p" }.map { $0.pubkey }
    }
    
    func firstA() -> String? {
        tags().first(where: { $0.type == "a" })?.value
    }
    
    func firstD() -> String? {
        tags().first(where: { $0.type == "d" })?.value
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
        let request = NSFetchRequest<Event>(entityName: "Event")
        request.entity = Event.entity()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        request.fetchBatchSize = 1
        return try context.fetch(request).first
    }
    
    static func fetchReplacableEvent(_ kind:Int64, pubkey:String, definition:String, context:NSManagedObjectContext) throws -> Event? {
        let request = NSFetchRequest<Event>(entityName: "Event")
        request.entity = Event.entity()
        request.predicate = NSPredicate(format: "kind == %d AND pubkey == %@ AND tagsSerialized CONTAINS %@", kind, pubkey, ###"[["d","###)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        let matches = try context.fetch(request).filter({ event in
            if let firstD = event.firstD() {
                return firstD == definition
            }
            return false
        })
        
        return matches.sorted(by: { $0.created_at > $1.created_at }).first
    }
    
    static func fetchProfileBadgesByATag(_ badgeA:String, context:NSManagedObjectContext) -> [Event] {
        // find and notify all kind 30008 where serialized tags contains
        // ["a","30009:aa77d356ac5a59dbedc78f0da17c6bdd3ae315778b5c78c40a718b5251391da6:test_badge"]
        // notify any related profile badge
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        fr.predicate = NSPredicate(format: "kind == 30008 AND tagsSerialized CONTAINS %@", badgeA)
        return (try? context.fetch(fr)) ?? []
    }

    
    static func eventExists(id:String, context:NSManagedObjectContext) -> Bool {
        let request = NSFetchRequest<Event>(entityName: "Event")
        request.entity = Event.entity()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.resultType = .countResultType
        request.fetchLimit = 1
        request.includesPropertyValues = false

        var count = 0
        do {
            count = try context.count(for: request)
        } catch {
            print("some error in eventExists()")
            print(error)
            return false
        }

        if count > 0 {
            return true
        }
        return false
    }
    
    
    static func extractZapRequest(tags:[NEventTag]) -> NEvent? {
        let description:NEventTag? = tags.first(where: { $0.type == "description" })
        guard description?.otherInformation[safe: 0] != nil else { return nil }
        
        let decoder = JSONDecoder()
        if let zapReqNEvent = try? decoder.decode(NEvent.self, from: description!.otherInformation[0].data(using: .utf8, allowLossyConversion: false)!) {
            do {
                
                // Its note in note, should we verify? is this verified by relays? or zapper? should be...
                guard try (!SettingsStore.shared.isSignatureVerificationEnabled) || (zapReqNEvent.verified()) else { return nil }
                
                return zapReqNEvent
            }
            catch {
                print(error)
                return nil
            }
        }
        return nil
    }
    
    static func saveZapRequest(event:NEvent, context:NSManagedObjectContext) -> Event? {
            if let existingZapReq = try! Event.fetchEvent(id: event.id, context: context) {
//                print("🔴 zap req already in db");
                return existingZapReq
            }
            
            // CREATE ZAP REQUEST EVENT
            let zapRequest = Event(context: context)
            zapRequest.insertedAt = Date.now
            
            zapRequest.id = event.id
            zapRequest.kind = Int64(event.kind.id)
            zapRequest.created_at = Int64(event.createdAt.timestamp)
            zapRequest.content = event.content
            zapRequest.sig = event.signature
            zapRequest.pubkey = event.publicKey
            zapRequest.likesCount = 0
            zapRequest.liked = false
            
            
            // set relation to Contact
            zapRequest.contact = Contact.fetchByPubkey(event.publicKey, context: context)

            zapRequest.tagsSerialized = TagSerializer.shared.encode(tags: event.tags)
            
            return zapRequest
    }
    
    static func updateRelays(_ id:String, relay: String) {
        let request = NSFetchRequest<Event>(entityName: "Event")
        request.entity = Event.entity()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        request.fetchBatchSize = 1
        
        let bg = DataProvider.shared().newTaskContext()
        bg.perform {
            if let event = try? bg.fetch(request).first {
                var relays = event.relays.split(separator: " ").map { String($0) }
                relays.append(relay)
                let uniqueRelays = Set(relays)
                event.relays = uniqueRelays.joined(separator: " ")
                if bg.hasChanges {
                    do {
                        try bg.save()
                    }
                    catch {
                        print("🔴🔴 error updateRelays \(error)")
                    }
                }
            }
        }
    }
    
    static func saveEvent(event:NEvent, context:NSManagedObjectContext, relay:String? = nil) -> Event {
        
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
        savedEvent.isRepost = event.kind == .repost
        savedEvent.contact = Contact.fetchByPubkey(event.publicKey, context: context)
        savedEvent.tagsSerialized = TagSerializer.shared.encode(tags: event.tags)
        savedEvent.relays = relay ?? ""
        
        if event.kind == .profileBadges {
            savedEvent.contact?.objectWillChange.send()
        }
        
//        if event.kind == .badgeAward {
//            // find and notify all kind 30008 where serialized tags contains
//            // ["a","30009:aa77d356ac5a59dbedc78f0da17c6bdd3ae315778b5c78c40a718b5251391da6:test_badge"]
//            // notify any related profile badge
//            let profileBadges = Event.fetchProfileBadgesByATag(event.badgeA, context:context)
//            for pb in profileBadges {
//                pb.objectWillChange.send()
//            }
////            sendNotification(.badgeAwardFetched)
//        }
        if event.kind == .badgeDefinition {
            // notify any related profile badge
            savedEvent.contact?.objectWillChange.send()
            let profileBadges = Event.fetchProfileBadgesByATag(event.badgeA, context:context)
            for pb in profileBadges {
                pb.objectWillChange.send()
            }
//            sendNotification(.badgeDefinitionFetched)
        }
        
        if event.kind == .zapNote {
            //TODO: Do we need any objectWillChange.send() here??
            
            // save 9734 seperate
            // so later we can do --> event(9735).zappedEvent(9734).contact
            let nZapRequest = Event.extractZapRequest(tags: event.tags)
            if (nZapRequest != nil) {
                let zapRequest = Event.saveZapRequest(event: nZapRequest!, context: context)
                
                savedEvent.zapFromRequest = zapRequest
                if let firstE = event.firstE() {
                    savedEvent.objectWillChange.send()
                    savedEvent.zappedEventId = firstE
                    savedEvent.zappedEvent = try? Event.fetchEvent(id: firstE, context: context)
                }
                if let firstP = event.firstP() {
                    savedEvent.objectWillChange.send()
                    savedEvent.zappedContactPubkey = firstP
                    savedEvent.zappedContact = Contact.fetchByPubkey(firstP, context: context)
                }
            }
            
            // bolt11 -- replaced with naiveBolt11Decoder
//            if let bolt11 = event.bolt11() {
//                let invoice = Invoice.fromStr(s: bolt11)
//                if let parsedInvoice = invoice.getValue() {
//                    savedEvent.cachedSats = Double((parsedInvoice.amountMilliSatoshis() ?? 0) / 1000)
//                }
//            }
        }
        
        if event.kind == .reaction {
            if let lastE = event.lastE() {
                savedEvent.objectWillChange.send()
                savedEvent.reactionToId = lastE
                savedEvent.reactionTo = try? Event.fetchEvent(id: lastE, context: context)
            }
            
            // TODO: dont need this?
//            if let lastP = event.lastP() {
//                savedEvent.reactionToContactId = lastP
//                savedEvent.reactionToContact = Contact.fetchByPubkey(lastP, context: context)
//            }
        }
        
        if (event.kind == .textNote) {
            // THIS EVENT REPLYING TO SOMETHING
            // CACHE THE REPLY "E" IN replyToId
            if let replyToEtag = event.replyToEtag() {
                savedEvent.replyToId = replyToEtag.id
                
                // IF WE ALREADY HAVE THE PARENT, ADD OUR NEW EVENT IN THE REPLIES
                if let replyTo = try? Event.fetchEvent(id: replyToEtag.id, context: context) {
                    savedEvent.replyTo = replyTo
                    
                    replyTo.objectWillChange.send()
                    replyTo.addToReplies(savedEvent)
                    replyTo.repliesCount += 1
                }
            }
            
            // IF THE THERE IS A ROOT, AND ITS NOT THE SAME AS THE REPLY TO
            // DO THE SAME AS WITH THE REPLY BEFORE
            if let replyToRootEtag = event.replyToRootEtag() {
                if (replyToRootEtag.id != savedEvent.replyToId) { // If reply root is same as reply, dont double add.
                    savedEvent.replyToRootId = replyToRootEtag.id
                    if (savedEvent.replyToId == nil) { // IF IT HAS ONLY A ROOT REPLY, NO NORMAL REPLY: THEN REPLYTOROOT = REPLYTO
                        savedEvent.replyToId = replyToRootEtag.id
                        
                        // IF WE ALREADY HAVE THE PARENT, ADD OUR NEW EVENT IN THE REPLIES
                        if let replyToRoot = try? Event.fetchEvent(id: replyToRootEtag.id, context: context) {
                            savedEvent.replyTo = replyToRoot // NO REPLYTO, SO REPLYTOROOT IS THE REPLYTO
                            
                            replyToRoot.objectWillChange.send()
                            replyToRoot.addToReplies(savedEvent)
                            replyToRoot.repliesCount += 1
                        }
                    }
                }
            }
              
//            let pPubkeys = event.pTags()
//            if pPubkeys.count > 0 {
//                let pContacts = Contact.fetchRequest()
//                pContacts.predicate = NSPredicate(format: "pubkey IN %@", pPubkeys)
//                let contacts = Array(try! context.fetch(pContacts))
//                for contact in contacts {
//                    savedEvent.objectWillChange.send()
//                    savedEvent.addToContacts(contact)
//                }
//            }
            
            if (event.content == "#[0]" && event.tags.count > 0 && event.tags[0].type == "e") {
                savedEvent.isRepost = true
            }
            
            // NEw: Save all p's in .contacts
            // Maybe slow??
            let contacts = Contact.ensureContactsCreated(event: event, context: context)
//            savedEvent.objectWillChange.send()
            savedEvent.addToContacts(NSSet(array: contacts))
//            for contact in contacts {
//                savedEvent.addToContacts(contact)
//            }
        }
        
        if (event.kind == .directMessage) { // needed to fetch contact in DMS: so event.firstP is in event.contacts
            let contacts = Contact.ensureContactsCreated(event: event, context: context)
            savedEvent.addToContacts(NSSet(array: contacts))
//            for contact in contacts {
//                savedEvent.addToContacts(contact)
//            }
        }
        
        // handle REPOST with normal mentions in .kind 1
        // todo handle first nostr:nevent or not?
        var alreadyCounted = false
        if event.kind == .textNote, let firstE = event.firstMentionETag() {
            savedEvent.firstQuoteId = firstE.id
            
            // IF WE ALREADY HAVE THE FIRST QUOTE, ADD OUR NEW EVENT IN THE MENTIONS
            if let firstQuote = try? Event.fetchEvent(id: savedEvent.firstQuoteId!, context: context) {
                savedEvent.firstQuote = firstQuote
                
                if (firstE.otherInformation[safe: 2] == "mention") {
                    firstQuote.objectWillChange.send()
                    firstQuote.mentionsCount += 1
                    alreadyCounted = true
                }
            }
        }
        
        // hmm above firstQuote doesn't seem to handle #[0] at .content end and "e" without "mention as first tag, so special case?
        if !alreadyCounted && event.kind == .textNote && event.content.contains("#[0]"), let firstE = event.firstE() {
            savedEvent.firstQuoteId = firstE
            
            // IF WE ALREADY HAVE THE FIRST QUOTE, ADD OUR NEW EVENT IN THE MENTIONS
            if let firstQuote = try? Event.fetchEvent(id: savedEvent.firstQuoteId!, context: context) {
                savedEvent.firstQuote = firstQuote
                
                firstQuote.objectWillChange.send()
                firstQuote.mentionsCount += 1
            }
        }
        
        // kind6 sigh
        if event.kind == .repost, let firstE = event.firstE() {
            savedEvent.firstQuoteId = firstE
            
            // IF WE ALREADY HAVE THE FIRST QUOTE, ADD OUR NEW EVENT IN THE MENTIONS
            if let firstQuote = try? Event.fetchEvent(id: savedEvent.firstQuoteId!, context: context) {
                savedEvent.firstQuote = firstQuote
                
                firstQuote.objectWillChange.send()
                firstQuote.mentionsCount += 1
            }
        }
        
        
        if (1 == 1 && event.kind == .textNote) { // TODO: Temp disabled for speed up check..
            // if other existing messages were replying, mentioning, reposting (to) this, fix the relation
            let pointingToEventReq = NSFetchRequest<Event>(entityName: "Event")
            //        pointingToEventReq.predicate = NSPredicate(format: "(kind IN {1,6} AND  (replyToId == %@ OR replyToRootId == %@ OR firstQuoteId == %@)", savedEvent.id, savedEvent.id, savedEvent.id)
            pointingToEventReq.predicate = NSPredicate(format: "kind IN {1,6} AND %@ IN {replyToId,replyToRootId,firstQuoteId}", savedEvent.id)
            // TODO: NEED 6 ALSO OR NOT?
//            pointingToEventReq.predicate = NSPredicate(format: "kind IN {1,6} AND %@ IN {replyToId,replyToRootId,firstQuoteId}", savedEvent.id)
            pointingToEventReq.sortDescriptors = []
            if let pointingToEvents = try? context.fetch(pointingToEventReq) { // TODO: SLOW?? Maybe only do this when opening the 1 or 6 instead of here.
                for event in pointingToEvents {
                    if (event.replyToId != nil) && (event.replyToId == savedEvent.id) {
                        event.objectWillChange.send()
                        event.replyTo = savedEvent
                    }
                    if (event.replyToRootId != nil) && (event.replyToRootId == savedEvent.id) {
                        event.objectWillChange.send()
                        event.replyToRoot = savedEvent
                    }
                    if (event.firstQuoteId != nil) && (event.firstQuoteId == savedEvent.id) {
                        event.objectWillChange.send()
                        event.firstQuote = savedEvent
                    }
                }
            }
        }
        
        if (event.kind == .contactList) {
            // delete older events
            let r = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
            r.predicate = NSPredicate(format: "kind == 3 AND pubkey == %@ AND insertedAt < %@", event.publicKey, savedEvent.insertedAt as NSDate)
            let batchDelete = NSBatchDeleteRequest(fetchRequest: r)
            batchDelete.resultType = .resultTypeCount
            
            do {
                _ = try context.execute(batchDelete) as! NSBatchDeleteResult
            } catch {
                print("🔴🔴 Failed to delete older kind 3 events")
            }
        }
        
        if event.kind == .delete {
            let eventIdsToDelete = event.eTags()
            
            let eventIdsToDeleteReq = NSFetchRequest<Event>(entityName: "Event")
            eventIdsToDeleteReq.predicate = NSPredicate(format: "kind IN {1,6} AND id IN %@", eventIdsToDelete)
            eventIdsToDeleteReq.sortDescriptors = []
            if let eventsToDelete = try? context.fetch(eventIdsToDeleteReq) {
                for d in eventsToDelete {
                    if (d.pubkey == event.publicKey) {
                        d.objectWillChange.send()
                        d.deletedById = event.id
                    }
                }
            }
        }
        
        return savedEvent
    }
    
    // Lets hope Event (Core Data) to nEvent will always keep correct id/sig and not lose integrity due to different storage
    func toNEvent() -> NEvent {
        var nEvent = NEvent(content: content!)
        nEvent.id = id
        nEvent.publicKey = pubkey
        nEvent.createdAt = NTimestamp(timestamp: Int(created_at))
        nEvent.kind = NEventKind(id: Int(kind))
        nEvent.tags = tags()
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
        fr.predicate = NSPredicate(format: "zappedEventId == %@ AND kind == 9735", id)
        
        return (try? context.fetch(fr)) ?? []
    }
    
//    func toVPost(pubkey: String? = nil, context: NSManagedObjectContext? = nil) -> VPost {
//        let p = pubkey ?? NosturState.shared.activeAccountPublicKey
////        let ctx = context ?? managedObjectContext ?? DataProvider.shared().viewContext
//        var vPost:VPost?
//        if (Thread.isMainThread) {
//            let vTransformer = VTransformer(pubkey: p)
//            vPost = vTransformer.eventToVPost(self)
//        }
//        else {
//            let bg = DataProvider.shared().bg
//            bg.performAndWait {
//                let vTransformer = VTransformer(pubkey: p)
//                vPost = vTransformer.eventToVPost(self)
//            }
//        }
//        return vPost!
//    }
}


extension DataProvider {
    func fetchEvent(id:String, context:NSManagedObjectContext? = nil) throws -> Event? {
        let request = NSFetchRequest<Event>(entityName: "Event")
        request.entity = Event.entity()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        request.fetchBatchSize = 1
        return try (context ?? viewContext).fetch(request).first
    }
}


// FIX ALL REPLY MENTION ROOT DETECTION ETC
extension NEvent {
    
    
    var mentionOnlyTags:[NEventTag] {
        let matches = content.matches(of: /#\[(\d+)\]/)
        let matchIndexes = matches.compactMap { Int($0.output.1) }
        let t = tags.enumerated().filter { matchIndexes.contains($0.offset) }.map { $0.element }
        let noRootOrReply = t.filter {
            $0.type == "e" && $0.otherInformation[safe: 2] != "root" && $0.otherInformation[safe: 2] != "reply"
        }
        return noRootOrReply
    }
    
    var threadETags:[NEventTag] {
        let mentionStrings = mentionOnlyTags.map { $0.id }
        return tags.filter {
            $0.type == "e" && !mentionStrings.contains($0.id)
        }
    }
    
    // E TAGS
    func replyToEtag() -> NEventTag? {
        if threadETags.count == 0 {
            return nil
        }
        // PREFERRED NEW METHOD
        // NIP-10: Those marked with "reply" denote the id of the reply event being responded to.
        let replyEtags = threadETags.filter { $0.otherInformation.count == 3 && $0.otherInformation[safe: 2] == "reply" }
        if (replyEtags.count != 0) {
            return replyEtags.first
        }

        // OLD METHOD NIP-10:
        // One "e" tag = REPLY
        if threadETags.count == 1 && (threadETags.first?.otherInformation[safe: 2] == nil) {
            return threadETags.first
        }
        
        // OLD METHOD NIP-10:
        // Two "e" tags: FIRST = ROOT, LAST = REPLY
        // Many "e" tags: SAME
        if (threadETags.count >= 2) {
            return threadETags.last
        }
        return nil
    }
    
    func replyToRootEtag() -> NEventTag? {
        if threadETags.count == 0 {
            return nil
        }
        let rootEtag = threadETags.filter { $0.otherInformation.count == 3 && $0.otherInformation[safe: 2] == "root" }.first
        // PREFERRED NEW METHOD
        if (rootEtag != nil) {
            return rootEtag
        }

        // OLD METHOD
        if threadETags.count == 1 && (threadETags.first?.otherInformation[safe: 2] == nil) {
            return threadETags.first

        }
        if (threadETags.count >= 2) && (threadETags.first?.otherInformation[safe: 2] == nil) {
            return threadETags.first

        }
        return nil
    }
    
    func firstMentionETag() -> NEventTag? {
        if mentionOnlyTags.count == 0 {
            return nil
        }
        return mentionOnlyTags.first
    }
}
