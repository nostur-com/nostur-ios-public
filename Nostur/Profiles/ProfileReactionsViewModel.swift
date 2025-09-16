//
//  ProfileReactionsViewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/09/2023.
//

import SwiftUI
import NostrEssentials
import Combine

class ProfileReactionsViewModel: ObservableObject {
    
    @Published var state: State
    private var pubkey: String
    private var reactedIds: Set<String>
    public var reactionsMap: [String: String] = [:] // post id - reaction mapping
    private var backlog: Backlog
    private static let POSTS_LIMIT = 25 // TODO: ADD PAGINATION
    private static let REQ_IDS_LIMIT = 500 // (strfry default)
    private var subscriptions = Set<AnyCancellable>()
    private var prefetchedIds = Set<String>()
        
    @Published var posts: [NRPost] = [] {
        didSet {
            guard !posts.isEmpty else { return }
            L.og.info("Profile Reactions: loaded \(self.posts.count) posts")
        }
    }
        
    public func timeout() {
        self.state = .timeout
    }
    
    public init(_ pubkey: String) {
        self.pubkey = pubkey
        self.state = .initializing
        self.reactedIds = []
        self.backlog = Backlog(timeout: 8.0, auto: true, backlogDebugName: "ProfileReactionsViewModel")
        
        receiveNotification(.blockListUpdated)
            .sink { [weak self] notification in
                guard let self else { return }
                let blockedPubkeys = notification.object as! Set<String>
                self.posts = self.posts.filter { !blockedPubkeys.contains($0.pubkey)  }
            }
            .store(in: &self.subscriptions)
    }
    
    // STEP 1: FETCH REACTIONS FROM RELAYS
    private func fetchReactionsFromRelays(_ onComplete: (() -> ())? = nil) {
        let reqTask = ReqTask(
            debounceTime: 0.5,
            subscriptionId: "PROFILEREACTIONS",
            reqCommand: { [weak self] taskId in
                guard let self else { return }
                if let cm = NostrEssentials
                            .ClientMessage(type: .REQ,
                                           subscriptionId: taskId,
                                           filters: [
                                            Filters(
                                                authors: [self.pubkey],
                                                kinds: Set([7]),
                                                limit: 500
                                            )
                                           ]
                            ).json() {
                    req(cm)
                }
                else {
                    L.og.error("Profile Reactions: Problem generating request")
                }
            },
            processResponseCommand: { [weak self] taskId, relayMessage, _ in
                self?.backlog.clear()
                self?.fetchReactionsFromDB(onComplete)

                L.og.info("Profile Reactions: ready to process relay response")
            },
            timeoutCommand: { [weak self] taskId in
                self?.backlog.clear()
                self?.fetchReactionsFromDB(onComplete)
                L.og.info("Profile Reactions: timeout ")
            })

        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    // STEP 2: FETCH RECEIVED REACTIONS FROM DB
    private func fetchReactionsFromDB(_ onComplete: (() -> ())? = nil) {
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind == 7 AND pubkey == %@", self.pubkey)
        bg().perform { [weak self] in
            guard let self else { return }
            guard let reactions = try? bg().fetch(fr) else { return }
                
            for reaction in reactions
                .sorted(by: { $0.created_at > $1.created_at })
                .prefix(Self.POSTS_LIMIT)
            {
                guard let reactionToId = reaction.reactionToId else { continue }
                self.reactedIds.insert(reactionToId)
                let reactionContent = reaction.content ?? "+"
                Task { @MainActor in // need to access from main later
                    self.reactionsMap[reactionToId] = reactionContent
                }
            }
            self.fetchPostsFromRelays(onComplete)
        }
    }
    
    // STEP 3: FETCH REACTED POSTS FROM RELAYS
    private func fetchPostsFromRelays(_ onComplete: (() -> ())? = nil) {
        
        // Skip ids we already have, so we can fit more into the default 500 limit
        bg().perform { [weak self] in
            guard let self else { return }
            let onlyNewIds = self.reactedIds
                .filter { postId in
                    Importer.shared.existingIds[postId] == nil
                }
                .prefix(Self.REQ_IDS_LIMIT)
        

            guard !onlyNewIds.isEmpty else {
                L.og.debug("Profile Reactions: fetchPostsFromRelays: empty ids")
                if (self.reactedIds.count > 0) {
                    L.og.debug("Profile Reactions: but we can render the duplicates")
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
            
            L.og.debug("Profile Reactions: fetching \(self.reactedIds.count) posts, skipped \(self.reactedIds.count - onlyNewIds.count) duplicates")
            
            let reqTask = ReqTask(
                debounceTime: 0.5,
                subscriptionId: "PROFILE-REACTED-POSTS",
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
                        L.og.error("Profile Reactions: Problem generating posts request")
                    }
                },
                processResponseCommand: { [weak self] taskId, relayMessage, _ in
                    self?.fetchPostsFromDB(onComplete)
                    self?.backlog.clear()
                    L.og.info("Profile Reactions: ready to process relay response")
                },
                timeoutCommand: { [weak self] taskId in
                    self?.fetchPostsFromDB(onComplete)
                    self?.backlog.clear()
                    L.og.info("Profile Reactions: timeout ")
                })

            self.backlog.add(reqTask)
            reqTask.fetch()
           
        }
    }
    
    // STEP 4: FETCH RECEIVED POSTS FROM DB
    private func fetchPostsFromDB(_ onComplete: (() -> ())? = nil) {
        let blockedPubkeys = blocks()
        bg().perform { [weak self] in
            guard let self else { return }
            guard !self.reactedIds.isEmpty else {
                L.og.debug("fetchPostsFromDB: empty ids")
                onComplete?()
                return
            }
            
            var nrPosts: [NRPost] = []
            for postId in self.reactedIds {
                if let event = Event.fetchEvent(id: postId, context: bg()) {
                    guard !blockedPubkeys.contains(event.pubkey) else { continue } // no blocked accounts
                    nrPosts.append(NRPost(event: event))
                }
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
        self.reactedIds = []
        self.posts = []
        self.fetchReactionsFromRelays()
    }
    
    // for after account change
    public func reload() {
        self.state = .loading
        self.reactedIds = []
        self.backlog.clear()
        self.posts = []
        self.fetchReactionsFromRelays()
    }
    
    // pull to refresh
    public func refresh() async {
        self.state = .loading
        self.reactedIds = []
        self.backlog.clear()
        
        await withCheckedContinuation { [weak self] continuation in
            self?.fetchReactionsFromRelays {
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
