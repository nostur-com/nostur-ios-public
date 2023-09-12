//
//  Even+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/01/2023.
//
//

import Foundation
import CoreData

// TODO: This file is too long, needs big refactor
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
    @NSManaged public var repostForId: String? // for tracking if we resposted or not (footer icon)
    
    @NSManaged public var isRepost: Bool // Cache
    
    // Counters (cached)
    @NSManaged public var likesCount: Int64 // Cache
    @NSManaged public var repostsCount: Int64 // Cache
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
    @NSManaged public var dTag: String
    
    var aTag:String { (String(kind) + ":" + pubkey  + ":" + dTag) }
    
    // For events with multiple versions (like NIP-33)
    // Most recent version should be nil
    // All older versions have a pointer to the most recent id
    // This makes it easy to query for the most recent event (mostRecentId = nil)
    @NSManaged public var mostRecentId: String?
    
    
    // Can be used for anything
    // Now we use it for:
    // - "is_update": to not show same article over and over in feed when it gets updates
    @NSManaged public var flags: String
    
    var contacts_:[Contact] {
        get { Array(contacts ?? [])  }
        set { contacts = Set(newValue) }
    }
    
    var hasMissingContacts:Bool {
        (contacts?.count ?? 0) < fastTags.filter({ $0.0 == "p" }).count
    }
    
    var reactionTo_:Event? {
        guard reactionTo == nil else { return reactionTo }
        guard let reactionToId = reactionToId else { return nil }
        guard let ctx = managedObjectContext else { return nil }
        if let found = try? Event.fetchEvent(id: reactionToId, context: ctx) {
//            self.objectWillChange.send()
            self.reactionTo = found
            return found
        }
        return nil
    }
    
    var contact_:Contact? {
        guard contact == nil else { return contact }
        guard let ctx = managedObjectContext else { return nil }
        if let found = Contact.fetchByPubkey(pubkey, context: ctx) {
            if Thread.isMainThread {
                found.objectWillChange.send()
                self.contact = found
                found.addToEvents(self)
            }
            else {
                self.contact = found
                found.addToEvents(self)
            }
            return found
        }
        return nil
    }
    
    var replyTo_:Event? {
        guard replyTo == nil else { return replyTo }
        if replyToId == nil && replyToRootId != nil { // Only replyToRootId? Treat as replyToId
            replyToId = replyToRootId
        }
        guard let replyToId = replyToId else { return nil }
        guard let ctx = managedObjectContext else { return nil }
        if let found = try? Event.fetchEvent(id: replyToId, context: ctx) {
            self.replyTo = found
            found.addToReplies(self)
            return found
        }
        return nil
    }
    
    var replyTo__:Event? {
        guard replyTo == nil else { return replyTo }
        if replyToId == nil && replyToRootId != nil { // Only replyToRootId? Treat as replyToId
            replyToId = replyToRootId
        }
        guard let replyToId = replyToId else { return nil }
        guard let ctx = managedObjectContext else { return nil }
        if let found = try? Event.fetchEvent(id: replyToId, context: ctx) {
            self.replyTo = found
            found.addToReplies(self)
            return found
        }
        return nil
    }
    
    var firstQuote_:Event? {
        guard firstQuote == nil else { return firstQuote }
        guard let firstQuoteId = firstQuoteId else { return nil }
        guard let ctx = managedObjectContext else { return nil }
        if let found = try? Event.fetchEvent(id: firstQuoteId, context: ctx) {
            self.firstQuote = found
            return found
        }
        return nil
    }

    var replies_: [Event] { Array(replies ?? []) }

    // Gets all parents. If until(id) is set, it will stop and wont traverse further, to prevent rendering duplicates
    static func getParentEvents(_ event:Event, fixRelations:Bool = false, until:String? = nil) -> [Event] {
        let RECURSION_LIMIT = 35 // PREVENT SPAM THREADS
        var parentEvents = [Event]()
        var currentEvent:Event? = event
        var i = 0
        while (currentEvent != nil) {
            if i > RECURSION_LIMIT {
                break
            }
            
            if until != nil && currentEvent!.replyToId == until {
                break
            }
            
            if let replyTo = fixRelations ? currentEvent?.replyTo__ : currentEvent?.replyTo {
                parentEvents.append(replyTo)
                currentEvent = replyTo
                i = (i + 1)
            }
            else {
                currentEvent = nil
            }
        }
        return parentEvents
            .sorted(by: { $0.created_at < $1.created_at })
    }
    
    func toMain() -> Event? {
        if Thread.isMainThread {
            return DataProvider.shared().viewContext.object(with: self.objectID) as? Event
        }
        else {
            return DispatchQueue.main.sync {
                return DataProvider.shared().viewContext.object(with: self.objectID) as? Event
            }
        }
    }
    
    func toBG() -> Event? {
        if Thread.isMainThread {
            L.og.info("🔴🔴🔴 toBG() should be in bg already, switching now but should fix code")
            return DataProvider.shared().bg.performAndWait {
                return DataProvider.shared().bg.object(with: self.objectID) as? Event
            }
        }
        else {
            return DataProvider.shared().bg.object(with: self.objectID) as? Event
        }
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
    @NSManaged public var otherPubkey: String?
    
    @NSManaged public var zapFromRequest: Event?
    @NSManaged public var zappedEvent: Event?
    @NSManaged public var zappedContact: Contact?
}

// MARK: Generated accessors for reactions
extension Event {
    @NSManaged public var reactionToId: String?
    @NSManaged public var reactionTo: Event?
}

