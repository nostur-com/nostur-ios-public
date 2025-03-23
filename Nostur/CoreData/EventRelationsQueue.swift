//
//  EventRelationsQueue.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/04/2023.
//

// When posts have related events that need to be fetched
// we queue them here so we don't have to query the entire
// local database of possibly 50000+ events

// Typically the flow will be:
// 1. We have some post, with a replyToRootId or replyToId, but not the reply or root itself
// 2. We queue this post here
// 3. We ask relays for the reply/root
// 4. Reply/Root comes in through socket didReceive -> MessageParser -> Importer
// 5. Reply/Root is saved in DB (BEFORE: OLD METHOD: this was were we updated the relation, but very slow since we need to query for any posts that have a matching replyToRootId or replyToId)
// 6. (NEW METHOD:) We check if there are any posts waiting for relations in EventRelationsQueue (Fast)
// 7. Update and save relation, send objectWillChange

import Foundation
import CoreData

class EventRelationsQueue {
    
    private let SPAM_LIMIT = 2000
    
    typealias EventId = String
    typealias ContactPubkey = String
    
    public struct QueuedEvent {
        let event: Event
        let queuedAt: Date
    }
    
    public struct QueuedContact {
        let contact: Contact
        let queuedAt: Date
    }
    
    static let shared = EventRelationsQueue()
    
    private var ctx = bg()
    private var waitingEvents = [EventId: QueuedEvent]()
    private var waitingContacts = [ContactPubkey: QueuedContact]()
    private var cleanUpTimer: Timer?
    
    private init() {
        cleanUpTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true, block: { [unowned self] timer in
            let now = Date()
            
            self.ctx.perform { [unowned self] in
                self.waitingEvents = self.waitingEvents.filter { now.timeIntervalSince($0.value.queuedAt) < 30 }
                self.waitingContacts = self.waitingContacts.filter { now.timeIntervalSince($0.value.queuedAt) < 30 }
            }            
        })
    }
    
    /// Adds event to the queue waiting for related data that is being fetched
    /// - Parameter event: Event should be from .bg context, if not this function will fetch it from .bg using .objectID
    public func addAwaitingEvent(_ event: Event? = nil, debugInfo: String? = "") {
        guard let event else { return }
#if DEBUG
        if event.managedObjectContext == nil {
            L.og.debug("🔴🔴 event is nil, debugInfo: \(debugInfo ?? "")")
            try? self.ctx.save()
        }
        else if event.managedObjectContext != self.ctx {
            L.og.debug("🔴🔴 event is not bg")
        }
#endif
        
        if event.managedObjectContext == nil {
            L.og.debug("🔴🔴 event is not yet saved")
            try? self.ctx.save()
        }
        
        // nil can apparently happen when we have event.replyTo.replyToRoot. 
        //                                          ^      ^        ^
        //                                          |      |        |
        //             has .managedObjectContext ---       |        |
        //                      has .managedObjectContext -         |
        //                           .managedObjectContext is nil  -
        let eventWithContextOrNil: Event? = if event.managedObjectContext == nil {
            self.ctx.object(with: event.objectID) as? Event
        }
        else {
            event
        }
        
        guard let eventWithContext = eventWithContextOrNil else { return }
        
        #if DEBUG
            if eventWithContext.managedObjectContext != ctx && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                fatalError("Should only be called from bg()")
            }
        #endif
        
        guard self.waitingEvents.count < SPAM_LIMIT else { L.og.info("🔴🔴 SPAM_LIMIT hit, addAwaitingEvent() cancelled"); return }
        guard self.waitingEvents[eventWithContext.id] == nil else { return }
        self.waitingEvents[eventWithContext.id] = QueuedEvent(event: eventWithContext, queuedAt: Date.now)
        
        #if DEBUG
        if self.waitingEvents.count % 25 == 0 {
            L.og.debug("🟢🟢🟢🟢🟢 addAwaitingEvent. now in queue: \(self.waitingEvents.count) -- \(debugInfo ?? "")")
        }
        #endif
    }
    
    /// Returns events that are waiting for relations to be updated, like .contact, .contacts, .replyTo etc
    /// - Returns: Events, these are background context (.bg)
    public func getAwaitingBgEvents() -> [Event] {
        return self.waitingEvents.values.map { $0.event }
    }
    
    public func getAwaitingBgEvent(byId id:EventId) -> Event? {
        return self.waitingEvents[id]?.event ?? EventCache.shared.retrieveObject(at: id)
    }
    
    public func removeAll() {
        ctx.perform { [unowned self] in
            self.waitingEvents = [EventId: QueuedEvent]()
            self.waitingContacts = [ContactPubkey: QueuedContact]()
        }
    }
    
    /// Adds contact to the queue waiting for info to be updated
    /// - Parameter contact: Contact should be from .bg context, if not this function will fetch it from .bg using .objectID
    public func addAwaitingContact(_ contact: Contact, debugInfo: String? = "") {
        if contact.managedObjectContext == ctx {
            ctx.perform { [unowned self] in
                guard self.waitingContacts.count < SPAM_LIMIT else { L.og.info("🔴🔴 SPAM_LIMIT hit, addAwaitingContact() cancelled"); return }
                self.waitingContacts[contact.pubkey] = QueuedContact(contact: contact, queuedAt: Date.now)
#if DEBUG
                    L.og.debug("🟢🟢🟢 addAwaitingContact. now in queue: \(self.waitingContacts.count) -- \(debugInfo ?? "") -[LOG]-")
#endif
            }
        }
        else {
            ctx.perform { [unowned self] in
                guard self.waitingContacts.count < SPAM_LIMIT else { L.og.info("🔴🔴 SPAM_LIMIT hit, addAwaitingContact() cancelled"); return }
                guard let privateContact = self.ctx.object(with: contact.objectID) as? Contact else { return }
                self.waitingContacts[privateContact.pubkey] = QueuedContact(contact: privateContact, queuedAt: Date.now)
#if DEBUG
                L.og.debug("🟢🟢🟢 addAwaitingContact. now in queue: \(self.waitingContacts.count) -- \(debugInfo ?? "") -[LOG]-")
#endif
            }
        }
    }

    /// Returns contacts that are waiting for info to be updated
    /// - Returns: Contacts, these are background context (.bg)
    public func getAwaitingBgContacts() -> [Contact] {
        return self.waitingContacts.values.map { $0.contact }
    }
    
    
    public func getAwaitingBgContact(byPubkey pubkey: ContactPubkey) -> Contact? {
        return self.waitingContacts[pubkey]?.contact
    }
}
