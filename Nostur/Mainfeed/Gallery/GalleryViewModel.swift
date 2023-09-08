//
//  GalleryViewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/09/2023.
//

import SwiftUI
import NostrEssentials
import CoreData

// Try out fetch from all follows:
// window: 1 hr (until)

// fetch since: 1 hrs ago (until empty)
// no full screen of media after 5 sec? 3 * 7 = 21 items
// since: 2hrs ago (until 1hr ago)

// no full screen of media after 2 sec? 3 * 7 = 21 items
// since: 3hrs ago (until 2hr ago)

// no full screen of media after 2 sec? 3 * 7 = 21 items
// since: 4hrs ago (until 3hr ago)

// no full screen of media after 2 sec? 3 * 7 = 21 items
// since: 5hrs ago (until 4hr ago)

class GalleryViewModel: ObservableObject {
    
    private var events:[Event]
    private var backlog:Backlog
    private var didLoad = false
    private static let ITEMS_LIMIT = 3 * 6 * 20
    private static let SPAM_LIMIT = 5
        
    @Published var items:[GalleryItem] = [] {
        didSet {
            guard !items.isEmpty else { return }
            L.og.info("Gallery feed loaded \(self.items.count) items")
        }
    }
    
    public init() {
        self.events = []
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

    private func fetchFromDB() {
        let blockedPubkeys = NosturState.shared.account?.blockedPubkeys_ ?? []
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "created_at > %i AND kind == 1 AND pubkey IN %@ AND NOT pubkey IN", agoTimestamp, follows, blockedPubkeys)
        // TODO: do 1063?
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        fr.fetchLimit = 9999
        bg().perform {
            
            let items:[GalleryItem] = []
            if let events = try? bg().fetch(fr) {
                for event in events {
                    guard let content = event.content else { continue }
                    
                    let urls = contentArray.flatMap { getImgUrlsFromContent($0) }
                    for url in urls.prefix(SPAM_LIMIT) {
                        items.append(GalleryItem(url: url, event: event))
                    }
                }

                DispatchQueue.main.async {
                    self.items = items
                }
            }
        }
    }
    
    private func fetchFromRelays() {
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
                                                kinds: Set([1]),
                                                since: self.agoFetchTimestamp,
                                                limit: 1000
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
    
    private var shouldReload: Bool {
        // Should only refetch since last fetch, if last fetch is more than 10 mins ago
        guard let lastFetch else { return true }

        if (Date.now.timeIntervalSince1970 - lastFetch.timeIntervalSince1970) > 60 * 10 {
            return true
        }
        return false
    }
}


struct GalleryItem: Identifiable, Hashable, Equatable {

    let id:String
    let pubkey:String // for blocklist filtering
    let url:URL
    let event:Event // bg
        
    init(url:URL, event:Event) {
        self.url = url
        self.event = event
        self.id = String(format: "%s%s", event.id, url.absoluteString)
        self.pubkey = event.pubkey
    }

    static func == (lhs: NRPost, rhs: NRPost) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
