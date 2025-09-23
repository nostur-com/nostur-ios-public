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

class GalleryViewModel: ObservableObject, Equatable, Hashable {
    
    static func == (lhs: GalleryViewModel, rhs: GalleryViewModel) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    let id = UUID()
    
    private var speedTest: NXSpeedTest?
    @Published var state: GalleryState
    private var posts: [PostID: RecommendedBy<Pubkey>]
    private var backlog: Backlog
    private var follows:Set<Pubkey>
    private var didLoad = false
    private static let POSTS_LIMIT = 100
    private static let REQ_IDS_LIMIT = 500 // (strfry default)
    private static let MAX_IMAGES_PER_POST = 3
    private var subscriptions = Set<AnyCancellable>()
    private var prefetchedIds = Set<String>()
        
    @Published var items: [GalleryItem] = [] {
        didSet {
            guard !items.isEmpty else { return }
#if DEBUG
            L.og.debug("Gallery feed loaded \(self.items.count) items")
#endif
        }
    }
    
    // From DB we always fetch the maximum time frame selected
    private var agoTimestamp:Int {
        return Int(Date.now.addingTimeInterval(Double(ago) * -3600).timeIntervalSince1970)
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
                self.fetchPostsFromDB {
                    Task { @MainActor in
                        self.speedTest?.loadingBarViewState = .finalLoad
                        if self.items.isEmpty {
#if DEBUG
                            L.og.debug("Gallery feed: timeout()")
#endif
                            self.timeout()
                        }
                    }
                }
            }
            else {
                self.state = .loading
                lastFetch = nil // need to fetch further back, so remove lastFetch
                self.follows = Nostur.follows()
                self.fetchLikesAndRepostsFromRelays {
                    Task { @MainActor in
                        self.speedTest?.loadingBarViewState = .finalLoad
                        if self.items.isEmpty {
#if DEBUG
                            L.og.debug("Gallery feed: timeout()")
#endif
                            self.timeout()
                        }
                    }
                }
            }
        }
    }
    
    var timeoutSeconds:Int { // 12 sec timeout for 1st 8hrs + 1 sec for every 4h after
        max(12, Int(ceil(Double(12 + ((ago-8)/4)))))
    }
    
    public func timeout() {
        speedTest?.loadingBarViewState = .timeout
        self.state = .timeout
    }
    
    public init() {
        self.state = .initializing
        self.posts = [PostID: RecommendedBy<Pubkey>]()
        self.backlog = Backlog(timeout: 5.0, auto: true, backlogDebugName: "GalleryViewModel")
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
        
        Task { @MainActor in
            if !ConnectionPool.shared.anyConnected {
                speedTest?.loadingBarViewState = .connecting
            }
            else {
                speedTest?.loadingBarViewState = .fetching
            }
        }
        
        let reqTask = ReqTask(
            debounceTime: 0.5,
            subscriptionId: "GALLERY",
            reqCommand: { [weak self] taskId in
                guard let self else { return }
                let follows = self.follows.count <= 2000 ? self.follows : Set(self.follows.shuffled().prefix(2000))
                if let cm = NostrEssentials
                            .ClientMessage(type: .REQ,
                                           subscriptionId: taskId,
                                           filters: [
                                            Filters(
                                                authors: follows,
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
#if DEBUG
                    L.og.error("Gallery feed: Problem generating request")
#endif
                    onComplete?()
                }
            },
            processResponseCommand: { [weak self] taskId, relayMessage, _ in
                guard let self else { return }
                self.backlog.clear()
                self.fetchLikesAndRepostsFromDB(onComplete)
#if DEBUG
                L.og.debug("Gallery feed: ready to process relay response")
#endif
            },
            timeoutCommand: { [weak self] taskId in
                guard let self else { return }
                self.backlog.clear()
                self.fetchLikesAndRepostsFromDB(onComplete)
#if DEBUG
                L.og.debug("Gallery feed: timeout ")
#endif
            })

        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    // STEP 2: FETCH RECEIVED LIKES/REPOSTS FROM DB, SORT MOST LIKED/REPOSTED POSTS (WE ONLY HAVE IDs HERE)
    private func fetchLikesAndRepostsFromDB(_ onComplete: (() -> ())? = nil) {
        
        Task { @MainActor in
            speedTest?.loadingBarViewState = .earlyLoad
        }
        
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "created_at > %i AND kind IN {6,7} AND pubkey IN %@", agoTimestamp, follows)
        bg().perform { [weak self] in
            guard let self else { return }
            guard let likesOrReposts = try? bg().fetch(fr) else {
                onComplete?()
                return
            }
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
        Task { @MainActor in
            speedTest?.loadingBarViewState = .secondFetching
        }
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
#if DEBUG
                L.og.debug("Gallery feed: fetchPostsFromRelays: empty ids")
#endif
                if (posts.count > 0) {
#if DEBUG
                    L.og.debug("Gallery feed: but we can render the duplicates")
#endif
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
            
#if DEBUG
            L.og.debug("Gallery feed: fetching \(ids.count) posts, skipped \(posts.count - ids.count) duplicates")
#endif
            
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
#if DEBUG
                        L.og.error("Gallery feed: Problem generating posts request")
#endif
                    }
                },
                processResponseCommand: { [weak self] taskId, relayMessage, _ in
                    guard let self else { return }
                    self.fetchPostsFromDB(onComplete)
                    self.backlog.clear()
#if DEBUG
                    L.og.debug("Gallery feed: ready to process relay response")
#endif
                },
                timeoutCommand: { [weak self] taskId in
                    guard let self else { return }
                    self.fetchPostsFromDB(onComplete)
                    self.backlog.clear()
#if DEBUG
                    L.og.debug("Gallery feed: timeout ")
#endif
                })

            self?.backlog.add(reqTask)
            reqTask.fetch()
        }
    }
    
    // STEP 4: FETCH RECEIVED POSTS FROM DB, SORT BY MOST LIKED/REPOSTED AND PUT ON SCREEN
    private func fetchPostsFromDB(_ onComplete: (() -> ())? = nil) {
        let ids = Set(self.posts.keys)
        guard !ids.isEmpty else {
#if DEBUG
            L.og.debug("fetchPostsFromDB: empty ids")
#endif
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
#if DEBUG
                if (likesOrReposts.count > 3) {
                    L.og.debug("🔝🔝 id:\(postId): \(likesOrReposts.count)")
                }
#endif
                if let event = Event.fetchEvent(id: postId, context: bg()) {
                    guard !blockedPubkeys.contains(event.pubkey) else { continue } // no blocked accounts
                    guard event.replyToId == nil && event.replyToRootId == nil else { continue } // no replies
                    guard event.created_at > self.agoTimestamp else { continue } // post itself should be within timeframe also
                    guard let content = event.content else { continue }
                    
                    var urls = getImgUrlsFromContent(content)
                    
                    if urls.isEmpty {
                        urls = event.fastTags.compactMap { imageUrlFromIMetaFastTag($0) }.filter { url in 
                            // Only if url matches imageRegex
                            let range = NSRange(url.absoluteString.startIndex..<url.absoluteString.endIndex, in: url.absoluteString)
                            return imageRegex.firstMatch(in: url.absoluteString, range: range) != nil
                        }
                    }

            
                    
                    guard !urls.isEmpty else { continue }
                    
                    for url in urls.prefix(Self.MAX_IMAGES_PER_POST) {
                        let iMeta: iMetaInfo? = findImeta(event.fastTags, url: url.absoluteString)
                        items.append(GalleryItem(url: url, pubkey: event.pubkey, eventId: event.id, dimensions: iMeta?.size, blurhash: iMeta?.blurHash))
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
    
    public func load(speedTest: NXSpeedTest) {
        self.speedTest = speedTest
        guard shouldReload else { return }
#if DEBUG
        L.og.debug("Gallery feed: load()")
#endif
        self.follows = Nostur.follows()
        self.state = .loading
        self.items = []
        
        self.speedTest?.start()
        self.fetchLikesAndRepostsFromRelays {
            Task { @MainActor in
                self.speedTest?.loadingBarViewState = .finalLoad
                if self.items.isEmpty {
#if DEBUG
                    L.og.debug("Gallery feed: timeout()")
#endif
                    self.timeout()
                }
            }
        }
    }
    
    // for after account change
    public func reload() {
        self.state = .loading
        self.lastFetch = nil
        self.posts = [PostID: RecommendedBy<Pubkey>]()
        self.backlog.clear()
        self.follows = Nostur.follows()
        self.items = []
        
        self.speedTest?.start()
        self.fetchLikesAndRepostsFromRelays {
            Task { @MainActor in
                self.speedTest?.loadingBarViewState = .finalLoad
                if self.items.isEmpty {
#if DEBUG
                    L.og.debug("Gallery feed: timeout()")
#endif
                    self.timeout()
                }
            }
        }
    }
    
    // pull to refresh
    public func refresh() async {
        // don't change .state on refresh, or rerender will cause the pull-to-refresh to be wonky
        self.lastFetch = nil
        self.posts = [PostID: RecommendedBy<Pubkey>]()
        self.backlog.clear()
        self.follows = Nostur.follows()
        
        self.speedTest?.start()
        await withCheckedContinuation { continuation in
            self.fetchLikesAndRepostsFromRelays {
                Task { @MainActor in
                    self.speedTest?.loadingBarViewState = .finalLoad
                    if self.items.isEmpty {
#if DEBUG
                        L.og.debug("Gallery feed: timeout()")
#endif
                        self.timeout()
                    }
                }
                continuation.resume()
            }
        }
    }
    
    public var shouldReload: Bool {
        // Should only refetch since last fetch, if last fetch is more than 10 mins ago
        guard let lastFetch else { return true }

        if (Date.now.timeIntervalSince1970 - lastFetch.timeIntervalSince1970) > 600 {
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


struct GalleryItem: Identifiable, Equatable, Hashable {
    
    func hash(into hasher: inout Hasher) {
        return hasher.combine(id)
    }
    
    let id: UUID
    let pubkey: String? // for blocklist filtering
    let url: URL

    let eventId: String? // need the id in main context
    var pfpPictureURL: URL?
    var dimensions: CGSize?
    var blurhash: String?
    var imageInfo: ImageInfo?
    var gifInfo: GifInfo?
        
    init(url: URL, pubkey: String? = nil, eventId: String? = nil, dimensions: CGSize? = nil, blurhash: String? = nil, imageInfo: ImageInfo? = nil, gifInfo: GifInfo? = nil) {
        self.url = url
        self.eventId = eventId
        self.id = UUID()
        self.pubkey = pubkey
        self.imageInfo = imageInfo
        self.gifInfo = gifInfo
        self.blurhash = blurhash
        self.dimensions = dimensions
        if let pubkey {
            self.pfpPictureURL = AccountsState.shared.loggedInAccount?.followingCache[pubkey]?.pfpURL
        }
    }
    
    var aspect: CGFloat? {
        if let dimensions {
            return dimensions.width / dimensions.height
        } else {
            return nil
        }
    }

    static func == (lhs: GalleryItem, rhs: GalleryItem) -> Bool {
        lhs.id == rhs.id
    }
}
