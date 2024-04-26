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
    
    let SPAM_LIMIT = 2000
    
    typealias EventId = String
    typealias ContactPubkey = String
    
    struct QueuedEvent {
        let event: Event
        let queuedAt: Date
    }
    
    struct QueuedContact {
        let contact: Contact
        let queuedAt: Date
    }
    
    static let shared = EventRelationsQueue()
    
    private var ctx = bg()
    private var waitingEvents = [EventId: QueuedEvent]()
    private var waitingContacts = [ContactPubkey: QueuedContact]()
    private var cleanUpTimer: Timer?
    
    init() {
        cleanUpTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true, block: { [weak self] timer in
            let now = Date()
            
            bg().perform {
                guard let self else { return }
                self.waitingEvents = self.waitingEvents.filter { now.timeIntervalSince($0.value.queuedAt) < 30 }
                self.waitingContacts = self.waitingContacts.filter { now.timeIntervalSince($0.value.queuedAt) < 30 }
            }            
        })
    }
    
    /// Adds event to the queue waiting for related data that is being fetched
    /// - Parameter event: Event should be from .bg context, if not this function will fetch it from .bg using .objectID
    public func addAwaitingEvent(_ event: Event? = nil, debugInfo:String? = "") {
        guard let event = event else { return }
        let isBGevent = event.managedObjectContext == ctx
        if Thread.isMainThread {
            if isBGevent {
                ctx.perform { [unowned self] in
                    guard self.waitingEvents.count < SPAM_LIMIT else { L.og.info("🔴🔴 SPAM_LIMIT hit, addAwaitingEvent() cancelled"); return }
                    self.waitingEvents[event.id] = QueuedEvent(event: event, queuedAt: Date.now)
                    L.og.debug("🟢🟢🟢🔴🔴 WRONG THREAD: addAwaitingEvent. now in queue: \(self.waitingEvents.count) -- \(debugInfo ?? "")")
                }
            }
            else {
                ctx.perform { [unowned self] in
                    guard self.waitingEvents.count < SPAM_LIMIT else { L.og.info("🔴🔴 SPAM_LIMIT hit, addAwaitingEvent() cancelled"); return }
                    guard let privateEvent = self.ctx.object(with: event.objectID) as? Event else { return }
                    self.waitingEvents[privateEvent.id] = QueuedEvent(event: privateEvent, queuedAt: Date.now)
                    L.og.debug("🟢🟢🟢🔴🔴 WRONG THREAD+MAINEVENT: addAwaitingEvent. now in queue: \(self.waitingEvents.count) -- \(debugInfo ?? "")")
                }
            }
        }
        else {
            guard self.waitingEvents.count < SPAM_LIMIT else { L.og.info("🔴🔴 SPAM_LIMIT hit, addAwaitingEvent() cancelled"); return }
            if isBGevent {
                guard self.waitingEvents[event.id] == nil else { return }
                self.waitingEvents[event.id] = QueuedEvent(event: event, queuedAt: Date.now)
                if self.waitingEvents.count % 25 == 0 {
                    L.og.debug("🟢🟢🟢🟢🟢 addAwaitingEvent. now in queue: \(self.waitingEvents.count) -- \(debugInfo ?? "")")
                }
                else {
                    L.og.debug("🟢🟢🟢🟢🟢 addAwaitingEvent. now in queue: \(self.waitingEvents.count) -- \(debugInfo ?? "")")
                }
            }
            else {
                guard let privateEvent = self.ctx.object(with: event.objectID) as? Event else { return }
                self.waitingEvents[privateEvent.id] = QueuedEvent(event: privateEvent, queuedAt: Date.now)
                L.og.debug("🟢🟢🟢🟢🔴🔴 WRONG MAINEVENT. addAwaitingEvent. now in queue: \(self.waitingEvents.count) -- \(debugInfo ?? "")")
            }
        }
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
                L.og.debug("🟢🟢🟢 addAwaitingContact. now in queue: \(self.waitingContacts.count) -- \(debugInfo ?? "")")
            }
        }
        else {
            ctx.perform { [unowned self] in
                guard self.waitingContacts.count < SPAM_LIMIT else { L.og.info("🔴🔴 SPAM_LIMIT hit, addAwaitingContact() cancelled"); return }
                guard let privateContact = self.ctx.object(with: contact.objectID) as? Contact else { return }
                self.waitingContacts[privateContact.pubkey] = QueuedContact(contact: privateContact, queuedAt: Date.now)
                L.og.debug("🟢🟢🟢 addAwaitingContact. now in queue: \(self.waitingContacts.count) -- \(debugInfo ?? "")")
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
