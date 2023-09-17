//
//  ProfileLikesViewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/09/2023.
//

import SwiftUI
import NostrEssentials
import Combine

class ProfileLikesViewModel: ObservableObject {
    
    @Published var state:State
    private var pubkey:String
    private var likedIds:Set<String>
    private var backlog:Backlog
    private static let POSTS_LIMIT = 25 // TODO: ADD PAGINATION
    private static let REQ_IDS_LIMIT = 500 // (strfry default)
    private var subscriptions = Set<AnyCancellable>()
    private var prefetchedIds = Set<String>()
        
    @Published var posts:[NRPost] = [] {
        didSet {
            guard !posts.isEmpty else { return }
            L.og.info("Profile Likes: loaded \(self.posts.count) posts")
        }
    }
        
    public func timeout() {
        self.state = .timeout
    }
    
    public init(_ pubkey: String) {
        self.pubkey = pubkey
        self.state = .initializing
        self.likedIds = []
        self.backlog = Backlog(timeout: 8.0, auto: true)
        
        receiveNotification(.blockListUpdated)
            .sink { [weak self] notification in
                guard let self else { return }
                let blockedPubkeys = notification.object as! [String]
                self.posts = self.posts.filter { !blockedPubkeys.contains($0.pubkey)  }
            }
            .store(in: &self.subscriptions)
    }
    
    // STEP 1: FETCH LIKES FROM FOLLOWS FROM RELAYS
    private func fetchLikesFromRelays(_ onComplete: (() -> ())? = nil) {
        let reqTask = ReqTask(
            debounceTime: 0.5,
            subscriptionId: "PROFILELIKES",
            reqCommand: { taskId in
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
                    L.og.error("Profile Likes: Problem generating request")
                }
            },
            processResponseCommand: { taskId, relayMessage in
                self.backlog.clear()
                self.fetchLikesFromDB(onComplete)

                L.og.info("Profile Likes: ready to process relay response")
            },
            timeoutCommand: { taskId in
                self.backlog.clear()
                self.fetchLikesFromDB(onComplete)
                L.og.info("Profile Likes: timeout ")
            })

        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    // STEP 2: FETCH RECEIVED LIKES FROM DB, SORT MOST LIKED POSTS (WE ONLY HAVE IDs HERE)
    private func fetchLikesFromDB(_ onComplete: (() -> ())? = nil) {
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind == 7 AND pubkey == %@", self.pubkey)
        bg().perform {
            guard let likes = try? bg().fetch(fr) else { return }
//            let likesSorted = likes
                
            for like in likes
                .sorted(by: { $0.created_at > $1.created_at })
                .prefix(Self.POSTS_LIMIT)
            {
                guard let reactionToId = like.reactionToId else { continue }
                self.likedIds.insert(reactionToId)
            }
            self.fetchPostsFromRelays()
        }
    }
    
    // STEP 3: FETCH MOST LIKED POSTS FROM RELAYS
    private func fetchPostsFromRelays(onComplete: (() -> ())? = nil) {
        
        // Skip ids we already have, so we can fit more into the default 500 limit
        bg().perform {
            let onlyNewIds = self.likedIds
                .filter { postId in
                    Importer.shared.existingIds[postId] == nil
                }
                .prefix(Self.REQ_IDS_LIMIT)
        

            guard !onlyNewIds.isEmpty else {
                L.og.debug("Profile Likes: fetchPostsFromRelays: empty ids")
                if (self.likedIds.count > 0) {
                    L.og.debug("Profile Likes: but we can render the duplicates")
                    DispatchQueue.main.async {
                        self.fetchPostsFromDB(onComplete)
                        self.backlog.clear()
                    }
                }
                return
            }
            
            L.og.debug("Profile Likes: fetching \(self.likedIds.count) posts, skipped \(self.likedIds.count - onlyNewIds.count) duplicates")
            
            let reqTask = ReqTask(
                debounceTime: 0.5,
                subscriptionId: "PROFILE-LIKED-POSTS",
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
                        L.og.error("Profile Likes: Problem generating posts request")
                    }
                },
                processResponseCommand: { taskId, relayMessage in
                    self.fetchPostsFromDB(onComplete)
                    self.backlog.clear()
                    L.og.info("Profile Likes: ready to process relay response")
                },
                timeoutCommand: { taskId in
                    self.fetchPostsFromDB(onComplete)
                    self.backlog.clear()
                    L.og.info("Profile Likes: timeout ")
                })

            self.backlog.add(reqTask)
            reqTask.fetch()
           
        }
    }
    
    // STEP 4: FETCH RECEIVED POSTS FROM DB, SORT BY MOST LIKED AND PUT ON SCREEN
    private func fetchPostsFromDB(_ onComplete: (() -> ())? = nil) {
        let blockedPubkeys = NosturState.shared.account?.blockedPubkeys_ ?? []
        bg().perform {
            guard !self.likedIds.isEmpty else {
                L.og.debug("fetchPostsFromDB: empty ids")
                return
            }
            
            var nrPosts:[NRPost] = []
            for postId in self.likedIds {
                if let event = try? Event.fetchEvent(id: postId, context: bg()) {
                    guard !blockedPubkeys.contains(event.pubkey) else { continue } // no blocked accoutns
                    nrPosts.append(NRPost(event: event))
                }
            }
            
            DispatchQueue.main.async {
                onComplete?()
                self.posts = Array(nrPosts
                    .sorted(by: { $0.createdAt > $1.createdAt })
                    .prefix(Self.POSTS_LIMIT))
                        
                self.state = .ready
            }
            
            guard !nrPosts.isEmpty else { return }
            guard SettingsStore.shared.fetchCounts else { return }
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
        self.likedIds = []
        self.posts = []
        self.fetchLikesFromRelays()
    }
    
    // for after acocunt change
    public func reload() {
        self.state = .loading
        self.likedIds = []
        self.backlog.clear()
        self.posts = []
        self.fetchLikesFromRelays()
    }
    
    // pull to refresh
    public func refresh() async {
        self.state = .loading
        self.likedIds = []
        self.backlog.clear()
        
        await withCheckedContinuation { continuation in
            self.fetchLikesFromRelays {
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