extension Event {
    
    var isSpam:Bool {
        // combine all the checks here
        
        if kind == 9735, let zapReq = zapFromRequest, zapReq.naiveSats >= 250 { // TODO: Make amount configurable
            // Never consider zaps of more than 250 sats as spam
            return false
        }
        
        // Flood check
        // TODO: Add flood check here
        
        // Block list
        // TODO: Move block list check here
        
        // Mute list
        // TODO: Move mute list check here
        
        
        // TODO: Think of more checks
        
        // Web of Trust filter
        if WOT_FILTER_ENABLED() {
            if inWoT { return false }
//            L.og.debug("🕸️🕸️ WebOfTrust: Filtered by WoT: kind: \(self.kind) id: \(self.id): \(self.content ?? "")")
            return true
        }
        
        return false
    }
    
    var inWoT:Bool {
        if kind == 9735, let zapReq = zapFromRequest {
            return NosturState.shared.wot?.isAllowed(zapReq.pubkey) ?? false
        }
        return NosturState.shared.wot?.isAllowed(pubkey) ?? false
    }
    
    var plainText:String {
        return NRTextParser.shared.copyPasteText(self, text: self.content ?? "").text
    }
    
    var date: Date {
        get {
            Date(timeIntervalSince1970: Double(created_at))
        }
    }
    
    var ago: String { date.agoString }
    
    var authorKey: String {
        String(pubkey.prefix(5))
    }
    
