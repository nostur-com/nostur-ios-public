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
    private var posts:[PostID: LikedBy<Pubkey>]
    private var backlog:Backlog
    private var follows:Set<Pubkey>
    private var didLoad = false
    private static let POSTS_LIMIT = 100
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
                self.fetchPostsFromDB()
            }
            else {
                self.state = .loading
                lastFetch = nil // need to fetch further back, so remove lastFetch
                self.fetchLikesFromRelays()
            }
        }
    }
    
    var timeoutSeconds:Int { // 10 sec timeout for 1st 8hrs + 1 sec for every 4h after
        max(10, Int(ceil(Double(10 + ((ago-8)/4)))))
    }
    
    public func timeout() {
        self.state = .timeout
    }
    
    public init() {
        self.state = .initializing
        self.posts = [PostID: LikedBy<Pubkey>]()
        self.backlog = Backlog(timeout: 5.0, auto: true)
        self.follows = NosturState.shared.followingPublicKeys
        
        receiveNotification(.blockListUpdated)
            .sink { [weak self] notification in
                guard let self else { return }
                let blockedPubkeys = notification.object as! [String]
                self.items = self.items.filter { !blockedPubkeys.contains($0.pubkey)  }
            }
            .store(in: &self.subscriptions)
    }
    
    // STEP 1: FETCH LIKES FROM FOLLOWS FROM RELAYS
    private func fetchLikesFromRelays(_ onComplete: (() -> ())? = nil) {
        let reqTask = ReqTask(
            debounceTime: 0.5,
            subscriptionId: "GALLERY",
            reqCommand: { taskId in
                if let cm = NostrEssentials
                            .ClientMessage(type: .REQ,
                                           subscriptionId: taskId,
                                           filters: [
                                            Filters(
                                                authors: self.follows,
                                                kinds: Set([7]),
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
                }
            },
            processResponseCommand: { taskId, relayMessage in
                self.backlog.clear()
                self.fetchLikesFromDB(onComplete)

                L.og.info("Gallery feed: ready to process relay response")
            },
            timeoutCommand: { taskId in
                self.backlog.clear()
                self.fetchLikesFromDB(onComplete)
                L.og.info("Gallery feed: timeout ")
            })

        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    // STEP 2: FETCH RECEIVED LIKES FROM DB, SORT MOST LIKED POSTS (WE ONLY HAVE IDs HERE)
    private func fetchLikesFromDB(_ onComplete: (() -> ())? = nil) {
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "created_at > %i AND kind == 7 AND pubkey IN %@", agoTimestamp, follows)
        bg().perform {
            guard let likes = try? bg().fetch(fr) else { return }
            for like in likes {
                guard let reactionToId = like.reactionToId else { continue }
                if self.posts[reactionToId] != nil {
                    self.posts[reactionToId]!.insert(like.pubkey)
                }
                else {
                    self.posts[reactionToId] = LikedBy([like.pubkey])
                }
            }
            
            self.fetchPostsFromRelays()
        }
    }

    // STEP 3: FETCH MOST LIKED POSTS FROM RELAYS
    private func fetchPostsFromRelays(onComplete: (() -> ())? = nil) {
        let ids = Set(self.posts.keys)
        guard !ids.isEmpty else {
            L.og.debug("fetchPostsFromRelays: empty ids")
            return
        }
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
//                    self.lastFetch = Date.now
                }
                else {
                    L.og.error("Gallery feed: Problem generating posts request")
                }
            },
            processResponseCommand: { taskId, relayMessage in
                self.fetchPostsFromDB(onComplete)
                self.backlog.clear()
                L.og.info("Gallery feed: ready to process relay response")
            },
            timeoutCommand: { taskId in
                self.fetchPostsFromDB(onComplete)
                self.backlog.clear()
                L.og.info("Gallery feed: timeout ")
            })

        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    // STEP 4: FETCH RECEIVED POSTS FROM DB, SORT BY MOST LIKED AND PUT ON SCREEN
    private func fetchPostsFromDB(_ onComplete: (() -> ())? = nil) {
        let ids = Set(self.posts.keys)
        guard !ids.isEmpty else {
            L.og.debug("fetchPostsFromDB: empty ids")
            return
        }
        let blockedPubkeys = NosturState.shared.account?.blockedPubkeys_ ?? []
        bg().perform {
            let sortedByLikes = self.posts
                .sorted(by: { $0.value.count > $1.value.count })
            
            
            var items:[GalleryItem] = []
            for (postId, likes) in sortedByLikes {
                if (likes.count > 3) {
                    L.og.debug("🔝🔝 id:\(postId): \(likes.count)")
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
            
            DispatchQueue.main.async {
                onComplete?()
                self.items = items
                self.state = .ready
            }
        }
    }
    
    public func load() {
        guard shouldReload else { return }
        self.state = .loading
        self.items = []
        self.fetchLikesFromRelays()
    }
    
    // for after acocunt change
    public func reload() {
        self.state = .loading
        self.lastFetch = nil
        self.posts = [PostID: LikedBy<Pubkey>]()
        self.backlog.clear()
        self.follows = NosturState.shared.followingPublicKeys
        self.items = []
        self.fetchLikesFromRelays()
    }
    
    // pull to refresh
    public func refresh() async {
        self.state = .loading
        self.lastFetch = nil
        self.posts = [PostID: LikedBy<Pubkey>]()
        self.backlog.clear()
        self.follows = NosturState.shared.followingPublicKeys
        
        await withCheckedContinuation { continuation in
            self.fetchLikesFromRelays {
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
    let pubkey:String // for blocklist filtering
    let url:URL
    let event:Event // bg
    var pfpPictureURL:URL?
        
    init(url:URL, event:Event) {
        self.url = url
        self.event = event
        self.id = UUID()
        self.pubkey = event.pubkey
        self.pfpPictureURL = NosturState.shared.bgFollowingPFPs[event.pubkey]
    }

    static func == (lhs: GalleryItem, rhs: GalleryItem) -> Bool {
        lhs.id == rhs.id
    }
}
