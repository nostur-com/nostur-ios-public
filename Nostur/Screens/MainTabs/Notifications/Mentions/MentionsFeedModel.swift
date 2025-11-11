//
//  MentionsFeedModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/06/2024.
//

import SwiftUI
import Combine

class MentionsFeedModel: ObservableObject {
    @Published public var mentions: [NRPost] = []

    private var pubkey: String?
    private var npub: String?
    public var account: CloudAccount? // Main context
    
    // bg
    public var mostRecentMentionCreatedAt: Int64 {
        allMentionEvents.sorted(by: { $0.created_at > $1.created_at }).first?.created_at ?? 0
    }
    private var allMentionEvents: [Event] = []
    private var subscriptions: Set<AnyCancellable> = []
    
    public init() {
        ViewUpdates.shared.feedUpdates
            .filter { $0.type == .Mentions && $0.accountPubkey == self.pubkey }
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
        self.account = AccountsState.shared.accounts.first(where: { $0.publicKey == pubkey })
        self.npub = self.account?.npub
    }
    
    public func load(limit: Int?, includeSpam: Bool = false, completion: ((Int64) -> Void)? = nil) {
        guard let pubkey, let npub else { return }
        let bgContext = bg()
        bgContext.perform { [weak self] in
            guard let self else { return }
            let r1 = Event.fetchRequest()
            r1.predicate = NSPredicate(
                format: "NOT pubkey IN %@ AND kind IN {1,1111,1222,1244,20,9802,30023,34235} AND tagsSerialized CONTAINS %@ AND NOT id IN %@ AND (replyToRootId == nil OR NOT replyToRootId IN %@) AND (replyToId == nil OR NOT replyToId IN %@) AND flags != \"is_update\" ",
                (AppState.shared.bgAppState.blockedPubkeys + [pubkey]),
                serializedP(pubkey),
                AppState.shared.bgAppState.mutedRootIds,
                AppState.shared.bgAppState.mutedRootIds,
                AppState.shared.bgAppState.mutedRootIds)
            r1.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            if let limit {
                r1.fetchLimit = limit
            }
            
            self.allMentionEvents = ((try? bgContext.fetch(r1)) ?? [])
                .filter { includeSpam || !$0.isSpam }
                
                // Hellthread handling
                .filter {
                
                    // check if actual mention is in content (if there are more than 20 Ps, potential hellthread)
                    if $0.fastPs.count > 20 {
                        // but always allow if its a root post
                        if $0.replyToId == nil && $0.replyToRootId == nil {
                            return true
                        }
                        
                        // but always allow if direct reply to own post
                        if let replyToId = $0.replyToId {
                            if let replyTo = Event.fetchEvent(id: replyToId, context: bg()) {
                                if replyTo.pubkey == pubkey { // direct reply to our post
                                    return true
                                }
                                // direct reply to someone elses post, check if we are actually mentioned in content. (we don't check old [0], [1] style...)
                                return $0.content != nil && $0.content!.contains(npub)
                            }
                            // We don't have our own event? Maybe new app user
                            return false // fallback to false
                        }
                        
                        // our npub is in content? (we don't check old [0], [1] style...)
                        return $0.content != nil && $0.content!.contains(npub)
                    }
                    
                    return true
                }
            
            let mentions = self.allMentionEvents.map { NRPost(event: $0, withFooter: true, withReplyTo: true, withParents: false, withReplies: false, plainText: false, withRepliesCount: true) }
            
            let mostRecentMentionCreatedAt = self.mostRecentMentionCreatedAt
            
            DispatchQueue.main.async {
                self.mentions = mentions
                if let completion {
                    completion(mostRecentMentionCreatedAt)
                }
            }
        }
    }
    
    public func showMore() {
        // TODO: Implement solution for gap mentions 60d ago and 223d ago caused by: We have mentions until 60d, we fetch until 60d with limit 500, we receive from 250d ago and newer but because of limit result is cut off at 223d because relays don't support ASC/DESC.
        guard let pubkey else { return }
        bg().perform { [weak self] in
            guard let self else { return }
            if let until = allMentionEvents.last?.created_at {
                req(RM.getMentions(
                    pubkeys: [pubkey],
                    kinds: [1,1111,1222,1244,20,9802,30023,34235],
                    limit: 500,
                    until: NTimestamp(timestamp: Int(until))
                ))
            }
            else {
                req(RM.getMentions(pubkeys: [pubkey], kinds: [1,1111,1222,1244,20,9802,30023,34235], limit: 500))
            }
            
            self.load(limit: 500)
        }
    }
}
