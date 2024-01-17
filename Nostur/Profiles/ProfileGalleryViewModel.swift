//
//  ProfileGalleryViewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/09/2023.
//

import SwiftUI
import NostrEssentials
import CoreData

// Copy pasta from GalleryViewModel and adjusted for just a single profile
// No need to sort by likes, gather all media from a pubkey
class ProfileGalleryViewModel: ObservableObject {
    
    @Published var state: GalleryState
    private var backlog: Backlog
    private var pubkey: String
    private var didLoad = false
    private static let POSTS_LIMIT = 300
    private static let MAX_IMAGES_PER_POST = 10
    private var prefetchedIds = Set<String>()
        
    @Published var items: [GalleryItem] = [] {
        didSet {
            guard !items.isEmpty else { return }
            L.og.info("Gallery feed loaded \(self.items.count) items")
        }
    }
    
    private var lastFetch: Date?
    
    public func timeout() {
        self.state = .timeout
    }
    
    public init(_ pubkey: String) {
        self.pubkey = pubkey
        self.state = .initializing
        self.backlog = Backlog(timeout: 10.0, auto: true)
    }
    
    // STEP 1: FETCH LIKES FROM FOLLOWS FROM RELAYS
    private func fetchPostsFromRelays(_ onComplete: (() -> ())? = nil) {
        let reqTask = ReqTask(
            debounceTime: 0.5,
            subscriptionId: "PROFILEGALLERY",
            reqCommand: { [weak self] taskId in
                guard let self else { return }
                if let cm = NostrEssentials
                            .ClientMessage(type: .REQ,
                                           subscriptionId: taskId,
                                           filters: [
                                            Filters(
                                                authors: Set([self.pubkey]),
                                                kinds: Set([1]),
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
            processResponseCommand: { [weak self] taskId, relayMessage, _ in
                self?.backlog.clear()
                self?.fetchPostsFromDB(onComplete)

                L.og.info("Gallery feed: ready to process relay response")
            },
            timeoutCommand: { [weak self] taskId in
                self?.backlog.clear()
                self?.fetchPostsFromDB(onComplete)
                L.og.info("Gallery feed: timeout ")
            })

        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    // STEP 2: FETCH RECEIVED POSTS FROM DB
    private func fetchPostsFromDB(_ onComplete: (() -> ())? = nil) {

        bg().perform { [weak self] in
            guard let self else { return }
            let fr = Event.fetchRequest()
            fr.predicate = NSPredicate(format: "pubkey == %@ AND kind == 1", self.pubkey)
            fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            
            var items: [GalleryItem] = []
            guard let events = try? bg().fetch(fr) else { return }
            
            for event in events {
                guard let content = event.content else { continue }
                let urls = getImgUrlsFromContent(content)
                guard !urls.isEmpty else { continue }
                
                for url in urls.prefix(Self.MAX_IMAGES_PER_POST) {
                    items.append(GalleryItem(url: url, event: event))
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
        self.state = .loading
        self.items = []
        self.fetchPostsFromRelays()
    }
    
    // for after acocunt change
    public func reload() {
        self.state = .loading
        self.backlog.clear()
        self.items = []
        self.fetchPostsFromRelays()
    }
    
    // pull to refresh
    public func refresh() async {
        self.state = .loading
        self.backlog.clear()
        await withCheckedContinuation { [weak self] continuation in
            self?.fetchPostsFromRelays {
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
