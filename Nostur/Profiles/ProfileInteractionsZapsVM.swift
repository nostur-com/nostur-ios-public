//
//  ProfileInteractionsZapsVM.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/02/2025.
//

import SwiftUI
import NostrEssentials
import Combine

class ProfileInteractionsZapsVM: ObservableObject {
    
    @Published var state: State
    private var accountPubkey: String?
    private var pubkey: String
    private var zappedEventIds: Set<String>
    public var zapsMap: [String: (Double, String?)] = [:] // post id: (amount, content)
    private var backlog: Backlog
    private static let POSTS_LIMIT = 250 // TODO: ADD PAGINATION
    private static let REQ_IDS_LIMIT = 500 // (strfry default)
    private var subscriptions = Set<AnyCancellable>()
    private var prefetchedIds = Set<String>()
        
    @Published var posts: [NRPost] = [] {
        didSet {
            guard !posts.isEmpty else { return }
            L.og.info("Profile Interactions - Zaps: loaded \(self.posts.count) posts")
        }
    }
        
    public func timeout() {
        self.state = .timeout
    }
    
    public init(_ pubkey: String) {
        self.accountPubkey = account()?.publicKey ?? AccountsState.shared.activeAccountPublicKey
        self.pubkey = pubkey
        self.state = .initializing
        self.zappedEventIds = []
        self.backlog = Backlog(timeout: 8.0, auto: true)
    }
    
    // STEP 1: FETCH ZAPS FROM RELAYS
    private func fetchZapsFromRelays(_ onComplete: (() -> ())? = nil) {
        guard let accountPubkey = self.accountPubkey else { return }
        let reqTask = ReqTask(
            debounceTime: 0.5,
            subscriptionId: "PROFILEINTERACTIONS-ZAPS",
            reqCommand: { [weak self] taskId in
                guard let self else { return }
                if let cm = NostrEssentials
                            .ClientMessage(type: .REQ,
                                           subscriptionId: taskId,
                                           filters: [
                                            Filters(
                                                kinds: Set([9735]),
                                                tagFilters: [
                                                    TagFilter(tag: "p", values: [accountPubkey]),
                                                    TagFilter(tag: "P", values: [self.pubkey])
                                                ],
                                                limit: 500
                                            )
                                           ]
                            ).json() {
                    req(cm)
                }
                else {
                    L.og.error("Profile Interactions - Zaps: Problem generating request")
                }
            },
            processResponseCommand: { [weak self] taskId, relayMessage, _ in
                self?.backlog.clear()
                self?.fetchZapsFromDB(onComplete)

                L.og.info("Profile Interactions - Zaps: ready to process relay response")
            },
            timeoutCommand: { [weak self] taskId in
                self?.backlog.clear()
                self?.fetchZapsFromDB(onComplete)
                L.og.info("Profile Interactions - Zaps: timeout ")
            })

        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    // STEP 2: FETCH ZAPS FROM DB
    private func fetchZapsFromDB(_ onComplete: (() -> ())? = nil) {
        guard let accountPubkey = self.accountPubkey else { return }
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind == 9735 AND otherPubkey = %@ AND fromPubkey == %@", accountPubkey, self.pubkey)
        bg().perform { [weak self] in
            guard let self else { return }
            guard let zaps = try? bg().fetch(fr) else { return }
                
            for zap in zaps
                .sorted(by: { $0.created_at > $1.created_at })
                .prefix(Self.POSTS_LIMIT)
            {
                guard let zappedEventId = zap.zappedEventId else { continue }
                guard !zappedEventId.contains(":") else { continue } // no easy way to query article aTags like kind:1 ids, so skip
                
                self.zappedEventIds.insert(zappedEventId)
                let zapInfo: (Double, String?) = (zap.naiveSats, zap.content)
                Task { @MainActor in
                    self.zapsMap[zappedEventId] = zapInfo
                }
            }
            self.fetchPostsFromRelays(onComplete)
        }
    }
    
    // STEP 3: FETCH ZAPPED POSTS FROM RELAYS
    private func fetchPostsFromRelays(_ onComplete: (() -> ())? = nil) {
        
        // Skip ids we already have, so we can fit more into the default 500 limit
        bg().perform { [weak self] in
            guard let self else { return }
            let onlyNewIds = self.zappedEventIds
                .filter { postId in
                    Importer.shared.existingIds[postId] == nil
                }
                .prefix(Self.REQ_IDS_LIMIT)
        

            guard !onlyNewIds.isEmpty else {
                L.og.debug("Profile Interactions - Zaps: fetchPostsFromRelays: empty ids")
                if (self.zappedEventIds.count > 0) {
                    L.og.debug("Profile Interactions - Zaps: but we can render the duplicates")
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
            
            L.og.debug("Profile Interactions - Zaps: fetching \(self.zappedEventIds.count) posts, skipped \(self.zappedEventIds.count - onlyNewIds.count) duplicates")
            
            let reqTask = ReqTask(
                debounceTime: 0.5,
                subscriptionId: "PROFILEINTERACTIONS-ZAPPED-POSTS",
                reqCommand: { taskId in
                    if let cm = NostrEssentials
                                .ClientMessage(type: .REQ,
                                               subscriptionId: taskId,
                                               filters: [
                                                Filters(
                                                    ids: Set(onlyNewIds),
                                                    limit: Self.REQ_IDS_LIMIT
                                                )
                                               ]
                                ).json() {
                        req(cm)
                    }
                    else {
                        L.og.error("Profile Interactions - Zaps: Problem generating posts request")
                    }
                },
                processResponseCommand: { [weak self] taskId, relayMessage, _ in
                    self?.fetchPostsFromDB(onComplete)
                    self?.backlog.clear()
                    L.og.info("Profile Interactions - Zaps: ready to process relay response")
                },
                timeoutCommand: { [weak self] taskId in
                    self?.fetchPostsFromDB(onComplete)
                    self?.backlog.clear()
                    L.og.info("Profile Interactions - Zaps: timeout ")
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
            guard !self.zappedEventIds.isEmpty else {
                L.og.debug("fetchPostsFromDB: empty ids")
                onComplete?()
                return
            }
                        
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "pubkey = %@ AND id IN %@", accountPubkey, self.zappedEventIds)
            
            let nrPosts: [NRPost] = ((try? bg().fetch(fr)) ?? [])
                .map { event in
                    NRPost(event: event)
                }

            
            DispatchQueue.main.async { [weak self] in
                onComplete?()
                self?.posts = Array(nrPosts
                    .sorted(by: { $0.createdAt > $1.createdAt }) // TODO: Should actually sort by repost.createdAt (kind 6)
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
        self.zappedEventIds = []
        self.posts = []
        self.fetchZapsFromRelays()
    }
    
    // for after account change
    public func reload() {
        self.state = .loading
        self.zappedEventIds = []
        self.backlog.clear()
        self.posts = []
        self.fetchZapsFromRelays()
    }
    
    // pull to refresh
    public func refresh() async {
        self.state = .loading
        self.zappedEventIds = []
        self.backlog.clear()
        
        await withCheckedContinuation { [weak self] continuation in
            self?.fetchZapsFromRelays {
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
