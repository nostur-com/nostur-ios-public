//
//  InstantFeed.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/05/2023.
//

import Foundation
import Combine

class InstantFeed {
    typealias CompletionHandler = ([Event]) -> ()
    var backlog = Backlog(auto: true)
    var bg = DataProvider.shared().bg
    var pongReceiver:AnyCancellable?
    var pubkey:Pubkey?
    var onComplete:CompletionHandler?
//    var pongReceived = false {
//        didSet {
//            if pongReceived, oldValue == false, let pubkey {
//                L.og.notice("🟪 First pong received. ")
//                fetchContactListPubkeys(pubkey: pubkey)
//            }
//        }
//    }
    var pubkeys:Set<Pubkey>? {
        didSet {
            if pubkeys != nil {
                fetchPostsFromRelays()
            }
        }
    }
    var events:[Event]? {
        didSet {
            if let events {
                self.onComplete?(events)
                self.backlog.clear()
            }
        }
    }
    
    public func start(_ pubkey:Pubkey, onComplete: @escaping CompletionHandler) {
        L.og.notice("🟪 InstantFeed.start(\(pubkey.short))")
        self.pubkey = pubkey
        self.onComplete = onComplete
//        SocketPool.shared.ping()
        fetchContactListPubkeys(pubkey: pubkey)
    }
    
    public func start(_ pubkeys:Set<Pubkey>, onComplete: @escaping CompletionHandler) {
        L.og.notice("🟪 InstantFeed.start(\(pubkeys.count) pubkeys)")

        self.onComplete = onComplete
//        SocketPool.shared.ping()
        self.pubkeys = pubkeys
        fetchPostsFromRelays()
    }
    
//    func checkConnection() {
//        L.og.notice("🟪 Checking connection (PING) ")
//        pongReceiver = receiveNotification(.pong)
//            .sink { [weak self] _ in
//                guard let self = self else { return }
//                self.pongReceived = true
//            }
//        SocketPool.shared.ping()
//    }
    
    var kind3listener:AnyCancellable?

    func fetchContactListPubkeys(pubkey: Pubkey) {
        Task.detached {
            self.bg.perform { [weak self] in
                guard let self = self else { return }
                if let account = try? Account.fetchAccount(publicKey: pubkey, context: bg), !account.follows_.isEmpty {
                    L.og.notice("🟪 Using account.follows")
                    self.pubkeys = Set(account.follows_.map { $0.pubkey } + [account.publicKey])
                }
                else if let clEvent = Event.fetchReplacableEvent(3, pubkey: pubkey, context: self.bg) {
                    L.og.notice("🟪 Found clEvent in database")
                    if let pubkey = self.pubkey {
                        self.pubkeys = Set(clEvent.fastPs.map { $0.1 } + [pubkey])
                    }
                    else {
                        self.pubkeys = Set(clEvent.fastPs.map { $0.1 })
                    }
                }
                else {
                    let getContactListTask = ReqTask(prefix: "CLT-") { taskId in
                        L.og.notice("🟪 Fetching clEvent from relays")
                        reqP(RM.getAuthorContactsList(pubkey: pubkey, subscriptionId: taskId))
                    } processResponseCommand: { taskId, _ in
                        self.bg.perform { [weak self] in
                            guard let self = self else { return }
                            L.og.notice("🟪 Processing clEvent response from relays")
                            if let clEvent = Event.fetchReplacableEvent(3, pubkey: pubkey, context: self.bg) {
                                self.pubkeys = Set(clEvent.fastPs.map { $0.1 })
                            }
                        }
                    } timeoutCommand: { taskId in
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
                            self.backlog.remove(getContactListTask)
                            self.pubkeys = Set(kind3.fastPs.map { $0.1 })
                        }
                }
            }
        }
    }
    
    func fetchPostsFromRelays() {
        Task.detached {
            self.bg.perform { [weak self] in
                guard let self = self else { return }
                guard let pubkeys = self.pubkeys else { return }
                
                let getFollowingEventsTask = ReqTask(prefix: "GFET-") { taskId in
                    L.og.notice("🟪 Fetching posts from relays using \(pubkeys.count) pubkeys")
                    reqP(RM.getFollowingEvents(pubkeys: Array(pubkeys), limit: 200, subscriptionId: taskId))
                } processResponseCommand: { taskId, _ in
                    self.bg.perform { [weak self] in
                        guard let self = self else { return }
                        let fr = Event.postsByPubkeys(pubkeys, lastAppearedCreatedAt: 0)
                        guard let events = try? self.bg.fetch(fr) else {
                            L.og.notice("🟪 \(taskId) Could not fetch posts from relays using \(pubkeys.count) pubkeys. Our pubkey: \(self.pubkey?.short ?? "-") ")
                            return
                        }
                        guard events.count > 35 else {
                            L.og.notice("🟪 \(taskId) Received only \(events.count) events, waiting for more. Our pubkey: \(self.pubkey?.short ?? "-") ")
                            return
                        }
                        self.events = events
                        L.og.notice("🟪 Received \(events.count) posts from relays (found in db)")
                    }
                } timeoutCommand: { taskId in
                    if self.events == nil {
                        L.og.notice("🟪 \(taskId) TIMEOUT: Could not fetch posts from relays using \(pubkeys.count) pubkeys. Our pubkey: \(self.pubkey?.short ?? "-") ")
                        self.events = []
                    }
                }
                
                self.backlog.add(getFollowingEventsTask)
                getFollowingEventsTask.fetch()
            }
        }
    }
    
    typealias Pubkey = String
}

