//
//  EventRelationsQueue.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/04/2023.
//

// When posts have related events that need to be fetched
// we queue them here so we don't have to query the entire
// database of 50000+ events

// Typically the flow will be:
// 1. We have some post, with a replyToRootId or replyToId, but not the reply or root itself
// 2. We queue this post here
// 3. We ask relays for the reply/root
// 4. Reply/Root comes in through socket didReceive -> MessageParser -> Importer
// 5. Reply/Root is saved in DB (BEFORE, OLD METHOD: this was were we updated the relation, but very slow since we need to query for any posts that have a matching replyToRootId or replyToId)
// 6. (NEW METHOD:) We check if there are any posts waiting for relations in EventRelationsQueue (Fast)
// 7. Update and save relation, send objectWillChange

import Foundation
import CoreData

class EventRelationsQueue {
    
    typealias EventId = String
    typealias ContactPubkey = String
    
    struct QueuedEvent {
        let event:Event
        let queuedAt: Date
    }
    
    struct QueuedContact {
        let contact:Contact
        let queuedAt: Date
    }
    
    static let shared = EventRelationsQueue()
    
    private var ctx = DataProvider.shared().bg
    private var waitingEvents = [EventId:QueuedEvent]()
    private var waitingContacts = [ContactPubkey:QueuedContact]()
    private var cleanUpTimer: Timer?
    
    init() {
        cleanUpTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true, block: { [unowned self] timer in
            let now = Date()
            
            DataProvider.shared().bg.perform {
                self.waitingEvents = self.waitingEvents.filter { now.timeIntervalSince($0.value.queuedAt) < 30 }
                self.waitingContacts = self.waitingContacts.filter { now.timeIntervalSince($0.value.queuedAt) < 30 }
            }            
        })
    }
    
    /// Adds event to the queue waiting for related data that is being fetched
    /// - Parameter event: Event should be from .bg context, if not this function will fetch it from .bg using .objectID
    public func addAwaitingEvent(_ event:Event, debugInfo:String? = "") {
        let isBGevent = event.managedObjectContext == ctx
        if Thread.isMainThread {
            if isBGevent {
                ctx.perform { [unowned self] in
                    self.waitingEvents[event.id] = QueuedEvent(event: event, queuedAt: Date.now)
                    L.og.info("🟢🟢🟢🔴🔴 WRONG THREAD: addAwaitingEvent. now in queue: \(self.waitingEvents.count) -- \(debugInfo ?? "")")
                }
            }
            else {
                ctx.perform { [unowned self] in
                    guard let privateEvent = self.ctx.object(with: event.objectID) as? Event else { return }
                    self.waitingEvents[privateEvent.id] = QueuedEvent(event: privateEvent, queuedAt: Date.now)
                    L.og.info("🟢🟢🟢🔴🔴 WRONG THREAD+MAINEVENT: addAwaitingEvent. now in queue: \(self.waitingEvents.count) -- \(debugInfo ?? "")")
                }
            }
        }
        else {
            if isBGevent {
                self.waitingEvents[event.id] = QueuedEvent(event: event, queuedAt: Date.now)
                L.og.info("🟢🟢🟢🟢🟢 addAwaitingEvent. now in queue: \(self.waitingEvents.count) -- \(debugInfo ?? "")")
            }
            else {
                guard let privateEvent = self.ctx.object(with: event.objectID) as? Event else { return }
                self.waitingEvents[privateEvent.id] = QueuedEvent(event: privateEvent, queuedAt: Date.now)
                L.og.info("🟢🟢🟢🟢🔴 WRONG MAINEVENT. addAwaitingEvent. now in queue: \(self.waitingEvents.count) -- \(debugInfo ?? "")")
            }
        }
    }

    public func removeAwaitingEvent(_ event:Event) {
        // Don't remove immediatly, give a few extra seconds, maybe needs to fetch more than 1 relation
//        self.delayedRemove(event, after: 5)
    }
    
    /// Returns events that are waiting for relations to be updated, like .contact, .contacts, .replyTo etc
    /// - Returns: Events, these are background context (.bg)
    public func getAwaitingBgEvents() -> [Event] {
        return self.waitingEvents.values.map { $0.event }
    }
    
    public func getAwaitingBgEvent(byId id:EventId) -> Event? {
        return self.waitingEvents[id]?.event
    }
    
    public func removeAll() {
        ctx.perform {
            self.waitingEvents = [EventId:QueuedEvent]()
            self.waitingContacts = [ContactPubkey:QueuedContact]()
        }
    }
    
    /// Adds contact to the queue waiting for info to be updated
    /// - Parameter contact: Contact should be from .bg context, if not this function will fetch it from .bg using .objectID
    public func addAwaitingContact(_ contact:Contact, debugInfo:String? = "") {
        if contact.managedObjectContext == ctx {
            ctx.perform { [unowned self] in
                self.waitingContacts[contact.pubkey] = QueuedContact(contact: contact, queuedAt: Date.now)
                L.og.info("🟢🟢🟢 addAwaitingContact. now in queue: \(self.waitingContacts.count) -- \(debugInfo ?? "")")
            }
        }
        else {
            ctx.perform { [unowned self] in
                guard let privateContact = self.ctx.object(with: contact.objectID) as? Contact else { return }
                self.waitingContacts[privateContact.pubkey] = QueuedContact(contact: privateContact, queuedAt: Date.now)
                L.og.info("🟢🟢🟢 addAwaitingContact. now in queue: \(self.waitingContacts.count) -- \(debugInfo ?? "")")
            }
        }
    }
    
//    private func delayedContactRemove(_ contact:Contact, after:Int = 15) {
//        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(after)) {
//            self.ctx.perform {
//                self.waitingContacts.remove(contact)
//            }
//        }
//    }
    
    public func removeAwaitingContact(_ contact:Contact) {
        // Don't remove immediatly, give a few extra seconds, maybe needs to fetch more than 1 relation
//        self.delayedContactRemove(contact, after: 10)
    }
    
    /// Returns contacts that are waiting for info to be updated
    /// - Returns: Contacts, these are background context (.bg)
    public func getAwaitingBgContacts() -> [Contact] {
        return self.waitingContacts.values.map { $0.contact }
    }
    
    
    public func getAwaitingBgContact(byPubkey pubkey:ContactPubkey) -> Contact? {
        return self.waitingContacts[pubkey]?.contact
    }
}
