//
//  ReactionsFeedModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/05/2024.
//

import SwiftUI
import Combine

class RepostsFeedModel: ObservableObject {
    @Published public var reposts: [NRPost] = []

    private var pubkey: String?
    private var account: CloudAccount? // Main context
    
    // bg
    public var mostRecentRepostCreatedAt: Int64 {
        allRepostEvents.sorted(by: { $0.created_at > $1.created_at }).first?.created_at ?? 0
    }
    private var allRepostEvents: [Event] = []
    private var subscriptions: Set<AnyCancellable> = []
    
    public init() {
        ViewUpdates.shared.feedUpdates
            .filter { $0.type == .Reposts && $0.accountPubkey == self.pubkey }
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
        
        receiveNotification(.muteListUpdated)
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
                format: "otherPubkey == %@ AND kind == 6 AND NOT pubkey IN %@ AND NOT id IN %@ AND (replyToRootId == nil OR NOT replyToRootId IN %@) AND (replyToId == nil OR NOT replyToId IN %@)",
                pubkey,
                (NRState.shared.blockedPubkeys + [pubkey]),
                NRState.shared.mutedRootIds,
                NRState.shared.mutedRootIds,
                NRState.shared.mutedRootIds)
            r1.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            if let limit {
                r1.fetchLimit = limit
            }
            
            self.allRepostEvents = ((try? bgContext.fetch(r1)) ?? [])
                .filter { includeSpam || !$0.isSpam }
            
            let reposts = self.allRepostEvents.map { NRPost(event: $0, withFooter: false, withReplyTo: false, withParents: false, withReplies: false, plainText: true, withRepliesCount: false) }
            
            let mostRecentRepostCreatedAt = self.mostRecentRepostCreatedAt
            
            DispatchQueue.main.async {
                self.reposts = reposts
                if let completion {
                    completion(mostRecentRepostCreatedAt)
                }
            }
        }
    }
    
    public func showMore() {
        // TODO: Implement solution for gap reactions 60d ago and 223d ago caused by: We have reactions until 60d, we fetch until 60d with limit 500, we receive from 250d ago and newer but because of limit result is cut off at 223d because relays don't support ASC/DESC.
        guard let pubkey else { return }
        bg().perform { [weak self] in
            guard let self else { return }
            if let until = allRepostEvents.last?.created_at {
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
