//
//  InstantFeed.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/05/2023.
//

import Foundation
import Combine
import NostrEssentials

class InstantFeed {
    typealias CompletionHandler = ([Event]) -> ()
    public var backlog = Backlog(timeout: 8, auto: true)
    private var pongReceiver: AnyCancellable?
    private var pubkey: Pubkey?
    private var onComplete: CompletionHandler?

    private var pubkeys:Set<Pubkey>? {
        didSet {
            if pubkeys != nil {
                fetchPostsFromRelays()
            }
        }
    }
    private var since: Int?
    private var events:[Event]? {
        didSet {
            if let events, events.count > 0 {
                self.isRunning = false
                self.onComplete?(events)
                self.backlog.clear()
            }
        }
    }
    private var relays:Set<RelayData> = []
    public var isRunning = false
    
    public func start(_ pubkey:Pubkey, since: Int? = nil, onComplete: @escaping CompletionHandler) {
        L.og.notice("🟪 InstantFeed.start(\(pubkey.short))")
        self.isRunning = true
        self.since = since
        self.pubkey = pubkey
        self.onComplete = onComplete
        fetchContactListPubkeys(pubkey: pubkey)
    }
    
    public func start(_ pubkeys:Set<Pubkey>, since: Int? = nil, onComplete: @escaping CompletionHandler) {
        L.og.notice("🟪 InstantFeed.start(\(pubkeys.count) pubkeys)")
        self.isRunning = true
        self.onComplete = onComplete
        self.since = since
        self.pubkeys = pubkeys
//        fetchPostsFromRelays() <-- No need, already done on .pubkeys { didSet }
    }
    
    public func start(_ relays: Set<RelayData>, since: Int? = nil, onComplete: @escaping CompletionHandler) {
#if DEBUG
        L.og.notice("🟪 InstantFeed.start(\(relays.count) relays)")
#endif
        self.isRunning = true
        self.onComplete = onComplete
        self.since = since
        self.relays = relays
        fetchPostsFromGlobalishRelays()
    }
    
    private var kind3listener: AnyCancellable?

    private func fetchContactListPubkeys(pubkey: Pubkey) {
        signpost(self, "InstantFeed", .event, "Fetching contact list pubkeys")
        Task.detached { [weak self] in
            bg().perform {
                guard let self = self else { return }
                if let account = try? CloudAccount.fetchAccount(publicKey: pubkey, context: bg()), !account.followingPubkeys.isEmpty {
#if DEBUG
                    L.og.notice("🟪 Using account.follows")
#endif
                    self.pubkeys = account.followingPubkeys.union(Set([account.publicKey]))
                }
                else if let clEvent = Event.fetchReplacableEvent(3, pubkey: pubkey, context: bg()) {
#if DEBUG
                    L.og.notice("🟪 Found clEvent in database")
#endif
                    if let pubkey = self.pubkey {
                        self.pubkeys = Set(((clEvent.fastPs.map { $0.1 }) + [pubkey]))
                    }
                    else {
                        self.pubkeys = Set(clEvent.fastPs.map { $0.1 })
                    }
                }
                else {
                    let getContactListTask = ReqTask(subscriptionId: "RM.getAuthorContactsList") { taskId in
#if DEBUG
                        L.og.notice("🟪 Fetching clEvent from relays")
#endif
                        req(RM.getAuthorContactsList(pubkey: pubkey, subscriptionId: taskId))
                    } processResponseCommand: { [weak self] taskId, _, _ in
                        bg().perform {
                            guard let self = self else { return }
#if DEBUG
                            L.og.notice("🟪 Processing clEvent response from relays")
#endif
                            if let clEvent = Event.fetchReplacableEvent(3, pubkey: pubkey, context: bg()) {
                                self.pubkeys = Set(clEvent.fastPs.map { $0.1 })
                            }
                        }
                    } timeoutCommand: { [weak self] taskId in
                        guard let self else { return }
                        if (self.pubkeys == nil) {
#if DEBUG
                            L.og.notice("🟪  \(taskId) Timeout in fetching clEvent / pubkeys")
#endif
                        }
                    }
                    self.backlog.add(getContactListTask)
                    getContactListTask.fetch()
                    
                    // If kind 3 is already being fetched by onboarding getContactListTask won't catch it (because of filtering duplicates in message parser / importer.
                    // so we have an extra listener on onboarding:
                    self.kind3listener = NewOnboardingTracker.shared.didFetchKind3
                        .sink { [weak self] kind3 in
                            guard let self = self else { return }
                            guard kind3.pubkey == pubkey else { return }
#if DEBUG
                            L.og.notice("🟪 Found clEvent already being processed by onboarding task")
#endif
                            self.backlog.remove(getContactListTask) // Swift access race in Nostur.Backlog.tasks.modify : Swift.Set<Nostur.ReqTask> at 0x10b7ffd20 - Thread 5899
                            self.pubkeys = Set(kind3.fastPs.map { $0.1 })
                        }
                }
            }
        }
    }
    
