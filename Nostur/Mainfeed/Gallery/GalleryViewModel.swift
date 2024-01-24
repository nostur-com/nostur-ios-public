//
//  GalleryViewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/09/2023.
//

import SwiftUI
import NostrEssentials
import CoreData
import Combine

class GalleryViewModel: ObservableObject {
    
    @Published var state:GalleryState
    private var posts:[PostID: RecommendedBy<Pubkey>]
    private var backlog:Backlog
    private var follows:Set<Pubkey>
    private var didLoad = false
    private static let POSTS_LIMIT = 100
    private static let REQ_IDS_LIMIT = 500 // (strfry default)
    private static let MAX_IMAGES_PER_POST = 3
    private var subscriptions = Set<AnyCancellable>()
    private var prefetchedIds = Set<String>()
        
    @Published var items:[GalleryItem] = [] {
        didSet {
            guard !items.isEmpty else { return }
            L.og.info("Gallery feed loaded \(self.items.count) items")
        }
    }
    
    // From DB we always fetch the maximum time frame selected
    private var agoTimestamp:Int {
        return Int(Date.now.addingTimeInterval(-1 * Double(ago) * 3600).timeIntervalSince1970)
    }
    
    // From relays we fetch maximum at first, and then from since the last fetch, but not if its outside of time frame
    private var agoFetchTimestamp:Int {
        if let lastFetch, Int(lastFetch.timeIntervalSince1970) < agoTimestamp {
            return Int(lastFetch.timeIntervalSince1970)
        }
        return agoTimestamp
    }
    private var lastFetch:Date?
    
    @AppStorage("feed_gallery_ago") var ago:Int = 12 {
        didSet {
            logAction("Gallery feed time frame changed to \(self.ago)h")
            backlog.timeout = max(Double(ago / 4), 8.0)
            if ago < oldValue {
                self.state = .loading
                self.follows = Nostur.follows()
                self.fetchPostsFromDB()
            }
            else {
                self.state = .loading
                lastFetch = nil // need to fetch further back, so remove lastFetch
                self.follows = Nostur.follows()
                self.fetchLikesAndRepostsFromRelays()
            }
        }
    }
    
    var timeoutSeconds:Int { // 12 sec timeout for 1st 8hrs + 1 sec for every 4h after
        max(12, Int(ceil(Double(12 + ((ago-8)/4)))))
    }
    
    public func timeout() {
        self.state = .timeout
    }
    
    public init() {
        self.state = .initializing
        self.posts = [PostID: RecommendedBy<Pubkey>]()
        self.backlog = Backlog(timeout: 5.0, auto: true)
        self.follows = Nostur.follows()
        
        receiveNotification(.blockListUpdated)
            .sink { [weak self] notification in
                guard let self else { return }
                let blockedPubkeys = notification.object as! Set<String>
                self.items = self.items.filter { $0.pubkey == nil || !blockedPubkeys.contains($0.pubkey!)  }
            }
            .store(in: &self.subscriptions)
    }
    
