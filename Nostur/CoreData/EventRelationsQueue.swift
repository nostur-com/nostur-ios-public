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
import Combine
import CoreData

class EventRelationsQueue {
    
    static let shared = EventRelationsQueue()
    
    private var ctx:NSManagedObjectContext
    private var waitingEvents = Set<Event>() // Contains events only from background context
    private var waitingEventsSubject = CurrentValueSubject<Set<Event>, Never>([])
    private var delayedRemove = PassthroughSubject<Event, Never>()
    
    private var waitingContacts = Set<Contact>() // Contains events only from background context
    private var waitingContactsSubject = CurrentValueSubject<Set<Contact>, Never>([])
    private var delayedContactRemove = PassthroughSubject<Contact, Never>()
    
    private var subscriptions = Set<AnyCancellable>()
    
    init() {
        ctx = DataProvider.shared().bg
        delayedRemove
            .delay(for: .seconds(5), scheduler: DispatchQueue.global())
            .sink { [weak self] event in
                self?.ctx.perform {
                    self?.waitingEvents.remove(event)
                }
            }
            .store(in: &subscriptions)
        
        delayedContactRemove
            .delay(for: .seconds(5), scheduler: DispatchQueue.global())
            .sink { [weak self] contact in
                self?.ctx.perform {
                    self?.waitingContacts.remove(contact)
                }
            }
            .store(in: &subscriptions)
    }
    
    
    /// Adds event to the queue waiting for related data that is being fetched
    /// - Parameter event: Event should be from .bg context, if not this function will fetch it from .bg using .objectID
    public func addAwaitingEvent(_ event:Event, debugInfo:String? = "") {
        if event.managedObjectContext == ctx {
            ctx.perform {
                self.waitingEvents.insert(event)
                print("🟢🟢🟢 addAwaitingEvent. now in queue: \(self.waitingEvents.count) -- \(debugInfo)")
            }
        }
        else {
            ctx.perform {
                guard let privateEvent = self.ctx.object(with: event.objectID) as? Event else { return }
                self.waitingEvents.insert(privateEvent)
                print("🟢🟢🟢🔴🔴 WRONG CONTEXT: addAwaitingEvent. now in queue: \(self.waitingEvents.count) -- \(debugInfo)")
            }
        }
    }
    
    public func removeAwaitingEvent(_ event:Event) {
        // Don't remove immediatly, give a few extra seconds, maybe needs to fetch more than 1 relation
        self.delayedRemove.send(event)
    }
    
    /// Returns events that are waiting for relations to be updated, like .contact, .contacts, .replyTo etc
    /// - Returns: Events, these are background context (.bg)
    public func getAwaitingBgEvents() -> Set<Event> {
        return self.waitingEvents
    }
    
    public func removeAll() {
        ctx.perform {
            self.waitingEvents = Set<Event>()
            self.waitingContacts = Set<Contact>()
        }
    }
    
    
    
    /// Adds contact to the queue waiting for info to be updated
    /// - Parameter contact: Contact should be from .bg context, if not this function will fetch it from .bg using .objectID
    public func addAwaitingContact(_ contact:Contact, debugInfo:String? = "") {
        if contact.managedObjectContext == ctx {
            ctx.perform {
                self.waitingContacts.insert(contact)
                print("🟢🟢🟢 addAwaitingContact. now in queue: \(self.waitingContacts.count) -- \(debugInfo)")
            }
        }
        else {
            ctx.perform {
                guard let privateContact = self.ctx.object(with: contact.objectID) as? Contact else { return }
                self.waitingContacts.insert(privateContact)
                print("🟢🟢🟢 addAwaitingContact. now in queue: \(self.waitingContacts.count) -- \(debugInfo)")
            }
        }
    }
    
    public func removeAwaitingContact(_ contact:Contact) {
        // Don't remove immediatly, give a few extra seconds, maybe needs to fetch more than 1 relation
        self.delayedContactRemove.send(contact)
    }
    
    /// Returns contacts that are waiting for info to be updated
    /// - Returns: Contacts, these are background context (.bg)
    public func getAwaitingBgContacts() -> Set<Contact> {
        return self.waitingContacts
    }
}
