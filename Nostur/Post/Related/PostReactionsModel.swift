//
//  PostReactionsModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/05/2024.
//

import SwiftUI
import Combine

class PostReactionsModel: ObservableObject {
    @Published public var reactions: [NRPost] = []
    @Published public var foundSpam: Bool = false
    @Published public var includeSpam: Bool = false
    

    private var eventId: String?
    
    // bg
    public var mostRecentReactionCreatedAt: Int64 {
        allReactionEvents.sorted(by: { $0.created_at > $1.created_at }).first?.created_at ?? 0
    }

    private var allReactionEvents: [Event] = []
    private var subscriptions: Set<AnyCancellable> = []
    
    public init() {
        ViewUpdates.shared.relatedUpdates
            .filter { $0.type == .Reactions && $0.eventId == self.eventId }
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
                format: "reactionToId == %@ AND kind == 7 AND NOT pubkey IN %@",
                eventId,
                AppState.shared.bgAppState.blockedPubkeys
            )
            r1.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: true)]
            if let limit {
                r1.fetchLimit = limit
            }
            
            self.allReactionEvents = ((try? bgContext.fetch(r1)) ?? [])
                .sorted(by: { !$0.isSpam && $1.isSpam })
            
            let reactions = self.allReactionEvents
                .filter { includeSpam || !$0.isSpam }
                .map { NRPost(event: $0, withFooter: false, withReplyTo: false, withParents: false, withReplies: false, plainText: true, withRepliesCount: false) }
            
            let mostRecentReactionCreatedAt = self.mostRecentReactionCreatedAt
            
            let foundSpam = self.allReactionEvents.count > reactions.count
            
            DispatchQueue.main.async {
                withAnimation {
                    self.reactions = reactions
                    self.foundSpam = foundSpam
                }
                if let completion {
                    completion(mostRecentReactionCreatedAt)
                }
            }
        }
    }
    
    public func showMore() {
        // TODO: Implement solution for gap reactions 60d ago and 223d ago caused by: We have reactions until 60d, we fetch until 60d with limit 500, we receive from 250d ago and newer but because of limit result is cut off at 223d because relays don't support ASC/DESC.
        guard let eventId else { return }
        bg().perform { [weak self] in
            guard let self else { return }
            if let until = allReactionEvents.last?.created_at {
                req(
                    RM.getEventReferences(
                        ids: [eventId],
                        limit: 500,
                        kinds: [7],
                        since: NTimestamp(timestamp: Int(until))
                    )
                )
            }
            else {
                req(
                    RM.getEventReferences(
                        ids: [eventId],
                        limit: 500,
                        kinds: [7]
                    )
                )
            }
            self.load(limit: 500, includeSpam: self.includeSpam)
        }
    }
}
