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
// 1. We some post, we need a replyToRootId or replyToId, but not the reply or root itself
// 2. We queue this post here
// 3. We ask relays for the reply/root
// 4. Reply/Root comes in through socket didReceive -> MessageParser -> Importer
// 5. Reply/Root is saved in DB (BEFORE, OLD METHOD: this was were we updated the relation, but very slow since we need to query for any posts that have a matching replyToRootId or replyToId)
// 6. (NEW METHOD:) We check if there are any posts waiting for relations in EventRelationsQueue (Fast)
// 7. Update and save relation, send objectWillChange

import Foundation
import Combine

class EventRelationsQueue {
    
    static let shared = EventRelationsQueue()
    
    private var waitingEvents = Set<Event>() // Contains events only from background context
    private var waitingEventsSubject = CurrentValueSubject<Set<Event>, Never>([])
    private var delayedRemove = PassthroughSubject<Event, Never>()
    
    private var subscriptions = Set<AnyCancellable>()
    
    init() {
        delayedRemove
//            .delay(for: .seconds(5), scheduler: RunLoop.main)
            .delay(for: .seconds(5), scheduler: DispatchQueue.global())
            .sink { [weak self] event in
                self?.waitingEvents.remove(event)
                print("🟢🟢🟢 delayedRemove. now in queue: \(String(describing: self?.waitingEvents.count))")
            }
            .store(in: &subscriptions)
    }
    
    public func addAwaitingEvent(_ event:Event) {
        let ctx = DataProvider.shared().bg
        if event.managedObjectContext == ctx {
            ctx.perform {
                self.waitingEvents.insert(event)
                print("🟢🟢🟢 addAwaitingEvent. now in queue: \(self.waitingEvents.count)")
            }
        }
        else {
            ctx.perform {
                guard let privateEvent = ctx.object(with: event.objectID) as? Event else { return }
                self.waitingEvents.insert(privateEvent)
                print("🟢🟢🟢 addAwaitingEvent. now in queue: \(self.waitingEvents.count)")
            }
        }
    }
    
    public func removeAwaitingEvent(_ event:Event) {
        // Don't remove immediatly, give a few extra seconds, maybe needs to fetch more than 1 relation
        self.delayedRemove.send(event)
    }
    
    public func getAwaitingEvents() -> Set<Event> {
        self.waitingEvents
    }
    
    public func removeAll() {
        self.waitingEvents = Set<Event>()
    }

//    public func 
}
