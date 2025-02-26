//
//  ProfileInteractionsReactionsVM.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/02/2025.
//

import SwiftUI
import NostrEssentials
import Combine

class ProfileInteractionsRepostsVM: ObservableObject {
    
    @Published var state: State
    private var accountPubkey: String?
    private var pubkey: String
    private var repostedIds: Set<String>
    private var backlog: Backlog
    private static let POSTS_LIMIT = 100 // TODO: ADD PAGINATION
    private static let REQ_IDS_LIMIT = 500 // (strfry default)
    private var subscriptions = Set<AnyCancellable>()
    private var prefetchedIds = Set<String>()
        
    @Published var posts: [NRPost] = [] {
        didSet {
            guard !posts.isEmpty else { return }
            L.og.info("Profile Interactions - Reposts: loaded \(self.posts.count) posts")
        }
    }
        
    public func timeout() {
        self.state = .timeout
    }
    
    public init(_ pubkey: String) {
        self.accountPubkey = account()?.publicKey ?? NRState.shared.activeAccountPublicKey
        self.pubkey = pubkey
        self.state = .initializing
        self.repostedIds = []
        self.backlog = Backlog(timeout: 8.0, auto: true)
    }
    
    // STEP 1: FETCH INTERACTIONS (REPOSTS) FROM RELAYS
    private func fetchInteractionsFromRelays(_ onComplete: (() -> ())? = nil) {
        guard let accountPubkey = self.accountPubkey else { return }
        let reqTask = ReqTask(
            debounceTime: 0.5,
            subscriptionId: "PROFILEINTERACTIONS-6",
            reqCommand: { [weak self] taskId in
                guard let self else { return }
                if let cm = NostrEssentials
                            .ClientMessage(type: .REQ,
                                           subscriptionId: taskId,
                                           filters: [
                                            Filters(
                                                authors: [self.pubkey],
                                                kinds: Set([6]),
                                                tagFilter: TagFilter(tag: "p", values: [accountPubkey]),
                                                limit: 2500
                                            )
                                           ]
                            ).json() {
                    req(cm)
                }
                else {
                    L.og.error("Profile Interactions - Reposts: Problem generating request")
                }
            },
            processResponseCommand: { [weak self] taskId, relayMessage, _ in
                self?.backlog.clear()
                self?.fetchRepostsFromDB(onComplete)

                L.og.info("Profile Interactions - Reposts: ready to process relay response")
            },
            timeoutCommand: { [weak self] taskId in
                self?.backlog.clear()
                self?.fetchRepostsFromDB(onComplete)
                L.og.info("Profile Interactions - Reposts: timeout ")
            })

        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    // STEP 2: FETCH RECEIVED REPOSTS FROM DB
    private func fetchRepostsFromDB(_ onComplete: (() -> ())? = nil) {
        guard let accountPubkey = self.accountPubkey else { return }
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind == 6 AND pubkey == %@ AND otherPubkey = %@", self.pubkey, accountPubkey)
        bg().perform { [weak self] in
            guard let self else { return }
            guard let reposts = try? bg().fetch(fr) else { return }
                
            for repost in reposts
                .sorted(by: { $0.created_at > $1.created_at })
                .prefix(Self.POSTS_LIMIT)
            {
                guard let firstQuoteId = repost.firstQuoteId else { continue }
                self.repostedIds.insert(firstQuoteId)
            }
            self.fetchPostsFromRelays(onComplete)
        }
    }
    
    // STEP 3: FETCH REPOSTED POSTS FROM RELAYS
    private func fetchPostsFromRelays(_ onComplete: (() -> ())? = nil) {
        
        // Skip ids we already have, so we can fit more into the default 500 limit
        bg().perform { [weak self] in
            guard let self else { return }
            let onlyNewIds = self.repostedIds
                .filter { postId in
                    Importer.shared.existingIds[postId] == nil
                }
                .prefix(Self.REQ_IDS_LIMIT)
        

            guard !onlyNewIds.isEmpty else {
                L.og.debug("Profile Interactions - Reposts: fetchPostsFromRelays: empty ids")
                if (self.repostedIds.count > 0) {
                    L.og.debug("Profile Interactions - Reposts: but we can render the duplicates")
                    DispatchQueue.main.async { [weak self] in
                        self?.fetchPostsFromDB(onComplete)
                        self?.backlog.clear()
                    }
                }
                else {
                    onComplete?()
                }
                return
            }
            
            L.og.debug("Profile Interactions - Reposts: fetching \(self.repostedIds.count) posts, skipped \(self.repostedIds.count - onlyNewIds.count) duplicates")
            
            let reqTask = ReqTask(
                debounceTime: 0.5,
                subscriptionId: "PROFILEINTERACTIONS-6-P",
                reqCommand: { taskId in
                    if let cm = NostrEssentials
                                .ClientMessage(type: .REQ,
                                               subscriptionId: taskId,
                                               filters: [
                                                Filters(
                                                    ids: Set(onlyNewIds),
                                                    limit: 9999
                                                )
                                               ]
                                ).json() {
                        req(cm)
                    }
                    else {
                        L.og.error("Profile Reposts: Problem generating posts request")
                    }
                },
                processResponseCommand: { [weak self] taskId, relayMessage, _ in
                    self?.fetchPostsFromDB(onComplete)
                    self?.backlog.clear()
                    L.og.info("Profile Reposts: ready to process relay response")
                },
                timeoutCommand: { [weak self] taskId in
                    self?.fetchPostsFromDB(onComplete)
                    self?.backlog.clear()
                    L.og.info("Profile Reposts: timeout ")
                })

            self.backlog.add(reqTask)
            reqTask.fetch()
           
        }
    }
    
    // STEP 4: FETCH RECEIVED POSTS FROM DB
    private func fetchPostsFromDB(_ onComplete: (() -> ())? = nil) {
        guard let accountPubkey = self.accountPubkey else { return }
        bg().perform { [weak self] in
            guard let self else { return }
            guard !self.repostedIds.isEmpty else {
                L.og.debug("fetchPostsFromDB: empty ids")
                onComplete?()
                return
            }
            
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "pubkey = %@ AND id IN %@", accountPubkey, self.repostedIds)
            
            let nrPosts: [NRPost] = ((try? bg().fetch(fr)) ?? [])
                .map { event in
                    NRPost(event: event)
                }

            DispatchQueue.main.async { [weak self] in
                onComplete?()
                self?.posts = Array(nrPosts
                    .sorted(by: { $0.createdAt > $1.createdAt })
                    .prefix(Self.POSTS_LIMIT))
                        
                self?.state = .ready
            }
            
            guard !nrPosts.isEmpty else { return }
            guard SettingsStore.shared.fetchCounts && SettingsStore.shared.rowFooterEnabled else { return }
            for nrPost in nrPosts.prefix(5) {
                EventRelationsQueue.shared.addAwaitingEvent(nrPost.event)
            }
            let eventIds = nrPosts.prefix(5).map { $0.id }
            L.fetching.info("🔢 Fetching counts for \(eventIds.count) posts")
            fetchStuffForLastAddedNotes(ids: eventIds)
            self.prefetchedIds = self.prefetchedIds.union(Set(eventIds))
        }
    }
    
