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
    
    // For other related Ids. eg Giftwrap ID
    @NSManaged public var otherId: String?
    
    // Link to CloudDMState.conversionId
    @NSManaged public var groupId: String?
    
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
    
    var shortId: String { String(id.prefix(8)) }
    
    var isSpam: Bool {
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
    
    var date: Date { Date(timeIntervalSince1970: Double(created_at)) }
    
    var ago: String { date.agoString }
    
    var authorKey: String { String(pubkey.prefix(5)) }
    
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
    
    var noteId: String {
        try! NIP19(prefix: "note", hexString: id).displayString
    }
    
    var npub: String { try! NIP19(prefix: "npub", hexString: pubkey).displayString }
    
    var via: String? { fastTags.first(where: { $0.0 == "client" })?.1 }
    
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
            
            
            CoreDataRelationFixer.shared.addTask({
                reactingToEvent.likesCount = (reactingToEvent.likesCount + 1)
                ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: reactingToEvent.id, likes: reactingToEvent.likesCount))
                guard contextWontCrash([reaction, reactingToEvent], debugInfo: "updateLikeCountCache") else { return }
                reaction.reactionTo = reactingToEvent
                reaction.reactionToId = reactingToEvent.id
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
            CoreDataRelationFixer.shared.addTask({
                zappedEvent.zapTally = (zappedEvent.zapTally + Int64(zap.naiveSats))
                zappedEvent.zapsCount = (zappedEvent.zapsCount + 1)
                ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: zappedEvent.id, zaps: zappedEvent.zapsCount, zapTally: zappedEvent.zapTally))
            })
        }
        
        // Repair things afterwards
        
        // Missing contact
        if zap.zappedContact == nil, let zappedPubkey = zap.otherPubkey {
            // but have in DB
            if let zappedContact = Contact.fetchByPubkey(zappedPubkey, context: context) {
                CoreDataRelationFixer.shared.addTask({
                    guard contextWontCrash([zap, zappedContact], debugInfo: "-- zap.zappedContact = zappedContact") else { return }
                    zap.zappedContact = zappedContact
                })
                
                if zappedContact.metadata_created_at == 0 { // no data yet
#if DEBUG
                    L.fetching.debug("⚡️⏳ updateZapTallyCache: missing contact info for zap. fetching: \(zappedContact.pubkey), and queueing zap \(zap.id) (A)")
#endif
                    QueuedFetcher.shared.enqueue(pTag: zappedPubkey)
                    ZapperPubkeyVerificationQueue.shared.addZap(zap)
                }
                
                // Check if zapper pubkey matches contacts published zapper pubkey
                else if zappedContact.zapperPubkeys.contains(zap.pubkey) {
                    zap.flags = "zpk_verified" // zapper pubkey is correct
                }
            }
            
            // don't have contact at all
            else {
#if DEBUG
                L.og.debug("⚡️🔴🔴 updateZapTallyCache: no contact for zap.otherPubkey: \(zappedPubkey)")
#endif
                QueuedFetcher.shared.enqueue(pTag: zappedPubkey)
                ZapperPubkeyVerificationQueue.shared.addZap(zap)
            }
        }

        
        else if let zappedContact = zap.zappedContact {
            
            if zappedContact.metadata_created_at == 0 { // Missing kind-0 metadata
#if DEBUG
                L.fetching.debug("⚡️⏳ updateZapTallyCache: missing contact info for zap. fetching: \(zappedContact.pubkey), and queueing zap \(zap.id)")
#endif
                QueuedFetcher.shared.enqueue(pTag: zappedContact.pubkey)
                ZapperPubkeyVerificationQueue.shared.addZap(zap)
            }
            else if zappedContact.zapperPubkeys.contains(zap.pubkey) {
                // Check if zapper pubkey matches contacts published zapper pubkey
                zap.flags = "zpk_verified" // zapper pubkey is correct
            }
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
    
    static func fetchEvent(id: String, isWrapId: Bool = false, context: NSManagedObjectContext) -> Event? {
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
        request.predicate = if !isWrapId {
            NSPredicate(format: "id == %@", id)
        } else {
            NSPredicate(format: "otherId == %@", id)
        }
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
    
    static func fetchEventsBy(pubkey: String, andKinds kinds: Set<Int>, context: NSManagedObjectContext) -> [Event] {
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        fr.predicate = NSPredicate(format: "pubkey == %@ AND kind IN %@", pubkey, kinds)
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
    
    static func fetchMostRecentEventBy(pubkey: String, andOtherPubkey otherPubkey: String? = nil, andKinds kinds: Set<Int>, context: NSManagedObjectContext) -> Event? {
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        fr.predicate = otherPubkey != nil
            ? NSPredicate(format: "pubkey == %@ AND otherPubkey == %@ AND kind IN %@", pubkey, otherPubkey!, kinds)
            : NSPredicate(format: "pubkey == %@ AND kind IN %d", pubkey, kinds)
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
    
    static func fetchReposts(id: String, context: NSManagedObjectContext = bg()) -> [Event] {
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
//        fr.predicate = NSPredicate(format: "(kind = 6 AND firstQuoteId == %@) OR (firstQuoteId = %@ AND kind = 1 AND content = \"#[0]\")", id, id)
        fr.predicate = NSPredicate(format: "kind = 6 AND firstQuoteId == %@", id)
        return (try? context.fetch(fr)) ?? []
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
    
    static func saveZapRequest(event: NEvent, context: NSManagedObjectContext) -> Event {
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
    
    static func safeUpdateRelays(for event: Event, relays: String) {
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
        
        CoreDataRelationFixer.shared.addTask({
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
        })
    }
    
    // TODO: 115.00 ms    1.0%    0 s          closure #1 in static Event.updateRelays(_:relays:)
    static func updateRelays(_ id: String, relays: String, isWrapId: Bool = false, context: NSManagedObjectContext) {
        #if DEBUG
            if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                fatalError("Should only be called from bg()")
            }
        #endif
        
        // Try getting event from queue first
        if let event = EventRelationsQueue.shared.getAwaitingBgEvent(byId: id),
           event.managedObjectContext != nil {
            safeUpdateRelays(for: event, relays: relays)
        }
        // Fallback to fetching from context
        else if let event = Event.fetchEvent(id: id, isWrapId: isWrapId, context: context) {
            safeUpdateRelays(for: event, relays: relays)
        }
    }
    
    // TODO: .saveEvent() and .importEvents() needs a refactor, to cleanly handle each kind in a reusable/maintainable way, this long list of if statements is becoming a mess.
    static func saveEvent(event: NEvent, relays: String? = nil, flags: String = "", kind6firstQuote: Event? = nil, wrapId: String? = nil, context: NSManagedObjectContext) -> Event {
        #if DEBUG
            if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                fatalError("Should only be called from bg()")
            }
        #endif
        
        if event.kind == .setMetadata { QueuedFetcher.shared.addRecentP(pTag: event.publicKey) }
        else { QueuedFetcher.shared.addRecentId(id: event.id) }
        
        // Save basic event info to DB
        let savedEvent = Event.fromNEvent(nEvent: event, flags: flags, context: context)
        savedEvent.otherId = wrapId // store outer wrap id on rumor
        
        // backwards compatible tag (used for kind 20 for now)
        if event.kind == .textNote, let kTag = event.fastTags.first(where: { $0.0 == "k" })?.1, let kTagInt = Int64(kTag) {
            savedEvent.kTag = kTagInt
        }
        
        if let relays = relays?.split(separator: " ").map({ String($0) }) {
            let uniqueRelays = Set(relays)
            savedEvent.relays = uniqueRelays.joined(separator: " ")
        }
        updateEventCache(wrapId ?? event.id, status: .SAVED, relays: relays)
        
        if (event.kind == .shortVoiceMessage || event.kind == .textNote || NIP22_COMMENT_KINDS.contains(event.kind.id)) {
            EventCache.shared.setObject(for: event.id, value: savedEvent)
#if DEBUG
            L.og.debug("Saved \(event.id) in cache -[LOG]-")
#endif
        }
        
        // Specific handling per kind
        handleZap(nEvent: event, savedEvent: savedEvent, context: context)
        handleReaction(nEvent: event, savedEvent: savedEvent, context: context)
        
        handleTextPost(nEvent: event, savedEvent: savedEvent, kind6firstQuote: kind6firstQuote, context: context)
        handlePostRelations(nEvent: event, savedEvent: savedEvent, context: context)
        handleRepost(nEvent: event, savedEvent: savedEvent, kind6firstQuote: kind6firstQuote, context: context)
        handleDM(nEvent: event, savedEvent: savedEvent, context: context)
        handleReplacableEvent(nEvent: event, context: context)
        handleAddressableReplacableEvent(nEvent: event, savedEvent: savedEvent, context: context)
        handleDelete(nEvent: event, context: context)
        handleComment(nEvent: event, savedEvent: savedEvent, context: context)
        handleProfileUpdate(nEvent: event, savedEvent: savedEvent, context: context)
        
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
    
    static func zapsForEvent(_ id: String, context: NSManagedObjectContext) -> [Event] {
        let fr = Event.fetchRequest()
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        fr.predicate = NSPredicate(format: "zappedEventId == %@ AND kind == 9735", id)
        
        return (try? context.fetch(fr)) ?? []
    }
    
    static func fromNEvent(nEvent: NEvent, flags: String = "", context: NSManagedObjectContext) -> Event {
        let savedEvent = Event(context: context)
        savedEvent.insertedAt = Date.now
        savedEvent.id = nEvent.id
        savedEvent.kind = Int64(nEvent.kind.id)
        savedEvent.created_at = Int64(nEvent.createdAt.timestamp)
        savedEvent.content = nEvent.content
        savedEvent.sig = nEvent.signature
        savedEvent.pubkey = nEvent.publicKey
        savedEvent.likesCount = 0
        savedEvent.flags = flags
        savedEvent.otherAtag = savedEvent.firstA()

        savedEvent.tagsSerialized = TagSerializer.shared.encode(tags: nEvent.tags) // TODO: why encode again, need to just store what we received before (performance)
        return savedEvent
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
