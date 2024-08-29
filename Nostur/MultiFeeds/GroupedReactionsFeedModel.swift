//
//  ReactionsFeedModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/05/2024.
//

import SwiftUI
import Combine

class GroupedReactionsFeedModel: ObservableObject {
    @Published public var groupedReactions: [GroupedReactions] = []

    private var pubkey: String?
    private var account: CloudAccount? // Main context
    
    // bg
    public var mostRecentReactionCreatedAt: Int64 {
        allReactionEvents.sorted(by: { $0.created_at > $1.created_at }).first?.created_at ?? 0
    }
    private var allReactionEvents: [Event] = []
    private var subscriptions: Set<AnyCancellable> = []
    
    public init() {
        ViewUpdates.shared.feedUpdates
            .filter { $0.type == .Reactions && $0.accountPubkey == self.pubkey }
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                withAnimation {
                    self.load(limit: 500)
                }
            }
            .store(in: &subscriptions)
        
        receiveNotification(.blockListUpdated)
            .sink { [weak self] notification in
                guard let self else { return }
                withAnimation {
                    self.load(limit: 500)
                }
            }
            .store(in: &subscriptions)
    }
    
    public func setup(pubkey: String) {
        self.pubkey = pubkey
        self.account = NRState.shared.accounts.first(where: { $0.publicKey == pubkey })
    }
    
    public func load(limit: Int?, includeSpam: Bool = false, completion: ((Int64) -> Void)? = nil) {
        guard let pubkey else { return }
        let bgContext = bg()
        bgContext.perform { [weak self] in
            guard let self else { return }
            let r1 = Event.fetchRequest()
            r1.predicate = NSPredicate(
                format: "otherPubkey == %@ AND kind == 7 AND NOT pubkey IN %@",
                pubkey,
                NRState.shared.blockedPubkeys
            )
            r1.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            if let limit {
                r1.fetchLimit = limit
            }
            
            self.allReactionEvents = ((try? bgContext.fetch(r1)) ?? [])
                .filter { includeSpam || !$0.isSpam }
            
            let eventsReactedTo: [Event] = allReactionEvents.compactMap { $0.reactionTo }
            let uniqueEventsReactedTo: Set<Event> = Set(eventsReactedTo)
        
            let groupedReactions: [GroupedReactions] = uniqueEventsReactedTo.map { reactedTo in
                GroupedReactions(
                    reactions: self.allReactionEvents
                        .filter { $0.reactionToId == reactedTo.id }
                        .reduce(into: [String: Event]()) { result, reaction in
                            result[reaction.pubkey] = reaction
                        }
                        .values
                        .sorted(by: { $0.created_at > $1.created_at })
                        .map { event in
                            return Reaction(id: event.id, pubkey: event.pubkey, pictureUrl: event.contact?.pictureUrl, authorName: event.contact?.authorName, createdAt: event.created_at, content: event.content)
                        },
                    nrPost: NRPost(event: reactedTo)
                )
            }
            .sorted(by: { $0.mostRecentCreatedAt > $1.mostRecentCreatedAt })
            
            let mostRecentReactionCreatedAt = self.mostRecentReactionCreatedAt
            
            DispatchQueue.main.async {
                self.groupedReactions = groupedReactions
                if let completion {
                    completion(mostRecentReactionCreatedAt)
                }
            }
        }
    }
    
    public func showMore() {
        // TODO: Implement solution for gap reactions 60d ago and 223d ago caused by: We have reactions until 60d, we fetch until 60d with limit 500, we receive from 250d ago and newer but because of limit result is cut off at 223d because relays don't support ASC/DESC.
        guard let pubkey else { return }
        bg().perform { [weak self] in
            guard let self else { return }
            if let until = allReactionEvents.last?.created_at {
                req(RM.getMentions(
                    pubkeys: [pubkey],
                    kinds: [7],
                    limit: 500,
                    until: NTimestamp(timestamp: Int(until))
                ))
            }
            else {
                req(RM.getMentions(pubkeys: [pubkey], kinds: [7], limit: 500))
            }
            
            self.load(limit: 500)
        }
    }
}

struct Reaction: Identifiable {
    public let id: String
    public let pubkey: String
    public var pictureUrl: URL?
    public var authorName: String?
    public let createdAt: Int64
    public let content: String?
}

class GroupedReactions: ObservableObject, Identifiable {
    public var id: String { nrPost.id }
    @Published public var reactions: [Reaction]
    public let nrPost: NRPost
    public var mostRecentCreatedAt: Int64 {
        reactions.sorted(by: { $0.createdAt > $1.createdAt } ).first?.createdAt ?? 0
    }
    
    public init(reactions: [Reaction], nrPost: NRPost) {
        self.reactions = reactions
        self.nrPost = nrPost
    }
}
