//
//  HotViewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/09/2023.
//

import SwiftUI
import NostrEssentials
import Combine

typealias PostID = String
typealias LikedBy = Set
typealias Pubkey = String


// Popular/Hot feed
// Fetch all likes from your follows in the last 24/12/8/4/2 hours
// Sort posts by unique (pubkey) likes
class HotViewModel: ObservableObject {
    
    private var posts:[PostID: LikedBy<Pubkey>]
    private var backlog:Backlog
    private var follows:Set<Pubkey>
    private var didLoad = false
    private static let POSTS_LIMIT = 250
    private var subscriptions = Set<AnyCancellable>()
    
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
    
    @Published var hotPosts:[NRPost] = [] {
        didSet {
            guard !hotPosts.isEmpty else { return }
            L.og.info("Hot feed loaded \(self.hotPosts.count) posts")
        }
    }
    
    @AppStorage("feed_hot_ago") var ago:Int = 12 {
        didSet {
            logAction("Hot feed time frame changed to \(self.ago)h")
            backlog.timeout = max(Double(ago / 4), 5.0)
            if ago < oldValue {
                self.hotPosts = []
                self.fetchFromDB()
            }
            else {
                self.hotPosts = []
                lastFetch = nil // need to fetch further back, so remove lastFetch
                self.fetchFromRelays()
            }
        }
    }
    
    public init() {
        self.posts = [PostID: LikedBy<Pubkey>]()
        self.backlog = Backlog(timeout: 5.0, auto: true)
        self.follows = NosturState.shared.followingPublicKeys
        
        receiveNotification(.blockListUpdated)
            .sink { [weak self] notification in
                guard let self else { return }
                let blockedPubkeys = notification.object as! [String]
                self.hotPosts = self.hotPosts.filter { !blockedPubkeys.contains($0.pubkey)  }
            }
            .store(in: &self.subscriptions)
    }

    private func fetchFromDB() {
        let blockedPubkeys = NosturState.shared.account?.blockedPubkeys_ ?? []
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "created_at > %i AND kind == 7 AND pubkey IN %@", agoTimestamp, follows)
        bg().perform {
            if let likes = try? bg().fetch(fr) {
                for like in likes {
                    guard let reactionToId = like.reactionToId else { continue }
                    if self.posts[reactionToId] != nil {
                        self.posts[reactionToId]!.insert(like.pubkey)
                    }
                    else {
                        self.posts[reactionToId] = LikedBy([like.pubkey])
                    }
                }
                
                
                let sortedByLikes = self.posts
                    .sorted(by: { $0.value.count > $1.value.count })
                    .prefix(Self.POSTS_LIMIT)
                
                var nrPosts:[NRPost] = []
                for (postId, likes) in sortedByLikes {
                    if (likes.count > 3) {
                        L.og.debug("🔝🔝 id:\(postId): \(likes.count)")
                    }
                    if let event = try? Event.fetchEvent(id: postId, context: bg()) {
                        guard !blockedPubkeys.contains(event.pubkey) else { continue } // no blocked accoutns
                        guard event.replyToId == nil && event.replyToRootId == nil else { continue } // no replies
                        guard event.created_at > self.agoTimestamp else { continue } // post itself should be within timeframe also
                        
                        nrPosts.append(NRPost(event: event, withParents: true))
                    }
                }
                
                DispatchQueue.main.async {
                    self.hotPosts = nrPosts
                }
            }
        }
    }
    
    private func fetchFromRelays() {
        let reqTask = ReqTask(
            debounceTime: 0.5,
            subscriptionId: "HOT",
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
                    L.og.error("Hot feed: Problem generating request")
                }
            },
            processResponseCommand: { taskId, relayMessage in
                self.fetchFromDB()
                self.backlog.clear()
                L.og.info("Hot feed: ready to process relay response")
            },
            timeoutCommand: { taskId in
                self.fetchFromDB()
                self.backlog.clear()
                L.og.info("Hot feed: timeout ")
            })

        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    public func load() {
        guard shouldReload else { return }
        self.hotPosts = []
        self.fetchFromRelays()
    }
    
    // for after acocunt change
    public func reload() {
        self.lastFetch = nil
        self.posts = [PostID: LikedBy<Pubkey>]()
        self.backlog.clear()
        self.follows = NosturState.shared.followingPublicKeys
        self.hotPosts = []
        self.fetchFromRelays()
    }
    
    public var shouldReload: Bool {
        // Should only refetch since last fetch, if last fetch is more than 10 mins ago
        guard let lastFetch else { return true }

        if (Date.now.timeIntervalSince1970 - lastFetch.timeIntervalSince1970) > 60 * 10 {
            return true
        }
        return false
    }
}