    var noteText: String {
        if kind == 4 {
            guard let account = (Thread.isMainThread ? NosturState.shared.account : NosturState.shared.bgAccount), let pk = account.privateKey, let encrypted = content else {
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
        guard !tags.isEmpty else { return content ?? "" }
        
        var newText = content ?? ""
        for index in tags.indices {
            if (tags[index].0 == "e") {
                if let note1string = note1(tags[index].1) {
                    newText = newText.replacingOccurrences(of: String("#[\(index)]"), with: "nostr:\(note1string)")
                }
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
        let viewContext = DataProvider.shared().container.viewContext
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
    static func updateRepliesCountCache(_ tags:[NostrTag], context:NSManagedObjectContext) throws -> Bool {
        // NIP-10: Those marked with "reply" denote the id of the reply event being responded to.
        
        
        // TODO: USE AWAITING EVENTS HERE. OR NOT, IT IS NO LONGER USED. ONLY IN SETTINGS DEV MODE FIXER
        let replyEtag = TagsHelpers(tags).replyToEtag()
        
        if (replyEtag != nil) {
            let request = NSFetchRequest<Event>(entityName: "Event")
            request.entity = Event.entity()
            request.predicate = NSPredicate(format: "id == %@", replyEtag!.id)
            request.fetchLimit = 1
            
            if let reactingToEvent = try context.fetch(request).first {
                //                print("updating .replies for .id = \(String(describing: reactingToEvent.id))")
//                reactingToEvent.objectWillChange.send()
                reactingToEvent.repliesCount = (reactingToEvent.repliesCount + 1)
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
//                reactingToEvent.objectWillChange.send()
                reactingToEvent.repliesCount = (reactingToEvent.repliesCount + 1)
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
                    
                    if let reactingToEvent = EventRelationsQueue.shared.getAwaitingBgEvent(byId: lastEtag) {
                        reactingToEvent.likesCount = (reactingToEvent.likesCount + 1)
                        reactingToEvent.likesDidChange.send(reactingToEvent.likesCount)
                        event.reactionTo = reactingToEvent
                        event.reactionToId = reactingToEvent.id
                    }
                    else if let reactingToEvent = try context.fetch(request).first {
                        reactingToEvent.likesCount = (reactingToEvent.likesCount + 1)
                        reactingToEvent.likesDidChange.send(reactingToEvent.likesCount)
                        event.reactionTo = reactingToEvent
                        event.reactionToId = reactingToEvent.id
                    }
                }
            case "-":
                print("downvote")
            default:
                break
        }
        return true
    }
    
    static func updateRepostCountCache(_ event:Event, content:String, context:NSManagedObjectContext) throws -> Bool {
        
        if let firstE = event.firstE() {
            let request = NSFetchRequest<Event>(entityName: "Event")
            request.entity = Event.entity()
            request.predicate = NSPredicate(format: "id == %@", firstE)
            request.fetchLimit = 1
            
            if let repostedEvent = EventRelationsQueue.shared.getAwaitingBgEvent(byId: firstE) {
                repostedEvent.repostsCount = (repostedEvent.repostsCount + 1)
                repostedEvent.repostsDidChange.send(repostedEvent.repostsCount)
            }
            else if let repostedEvent = try context.fetch(request).first {
                repostedEvent.repostsCount = (repostedEvent.repostsCount + 1)
                repostedEvent.repostsDidChange.send(repostedEvent.repostsCount)
            }
        }
        return true
    }
    
    // To fix event.reactionTo but not count+1, because +1 is instant at tap, but this relation happens after 8 sec (unpublisher)
    static func updateReactionTo(_ event:Event, context:NSManagedObjectContext) throws {
        if let lastEtag = event.lastE() {
            let request = NSFetchRequest<Event>(entityName: "Event")
            request.entity = Event.entity()
            request.predicate = NSPredicate(format: "id == %@", lastEtag)
            request.fetchLimit = 1
            
            if let reactingToEvent = try context.fetch(request).first {
                reactingToEvent.likesDidChange.send(reactingToEvent.likesCount)
                event.reactionTo = reactingToEvent
                event.reactionToId = reactingToEvent.id
            }
        }
    }
    
    
    static func updateZapTallyCache(_ zap:Event, context:NSManagedObjectContext) -> Bool {
        guard let zappedContact = zap.zappedContact else { // NO CONTACT
            if let zappedPubkey = zap.otherPubkey {
                L.fetching.info("⚡️⏳ missing contact for zap. fetching: \(zappedPubkey), and queueing zap \(zap.id)")
                QueuedFetcher.shared.enqueue(pTag: zappedPubkey)
                ZapperPubkeyVerificationQueue.shared.addZap(zap)
            }
            return false
        }
        
        guard zappedContact.metadata_created_at != 0 else { // CONTACT INFO MISSING
            L.fetching.info("⚡️⏳ missing contact info for zap. fetching: \(zappedContact.pubkey), and queueing zap \(zap.id)")
            QueuedFetcher.shared.enqueue(pTag: zappedContact.pubkey)
                ZapperPubkeyVerificationQueue.shared.addZap(zap)
            return false
        }
        
        // Check if contact matches the zapped event contact
        if let otherPubkey = zap.otherPubkey, let zappedEvent = zap.zappedEvent {
            guard otherPubkey == zappedEvent.pubkey else {
                L.og.info("⚡️🔴🔴 zapped contact pubkey is not the same as zapped event pubkey. zap: \(zap.id)")
                zap.flags = "zpk_mismatch_event"
                return false
            }
        }
        
        // Check if zapper pubkey matches contacts published zapper pubkey
        if let zappedContact = zap.zappedContact, let zapperPubkey = zappedContact.zapperPubkey {
            guard zap.pubkey == zapperPubkey else {
                L.og.info("⚡️🔴🔴 zapper pubkey does not match contacts published zapper pubkey. zap: \(zap.id)")
                zap.flags = "zpk_mismatch"
                return false
            }
            zap.flags = "zpk_verified" // zapper pubkey is correct
        }
        else {
            zap.flags = "zpk_unverified" // missing contact
            return false
        }
                
        if let zappedEvent = zap.zappedEvent {
            zappedEvent.zapTally = (zappedEvent.zapTally + Int64(zap.naiveSats))
            zappedEvent.zapsCount = (zappedEvent.zapsCount + 1)
            zappedEvent.zapsDidChange.send((zappedEvent.zapsCount, zappedEvent.zapTally))
        }
        return true
    }
    
    // NIP-10: Those marked with "mention" denote a quoted or reposted event id.
    static func updateMentionsCountCache(_ tags:[NostrTag], context:NSManagedObjectContext) throws -> Bool {
        // NIP-10: Those marked with "mention" denote a quoted or reposted event id.
        if let mentionEtags = TagsHelpers(tags).newerMentionEtags() {
            for etag in mentionEtags {
                let request = NSFetchRequest<Event>(entityName: "Event")
                request.entity = Event.entity()
                request.predicate = NSPredicate(format: "id == %@", etag.id)
                request.fetchLimit = 1
                
                if let reactingToEvent = try context.fetch(request).first {
//                    reactingToEvent.objectWillChange.send()
                    //                    print("updating .mentions for .id = \(String(describing: reactingToEvent.id))")
                    reactingToEvent.mentionsCount = (reactingToEvent.mentionsCount + 1)
                    
                }
            }
        }
        return true
    }
    
    var fastTags:[(String, String, String?, String?)] {
        guard let tagsSerialized = tagsSerialized else { return [] }
        guard let jsonData = tagsSerialized.data(using: .utf8) else { return [] }
        
        guard let jsonArray = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String]] else {
            return []
        }
        
        return jsonArray
        //            .filter { $0.count >= 2 }
            .map { ($0[safe: 0] ?? "WTF", $0[safe: 1] ?? "WTF", $0[safe: 2], $0[safe: 3]) }
    }
    
    var fastPs:[(String, String, String?, String?)] {
        fastTags.filter { $0.0 == "p" && $0.1.count == 64 }
    }
    
    var fastEs:[(String, String, String?, String?)] {
        fastTags.filter { $0.0 == "e" && $0.1.count == 64 }
    }
    
    var fastTs:[(String, String, String?, String?)] {
        fastTags.filter { $0.0 == "t" && !$0.1.isEmpty }
    }
    
    
    func tags() -> [NostrTag] {
        let decoder = JSONDecoder()
        
        if (tagsSerialized != nil) {
            guard let tags = try? decoder.decode([NostrTag].self, from: Data(tagsSerialized!.utf8)) else {
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
        guard let tagsSerialized = tagsSerialized else { return nil }
        
        if let rangeStart = tagsSerialized.range(of: prefix)?.upperBound,
           let rangeEnd = tagsSerialized.range(of: suffix, range: rangeStart..<tagsSerialized.endIndex)?.lowerBound {
            let extractedString = String(tagsSerialized[rangeStart..<rangeEnd])
            
            return extractedString
        }
        return nil
    }
    
    func bolt11() -> String? {
        tags().first(where: { $0.type == "bolt11" })?.tag[1]
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
            guard let tags = try? decoder.decode([NostrTag].self, from: Data(tagsSerialized!.utf8)) else {
                return nil
            }
            
            return tags.filter { $0.type == "p" } .map { $0.pubkey }
        }
        else {
            return nil
        }
    }
    
    static func fetchLastSeen(pubkey:String, context:NSManagedObjectContext) -> Event? {
        let request = NSFetchRequest<Event>(entityName: "Event")
        request.predicate = NSPredicate(format: "pubkey == %@", pubkey)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        request.fetchLimit = 1
        request.fetchBatchSize = 1
        return try? context.fetch(request).first
    }
    
    static func fetchEvent(id:String, context:NSManagedObjectContext) throws -> Event? {
        let request = NSFetchRequest<Event>(entityName: "Event")
        //        request.entity = Event.entity()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        request.fetchBatchSize = 1
        return try context.fetch(request).first
    }
    
    static func fetchEventsBy(pubkey:String, andKind kind:Int, context:NSManagedObjectContext) -> [Event] {
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        fr.predicate = NSPredicate(format: "pubkey == %@ AND kind == %d", pubkey, kind)
        return (try? context.fetch(fr)) ?? []
    }
    
    static func fetchMostRecentEventBy(pubkey:String, andOtherPubkey otherPubkey:String? = nil, andKind kind:Int, context:NSManagedObjectContext) -> Event? {
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        fr.predicate = otherPubkey != nil
            ? NSPredicate(format: "pubkey == %@ AND otherPubkey == %@ AND kind == %d", pubkey, otherPubkey!, kind)
            : NSPredicate(format: "pubkey == %@ AND kind == %d", pubkey, kind)
        fr.fetchLimit = 1
        fr.fetchBatchSize = 1
        return try? context.fetch(fr).first
    }
    
    static func fetchReplacableEvent(_ kind:Int64, pubkey:String, definition:String, context:NSManagedObjectContext) -> Event? {
        let request = NSFetchRequest<Event>(entityName: "Event")
        request.predicate = NSPredicate(format: "kind == %d AND pubkey == %@ AND dTag == %@ AND mostRecentId == nil", kind, pubkey, definition)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        request.fetchLimit = 1
        
        return try? context.fetch(request).first
    }
    
    static func fetchReplacableEvent(aTag:String, context:NSManagedObjectContext) -> Event? {
        let elements = aTag.split(separator: ":")
        guard elements.count >= 3 else { return nil }
        guard let kindString = elements[safe: 0], let kind = Int64(kindString) else { return nil }
        guard let pubkey = elements[safe: 1] else { return nil }
        guard let definition = elements[safe: 2] else { return nil }
        
        return Self.fetchReplacableEvent(kind, pubkey: String(pubkey), definition: String(definition), context: context)
    }
    
    static func fetchReplacableEvent(_ kind:Int64, pubkey:String, context:NSManagedObjectContext) -> Event? {
        let request = NSFetchRequest<Event>(entityName: "Event")
        request.predicate = NSPredicate(format: "kind == %d AND pubkey == %@", kind, pubkey)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
    
    static func fetchProfileBadgesByATag(_ badgeA:String, context:NSManagedObjectContext) -> [Event] {
        // find all kind 30008 where serialized tags contains
        // ["a","30009:aa77d356ac5a59dbedc78f0da17c6bdd3ae315778b5c78c40a718b5251391da6:test_badge"]
        // notify any related profile badge
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        fr.predicate = NSPredicate(format: "kind == 30008 AND tagsSerialized CONTAINS %@", badgeA)
        return (try? context.fetch(fr)) ?? []
    }
    
    
    static func eventExists(id:String, context:NSManagedObjectContext) -> Bool {
        if Thread.isMainThread {
            L.og.info("☠️☠️☠️☠️ eventExists")
        }
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
            L.og.error("some error in eventExists() \(error)")
            return false
        }
        
        if count > 0 {
            return true
        }
        return false
    }
    
    
    static func extractZapRequest(tags:[NostrTag]) -> NEvent? {
        let description:NostrTag? = tags.first(where: { $0.type == "description" })
        guard description?.tag[safe: 1] != nil else { return nil }
        
        let decoder = JSONDecoder()
        if let zapReqNEvent = try? decoder.decode(NEvent.self, from: description!.tag[1].data(using: .utf8, allowLossyConversion: false)!) {
            do {
                
                // Its note in note, should we verify? is this verified by relays? or zapper? should be...
                guard try (!SettingsStore.shared.isSignatureVerificationEnabled) || (zapReqNEvent.verified()) else { return nil }
                
                return zapReqNEvent
            }
            catch {
                L.og.error("extractZapRequest \(error)")
                return nil
            }
        }
        return nil
    }
    
    static func saveZapRequest(event:NEvent, context:NSManagedObjectContext) -> Event? {
        if let existingZapReq = try! Event.fetchEvent(id: event.id, context: context) {
            //                print("🔴🔴 zap req already in db");
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
        
        
        // set relation to Contact
        zapRequest.contact = Contact.fetchByPubkey(event.publicKey, context: context)
        
        zapRequest.tagsSerialized = TagSerializer.shared.encode(tags: event.tags)
        
        return zapRequest
    }
    
    static func updateRelays(_ id:String, relays: String) {
        let bg = DataProvider.shared().bg
        bg.perform {
            if let event = EventRelationsQueue.shared.getAwaitingBgEvent(byId: id) {
                let existingRelays = event.relays.split(separator: " ").map { String($0) }
                let newRelays = relays.split(separator: " ").map { String($0) }
                let uniqueRelays = Set(existingRelays + newRelays)
                if uniqueRelays.count > existingRelays.count {
                    event.relays = uniqueRelays.joined(separator: " ")
                    event.relaysUpdated.send(event.relays)
                    do {
                        try bg.save()
                    }
                    catch {
                        L.og.error("🔴🔴 error updateRelays \(error)")
                    }
                }
            }
            else if let event = try? Event.fetchEvent(id: id, context: bg) {
                let existingRelays = event.relays.split(separator: " ").map { String($0) }
                let newRelays = relays.split(separator: " ").map { String($0) }
                let uniqueRelays = Set(existingRelays + newRelays)
                if uniqueRelays.count > existingRelays.count {
                    event.relays = uniqueRelays.joined(separator: " ")
                    event.relaysUpdated.send(event.relays)
                    do {
                        try bg.save()
                    }
                    catch {
                        L.og.error("🔴🔴 error updateRelays \(error)")
                    }
                }
            }
        }
    }
    
    static func saveEventFromMain(event:NEvent, relays:String? = nil) -> Event {
        let context = DataProvider.shared().bg
        return context.performAndWait {
            Event.saveEvent(event: event, relays: relays)
        }
    }
    
    static func saveEvent(event:NEvent, relays:String? = nil, flags:String = "", kind6firstQuote:Event? = nil) -> Event {
        #if DEBUG
            if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                fatalError("Should only be called from bg()")
            }
        #endif
        let context = DataProvider.shared().bg
        
        let savedEvent = Event(context: context)
        savedEvent.insertedAt = Date.now
        savedEvent.id = event.id
        savedEvent.kind = Int64(event.kind.id)
        savedEvent.created_at = Int64(event.createdAt.timestamp)
        savedEvent.content = event.content
        savedEvent.sig = event.signature
        savedEvent.pubkey = event.publicKey
        savedEvent.likesCount = 0
        savedEvent.isRepost = event.kind == .repost
        savedEvent.flags = flags
        if let contact = EventRelationsQueue.shared.getAwaitingBgContacts().first(where: { $0.pubkey == event.publicKey }) {
            savedEvent.contact = contact
        }
        else {
            savedEvent.contact = Contact.fetchByPubkey(event.publicKey, context: context)
        }
        savedEvent.tagsSerialized = TagSerializer.shared.encode(tags: event.tags)
        
        if let relays = relays?.split(separator: " ").map({ String($0) }) {
            let uniqueRelays = Set(relays)
            savedEvent.relays = uniqueRelays.joined(separator: " ")
        }
        updateEventCache(event.id, status: .SAVED, relays: relays)
        
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
        
        if event.kind == .community {
            saveCommunityDefinition(savedEvent: savedEvent, nEvent: event)
        }
        
        if event.kind == .zapNote {
            // save 9734 seperate
            // so later we can do --> event(9735).zappedEvent(9734).contact
            let nZapRequest = Event.extractZapRequest(tags: event.tags)
            if (nZapRequest != nil) {
                let zapRequest = Event.saveZapRequest(event: nZapRequest!, context: context)
                
                savedEvent.zapFromRequest = zapRequest
                if let firstE = event.firstE() {
                    savedEvent.zappedEventId = firstE
                    
                    if let awaitingEvent = EventRelationsQueue.shared.getAwaitingBgEvent(byId: firstE) {
                        savedEvent.zappedEvent = awaitingEvent
                    }
                    else {
                        savedEvent.zappedEvent = try? Event.fetchEvent(id: firstE, context: context)
                    }
                    if let zapRequest, zapRequest.pubkey == NosturState.shared.activeAccountPublicKey {
                        savedEvent.zappedEvent?.zapState = .zapReceiptConfirmed
                        savedEvent.zappedEvent?.zapStateChanged.send(.zapReceiptConfirmed)
                    }
                }
                if let firstP = event.firstP() {
//                    savedEvent.objectWillChange.send()
                    savedEvent.otherPubkey = firstP
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
//                savedEvent.objectWillChange.send()
                savedEvent.reactionToId = lastE
                savedEvent.reactionTo = try? Event.fetchEvent(id: lastE, context: context)
            }
        }
        
        if (event.kind == .textNote) {
            
            if (event.content == "#[0]" && !event.tags.isEmpty && event.tags[0].type == "e") {
                savedEvent.isRepost = true
                savedEvent.repostForId = event.tags[0].id // repost
            }
            
            // NEw: Save all p's in .contacts
            // Maybe slow??
            let contacts = Contact.ensureContactsCreated(event: event, context: context)
            savedEvent.addToContacts(NSSet(array: contacts))
            
            if let replyToAtag = event.replyToAtag() { // Comment on article
                if let dbArticle = Event.fetchReplacableEvent(aTag: replyToAtag.value, context: context) {
                    savedEvent.replyToId = dbArticle.id
                    savedEvent.replyTo = dbArticle
                    
                    dbArticle.addToReplies(savedEvent)
                    dbArticle.repliesCount += 1
                    dbArticle.repliesUpdated.send(dbArticle.replies_)
                }
                else {
                    // we don't have the article yet, store aTag in replyToId
                    savedEvent.replyToId = replyToAtag.value
                }
            }
            else if let replyToRootAtag = event.replyToRootAtag() {
                // Comment has article as root, but replying to other comment, not to article.
                if let dbArticle = Event.fetchReplacableEvent(aTag: replyToRootAtag.value, context: context) {
                    savedEvent.replyToRootId = dbArticle.id
                    savedEvent.replyToRoot = dbArticle
                }
                else {
                    // we don't have the article yet, store aTag in replyToRootId
                    savedEvent.replyToRootId = replyToRootAtag.value
                }
                
                // if there is no replyTo (e or a) then the replyToRoot is the replyTo
                // but check first if we maybe have replyTo from e tags
            }
             
            // Original replyTo/replyToRoot handling, don't overwrite aTag handling
                
            // THIS EVENT REPLYING TO SOMETHING
            // CACHE THE REPLY "E" IN replyToId
            if let replyToEtag = event.replyToEtag(), savedEvent.replyToId == nil {
                savedEvent.replyToId = replyToEtag.id
                
                // IF WE ALREADY HAVE THE PARENT, ADD OUR NEW EVENT IN THE REPLIES
                if let replyTo = EventRelationsQueue.shared.getAwaitingBgEvent(byId: replyToEtag.id) {
                    savedEvent.replyTo = replyTo
                    replyTo.addToReplies(savedEvent)
                    replyTo.repliesCount += 1
                    replyTo.repliesUpdated.send(replyTo.replies_)
                }
                else if let replyTo = try? Event.fetchEvent(id: replyToEtag.id, context: context) {
                    savedEvent.replyTo = replyTo
                    replyTo.addToReplies(savedEvent)
                    replyTo.repliesCount += 1
                    replyTo.repliesUpdated.send(replyTo.replies_)
                }
            }
            
            // IF THE THERE IS A ROOT, AND ITS NOT THE SAME AS THE REPLY TO. AND ROOT IS NOT ALREADY SET FROM ROOTATAG
            // DO THE SAME AS WITH THE REPLY BEFORE
            if let replyToRootEtag = event.replyToRootEtag(), savedEvent.replyToRootId == nil {
                savedEvent.replyToRootId = replyToRootEtag.id
                // Need to put it in queue to fix relations for replies to root / grouped replies
                //                EventRelationsQueue.shared.addAwaitingEvent(savedEvent, debugInfo: "saveEvent.123")
                
                if (savedEvent.replyToId == nil) {
                    savedEvent.replyToId = savedEvent.replyToRootId // NO REPLYTO, SO REPLYTOROOT IS THE REPLYTO
                }
                if let replyToRoot = EventRelationsQueue.shared.getAwaitingBgEvent(byId: replyToRootEtag.id) {
                    savedEvent.replyToRoot = replyToRoot
                    replyToRoot.replyToRootUpdated.send(savedEvent)
                    if (savedEvent.replyToId == savedEvent.replyToRootId) {
                        savedEvent.replyTo = replyToRoot // NO REPLYTO, SO REPLYTOROOT IS THE REPLYTO
                        replyToRoot.addToReplies(savedEvent)
                        replyToRoot.repliesCount += 1
                        replyToRoot.repliesUpdated.send(replyToRoot.replies_)
                        savedEvent.replyToUpdated.send(replyToRoot) // TODO: This event can't have any updates, its brand new..??
                    }
                }
                else if let replyToRoot = try? Event.fetchEvent(id: replyToRootEtag.id, context: context) {
                    savedEvent.replyToRoot = replyToRoot
                    replyToRoot.replyToRootUpdated.send(savedEvent)
                    if (savedEvent.replyToId == savedEvent.replyToRootId) {
                        savedEvent.replyTo = replyToRoot // NO REPLYTO, SO REPLYTOROOT IS THE REPLYTO
                        replyToRoot.addToReplies(savedEvent)
                        replyToRoot.repliesCount += 1
                        replyToRoot.repliesUpdated.send(replyToRoot.replies_)
                    }
                }
            }
            
            // Finally, we have a reply to root set from aTag, but we still don't have a replyTo
            else if savedEvent.replyToRootId != nil, savedEvent.replyToId == nil {
                // so set replyToRoot (aTag) as replyTo
                savedEvent.replyToId = savedEvent.replyToRootId
                savedEvent.replyTo = savedEvent.replyToRoot
                
                if let replyTo = savedEvent.replyTo {
                    replyTo.addToReplies(savedEvent)
                    replyTo.repliesCount += 1
                    replyTo.repliesUpdated.send(replyTo.replies_)
                }
            }
            
        }
        
        if (event.kind == .directMessage) { // needed to fetch contact in DMS: so event.firstP is in event.contacts
            let contacts = Contact.ensureContactsCreated(event: event, context: context)
            savedEvent.addToContacts(NSSet(array: contacts))
            savedEvent.otherPubkey = event.firstP()
            
            if let contactPubkey = savedEvent.otherPubkey { // If we have a DM kind 4, but no p, then something is wrong
                if let dmState = DMState.fetchExisting(event.publicKey, contactPubkey: contactPubkey, context: context) {
                    
                    // if we already track the conversation, consider accepted if we replied to the DM
                    // DM is sent from one of our current logged in pubkey
                    if !dmState.accepted && NosturState.shared.bgAccountKeys.contains(event.publicKey) {
                        dmState.accepted = true
                        
                        if let current = dmState.markedReadAt, savedEvent.date > current {
                            dmState.markedReadAt = savedEvent.date
                        }
                        else if dmState.markedReadAt == nil {
                            dmState.markedReadAt = savedEvent.date
                        }
                    }
                    // Let DirectMessageViewModel handle view updates
                    DirectMessageViewModel.default.newMessage(dmState)
                }
                // Same but account / contact switched, because we support multiple accounts so we need to be able to track both ways
                else if let dmState = DMState.fetchExisting(contactPubkey, contactPubkey: event.publicKey, context: context) {
                    
                    // if we already track the conversation, consider accepted if we replied to the DM
                    if !dmState.accepted && NosturState.shared.bgAccountKeys.contains(event.publicKey) {
                        dmState.accepted = true
                    }
                    // Let DirectMessageViewModel handle view updates
                    DirectMessageViewModel.default.newMessage(dmState)
                }
                else {
                    
                    // if we are sender
                    if NosturState.shared.bgAccountKeys.contains(event.publicKey) {
                        let dmState = DMState(context: context)
                        dmState.accountPubkey = event.publicKey
                        dmState.contactPubkey = contactPubkey
                        dmState.accepted = true
                        dmState.markedReadAt = savedEvent.date
                        // Let DirectMessageViewModel handle view updates
                        DirectMessageViewModel.default.newMessage(dmState)
                    }
                    
                    // if we are receiver
                    else if NosturState.shared.bgAccountKeys.contains(contactPubkey) {
                        let dmState = DMState(context: context)
                        dmState.accountPubkey = contactPubkey
                        dmState.contactPubkey = event.publicKey
                        dmState.accepted = false
                        // Let DirectMessageViewModel handle view updates
                        DirectMessageViewModel.default.newMessage(dmState)
                    }
                }
            }
        }
        
        // handle REPOST with normal mentions in .kind 1
        // TODO: handle first nostr:nevent or not?
        var alreadyCounted = false
        if event.kind == .textNote, let firstE = event.firstMentionETag(), let replyToId = savedEvent.replyToId, firstE.id != replyToId { // also fQ not the same as replyToId
            savedEvent.firstQuoteId = firstE.id
            
            // IF WE ALREADY HAVE THE FIRST QUOTE, ADD OUR NEW EVENT IN THE MENTIONS
            if let firstQuote = try? Event.fetchEvent(id: savedEvent.firstQuoteId!, context: context) {
                savedEvent.firstQuote = firstQuote
                
                if (firstE.tag[safe: 3] == "mention") {
//                    firstQuote.objectWillChange.send()
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
                
//                firstQuote.objectWillChange.send()
                firstQuote.mentionsCount += 1
            }
        }
        
        // kind6 - repost, the reposted post is put in as .firstQuote
        if event.kind == .repost, let firstE = event.firstE() {
            savedEvent.firstQuoteId = firstE
            savedEvent.firstQuote = kind6firstQuote // got it passed in as parameter on saveEvent() already.

            if savedEvent.firstQuote == nil { // or we fetch it if we dont have it yet
                // IF WE ALREADY HAVE THE FIRST QUOTE, ADD OUR NEW EVENT + UPDATE REPOST COUNT
                if let repostedEvent = EventRelationsQueue.shared.getAwaitingBgEvent(byId: firstE) {
                    savedEvent.firstQuote = repostedEvent
                    repostedEvent.repostsCount = (repostedEvent.repostsCount + 1)
                    repostedEvent.repostsDidChange.send(repostedEvent.repostsCount)
                }
                else if let repostedEvent = try? Event.fetchEvent(id: savedEvent.firstQuoteId!, context: context) {
                    savedEvent.firstQuote = repostedEvent
                    repostedEvent.repostsCount += 1
                    repostedEvent.repostsDidChange.send(repostedEvent.repostsCount)
                }
            }
        }
        
        if (event.kind == .contactList) {
            // delete older events
            let r = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
            r.predicate = NSPredicate(format: "kind == 3 AND pubkey == %@ AND created_at < %d", event.publicKey, savedEvent.created_at)
            let batchDelete = NSBatchDeleteRequest(fetchRequest: r)
            batchDelete.resultType = .resultTypeCount
            
            do {
                _ = try context.execute(batchDelete) as! NSBatchDeleteResult
            } catch {
                L.og.error("🔴🔴 Failed to delete older kind 3 events")
            }
        }
        
        if event.kind == .delete {
            let eventIdsToDelete = event.eTags()
            
            let eventIdsToDeleteReq = NSFetchRequest<Event>(entityName: "Event")
            eventIdsToDeleteReq.predicate = NSPredicate(format: "kind IN {1,6,9802,30023} AND id IN %@", eventIdsToDelete)
            eventIdsToDeleteReq.sortDescriptors = []
            if let eventsToDelete = try? context.fetch(eventIdsToDeleteReq) {
                for d in eventsToDelete {
                    if (d.pubkey == event.publicKey) {
//                        d.objectWillChange.send()
                        d.deletedById = event.id
                        d.postDeleted.send(event.id)
                    }
                }
            }
        }
        
        if (event.kind == .highlight) { // needed to fetch highlight author so put event.firstP in event.contacts
            let contacts = Contact.ensureContactsCreated(event: event, context: context)
            savedEvent.addToContacts(NSSet(array: contacts))
        }
        
        // Handle replacable event (NIP-33)
        if (event.kind.id >= 30000 && event.kind.id < 40000) {
            savedEvent.dTag = event.tags.first(where: { $0.type == "d" })?.value ?? ""
            // update older events:
            // 1. set pointer to most recent (this one)
            // 2. set "is_update" flag on this one so it doesn't show up as new in feed
            let r = Event.fetchRequest()
            r.predicate = NSPredicate(format: "dTag == %@ AND kind == %d AND pubkey == %@ AND created_at < %d", savedEvent.dTag, savedEvent.kind, event.publicKey, savedEvent.created_at)
            
            
            var existingArticleIds = Set<String>() // need to repoint all replies to older articles to the newest id
            
            if let olderEvents = try? context.fetch(r) {
                for olderEvent in olderEvents {
                    olderEvent.mostRecentId = savedEvent.id
                    existingArticleIds.insert(olderEvent.id)
                }
                
                if olderEvents.count > 0 {
                    savedEvent.flags = "is_update"
                }
            }
            
            // Find existing events referencing this event (can only be replyToRootId = "3XXXX:pubkey:dTag", or replyToRootId = "<older article ids>")
            // or same but for replyToId
            existingArticleIds.insert(savedEvent.aTag)
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "replyToRootId IN %@", existingArticleIds)
            if let existingReplies = try? context.fetch(fr) {
                for existingReply in existingReplies {
                    existingReply.replyToRootId = savedEvent.id
                    existingReply.replyToRoot = savedEvent
                }
            }
            
            let fr2 = Event.fetchRequest()
            fr2.predicate = NSPredicate(format: "replyToId IN %@", existingArticleIds)
            if let existingReplies = try? context.fetch(fr) {
                for existingReply in existingReplies {
                    existingReply.replyToId = savedEvent.id
                    existingReply.replyTo = savedEvent
                }
            }
            
        }
        
        
        
        
        
        // Use new EventRelationsQueue to fix relations
        if (event.kind == .textNote) {
            
            let awaitingEvents = EventRelationsQueue.shared.getAwaitingBgEvents()
            
            for waitingEvent in awaitingEvents {
                if (waitingEvent.replyToId != nil) && (waitingEvent.replyToId == savedEvent.id) {
                    waitingEvent.replyTo = savedEvent
                    waitingEvent.replyToUpdated.send(savedEvent)
                }
                if (waitingEvent.replyToRootId != nil) && (waitingEvent.replyToRootId == savedEvent.id) {
                    waitingEvent.replyToRoot = savedEvent
                    waitingEvent.replyToRootUpdated.send(savedEvent)
                }
                if (waitingEvent.firstQuoteId != nil) && (waitingEvent.firstQuoteId == savedEvent.id) {
                    waitingEvent.firstQuote = savedEvent
                    waitingEvent.firstQuoteUpdated.send(savedEvent)
                }
            }
        }
        
        
        return savedEvent
    }
    
    func toNEvent() -> NEvent {
        var nEvent = NEvent(content: content ?? "")
        nEvent.id = id
        nEvent.publicKey = pubkey
        nEvent.createdAt = NTimestamp(timestamp: Int(created_at))
        nEvent.kind = NEventKind(id: Int(kind))
        nEvent.tags = tags()
        nEvent.signature = sig ?? ""
        return nEvent
    }
    
    func getMetadataContent() throws -> NSetMetadata? {
        if kind != NEventKind.setMetadata.id {
            throw "Event is not kind 0"
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
    static let indexedMentionRegex = /#\[(\d+)\]/
    
    var mentionOnlyTags:[NostrTag] {
        let matches = content.matches(of: NEvent.indexedMentionRegex) // TODO: hmmm performance hit measured with Instruments here...
        let matchIndexes = matches.compactMap { Int($0.output.1) }
        let t = tags.enumerated().filter { matchIndexes.contains($0.offset) }.map { $0.element }
        let noRootOrReply = t.filter {
            $0.type == "e" && $0.tag[safe: 3] != "root" && $0.tag[safe: 3] != "reply"
        }
        return noRootOrReply
    }
    
    var threadETags:[NostrTag] {
        let mentionStrings = mentionOnlyTags.map { $0.id }
        return tags.filter {
            $0.type == "e" && !mentionStrings.contains($0.id)
        }
    }
    
    // E TAGS
    func replyToEtag() -> NostrTag? {
        if threadETags.isEmpty {
            return nil
        }
        // PREFERRED NEW METHOD
        // NIP-10: Those marked with "reply" denote the id of the reply event being responded to.
        let replyEtags = threadETags.filter { $0.tag.count == 4 && $0.tag[safe: 3] == "reply" }
        if (!replyEtags.isEmpty) {
            return replyEtags.first
        }
        
        // OLD METHOD NIP-10:
        // One "e" tag = REPLY
        if threadETags.count == 1 && (threadETags.first?.tag[safe: 3] == nil) {
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
    
    func replyToRootEtag() -> NostrTag? {
        if threadETags.isEmpty {
            return nil
        }
        let rootEtag = threadETags.filter { $0.tag.count == 4 && $0.tag[safe: 3] == "root" }.first
        // PREFERRED NEW METHOD
        if (rootEtag != nil) {
            return rootEtag
        }
        
        // OLD METHOD
        if threadETags.count == 1 && (threadETags.first?.tag[safe: 3] == nil) {
            return threadETags.first
            
        }
        if (threadETags.count >= 2) && (threadETags.first?.tag[safe: 3] == nil) {
            return threadETags.first
            
        }
        return nil
    }
    
    func firstMentionETag() -> NostrTag? {
        if mentionOnlyTags.isEmpty {
            return nil
        }
        return mentionOnlyTags.first
    }
    
    
    
    // ARTICLE/PARAMETERIZED REPLACABLE EVENTS / NIP-33 reply / root

    func replyToAtag() -> NostrTag? {
        // NIP-10: Those marked with "reply" denote the id of the reply event being responded to.
        // The spec is for "e" but we do the same for "a"
        return tags.first(where: { $0.type == "a" && $0.tag[safe: 3] == "reply" })
    }
    
    func replyToRootAtag() -> NostrTag? {
        return tags.first(where: { $0.type == "a" && $0.tag[safe: 3] == "root" })
    }
}
