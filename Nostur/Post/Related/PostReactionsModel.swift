//
//  PostReactionsModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/05/2024.
//

import SwiftUI
import Combine

@MainActor
class PostReactionsModel: ObservableObject {
    @Published public var fetchTimedOut = false
    @Published public var isLoading = true
    @Published public var reactions: [NRPost] = []
    @Published public var foundSpam: Bool = false
    @Published public var hiddenReactionCount = 0
    @Published public var includeSpam: Bool = false
    

    private var eventId: String?
    
    private var oldestReactionCreatedAt: Int64?
    public private(set) var mostRecentReactionCreatedAt: Int64 = 0

    private var subscriptions: Set<AnyCancellable> = []
    
    public init() {
        ViewUpdates.shared.relatedUpdates
            .receive(on: RunLoop.main)
            .filter { [weak self] in $0.type == .Reactions && $0.eventId == self?.eventId }
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
    
    public func load(limit: Int?, includeSpam: Bool = false, finishesFetch: Bool = false, completion: ((Int64) -> Void)? = nil) {
        guard let eventId else { return }
        let blocked = AppState.shared.bgAppState.blockedPubkeys
        let bgContext = bg()
        bgContext.perform { [weak self] in
            let r1 = Event.fetchRequest()
            r1.predicate = NSPredicate(
                format: "reactionToId == %@ AND kind == 7 AND groupId == nil AND NOT pubkey IN %@",
                eventId,
                blocked
            )
            r1.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: true)]
            if let limit {
                r1.fetchLimit = limit
            }
            
            var seen = Set<String>()
            let fetchedEvents = (try? bgContext.fetch(r1)) ?? []
            let allReactionEvents = fetchedEvents
                .filter { $0.deletedById == nil && seen.insert($0.id).inserted }
                .sorted(by: { !$0.isSpam && $1.isSpam })
            
            // Keep the cached lower bound while loading. Completed nonempty
            // fetches can repair an inflated counter; empty responses cannot.
            let positiveCount = allReactionEvents.filter { $0.content != "-" && $0.deletedById == nil }.count
            if let event = Event.fetchEvent(id: eventId, context: bgContext) {
                let count = Self.reconciledCount(cached: event.likesCount, available: positiveCount,
                    finishesFetch: finishesFetch, capped: limit.map { fetchedEvents.count >= $0 } ?? false)
                if count != event.likesCount {
                    event.likesCount = count
                    ViewUpdates.shared.eventStatChanged.send(EventStatChange(id: eventId, likes: count))
                    DataProvider.shared().saveToDisk(.bgContext)
                }
            }

            let reactions = allReactionEvents
                .filter { includeSpam || !$0.isSpam }
                .map { NRPost(event: $0, withFooter: false, withReplyTo: false, withParents: false, withReplies: false, plainText: true, withRepliesCount: false) }
            
            let mostRecent = allReactionEvents.map(\.created_at).max() ?? 0
            let oldest = allReactionEvents.map(\.created_at).min()
            
            let foundSpam = allReactionEvents.count > reactions.count
            
            Task { @MainActor [weak self] in
                guard let self, self.eventId == eventId else { return }
                self.mostRecentReactionCreatedAt = mostRecent
                self.oldestReactionCreatedAt = oldest
                withAnimation {
                    if finishesFetch { self.isLoading = false }
                    self.reactions = reactions
                    self.foundSpam = foundSpam
                    self.hiddenReactionCount = allReactionEvents.count - reactions.count
                }
                if let completion {
                    completion(mostRecent)
                }
            }
        }
    }
    
    nonisolated static func reconciledCount(cached: Int64, available: Int, finishesFetch: Bool = false, capped: Bool = false) -> Int64 {
        // After a successful fetch, rebuild a stale incremental counter from the
        // reactions we can actually list. An empty/capped fetch remains inconclusive.
        if finishesFetch && available > 0 && !capped { return Int64(available) }
        return max(cached, Int64(available))
    }

    public func beginFetch() { fetchTimedOut = false; isLoading = true }
    public func markFetchTimedOut() { fetchTimedOut = true; isLoading = false }

    nonisolated static func historyRequest(eventId: String, subscriptionId: String) -> String {
        // A recent local row does not prove that older reactions are still stored.
        RM.getEventReferences(ids: [eventId], limit: 500, subscriptionId: subscriptionId, kinds: [7])
    }

    public func showMore() {
        guard let eventId else { return }
        req(RM.getEventReferences(ids: [eventId], limit: 500, kinds: [7],
            since: oldestReactionCreatedAt.map { NTimestamp(timestamp: Int($0)) }))
        load(limit: 500, includeSpam: includeSpam)
    }
}
