//
//  PostZapsModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/05/2024.
//

import SwiftUI
import Combine

class PostZapsModel: ObservableObject {
    @Published public var verifiedZaps: [NRPost] = []
    @Published public var unverifiedZaps: [NRPost] = []
    
    @Published public var foundSpam: Bool = false
    @Published public var includeSpam: Bool = false

    private var eventId: String?
    
    // bg
    public var mostRecentZapCreatedAt: Int64 {
        allZapEvents.sorted(by: { $0.created_at > $1.created_at }).first?.created_at ?? 0
    }
    private var allZapEvents: [Event] = []
    private var subscriptions: Set<AnyCancellable> = []
    
    public init() {
        ViewUpdates.shared.relatedUpdates
            .filter { $0.type == .Zaps && $0.eventId == self.eventId }
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                withAnimation {
                    self.load(limit: 500, includeSpam: self.includeSpam)
                }
            }
            .store(in: &subscriptions)
    }
    
    public func setup(eventId: String) {
        self.eventId = eventId
    }
    
    public func load(limit: Int?, includeSpam: Bool = false, completion: ((Int64) -> Void)? = nil) {
        guard let eventId else { return }
        let bgContext = bg()
        bgContext.perform { [weak self] in
            guard let self else { return }
            let r1 = Event.fetchRequest()
            r1.predicate = NSPredicate(
                format: "zappedEventId == %@ AND kind == 9735 AND NOT pubkey IN %@",
                eventId,
                AppState.shared.bgAppState.blockedPubkeys
            )
            r1.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: true)]
            if let limit {
                r1.fetchLimit = limit
            }
            
            self.allZapEvents = ((try? bgContext.fetch(r1)) ?? [])
                .sorted(by: { !$0.isSpam && $1.isSpam })
            
            let zaps: [NRPost] = self.allZapEvents
                .filter { includeSpam || !$0.isSpam }
                .compactMap {
                    guard $0.fromPubkey != nil else { return nil }
                    return NRPost(event: $0)
                }
                .sorted(by: { $0.sats > $1.sats })
            
            let foundSpam = self.allZapEvents.count > zaps.count
            
            let verifiedZaps = zaps.filter { $0.verified }
            let unverifiedZaps = zaps.filter { !$0.verified }
            
            let mostRecentZapCreatedAt = self.mostRecentZapCreatedAt
            
            DispatchQueue.main.async {
                self.verifiedZaps = verifiedZaps
                self.unverifiedZaps = unverifiedZaps
                self.foundSpam = foundSpam
                if let completion {
                    completion(mostRecentZapCreatedAt)
                }
            }
            
            self.fixTally()
        }
    }
    
    public func showMore() {
        // TODO: Implement solution for gap reactions 60d ago and 223d ago caused by: We have reactions until 60d, we fetch until 60d with limit 500, we receive from 250d ago and newer but because of limit result is cut off at 223d because relays don't support ASC/DESC.
        guard let eventId else { return }
        bg().perform { [weak self] in
            guard let self else { return }
            if let until = allZapEvents.last?.created_at {
                req(
                    RM.getEventReferences(
                        ids: [eventId],
                        limit: 500,
                        kinds: [9735],
                        since: NTimestamp(timestamp: Int(until))
                    )
                )
            }
            else {
                req(
                    RM.getEventReferences(
                        ids: [eventId],
                        limit: 500,
                        kinds: [9735]
                    )
                )
            }
            self.load(limit: 500)
        }
    }
    
    private func fixTally() {
        guard let eventId else { return }
        // Fix zaps afterwards??
        // (0, 0) = (tally, count)
        let tally = verifiedZaps
            .reduce((0, 0)) { partialResult, nrPost in
                return (partialResult.0 + Int64(nrPost.sats), partialResult.1 + Int64(1))
        }
        
        if let event = Event.fetchEvent(id: eventId, context: bg()) {
            if event.zapsCount != tally.1 {
                event.zapsCount = tally.1
                event.zapTally = tally.0
                ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: event.id, zaps: tally.1, zapTally: tally.0))
            }
        }
            
        var missing: [Event] = []
        for zap in allZapEvents {
            if let zapFromPubkey = zap.fromPubkey {
                if let contact = Contact.fetchByPubkey(zapFromPubkey, context: bg()), contact.metadata_created_at == 0 {
                    missing.append(zap)
                    EventRelationsQueue.shared.addAwaitingContact(contact, debugInfo: "PostZapsModel.001")
                }
            }
        }
            
        QueuedFetcher.shared.enqueue(pTags: missing.compactMap { $0.fromPubkey })
    }
}
