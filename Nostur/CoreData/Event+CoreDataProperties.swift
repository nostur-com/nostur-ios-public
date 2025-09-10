//
//  Even+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/01/2023.
//
//

import Foundation
import CoreData
import NostrEssentials

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
    
    @NSManaged public var isRepost: Bool // Cache
    
    // Counters (cached)
    @NSManaged public var likesCount: Int64 // Cache
    @NSManaged public var repostsCount: Int64 // Cache
    @NSManaged public var repliesCount: Int64 // Cache
    @NSManaged public var mentionsCount: Int64 // Cache (No longer used? is now repostsCount)
    @NSManaged public var zapsCount: Int64 // Cache
    
    @NSManaged public var personZapping: Contact?
    @NSManaged public var replyTo: Event?
    @NSManaged public var replyToRoot: Event?
    @NSManaged public var firstQuote: Event?
    @NSManaged public var zapTally: Int64
    
    @NSManaged public var replies: Set<Event>?
    
    @NSManaged public var deletedById: String?
    @NSManaged public var dTag: String
    @NSManaged public var kTag: Int64 // backwards compatible kind

    
    // A referenced A tag 
    @NSManaged public var otherAtag: String?
    
    // For events with multiple versions (like NIP-33)
    // Most recent version should be nil
    // All older versions have a pointer to the most recent id
    // This makes it easy to query for the most recent event (mostRecentId = nil)
    @NSManaged public var mostRecentId: String?
    
    
    // Can be used for anything
    // Now we use it for:
    // - "is_update": to not show same article over and over in feed when it gets updates
    @NSManaged public var flags: String
    
    // Calculate this events aTag
    var aTag: String { (String(kind) + ":" + pubkey  + ":" + dTag) }
    
    public var contact: Contact? {
        guard let ctx = managedObjectContext else { return nil }
        return Contact.fetchByPubkey(pubkey, context: ctx)
    }

    var replyTo_:Event? {
        guard replyTo == nil else { return replyTo }
        if replyToId == nil && replyToRootId != nil { // Only replyToRootId? Treat as replyToId
            replyToId = replyToRootId
        }
        guard let replyToId = replyToId else { return nil }
        guard let ctx = managedObjectContext else { return nil }
        if let found = Event.fetchEvent(id: replyToId, context: ctx) {
            CoreDataRelationFixer.shared.addTask({
                guard contextWontCrash([self, found], debugInfo: ".replyTo_") else { return }
                self.replyTo = found
                found.addToReplies(self)
            })
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
        if let found = Event.fetchEvent(id: replyToId, context: ctx) {
            CoreDataRelationFixer.shared.addTask({
                guard contextWontCrash([self, found], debugInfo: ".replyTo__") else { return }
                self.replyTo = found
                found.addToReplies(self)
            })
            return found
        }
        return nil
    }
    
    var firstQuote_:Event? {
        guard firstQuote == nil else { return firstQuote }
        guard let firstQuoteId = firstQuoteId else { return nil }
        guard let ctx = managedObjectContext else { return nil }
        if let found = Event.fetchEvent(id: firstQuoteId, context: ctx) {
            CoreDataRelationFixer.shared.addTask({
                guard contextWontCrash([self, found], debugInfo: ".firstQuote_") else { return }
                self.firstQuote = found
            })
            return found
        }
        return nil
    }

    var replies_: [Event] { Array(replies ?? []) }
    
    
    var relays_: Set<String> {
        get {
            guard relays != "" else { return [] }
            return Set(relays.split(separator: " ").map { String($0) })
        }
        set {
            relays = newValue.joined(separator: " ")
        }
    }

    // Gets all parents. If until(id) is set, it will stop and wont traverse further, to prevent rendering duplicates
    static func getParentEvents(_ event:Event, fixRelations:Bool = false, until:String? = nil) -> [Event] {
        let RECURSION_LIMIT = 35 // PREVENT SPAM THREADS
        var parentEvents = [Event]()
        var currentEvent: Event? = event
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
            return bg().performAndWait {
                return bg().object(with: self.objectID) as? Event
            }
        }
        else {
            return bg().object(with: self.objectID) as? Event
        }
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
    
    var shortId: String {
        String(id.prefix(8))
    }
    
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
    
    var inWoT: Bool {
        if kind == 9735, let zapReq = zapFromRequest {
            return WebOfTrust.shared.isAllowed(zapReq.pubkey)
        }
        return WebOfTrust.shared.isAllowed(pubkey)
    }
    
    var isRestricted: Bool {
        self.fastTags.first(where: { $0.0 == "-" }) != nil
    }
    
    var plainText: String {
        return NRTextParser.shared.copyPasteText(fastTags: self.fastTags, event: self, text: self.content ?? "").text
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
            guard let account = account(), let pk = account.privateKey, let encrypted = content else {
                return convertToHieroglyphs(text: "(Encrypted content)")
            }
            if pubkey == account.publicKey, let firstP = self.firstP() {
                return Keys.decryptDirectMessageContent(withPrivateKey: pk, pubkey: firstP, content: encrypted) ?? "(Encrypted content)"
            }
            else {
                return Keys.decryptDirectMessageContent(withPrivateKey: pk, pubkey: pubkey, content: encrypted) ?? "(Encrypted content)"
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
    
    var via:String? { fastTags.first(where: { $0.0 == "client" })?.1 }
    
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
    
    // NIP-25: The generic reaction, represented by the content set to a + string, SHOULD be interpreted as a "like" or "upvote".
    // NIP-25: The content MAY be an emoji, in this case it MAY be interpreted as a "like" or "dislike", or the client MAY display this emoji reaction on the post.
    // TODO: 167.00 ms    1.5%    0 s          specialized static Event.updateLikeCountCache(_:content:context:)
    static func updateLikeCountCache(_ reaction: Event, content: String, context: NSManagedObjectContext) {
        switch content {
        case "-": // (down vote)
            break
        default:
            // # NIP-25: The last e tag MUST be the id of the note that is being reacted to.
            guard let lastEtag = reaction.lastE() else { break }
            guard let reactingToEvent = Event.fetchEvent(id: lastEtag, context: context) else { break }
            
            
            CoreDataRelationFixer.shared.addTask ({
                reactingToEvent.likesCount = (reactingToEvent.likesCount + 1)
                ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: reactingToEvent.id, likes: reactingToEvent.likesCount))
                reaction.reactionTo = reactingToEvent
                reaction.reactionToId = reactingToEvent.id
            })
        }
    }
    
    static func updateRepostsCountCache(_ repost: Event, context: NSManagedObjectContext)  {
        if let firstQuote = repost.firstQuote {
            firstQuote.repostsCount = (firstQuote.repostsCount + 1)
            ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: firstQuote.id, reposts: firstQuote.repostsCount))
        }
        else if let firstQuoteId = repost.firstQuoteId {
            guard let firstQuote = Event.fetchEvent(id: firstQuoteId, context: context) else { return }
            CoreDataRelationFixer.shared.addTask ({
                firstQuote.repostsCount = (firstQuote.repostsCount + 1)
                ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: firstQuote.id, reposts: firstQuote.repostsCount))
            })
        }
    }
    
    // To fix event.reactionTo but not count+1, because +1 is instant at tap, but this relation happens after 8 sec (unpublisher)
    static func updateReactionTo(_ event: Event, context: NSManagedObjectContext) {
        guard let lastEtag = event.lastE() else { return }
        guard let reactingToEvent = Event.fetchEvent(id: lastEtag, context: context) else { return }
        
        CoreDataRelationFixer.shared.addTask({
            ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: reactingToEvent.id, likes: reactingToEvent.likesCount))
            guard contextWontCrash([event, reactingToEvent], debugInfo: "updateReactionTo") else { return }
            event.reactionTo = reactingToEvent
            event.reactionToId = reactingToEvent.id
        })
    }
    
    static func updateZapTallyCache(_ zap: Event, context: NSManagedObjectContext) {
        if let zappedEvent = zap.zappedEvent {
            zappedEvent.zapTally = (zappedEvent.zapTally + Int64(zap.naiveSats))
            zappedEvent.zapsCount = (zappedEvent.zapsCount + 1)
            ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: zappedEvent.id, zaps: zappedEvent.zapsCount, zapTally: zappedEvent.zapTally))
        }
        else if let zappedEventId = zap.zappedEventId {
            guard let zappedEvent = Event.fetchEvent(id: zappedEventId, context: context) else { return }
            CoreDataRelationFixer.shared.addTask ({
                zappedEvent.zapTally = (zappedEvent.zapTally + Int64(zap.naiveSats))
                zappedEvent.zapsCount = (zappedEvent.zapsCount + 1)
                ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: zappedEvent.id, zaps: zappedEvent.zapsCount, zapTally: zappedEvent.zapTally))
            })
        }
        
        // Repair things afterwards
        
        // Missing contact
        if zap.zappedContact == nil {
            if let zappedPubkey = zap.otherPubkey {
#if DEBUG
                L.fetching.debug("⚡️⏳ updateZapTallyCache: missing contact for zap. fetching: \(zappedPubkey), and queueing zap \(zap.id)")
#endif
                QueuedFetcher.shared.enqueue(pTag: zappedPubkey)
                ZapperPubkeyVerificationQueue.shared.addZap(zap)
            }
        }
        
        // Missing kind-0 metadata
        else if let zappedContact = zap.zappedContact, zappedContact.metadata_created_at == 0 {
#if DEBUG
            L.fetching.debug("⚡️⏳ updateZapTallyCache: missing contact info for zap. fetching: \(zappedContact.pubkey), and queueing zap \(zap.id)")
#endif
            QueuedFetcher.shared.enqueue(pTag: zappedContact.pubkey)
            ZapperPubkeyVerificationQueue.shared.addZap(zap)
        }
        
        
        // Check if contact matches the zapped event contact
        if let otherPubkey = zap.otherPubkey, let zappedEvent = zap.zappedEvent {
            if otherPubkey != zappedEvent.pubkey {
#if DEBUG
                L.og.debug("⚡️🔴🔴 updateZapTallyCache: zapped contact pubkey is not the same as zapped event pubkey. zap: \(zap.id)")
#endif
                zap.flags = "zpk_mismatch_event"
            }
        }
        
        // Check if zapper pubkey matches contacts published zapper pubkey
        if let zappedContact = zap.zappedContact, zappedContact.zapperPubkeys.contains(zap.pubkey) {
            zap.flags = "zpk_verified" // zapper pubkey is correct
        }
    }
    
    // NIP-10: Those marked with "mention" denote a quoted or reposted event id.
    // TODO: REPLACE WITH q tag handling (NIP-18
    static func updateMentionsCountCache(_ tags:[NostrTag], context: NSManagedObjectContext) {
        // NIP-10: Those marked with "mention" denote a quoted or reposted event id.
        guard let mentionEtags = TagsHelpers(tags).newerMentionEtags() else { return }
        
        CoreDataRelationFixer.shared.addTask({
            for etag in mentionEtags {
                if let mentioningEvent = Event.fetchEvent(id: etag.id, context: context) {
                    guard contextWontCrash([mentioningEvent], debugInfo: "updateMentionsCountCache") else { return }
                    mentioningEvent.mentionsCount = (mentioningEvent.mentionsCount + 1)
                }
            }
        })
    }
    
    var fastEs: [FastTag] {
        fastTags.filter { $0.0 == "e" && $0.1.count == 64 }
    }
    
    var fastTs: [FastTag] {
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
        guard let tagsSerialized else { return nil }
        if let match = NostrRegexes.default.cache[.bolt11]!.firstMatch(in: tagsSerialized, range: NSRange(tagsSerialized.startIndex..., in: tagsSerialized)) {
            
            if let range = Range(match.range(at: 1), in: tagsSerialized) {
                return String(tagsSerialized[range])
            }
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
            
            return tags.filter { $0.type == "p" && $0.pubkey.count == 64 } .map { $0.pubkey }
        }
        else {
            return nil
        }
    }
    
    static func fetchLastSeen(pubkey: String, context: NSManagedObjectContext) -> Event? {
        let request = NSFetchRequest<Event>(entityName: "Event")
        request.predicate = NSPredicate(format: "pubkey == %@", pubkey)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        request.fetchLimit = 1
        request.fetchBatchSize = 1
        return try? context.fetch(request).first
    }
    
    static func fetchEvent(id: String, context: NSManagedObjectContext) -> Event? {
        if !Thread.isMainThread {
            guard Importer.shared.existingIds[id]?.status == .SAVED else { return nil }
        }
        
        if !Thread.isMainThread {
            if let bgEvent = EventRelationsQueue.shared.getAwaitingBgEvent(byId: id), !bgEvent.isDeleted {
                return bgEvent
            }
        }
        
        if !Thread.isMainThread {
            if let eventfromCache = EventCache.shared.retrieveObject(at: id), !eventfromCache.isDeleted {
                return eventfromCache
            }
        }
                
        let request = NSFetchRequest<Event>(entityName: "Event")
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        request.fetchBatchSize = 1
        return try? context.fetch(request).first
    }
    
    static func fetchEventsBy(pubkey: String, andKind kind: Int, context: NSManagedObjectContext) -> [Event] {
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        fr.predicate = NSPredicate(format: "pubkey == %@ AND kind == %d", pubkey, kind)
        return (try? context.fetch(fr)) ?? []
    }
    
    static func fetchEventsBy(kind: Int, context: NSManagedObjectContext) -> [Event] {
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        fr.predicate = NSPredicate(format: "kind == %d", kind)
        return (try? context.fetch(fr)) ?? []
    }
    
    static func fetchMostRecentEventBy(pubkey: String, andOtherPubkey otherPubkey: String? = nil, andKind kind: Int, context: NSManagedObjectContext) -> Event? {
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        fr.predicate = otherPubkey != nil
            ? NSPredicate(format: "pubkey == %@ AND otherPubkey == %@ AND kind == %d", pubkey, otherPubkey!, kind)
            : NSPredicate(format: "pubkey == %@ AND kind == %d", pubkey, kind)
        fr.fetchLimit = 1
        fr.fetchBatchSize = 1
        return try? context.fetch(fr).first
    }
    
    static func fetchReplacableEvent(_ kind: Int64, pubkey: String, definition: String, context: NSManagedObjectContext) -> Event? {
        let request = NSFetchRequest<Event>(entityName: "Event")
        request.predicate = NSPredicate(format: "kind == %d AND pubkey == %@ AND dTag == %@ AND mostRecentId == nil", kind, pubkey, definition)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        request.fetchLimit = 1
        
        return try? context.fetch(request).first
    }
    
    static func fetchReplacableEvent(aTag: ATag, context: NSManagedObjectContext) -> Event? {
        return Self.fetchReplacableEvent(aTag.kind, pubkey: aTag.pubkey, definition: aTag.definition, context: context)
    }
    
    static func fetchReplacableEvent(aTag: String, context: NSManagedObjectContext) -> Event? {
        let elements = aTag.split(separator: ":")
        guard elements.count >= 3 else { return nil }
        guard let kindString = elements[safe: 0], let kind = Int64(kindString) else { return nil }
        guard let pubkey = elements[safe: 1] else { return nil }
        guard let definition = elements[safe: 2] else { return nil }
        
        return Self.fetchReplacableEvent(kind, pubkey: String(pubkey), definition: String(definition), context: context)
    }
    
    static func fetchEvents(_ ids: [String], context: NSManagedObjectContext = bg()) -> [Event] {
        let request = NSFetchRequest<Event>(entityName: "Event")
        request.predicate = NSPredicate(format: "id IN %@", ids)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        return (try? context.fetch(request)) ?? []
    }
    
    static func fetchEvents(_ ids: Set<String>, context: NSManagedObjectContext = bg()) -> [Event] {
        Self.fetchEvents(Array(ids), context: context)
    }
    
    static func fetchReplacableEvent(_ kind: Int64, pubkey: String, context: NSManagedObjectContext = bg()) -> Event? {
        let request = NSFetchRequest<Event>(entityName: "Event")
        request.predicate = NSPredicate(format: "kind == %d AND pubkey == %@ AND deletedById = nil", kind, pubkey)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
    
    static func fetchProfileBadgesByATag(_ badgeA: String, context: NSManagedObjectContext) -> [Event] {
        // find all kind 30008 where serialized tags contains
        // ["a","30009:aa77d356ac5a59dbedc78f0da17c6bdd3ae315778b5c78c40a718b5251391da6:test_badge"]
        // notify any related profile badge
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        fr.predicate = NSPredicate(format: "kind == 30008 AND mostRecentId == nil AND tagsSerialized CONTAINS %@", badgeA)
        return (try? context.fetch(fr)) ?? []
    }
    
    static func fetchReplacableEvents(_ kind: Int64, pubkeys: Set<String>, context: NSManagedObjectContext) -> [Event] {
        let request = NSFetchRequest<Event>(entityName: "Event")
        request.predicate = NSPredicate(format: "kind == %d AND pubkey IN %@", kind, pubkeys)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        return (try? context.fetch(request)) ?? []
    }
    
    static func eventExists(id: String, context: NSManagedObjectContext) -> Bool {
        if Importer.shared.existingIds[id]?.status == .SAVED {
            return true
        }
        
        return false
        
//        if Thread.isMainThread {
//            L.og.info("☠️☠️☠️☠️ eventExists")
//        }
//        let request = NSFetchRequest<Event>(entityName: "Event")
//        request.entity = Event.entity()
//        request.predicate = NSPredicate(format: "id == %@", id)
//        request.resultType = .countResultType
//        request.fetchLimit = 1
//        request.includesPropertyValues = false
//        
//        var count = 0
//        do {
//            count = try context.count(for: request)
//        } catch {
//            L.og.error("some error in eventExists() \(error)")
//            return false
//        }
//        
//        if count > 0 {
//            return true
//        }
//        return false
    }
    
    
    static func extractZapRequest(tags: [NostrTag]) -> NEvent? {
        let description:NostrTag? = tags.first(where: { $0.type == "description" })
        guard description?.tag[safe: 1] != nil else { return nil }
        
        let decoder = JSONDecoder()
        if let zapReqNEvent = try? decoder.decode(NEvent.self, from: description!.tag[1].data(using: .utf8, allowLossyConversion: false)!) {
            do {
                
                // Its note in note, should we verify? is this verified by relays? or zapper? should be...
                guard try (!MessageParser.shared.isSignatureVerificationEnabled) || (zapReqNEvent.verified()) else { return nil }
                
                return zapReqNEvent
            }
            catch {
#if DEBUG
                L.og.error("extractZapRequest \(error)")
#endif
                return nil
            }
        }
        return nil
    }
    
    static func saveZapRequest(event: NEvent, context: NSManagedObjectContext) -> Event? {
        if let existingZapReq = Event.fetchEvent(id: event.id, context: context) {
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
        
        zapRequest.tagsSerialized = TagSerializer.shared.encode(tags: event.tags)
        
        return zapRequest
    }
    
    // TODO: 115.00 ms    1.0%    0 s          closure #1 in static Event.updateRelays(_:relays:)
    static func updateRelays(_ id: String, relays: String, context: NSManagedObjectContext) {
        #if DEBUG
            if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                fatalError("Should only be called from bg()")
            }
        #endif
        
        func safeUpdateRelays(for event: Event) {
            // Verify context is still valid
            guard let eventContext = event.managedObjectContext,
                  eventContext.persistentStoreCoordinator != nil
            else {
                return
            }
            
            // Ensure event still exists in context
            guard !event.isDeleted,
                  (try? eventContext.existingObject(with: event.objectID)) != nil else {
                return
            }
            
            CoreDataRelationFixer.shared.addTask {
                do {
                    // Refetch event to ensure fresh state
                    guard let freshEvent = try eventContext.existingObject(with: event.objectID) as? Event else {
                        return
                    }
                    
                    let existingRelays = freshEvent.relays.split(separator: " ").map { String($0) }
                    let newRelays = relays.split(separator: " ").map { String($0) }
                    let uniqueRelays = Set(existingRelays + newRelays)
                    
                    if uniqueRelays.count > existingRelays.count {
                        freshEvent.relays = uniqueRelays.joined(separator: " ")
                    }
                    if freshEvent.flags == "awaiting_send" && uniqueRelays.count > 0  {
                        freshEvent.flags = ""
                    }
                } catch {
                    print("Failed to update relays: \(error)")
                }
            }
        }
        
        // Try getting event from queue first
        if let event = EventRelationsQueue.shared.getAwaitingBgEvent(byId: id),
           event.managedObjectContext != nil {
            safeUpdateRelays(for: event)
        }
        // Fallback to fetching from context
        else if let event = Event.fetchEvent(id: id, context: context) {
            safeUpdateRelays(for: event)
        }
    }
    
    // TODO: .saveEvent() and .importEvents() needs a refactor, to cleanly handle each kind in a reusable/maintainable way, this long list of if statements is becoming a mess.
    static func saveEvent(event: NEvent, relays: String? = nil, flags: String = "", kind6firstQuote: Event? = nil, context: NSManagedObjectContext) -> Event {
        #if DEBUG
            if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                fatalError("Should only be called from bg()")
            }
        #endif
        
        if event.kind == .setMetadata {
            QueuedFetcher.shared.addRecentP(pTag: event.publicKey)
        }
        else {
            QueuedFetcher.shared.addRecentId(id: event.id)
        }
        
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
        savedEvent.otherAtag = savedEvent.firstA()

        savedEvent.tagsSerialized = TagSerializer.shared.encode(tags: event.tags) // TODO: why encode again, need to just store what we received before (performance)
        
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
                        CoreDataRelationFixer.shared.addTask({
                            guard contextWontCrash([savedEvent, awaitingEvent], debugInfo: "OO savedEvent.zappedEvent = awaitingEvent") else { return }
                            savedEvent.zappedEvent = awaitingEvent
                        })
                         // Thread 3273: "Illegal attempt to establish a relationship 'zappedEvent' between objects in different contexts
                        // _PFManagedObject_coerceValueForKeyWithDescription
                        // _sharedIMPL_setvfk_core
                    }
                    else {
                        CoreDataRelationFixer.shared.addTask({
                            if let zappedEvent = Event.fetchEvent(id: firstE, context: context) {
                                guard contextWontCrash([savedEvent, zappedEvent], debugInfo: "NN savedEvent.zappedEvent = zappedEvent") else { return }
                                savedEvent.zappedEvent = zappedEvent
                            }
                        })
                    }
                    if let zapRequest, zapRequest.pubkey == AccountsState.shared.activeAccountPublicKey {
                        savedEvent.zappedEvent?.zapState = .zapReceiptConfirmed
                        ViewUpdates.shared.zapStateChanged.send(ZapStateChange(pubkey: savedEvent.pubkey, eTag: savedEvent.zappedEventId, zapState: .zapReceiptConfirmed))
                        
                        // Update own zapped cache
                        Task { @MainActor in
                            accountCache()?.addZapped(firstE)
                            sendNotification(.postAction, PostActionNotification(type: .zapped, eventId: firstE))
                        }
                    }
                }
                if let firstA = event.firstA() {
                    savedEvent.zappedEventId = firstA
                    savedEvent.otherAtag = firstA
                    
                    if let awaitingEvent = EventRelationsQueue.shared.getAwaitingBgEvent(byId: firstA) {
                        CoreDataRelationFixer.shared.addTask({
                            guard contextWontCrash([savedEvent, awaitingEvent], debugInfo: "MM savedEvent.zappedEvent = awaitingEvent") else { return }
                            savedEvent.zappedEvent = awaitingEvent
                        })
                        // Thread 3273: "Illegal attempt to establish a relationship 'zappedEvent' between objects in different contexts
                        // _PFManagedObject_coerceValueForKeyWithDescription
                        // _sharedIMPL_setvfk_core
                    }
                    else {
                        CoreDataRelationFixer.shared.addTask({
                            if let zappedEvent = Event.fetchEvent(id: firstA, context: context) {
                                guard contextWontCrash([savedEvent, zappedEvent], debugInfo: "LL savedEvent.zappedEvent = zappedEvent") else { return }
                                savedEvent.zappedEvent = zappedEvent
                            }
                        })
                    }
                    if let zapRequest, zapRequest.pubkey == AccountsState.shared.activeAccountPublicKey {
                        savedEvent.zappedEvent?.zapState = .zapReceiptConfirmed
                        ViewUpdates.shared.zapStateChanged.send(ZapStateChange(pubkey: savedEvent.pubkey, aTag: firstA, zapState: .zapReceiptConfirmed))
                        // TODO: How to handle a tag here?? need to update cache and reading from cache if its aTag instead of id
                        // Update own zapped cache
//                        Task { @MainActor in
//                            accountCache()?.addZapped(firstA)
//                        sendNotification(.postAction, PostActionNotification(type: .zapped, eventId: firstA))
//                        }
                    }
                }
                if let firstP = event.firstP() {
//                    savedEvent.objectWillChange.send()
                    savedEvent.otherPubkey = firstP
                    if let zappedContact = Contact.fetchByPubkey(firstP, context: context) {
                        CoreDataRelationFixer.shared.addTask({
                            guard contextWontCrash([savedEvent, zappedContact], debugInfo: "KK savedEvent.zappedContact = zappedContact") else { return }
                            savedEvent.zappedContact = zappedContact
                        })
                    }
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
                savedEvent.reactionToId = lastE
                // Thread 927: "Illegal attempt to establish a relationship 'reactionTo' between objects in different contexts
                // here savedEvent is not saved yet, so appears it can crash on context, even when its the same context
                CoreDataRelationFixer.shared.addTask({
                    if let reactionTo = Event.fetchEvent(id: lastE, context: context) {
                        guard contextWontCrash([savedEvent, reactionTo], debugInfo: "JJ savedEvent.reactionTo = reactionTo") else { return }
                        savedEvent.reactionTo = reactionTo
                    }
                })
                
                if let otherPubkey =  savedEvent.reactionTo?.pubkey {
                    savedEvent.otherPubkey = otherPubkey
                }
                if savedEvent.otherPubkey == nil, let lastP = event.lastP() {
                    savedEvent.otherPubkey = lastP
                }
            }
        }
        
        if (event.kind == .textNote) {
            
            // backwards compatible tag (used for kind 20 for now)
            if let kTag = event.fastTags.first(where: { $0.0 == "k" })?.1, let kTagInt = Int64(kTag) {
                savedEvent.kTag = kTagInt
            }
            
            EventCache.shared.setObject(for: event.id, value: savedEvent)
#if DEBUG
            L.og.debug("Saved \(event.id) in cache -[LOG]-")
#endif
            
            if event.content == "#[0]", let firstE = event.firstE() {
                savedEvent.isRepost = true
                
                savedEvent.firstQuoteId = firstE
                
                if let kind6firstQuote = kind6firstQuote {
                    CoreDataRelationFixer.shared.addTask({
                        guard contextWontCrash([savedEvent, kind6firstQuote], debugInfo: "#[0] savedEvent.firstQuote = kind6firstQuote") else { return }
                        savedEvent.firstQuote = kind6firstQuote // got it passed in as parameter on saveEvent() already.
                        
                        // Also save reposted pubkey in .otherPubkey for easy querying for repost notifications
                        savedEvent.otherPubkey = kind6firstQuote.pubkey
                    })
                }
                else {
                    // IF WE ALREADY HAVE THE FIRST QUOTE, ADD OUR NEW EVENT + UPDATE REPOST COUNT
                    if let repostedEvent = Event.fetchEvent(id: savedEvent.firstQuoteId!, context: context) {
                        CoreDataRelationFixer.shared.addTask({
                            guard contextWontCrash([savedEvent, repostedEvent], debugInfo: "II savedEvent.firstQuote = repostedEvent") else { return }
                            savedEvent.firstQuote = repostedEvent
                            
                            // Also save reposted pubkey in .otherPubkey for easy querying for repost notifications
                            savedEvent.otherPubkey = repostedEvent.pubkey
                        })
                        repostedEvent.repostsCount = (repostedEvent.repostsCount + 1)
//                        repostedEvent.repostsDidChange.send(repostedEvent.repostsCount)
                        ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: repostedEvent.id, reposts: repostedEvent.repostsCount))
                    }
                    else if let firstP = event.firstP() { // or lastP? not sure
                        savedEvent.otherPubkey = firstP
                    }
                }
            }
            
            if let replyToAtag = event.replyToAtag() { // Comment on article
                if let dbArticle = Event.fetchReplacableEvent(aTag: replyToAtag.value, context: context) {
                    savedEvent.replyToId = dbArticle.id
                    CoreDataRelationFixer.shared.addTask({
                        guard contextWontCrash([savedEvent, dbArticle], debugInfo: "HH savedEvent.replyTo = dbArticle") else { return }
                        savedEvent.replyTo = dbArticle
                    })
                    
                    dbArticle.addToReplies(savedEvent)
                    dbArticle.repliesCount += 1
//                    dbArticle.repliesUpdated.send(dbArticle.replies_)
                    ViewUpdates.shared.repliesUpdated.send(EventRepliesChange(id: dbArticle.id, replies: dbArticle.replies_))
                    ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: dbArticle.id, replies: dbArticle.repliesCount))
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
                    CoreDataRelationFixer.shared.addTask({
                        guard contextWontCrash([savedEvent, dbArticle], debugInfo: "GG savedEvent.replyToRoot = dbArticle") else { return }
                        savedEvent.replyToRoot = dbArticle
                    })
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
                if let parent = Event.fetchEvent(id: replyToEtag.id, context: context) {
                    CoreDataRelationFixer.shared.addTask({
                        // Thread 24: "Illegal attempt to establish a relationship 'replyTo' between objects in different contexts
                        // (when opening from bookmarks)
                        guard contextWontCrash([savedEvent, parent], debugInfo: "FF savedEvent.replyTo = parent") else { return }
                        savedEvent.replyTo = parent
                    })
                    // Illegal attempt to establish a relationship 'replyTo' between objects in different contexts
                    parent.addToReplies(savedEvent)
                    parent.repliesCount += 1
//                    replyTo.repliesUpdated.send(replyTo.replies_)
                    ViewUpdates.shared.repliesUpdated.send(EventRepliesChange(id: parent.id, replies: parent.replies_))
                    ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: parent.id, replies: parent.repliesCount))
                }
            }
            
            // IF THE THERE IS A ROOT, AND ITS NOT THE SAME AS THE REPLY TO. AND ROOT IS NOT ALREADY SET FROM ROOTATAG
            // DO THE SAME AS WITH THE REPLY BEFORE
            if let replyToRootEtag = event.replyToRootEtag(), savedEvent.replyToRootId == nil {
                savedEvent.replyToRootId = replyToRootEtag.id
                // Need to put it in queue to fix relations for replies to root / grouped replies
                //                EventRelationsQueue.shared.addAwaitingEvent(savedEvent, debugInfo: "saveEvent.123")
                
                let replyToRootIsSameAsReplyTo = savedEvent.replyToId == replyToRootEtag.id
                
                if (savedEvent.replyToId == nil) {
                    savedEvent.replyToId = savedEvent.replyToRootId // NO REPLYTO, SO REPLYTOROOT IS THE REPLYTO
                }
                
                if !replyToRootIsSameAsReplyTo, let root = Event.fetchEvent(id: replyToRootEtag.id, context: context) {
                    
                    CoreDataRelationFixer.shared.addTask({
                        guard contextWontCrash([savedEvent, root], debugInfo: "EE savedEvent.replyToRoot = root") else { return }
                        savedEvent.replyToRoot = root
                    })
                    
                    // Thread 32193: "Illegal attempt to establish a relationship 'replyToRoot' between objects in different contexts (source = <Nostur.Event: 0x371850ee0> (entity: Event; id: 0x351b9e3e0 <x-coredata:///Event/tB769F78C-0ED3-427A-B8A2-BDDA94C71D1030798>; data: {\n    bookmarkedBy =     (\n    );\n    contact = \"0xafbaca1f2e1691dc <x-coredata://3DA0D6F2-885E-43D0-B952-9C23B7D82BA8/Contact/p12190>\";\n    content = \"Do you mind elaborating on \\U201crolling your own kind number is a heavy lift in practice\\U201d? \\n\\nIs it the choice of which kind number to use that\\U2019s the blocker? Are people hesitant to pick a new one and just\";\n    \"created_at\" = 1728407076;\n    dTag = \"\";\n    deletedById = nil;\n    dmAccepted = 0;\n    firstQuote = nil;\n    firstQuoteId = nil;\n    flags = \"\";\n    id = 10eeb3d72083929e9409750c6ad009f736297557b6f8e76bb320b3bd1e61bebd;\n    insertedAt = \"2024-10-10 19:27:50 +0000\";\n    isRepost = 0;\n    kind = 1;\n    lastSeenDMCreatedAt = 0;\n    likesCount = 0;\n    mentionsCount = 0;\n    mostRecentId = nil;\n    otherAtag"
                    
                    ViewUpdates.shared.eventRelationUpdate.send(EventRelationUpdate(relationType: .replyToRoot, id: savedEvent.id, event: root))
                    ViewUpdates.shared.eventRelationUpdate.send(EventRelationUpdate(relationType: .replyToRootInverse, id:  root.id, event: savedEvent))
                    if (savedEvent.replyToId == savedEvent.replyToRootId) {
                        CoreDataRelationFixer.shared.addTask({
                            guard contextWontCrash([savedEvent, root], debugInfo: "DD savedEvent.replyTo = root") else { return }
                            savedEvent.replyTo = root // NO REPLYTO, SO REPLYTOROOT IS THE REPLYTO
                        })
                        root.addToReplies(savedEvent)
                        root.repliesCount += 1
                        ViewUpdates.shared.repliesUpdated.send(EventRepliesChange(id: root.id, replies: root.replies_))
                        ViewUpdates.shared.eventRelationUpdate.send(EventRelationUpdate(relationType: .replyTo, id: savedEvent.id, event: root))
                        ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: root.id, replies: root.repliesCount))
                    }
                }
            }
            
            // Finally, we have a reply to root set from aTag, but we still don't have a replyTo
            else if savedEvent.replyToRootId != nil, savedEvent.replyToId == nil {
                // so set replyToRoot (aTag) as replyTo
                savedEvent.replyToId = savedEvent.replyToRootId
                CoreDataRelationFixer.shared.addTask({
                    guard let replyToRoot = savedEvent.replyToRoot, contextWontCrash([savedEvent, replyToRoot], debugInfo: "CC savedEvent.replyTo = replyToRoot") else { return }
                    savedEvent.replyTo = replyToRoot
                    
                    if let parent = savedEvent.replyTo {
                        parent.addToReplies(savedEvent)
                        parent.repliesCount += 1
    //                    replyTo.repliesUpdated.send(replyTo.replies_)
                        ViewUpdates.shared.repliesUpdated.send(EventRepliesChange(id: parent.id, replies: parent.replies_))
                        ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: parent.id, replies: parent.repliesCount))
                    }
                })
            }
            
            if let replyToId = savedEvent.replyToId, event.publicKey == AccountsState.shared.activeAccountPublicKey {
                // Update own replied to cache
                Task { @MainActor in
                    accountCache()?.addRepliedTo(replyToId)
                    sendNotification(.postAction, PostActionNotification(type: .replied, eventId: replyToId))
                }
            }
        }
        
        if (event.kind == .directMessage) { // needed to fetch contact in DMS: so event.firstP is in event.contacts
            savedEvent.otherPubkey = event.firstP()
            
            if let contactPubkey = savedEvent.otherPubkey { // If we have a DM kind 4, but no p, then something is wrong
                if let dmState = CloudDMState.fetchExisting(event.publicKey, contactPubkey: contactPubkey, context: context) {
                    
                    // if we already track the conversation, consider accepted if we replied to the DM
                    // DM is sent from one of our current logged in pubkey
                    if !dmState.accepted && AccountsState.shared.bgAccountPubkeys.contains(event.publicKey) {
                        dmState.accepted = true
                        
                        if let current = dmState.markedReadAt_, savedEvent.date > current {
                            dmState.markedReadAt_ = savedEvent.date
                        }
                        else if dmState.markedReadAt_ == nil {
                            dmState.markedReadAt_ = savedEvent.date
                        }
                    }
                    // Let DirectMessageViewModel handle view updates
                    DirectMessageViewModel.default.newMessage(dmState)
                    DirectMessageViewModel.default.checkNeedsNotification(savedEvent)
                }
                // Same but account / contact switched, because we support multiple accounts so we need to be able to track both ways
                else if let dmState = CloudDMState.fetchExisting(contactPubkey, contactPubkey: event.publicKey, context: context) {
                    
                    // if we already track the conversation, consider accepted if we replied to the DM
                    if !dmState.accepted && AccountsState.shared.bgAccountPubkeys.contains(event.publicKey) {
                        dmState.accepted = true
                    }
                    // Let DirectMessageViewModel handle view updates
                    DirectMessageViewModel.default.newMessage(dmState)
                    DirectMessageViewModel.default.checkNeedsNotification(savedEvent)
                }
                else {
                    // if we are sender with full account
                    if AccountsState.shared.bgAccountPubkeys.contains(event.publicKey) {
                        let dmState = CloudDMState(context: context)
                        dmState.accountPubkey_ = event.publicKey
                        dmState.contactPubkey_ = contactPubkey
                        dmState.accepted = true
                        dmState.markedReadAt_ = savedEvent.date
                        // Let DirectMessageViewModel handle view updates
                        DirectMessageViewModel.default.newMessage(dmState)
                        DirectMessageViewModel.default.checkNeedsNotification(savedEvent)
                    }
                    
                    // if we are receiver with full account
                    else if AccountsState.shared.bgAccountPubkeys.contains(contactPubkey) {
                        let dmState = CloudDMState(context: context)
                        dmState.accountPubkey_ = contactPubkey
                        dmState.contactPubkey_ = event.publicKey
                        dmState.accepted = false
                        // Let DirectMessageViewModel handle view updates
                        DirectMessageViewModel.default.newMessage(dmState)
                        DirectMessageViewModel.default.checkNeedsNotification(savedEvent)
                    }
                    
                    // if we are sender with read only account
                    else if AccountsState.shared.bgAccountPubkeys.contains(event.publicKey) {
                        let dmState = CloudDMState(context: context)
                        dmState.accountPubkey_ = event.publicKey
                        dmState.contactPubkey_ = contactPubkey
                        dmState.accepted = true
                        dmState.markedReadAt_ = savedEvent.date
                        // Let DirectMessageViewModel handle view updates
                        DirectMessageViewModel.default.newMessage(dmState)
                        DirectMessageViewModel.default.checkNeedsNotification(savedEvent)
                    }
                    
                    // if we are receiver with read only account
                    else if AccountsState.shared.bgAccountPubkeys.contains(contactPubkey) {
                        let dmState = CloudDMState(context: context)
                        dmState.accountPubkey_ = contactPubkey
                        dmState.contactPubkey_ = event.publicKey
                        dmState.accepted = false
                        // Let DirectMessageViewModel handle view updates
                        DirectMessageViewModel.default.newMessage(dmState)
                        DirectMessageViewModel.default.checkNeedsNotification(savedEvent)
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
            if let firstQuote = Event.fetchEvent(id: savedEvent.firstQuoteId!, context: context) {
                CoreDataRelationFixer.shared.addTask({
                    guard contextWontCrash([savedEvent, firstQuote], debugInfo: "BB savedEvent.firstQuote = firstQuote") else { return }
                    savedEvent.firstQuote = firstQuote
                })
                
                if (firstE.tag[safe: 3] == "mention") {
//                    firstQuote.objectWillChange.send()
                    firstQuote.mentionsCount += 1
                    alreadyCounted = true
                }
            }
        }
        
        // hmm above firstQuote doesn't seem to handle #[0] at .content end and "e" without "mention as first tag, so special case?
        if !alreadyCounted && event.kind == .textNote && event.content.contains("#[0]"), let firstE = event.firstMentionETag() {
            savedEvent.firstQuoteId = firstE.id
            
            // IF WE ALREADY HAVE THE FIRST QUOTE, ADD OUR NEW EVENT IN THE MENTIONS
            if let firstQuote = Event.fetchEvent(id: savedEvent.firstQuoteId!, context: context) {
                CoreDataRelationFixer.shared.addTask({
                    guard contextWontCrash([savedEvent, firstQuote], debugInfo: "AA savedEvent.firstQuote = firstQuote") else { return }
                    savedEvent.firstQuote = firstQuote
                })
                
//                firstQuote.objectWillChange.send()
                firstQuote.mentionsCount += 1
            }
        }
        
        // kind6 - repost, the reposted post is put in as .firstQuote
        if event.kind == .repost {
            savedEvent.firstQuoteId = kind6firstQuote?.id ?? event.firstE()
            
            if let firstQuoteId = savedEvent.firstQuoteId, event.publicKey == AccountsState.shared.activeAccountPublicKey {
                // Update own reposted cache
                Task { @MainActor in
                    accountCache()?.addReposted(firstQuoteId)
                    sendNotification(.postAction, PostActionNotification(type: .reposted, eventId: firstQuoteId))
                }
            }
            
            if let kind6firstQuote {
                CoreDataRelationFixer.shared.addTask({
                    guard contextWontCrash([savedEvent, kind6firstQuote], debugInfo: ".repost savedEvent.firstQuote = kind6firstQuote") else { return }
                    savedEvent.firstQuote = kind6firstQuote // got it passed in as parameter on saveEvent() already.
                    
                    // if we already have the firstQuote (reposted post), we use that .pubkey
                    savedEvent.otherPubkey = kind6firstQuote.pubkey
                    
                    if let repostedEvent = savedEvent.firstQuote { // we already got firstQuote passed in as param
                        repostedEvent.repostsCount = (repostedEvent.repostsCount + 1)
        //                repostedEvent.repostsDidChange.send(repostedEvent.repostsCount)
                        ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: repostedEvent.id, reposts: repostedEvent.repostsCount))
                    }
                    else {
                        // We need to get firstQuote from db or cache
                        if let firstE = event.firstE() {
                            if let repostedEvent = EventRelationsQueue.shared.getAwaitingBgEvent(byId: firstE) {
                                savedEvent.firstQuote = repostedEvent // "Illegal attempt to establish a relationship 'firstQuote' between objects in different contexts
                                repostedEvent.repostsCount = (repostedEvent.repostsCount + 1)
        //                        repostedEvent.repostsDidChange.send(repostedEvent.repostsCount)
                                ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: repostedEvent.id, reposts: repostedEvent.repostsCount))
                            }
                            else if let repostedEvent = Event.fetchEvent(id: firstE, context: context) {
                                savedEvent.firstQuote = repostedEvent
                                repostedEvent.repostsCount = (repostedEvent.repostsCount + 1)
        //                        repostedEvent.repostsDidChange.send(repostedEvent.repostsCount)
                                ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: repostedEvent.id, reposts: repostedEvent.repostsCount))
                            }
                        }
                    }
                })
            }
            else if savedEvent.firstQuoteId != nil, let firstP = event.firstP() { // or lastP?
                // Also save reposted pubkey in .otherPubkey for easy querying for repost notifications
                savedEvent.otherPubkey = firstP
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
        
        if (event.kind.id >= 10000 && event.kind.id < 20000) {
            // delete older events
            let r = NSFetchRequest<NSFetchRequestResult>(entityName: "Event")
            r.predicate = NSPredicate(format: "kind == %d AND pubkey == %@ AND created_at < %d", event.kind.id, event.publicKey, savedEvent.created_at)
            let batchDelete = NSBatchDeleteRequest(fetchRequest: r)
            batchDelete.resultType = .resultTypeCount
            
            do {
                _ = try context.execute(batchDelete) as! NSBatchDeleteResult
            } catch {
                L.og.error("🔴🔴 Failed to delete older replaceable events for \(event.id)")
            }
        }
        
        if event.kind == .delete {
            let eventIdsToDelete = event.eTags()
            // TODO: Also do aTags
            
            let eventIdsToDeleteReq = NSFetchRequest<Event>(entityName: "Event")
            
            // Only same author (pubkey) can delete
            eventIdsToDeleteReq.predicate = NSPredicate(format: "kind IN {1,1111,1222,1244,6,20,9802,10001,10601,30023,34235} AND pubkey = %@ AND id IN %@ AND deletedById = nil", event.publicKey, eventIdsToDelete)
            eventIdsToDeleteReq.sortDescriptors = []
            if let eventsToDelete = try? context.fetch(eventIdsToDeleteReq) {
                for eventToDelete in eventsToDelete {
                    eventToDelete.deletedById = event.id
                    ViewUpdates.shared.postDeleted.send((toDeleteId: eventToDelete.id, deletedById: event.id))
                }
            }
        }
        
        // Handle replacable event (NIP-33)
        if (event.kind.id >= 30000 && event.kind.id < 40000) {
            savedEvent.dTag = event.tags.first(where: { $0.type == "d" })?.value ?? ""
            // update older events:
            // 1. set pointer to most recent (this one)
            // 2. set "is_update" flag on this one so it doesn't show up as new in feed
            let r = Event.fetchRequest()
            r.predicate = NSPredicate(format: "dTag == %@ AND kind == %d AND pubkey == %@", savedEvent.dTag, savedEvent.kind, event.publicKey)

            var existingEventIds = Set<String>() // need to repoint all replies to older articles to the newest id
            
            // Set pointer on older events to the latest event id
            if let existingEvents = try? context.fetch(r) {
                
                // existingEvents will already include the savedEvent event also (can also be older one, if from relay that doesn't have latest
                let newestFirst = existingEvents.sorted { $0.created_at > $1.created_at }
                
                // most recent event (.created_at)
                if let first = newestFirst.first {
                    // .mostRecentId should be nil
                    first.mostRecentId = nil
                    
                    // if we already had this article, mark this one as "is_update" so it doesn't reappear in feed
                    if existingEvents.count > 1 && first.id == savedEvent.id {
                        savedEvent.flags = "is_update" // is supdate, don't reappear in feed
                    }
                    
                    // older events
                    for existingEvent in newestFirst.dropFirst() {
                        existingEvent.mostRecentId = first.id
                        existingEventIds.insert(existingEvent.id)
                    }
                    
                    
                    
                    // Find existing replies referencing this event (can only be replyToRootId = "3XXXX:pubkey:dTag", or replyToRootId = "<older article ids>")
                    // also do for replyToId
                    if savedEvent.kind == 30023 { // Only do this for articles
                        existingEventIds.insert(savedEvent.aTag)
                        let fr = Event.fetchRequest()
                        fr.predicate = NSPredicate(format: "kind IN {1,1111,1244} AND replyToRootId IN %@", existingEventIds)
                        if let existingReplies = try? context.fetch(fr) {
                            for existingReply in existingReplies {
                                existingReply.replyToRootId = first.id
                                existingReply.replyToRoot = first
                            }
                        }
                        
                        let fr2 = Event.fetchRequest()
                        fr2.predicate = NSPredicate(format: "kind IN {1,1111,1244} AND replyToId IN %@", existingEventIds)
                        if let existingReplies = try? context.fetch(fr) {
                            for existingReply in existingReplies {
                                existingReply.replyToId = first.id
                                existingReply.replyTo = first
                            }
                        }
                    }
                }
            }

            if Set([30311]).contains(savedEvent.kind) { // Only update views for kinds that need it (so far: 30311)
                ViewUpdates.shared.replacableEventUpdate.send(savedEvent)
            }
        }
        
        
        
        
        
        // Use new EventRelationsQueue to fix relations
        if (event.kind == .textNote) {
            
            let awaitingEvents = EventRelationsQueue.shared.getAwaitingBgEvents()
            
            for waitingEvent in awaitingEvents {
                if (waitingEvent.replyToId != nil) && (waitingEvent.replyToId == savedEvent.id) {
                    CoreDataRelationFixer.shared.addTask({
                        guard contextWontCrash([savedEvent, waitingEvent], debugInfo: "waitingEvent.replyTo = savedEvent") else { return }
                        waitingEvent.replyTo = savedEvent
                    })
                    ViewUpdates.shared.eventRelationUpdate.send((EventRelationUpdate(relationType: .replyTo, id: waitingEvent.id, event: savedEvent)))
                }
                if (waitingEvent.replyToRootId != nil) && (waitingEvent.replyToRootId == savedEvent.id) {
                    CoreDataRelationFixer.shared.addTask({
                        guard contextWontCrash([savedEvent, waitingEvent], debugInfo: "waitingEvent.replyToRoot = savedEvent") else { return }
                        waitingEvent.replyToRoot = savedEvent
                    })
                    ViewUpdates.shared.eventRelationUpdate.send((EventRelationUpdate(relationType: .replyToRoot, id: waitingEvent.id, event: savedEvent)))
                    ViewUpdates.shared.eventRelationUpdate.send((EventRelationUpdate(relationType: .replyToRootInverse, id: savedEvent.id, event: waitingEvent)))
                }
                if (waitingEvent.firstQuoteId != nil) && (waitingEvent.firstQuoteId == savedEvent.id) {
                    CoreDataRelationFixer.shared.addTask({
                        // Ensure both objects have a valid context
                        guard contextWontCrash([waitingEvent, savedEvent], debugInfo: "waitingEvent.firstQuote = savedEvent") else { return }
                        waitingEvent.firstQuote = savedEvent
                    })
                    ViewUpdates.shared.eventRelationUpdate.send((EventRelationUpdate(relationType: .firstQuote, id: waitingEvent.id, event: savedEvent)))
                }
            }
        }
        
        
        
        // Handle Voice Message (root)
        if (event.kind == .shortVoiceMessage) {
            
            EventCache.shared.setObject(for: event.id, value: savedEvent)
#if DEBUG
            L.og.debug("Saved \(event.id) in cache -[LOG]-")
#endif
            
            // IF we already have replies, need to link them to this root:
            let awaitingEvents = EventRelationsQueue.shared.getAwaitingBgEvents()
            
            for waitingEvent in awaitingEvents {
                if (waitingEvent.replyToId != nil) && (waitingEvent.replyToId == savedEvent.id) {
                    CoreDataRelationFixer.shared.addTask({
                        guard contextWontCrash([savedEvent, waitingEvent], debugInfo: "XwaitingEvent.replyTo = savedEvent") else { return }
                        waitingEvent.replyTo = savedEvent
                    })
                    ViewUpdates.shared.eventRelationUpdate.send((EventRelationUpdate(relationType: .replyTo, id: waitingEvent.id, event: savedEvent)))
                }
                if (waitingEvent.replyToRootId != nil) && (waitingEvent.replyToRootId == savedEvent.id) {
                    CoreDataRelationFixer.shared.addTask({
                        guard contextWontCrash([savedEvent, waitingEvent], debugInfo: "XwaitingEvent.replyToRoot = savedEvent") else { return }
                        waitingEvent.replyToRoot = savedEvent
                    })
                    ViewUpdates.shared.eventRelationUpdate.send((EventRelationUpdate(relationType: .replyToRoot, id: waitingEvent.id, event: savedEvent)))
                    ViewUpdates.shared.eventRelationUpdate.send((EventRelationUpdate(relationType: .replyToRootInverse, id: savedEvent.id, event: waitingEvent)))
                }
            }
            
        }
        
        
        // Handle Voice Message (comment/reply)
        if NIP22_COMMENT_KINDS.contains(event.kind.id) {
            EventCache.shared.setObject(for: event.id, value: savedEvent)
#if DEBUG
            L.og.debug("Saved \(event.id) in cache -[LOG]-")
#endif
            
            // THIS EVENT REPLYING TO SOMETHING
            // CACHE THE REPLY "E" IN replyToId
            if let replyToEtag = event.replyToEtag(), savedEvent.replyToId == nil {
                savedEvent.replyToId = replyToEtag.id
                
                // IF WE ALREADY HAVE THE PARENT, ADD OUR NEW EVENT IN THE REPLIES
                if let parent = Event.fetchEvent(id: replyToEtag.id, context: context) {
                    CoreDataRelationFixer.shared.addTask({
                        // Thread 24: "Illegal attempt to establish a relationship 'replyTo' between objects in different contexts
                        // (when opening from bookmarks)
                        guard contextWontCrash([savedEvent, parent], debugInfo: "XF savedEvent.replyTo = parent") else { return }
                        savedEvent.replyTo = parent
                    })
                    // Illegal attempt to establish a relationship 'replyTo' between objects in different contexts
                    parent.addToReplies(savedEvent)
                    parent.repliesCount += 1
//                    replyTo.repliesUpdated.send(replyTo.replies_)
                    ViewUpdates.shared.repliesUpdated.send(EventRepliesChange(id: parent.id, replies: parent.replies_))
                    ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: parent.id, replies: parent.repliesCount))
                }
            }
            
            // IF THE THERE IS A ROOT, AND ITS NOT THE SAME AS THE REPLY TO. AND ROOT IS NOT ALREADY SET FROM ROOT E TAG
            // DO THE SAME AS WITH THE REPLY BEFORE
            if let replyToRootEtag = event.replyToRootEtag(), savedEvent.replyToRootId == nil {
                savedEvent.replyToRootId = replyToRootEtag.id
                // Need to put it in queue to fix relations for replies to root / grouped replies
                //                EventRelationsQueue.shared.addAwaitingEvent(savedEvent, debugInfo: "saveEvent.123")
                
                let replyToRootIsSameAsReplyTo = savedEvent.replyToId == replyToRootEtag.id
                
                if (savedEvent.replyToId == nil) {
                    savedEvent.replyToId = savedEvent.replyToRootId // NO REPLYTO, SO REPLYTOROOT IS THE REPLYTO
                }
                
                if !replyToRootIsSameAsReplyTo, let root = Event.fetchEvent(id: replyToRootEtag.id, context: context) {
                    
                    CoreDataRelationFixer.shared.addTask({
                        guard contextWontCrash([savedEvent, root], debugInfo: "XEE savedEvent.replyToRoot = root") else { return }
                        savedEvent.replyToRoot = root
                    })
                    
                    // Thread 32193: "Illegal attempt to establish a relationship 'replyToRoot' between objects in different contexts (source = <Nostur.Event: 0x371850ee0> (entity: Event; id: 0x351b9e3e0 <x-coredata:///Event/tB769F78C-0ED3-427A-B8A2-BDDA94C71D1030798>; data: {\n    bookmarkedBy =     (\n    );\n    contact = \"0xafbaca1f2e1691dc <x-coredata://3DA0D6F2-885E-43D0-B952-9C23B7D82BA8/Contact/p12190>\";\n    content = \"Do you mind elaborating on \\U201crolling your own kind number is a heavy lift in practice\\U201d? \\n\\nIs it the choice of which kind number to use that\\U2019s the blocker? Are people hesitant to pick a new one and just\";\n    \"created_at\" = 1728407076;\n    dTag = \"\";\n    deletedById = nil;\n    dmAccepted = 0;\n    firstQuote = nil;\n    firstQuoteId = nil;\n    flags = \"\";\n    id = 10eeb3d72083929e9409750c6ad009f736297557b6f8e76bb320b3bd1e61bebd;\n    insertedAt = \"2024-10-10 19:27:50 +0000\";\n    isRepost = 0;\n    kind = 1;\n    lastSeenDMCreatedAt = 0;\n    likesCount = 0;\n    mentionsCount = 0;\n    mostRecentId = nil;\n    otherAtag"
                    
                    ViewUpdates.shared.eventRelationUpdate.send(EventRelationUpdate(relationType: .replyToRoot, id: savedEvent.id, event: root))
                    ViewUpdates.shared.eventRelationUpdate.send(EventRelationUpdate(relationType: .replyToRootInverse, id:  root.id, event: savedEvent))
                    if (savedEvent.replyToId == savedEvent.replyToRootId) {
                        CoreDataRelationFixer.shared.addTask({
                            guard contextWontCrash([savedEvent, root], debugInfo: "DDX savedEvent.replyTo = root") else { return }
                            savedEvent.replyTo = root // NO REPLYTO, SO REPLYTOROOT IS THE REPLYTO
                        })
                        root.addToReplies(savedEvent)
                        root.repliesCount += 1
                        ViewUpdates.shared.repliesUpdated.send(EventRepliesChange(id: root.id, replies: root.replies_))
                        ViewUpdates.shared.eventRelationUpdate.send(EventRelationUpdate(relationType: .replyTo, id: savedEvent.id, event: root))
                        ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: root.id, replies: root.repliesCount))
                    }
                }
            }
            
            // Finally, we have a reply to root set from e tag, but we still don't have a replyTo
            else if savedEvent.replyToRootId != nil, savedEvent.replyToId == nil {
                // so set replyToRoot as replyTo
                savedEvent.replyToId = savedEvent.replyToRootId
                CoreDataRelationFixer.shared.addTask({
                    guard let replyToRoot = savedEvent.replyToRoot, contextWontCrash([savedEvent, replyToRoot], debugInfo: "CC savedEvent.replyTo = replyToRoot") else { return }
                    savedEvent.replyTo = replyToRoot
                    
                    if let parent = savedEvent.replyTo {
                        parent.addToReplies(savedEvent)
                        parent.repliesCount += 1
    //                    replyTo.repliesUpdated.send(replyTo.replies_)
                        ViewUpdates.shared.repliesUpdated.send(EventRepliesChange(id: parent.id, replies: parent.replies_))
                        ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: parent.id, replies: parent.repliesCount))
                    }
                })
            }
            
            if let replyToId = savedEvent.replyToId, event.publicKey == AccountsState.shared.activeAccountPublicKey {
                // Update own replied to cache
                Task { @MainActor in
                    accountCache()?.addRepliedTo(replyToId)
                    sendNotification(.postAction, PostActionNotification(type: .replied, eventId: replyToId))
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

// Can't fix context crash. We only have main context and bg context
// Sometimes there is suddely 0x0 context. Maybe when unsaved? Don't know how
// Just use this guard everywhere so we never crash anymore
func contextWontCrash(_ objects: [NSManagedObject], debugInfo: String? = nil) -> Bool {
    var theContext: NSManagedObjectContext? // <-- All events should have this context
    
    if objects.count(where: { $0.managedObjectContext == nil }) == objects.count {
        // if no objects have context, that should be fine too, none are saved yet
#if DEBUG
        L.og.debug("🟠🟠 all contexts nil, should be fine? - \(debugInfo ?? "")")
#endif
        return true
    }
    
    for object in objects {
        // We should at least have A context
        guard let context = object.managedObjectContext else {
#if DEBUG
            L.og.debug("🔴🔴 Missing context, preventing crash. - \(debugInfo ?? "")")
#endif
            return false
        }
        
        if theContext == nil { // This first context found
            theContext = context
        }
        else { // All other events should have the same context as the first event
            if theContext != context {
#if DEBUG
                L.og.debug("🔴🔴 Context is not the same for all events, preventing crash. - \(debugInfo ?? "")")
#endif
                return false
            }
        }
    }
    
    return true
}


struct ATag {
    
    let kind: Int64
    let pubkey: String
    let definition: String
    
    init(_ aTag: String) throws {
        let elements = aTag.split(separator: ":")
        guard elements.count >= 3 else { throw NSError(domain: "", code: 0, userInfo: nil) }
        
        guard let kindString = elements[safe: 0], let kind = Int64(kindString) else { throw NSError(domain: "", code: 0, userInfo: nil) }
        self.kind = kind
        
        guard let pubkey = elements[safe: 1] else { throw NSError(domain: "", code: 0, userInfo: nil) }
        self.pubkey = String(pubkey)
        
        guard let definition = elements[safe: 2] else { throw NSError(domain: "", code: 0, userInfo: nil) }
        self.definition = String(definition)
    }
    
    init(kind: Int64, pubkey: String, definition: String) {
        self.kind = kind
        self.pubkey = pubkey
        self.definition = definition
    }
    
    public var aTag: String {
        return String(format: "%lld:%@:%@", kind, pubkey, definition)
    }
}