    public func prefetch(_ post:NRPost) {
        guard SettingsStore.shared.fetchCounts else { return }
        guard !self.prefetchedIds.contains(post.id) else { return }
        guard let index = self.posts.firstIndex(of: post) else { return }
        guard index % 5 == 0 else { return }
        
        let nextIds = self.posts.dropFirst(max(0,index - 1)).prefix(5).map { $0.id }
        guard !nextIds.isEmpty else { return }
        L.fetching.info("🔢 Fetching counts for \(nextIds.count) posts")
        fetchStuffForLastAddedNotes(ids: nextIds)
        self.prefetchedIds = self.prefetchedIds.union(Set(nextIds))
    }
    
    public func load() {
        self.state = .loading
        self.repostedIds = []
        self.posts = []
        self.fetchInteractionsFromRelays()
    }
    
    // for after account change
    public func reload() {
        self.accountPubkey = account()?.publicKey ?? NRState.shared.activeAccountPublicKey
        self.state = .loading
        self.backlog.clear()
        self.repostedIds = []
        self.posts = []
        self.fetchInteractionsFromRelays()
    }
    
    // pull to refresh
    public func refresh() async {
        self.accountPubkey = account()?.publicKey ?? NRState.shared.activeAccountPublicKey
        self.state = .loading
        self.backlog.clear()
        
        await withCheckedContinuation { [weak self] continuation in
            self?.fetchInteractionsFromRelays {
                continuation.resume()
            }
        }
    }
    
    public enum State {
        case initializing
        case loading
        case ready
        case timeout
    }
}
