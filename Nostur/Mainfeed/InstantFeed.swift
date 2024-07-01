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
    public var backlog = Backlog(timeout: 15, auto: true)
    private var pongReceiver:AnyCancellable?
    private var pubkey:Pubkey?
    private var onComplete:CompletionHandler?

    private var pubkeys:Set<Pubkey>? {
        didSet {
            if pubkeys != nil {
                fetchPostsFromRelays()
            }
        }
    }
    private var events:[Event]? {
        didSet {
            if let events, events.count > 20 {
                self.isRunning = false
                self.onComplete?(events)
                self.backlog.clear()
            }
        }
    }
    private var relays:Set<RelayData> = []
    public var isRunning = false
    
    public func start(_ pubkey:Pubkey, onComplete: @escaping CompletionHandler) {
        L.og.notice("🟪 InstantFeed.start(\(pubkey.short))")
        self.isRunning = true
        self.pubkey = pubkey
        self.onComplete = onComplete
        fetchContactListPubkeys(pubkey: pubkey)
    }
    
    public func start(_ pubkeys:Set<Pubkey>, onComplete: @escaping CompletionHandler) {
        L.og.notice("🟪 InstantFeed.start(\(pubkeys.count) pubkeys)")
        self.isRunning = true
        self.onComplete = onComplete
        self.pubkeys = pubkeys
//        fetchPostsFromRelays() <-- No need, already done on .pubkeys { didSet }
    }
    
    public func start(_ relays:Set<RelayData>, onComplete: @escaping CompletionHandler) {
        L.og.notice("🟪 InstantFeed.start(\(relays.count) relays)")
        self.isRunning = true
        self.onComplete = onComplete
        self.relays = relays
        fetchPostsFromGlobalishRelays()
    }
    
    private var kind3listener:AnyCancellable?

    private func fetchContactListPubkeys(pubkey: Pubkey) {
        signpost(self, "InstantFeed", .event, "Fetching contact list pubkeys")
        Task.detached { [weak self] in
            bg().perform {
                guard let self = self else { return }
                if let account = try? CloudAccount.fetchAccount(publicKey: pubkey, context: bg()), !account.followingPubkeys.isEmpty {
                    L.og.notice("🟪 Using account.follows")
                    self.pubkeys = account.followingPubkeys.union(Set([account.publicKey]))
                }
                else if let clEvent = Event.fetchReplacableEvent(3, pubkey: pubkey, context: bg()) {
                    L.og.notice("🟪 Found clEvent in database")
                    if let pubkey = self.pubkey {
                        self.pubkeys = Set(((clEvent.fastPs.map { $0.1 }) + [pubkey]))
                    }
                    else {
                        self.pubkeys = Set(clEvent.fastPs.map { $0.1 })
                    }
                }
                else {
                    let getContactListTask = ReqTask(subscriptionId: "RM.getAuthorContactsList") { taskId in
                        L.og.notice("🟪 Fetching clEvent from relays")
                        req(RM.getAuthorContactsList(pubkey: pubkey, subscriptionId: taskId))
                    } processResponseCommand: { [weak self] taskId, _, _ in
                        bg().perform {
                            guard let self = self else { return }
                            L.og.notice("🟪 Processing clEvent response from relays")
                            if let clEvent = Event.fetchReplacableEvent(3, pubkey: pubkey, context: bg()) {
                                self.pubkeys = Set(clEvent.fastPs.map { $0.1 })
                            }
                        }
                    } timeoutCommand: { [weak self] taskId in
                        guard let self else { return }
                        if (self.pubkeys == nil) {
                            L.og.notice("🟪  \(taskId) Timeout in fetching clEvent / pubkeys")
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
                            L.og.notice("🟪 Found clEvent already being processed by onboarding task")
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
            guard let self = self else { return }
            guard let pubkeys = self.pubkeys else { return }
            
            let getFollowingEventsTask = ReqTask(prefix: "GFET-") { taskId in
                L.og.notice("🟪 Fetching posts from relays using \(pubkeys.count) pubkeys")
//                req(RM.getFollowingEvents(pubkeys: Array(pubkeys), limit: 400, subscriptionId: taskId))
                let filters = [Filters(authors: pubkeys, kinds: [1,5,6,9802,30023,34235], limit: 400)]
                outboxReq(NostrEssentials.ClientMessage(type: .REQ, subscriptionId: taskId, filters: filters))
                
            } processResponseCommand: { [weak self] taskId, _, _ in
                bg().perform {
                    guard let self = self else { return }
                    let fr = Event.postsByPubkeys(pubkeys, lastAppearedCreatedAt: 0)
                    guard let events = try? bg().fetch(fr) else {
                        L.og.notice("🟪 \(taskId) Could not fetch posts from relays using \(pubkeys.count) pubkeys. Our pubkey: \(self.pubkey?.short ?? "-") ")
                        return
                    }
                    guard events.count > 20 else {
                        L.og.notice("🟪 \(taskId) Received only \(events.count) events, waiting for more. Our pubkey: \(self.pubkey?.short ?? "-") ")
                        return
                    }
                    self.events = events
                    L.og.notice("🟪 Received \(events.count) posts from relays (found in db)")
                }
            } timeoutCommand: { [weak self] taskId in
                guard let self = self else { return }
                if self.events == nil {
                    L.og.notice("🟪 \(taskId) TIMEOUT: Could not fetch posts from relays using \(pubkeys.count) pubkeys. Our pubkey: \(self.pubkey?.short ?? "-") ")
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
                let getGlobalEventsTask = ReqTask(subscriptionId: "RM.getGlobalFeedEvents-" + UUID().uuidString) { taskId in
                    L.og.notice("🟪 Fetching posts from globalish relays using \(relayCount) relays")
                    req(RM.getGlobalFeedEvents(limit: 200, subscriptionId: taskId), relays: self.relays)
                } processResponseCommand: { [weak self] taskId, _, _ in
                    bg().perform {
                        guard let self = self else { return }
                        let fr = Event.postsByRelays(self.relays, lastAppearedCreatedAt: 0)
                        guard let events = try? bg().fetch(fr) else {
                            L.og.notice("🟪 \(taskId) Could not fetch posts from globalish relays using \(relayCount) relays.")
                            return
                        }
                        guard events.count > 15 else {
                            L.og.notice("🟪 \(taskId) Received only \(events.count) events, waiting for more.")
                            return
                        }
                        self.events = events
                        L.og.notice("🟪 Received \(events.count) posts from relays (found in db)")
                    }
                } timeoutCommand: { [weak self] taskId in
                    guard let self else { return }
                    self.isRunning = false
                    if self.events == nil {
                        L.og.notice("🟪 \(taskId) TIMEOUT: Could not fetch posts from globalish relays using \(relayCount) relays. ")
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