    // STEP 1: FETCH LIKES AND REPOSTS FROM FOLLOWS FROM RELAYS
    private func fetchLikesAndRepostsFromRelays(_ onComplete: (() -> ())? = nil) {
        let reqTask = ReqTask(
            debounceTime: 0.5,
            subscriptionId: "GALLERY",
            reqCommand: { [weak self] taskId in
                guard let self else { return }
                if let cm = NostrEssentials
                            .ClientMessage(type: .REQ,
                                           subscriptionId: taskId,
                                           filters: [
                                            Filters(
                                                authors: self.follows,
                                                kinds: Set([6,7]),
                                                since: self.agoFetchTimestamp,
                                                limit: 9999
                                            )
                                           ]
                            ).json() {
                    req(cm)
                    self.lastFetch = Date.now
                }
                else {
                    L.og.error("Gallery feed: Problem generating request")
                    onComplete?()
                }
            },
            processResponseCommand: { [weak self] taskId, relayMessage, _ in
                guard let self else { return }
                self.backlog.clear()
                self.fetchLikesAndRepostsFromDB(onComplete)

                L.og.info("Gallery feed: ready to process relay response")
            },
            timeoutCommand: { [weak self] taskId in
                guard let self else { return }
                self.backlog.clear()
                self.fetchLikesAndRepostsFromDB(onComplete)
                L.og.info("Gallery feed: timeout ")
            })

        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    // STEP 2: FETCH RECEIVED LIKES/REPOSTS FROM DB, SORT MOST LIKED/REPOSTED POSTS (WE ONLY HAVE IDs HERE)
    private func fetchLikesAndRepostsFromDB(_ onComplete: (() -> ())? = nil) {
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "created_at > %i AND kind IN {6,7} AND pubkey IN %@", agoTimestamp, follows)
        bg().perform { [weak self] in
            guard let self else { return }
            guard let likesOrReposts = try? bg().fetch(fr) else { return }
            for item in likesOrReposts {
                switch item.kind {
                case 6:
                    guard let firstQuoteId = item.firstQuoteId else { continue }
                    if self.posts[firstQuoteId] != nil {
                        self.posts[firstQuoteId]!.insert(item.pubkey)
                    }
                    else {
                        self.posts[firstQuoteId] = RecommendedBy([item.pubkey])
                    }
                case 7:
                    guard let reactionToId = item.reactionToId else { continue }
                    if self.posts[reactionToId] != nil {
                        self.posts[reactionToId]!.insert(item.pubkey)
                    }
                    else {
                        self.posts[reactionToId] = RecommendedBy([item.pubkey])
                    }
                default:
                    continue
                }
                
            }
            
            self.fetchPostsFromRelays(onComplete)
        }
    }

    // STEP 3: FETCH MOST LIKED/REPOSTED POSTS FROM RELAYS
    private func fetchPostsFromRelays(_ onComplete: (() -> ())? = nil) {
        
        // Skip ids we already have, so we can fit more into the default 500 limit
        let posts = self.posts
        bg().perform { [weak self] in
            let onlyNewIds = posts.keys
                .filter { postId in
                    Importer.shared.existingIds[postId] == nil
                }
            
            let sortedByLikesAndReposts = posts
                .filter({ el in
                    onlyNewIds.contains(el.key)
                })
                .sorted(by: { $0.value.count > $1.value.count })
                .prefix(Self.REQ_IDS_LIMIT)
        
            let ids = Set(sortedByLikesAndReposts.map { (postId, likedOrRepostedBy) in postId })

            guard !ids.isEmpty else {
                L.og.debug("Gallery feed: fetchPostsFromRelays: empty ids")
                if (posts.count > 0) {
                    L.og.debug("Gallery feed: but we can render the duplicates")
                    DispatchQueue.main.async {
                        self?.fetchPostsFromDB(onComplete)
                        self?.backlog.clear()
                    }
                }
                else {
                    onComplete?()
                }
                return
            }
            
            L.og.debug("Gallery feed: fetching \(ids.count) posts, skipped \(posts.count - ids.count) duplicates")
            
            let reqTask = ReqTask(
                debounceTime: 0.5,
                subscriptionId: "GALLERY-POSTS",
                reqCommand: { taskId in
                    if let cm = NostrEssentials
                                .ClientMessage(type: .REQ,
                                               subscriptionId: taskId,
                                               filters: [
                                                Filters(
                                                    ids: ids,
                                                    limit: 9999
                                                )
                                               ]
                                ).json() {
                        req(cm)
                    }
                    else {
                        L.og.error("Gallery feed: Problem generating posts request")
                    }
                },
                processResponseCommand: { [weak self] taskId, relayMessage, _ in
                    guard let self else { return }
                    self.fetchPostsFromDB(onComplete)
                    self.backlog.clear()
                    L.og.info("Gallery feed: ready to process relay response")
                },
                timeoutCommand: { [weak self] taskId in
                    guard let self else { return }
                    self.fetchPostsFromDB(onComplete)
                    self.backlog.clear()
                    L.og.info("Gallery feed: timeout ")
                })

            self?.backlog.add(reqTask)
            reqTask.fetch()
        }
    }
    