    private func fetchPostsFromRelays() {
        signpost(self, "InstantFeed", .event, "Fetching posts from relays")
        bg().perform { [weak self] in
            guard let self else { return }
            guard let pubkeys else { return }
            
            let getFollowingEventsTask = ReqTask(prefix: "GFET-") { taskId in
#if DEBUG
                L.og.notice("🟪 Fetching posts from relays using \(pubkeys.count) pubkeys")
#endif
                let filters = [Filters(authors: pubkeys, kinds: [1,1222,5,6,20,9802,30023,34235], since: self.since, limit: 500)]
                outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: taskId, filters: filters))
                
            } processResponseCommand: { [weak self] taskId, _, _ in
                bg().perform {
                    guard let self else { return }
                    let fr = Event.postsByPubkeys(pubkeys, lastAppearedCreatedAt: Int64(self.since ?? 0), kinds: QUERY_FOLLOWING_KINDS)
                    guard let events = try? bg().fetch(fr) else {
#if DEBUG
                        L.og.notice("🟪 \(taskId) Could not fetch posts from relays using \(pubkeys.count) pubkeys. Our pubkey: \(self.pubkey?.short ?? "-") ")
#endif
                        
                        return
                    }
                    guard events.count > 20 else {
#if DEBUG
                        L.og.notice("🟪 \(taskId) Received only \(events.count) events, waiting for more. Our pubkey: \(self.pubkey?.short ?? "-") ")
#endif
                        return
                    }
                    self.events = events
#if DEBUG
                    L.og.notice("🟪 Received \(events.count) posts from relays (found in db)")
#endif
                }
            } timeoutCommand: { [weak self] taskId in
                guard let self = self else { return }
                if self.events == nil {
#if DEBUG
                    L.og.notice("🟪 \(taskId) TIMEOUT: Could not fetch posts from relays using \(pubkeys.count) pubkeys. Our pubkey: \(self.pubkey?.short ?? "-") ")
#endif
                    bg().perform { [weak self] in
                        self?.events = []
                    }
                }
            }
            
            self.backlog.add(getFollowingEventsTask)
            getFollowingEventsTask.fetch()
        }
    }
    
    private func fetchPostsFromGlobalishRelays() {
        guard !relays.isEmpty else { return }
        let relayCount = relays.count
        
        Task.detached { [weak self] in
            bg().perform {
                guard let self = self else { return }
                let getGlobalEventsTask = ReqTask(subscriptionId: "RM.getRelayFeedEvents-" + UUID().uuidString) { taskId in
#if DEBUG
                    L.og.notice("🟪 Fetching posts from globalish relays using \(relayCount) relays")
#endif
                    let filters = [Filters(kinds: [1,1222,5,6,20,9802,30023,34235], since: self.since != 0 ? self.since : nil, limit: 500)]
                    if let message = CM(type: .REQ, subscriptionId: taskId, filters: filters).json() {
                        req(message, relays: self.relays)
                    }
                } processResponseCommand: { [weak self] taskId, _, _ in
                    bg().perform {
                        guard let self = self else { return }
                        let fr = Event.postsByRelays(self.relays, lastAppearedCreatedAt: Int64(self.since ?? 0), fetchLimit: 250, kinds: QUERY_FOLLOWING_KINDS)
                        
                        guard let events = try? bg().fetch(fr) else {
#if DEBUG
                            L.og.notice("🟪 \(taskId) Could not fetch posts from globalish relays using \(relayCount) relays.")
#endif
                            return
                        }
                        guard events.count > 0 else {
#if DEBUG
                            L.og.notice("🟪 \(taskId) Received only \(events.count) events, waiting for more.")
#endif
                            return
                        }
                        self.events = events
#if DEBUG
                        L.og.notice("🟪 Received \(events.count) posts from relays (found in db)")
#endif
                    }
                } timeoutCommand: { [weak self] taskId in
                    guard let self else { return }
                    self.isRunning = false
                    let fr = Event.postsByRelays(self.relays, lastAppearedCreatedAt: Int64(self.since ?? 0), fetchLimit: 500, force: true, kinds: QUERY_FOLLOWING_KINDS)
                    if let events = try? bg().fetch(fr), !events.isEmpty {
#if DEBUG
                        L.og.notice("🟪 \(taskId) TIMEOUT: Could not fetch posts from globalish relays using \(relayCount) relays. (1) ")
#endif
                        self.events = events
                    }
                    else {
#if DEBUG
                        L.og.notice("🟪 \(taskId) TIMEOUT: Could not fetch posts from globalish relays using \(relayCount) relays. (2)")
#endif
                        self.events = []
                    }
                }
                
                self.backlog.add(getGlobalEventsTask)
                getGlobalEventsTask.fetch()
            }
        }
    }
    
    typealias Pubkey = String
}