    // STEP 4: FETCH RECEIVED POSTS FROM DB, SORT BY MOST LIKED/REPOSTED AND PUT ON SCREEN
    private func fetchPostsFromDB(_ onComplete: (() -> ())? = nil) {
        let ids = Set(self.posts.keys)
        guard !ids.isEmpty else {
            L.og.debug("fetchPostsFromDB: empty ids")
            onComplete?()
            return
        }
        let blockedPubkeys = blocks()
        bg().perform { [weak self] in
            guard let self else { return }
            let sortedByLikesAndReposts = self.posts
                .sorted(by: { $0.value.count > $1.value.count })
            
            
            var items:[GalleryItem] = []
            for (postId, likesOrReposts) in sortedByLikesAndReposts {
                if (likesOrReposts.count > 3) {
                    L.og.debug("🔝🔝 id:\(postId): \(likesOrReposts.count)")
                }
                if let event = try? Event.fetchEvent(id: postId, context: bg()) {
                    guard !blockedPubkeys.contains(event.pubkey) else { continue } // no blocked accoutns
                    guard event.replyToId == nil && event.replyToRootId == nil else { continue } // no replies
                    guard event.created_at > self.agoTimestamp else { continue } // post itself should be within timeframe also
                    guard let content = event.content else { continue }
                    
                    let urls = getImgUrlsFromContent(content)
                    guard !urls.isEmpty else { continue }
                    
                    for url in urls.prefix(Self.MAX_IMAGES_PER_POST) {
                        items.append(GalleryItem(url: url, event: event))
                    }
                }
            }
            
            DispatchQueue.main.async { [weak self] in
                onComplete?()
                self?.items = items
                self?.state = .ready
            }
        }
    }
    
    public func load() {
        guard shouldReload else { return }
        L.og.info("Gallery feed: load()")
        self.follows = Nostur.follows()
        self.state = .loading
        self.items = []
        self.fetchLikesAndRepostsFromRelays()
    }
    
    // for after acocunt change
    public func reload() {
        self.state = .loading
        self.lastFetch = nil
        self.posts = [PostID: RecommendedBy<Pubkey>]()
        self.backlog.clear()
        self.follows = Nostur.follows()
        self.items = []
        self.fetchLikesAndRepostsFromRelays()
    }
    
    // pull to refresh
    public func refresh() async {
        // don't change .state on refresh, or rerender will cause the pull-to-refresh to be wonky
        self.lastFetch = nil
        self.posts = [PostID: RecommendedBy<Pubkey>]()
        self.backlog.clear()
        self.follows = Nostur.follows()
        
        await withCheckedContinuation { continuation in
            self.fetchLikesAndRepostsFromRelays {
                continuation.resume()
            }
        }
    }
    
    public var shouldReload: Bool {
        // Should only refetch since last fetch, if last fetch is more than 10 mins ago
        guard let lastFetch else { return true }

        if (Date.now.timeIntervalSince1970 - lastFetch.timeIntervalSince1970) > 60 * 10 {
            return true
        }
        return false
    }
    
    public enum GalleryState {
        case initializing
        case loading
        case ready
        case timeout
    }
}


struct GalleryItem: Identifiable, Equatable {

    let id:UUID
    let pubkey:String? // for blocklist filtering
    let url:URL
    let event:Event? // bg
    let eventId:String? // need the id in main context
    var pfpPictureURL:URL?
        
    init(url:URL, event:Event? = nil) {
        self.url = url
        self.event = event
        self.eventId = event?.id
        self.id = UUID()
        self.pubkey = event?.pubkey
        if let event {
            self.pfpPictureURL = NRState.shared.loggedInAccount?.followingCache[event.pubkey]?.pfpURL
        }
    }

    static func == (lhs: GalleryItem, rhs: GalleryItem) -> Bool {
        lhs.id == rhs.id
    }
}
