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

    private static let MAX_IMAGES_PER_POST = 10
        
    @Published var items: [GalleryItem] = [] {
        didSet {
            guard !items.isEmpty else { return }
            L.og.info("Profile Gallery feed loaded \(self.items.count) items")
        }
    }
    
    public func timeout() {
        self.state = .timeout
    }
    
    public init(_ pubkey: String) {
        self.pubkey = pubkey
        self.state = .initializing
        self.backlog = Backlog(timeout: 13.0, auto: true)
    }
    
    // STEP 1: FETCH POSTS FROM SINGLE AUTHOR FROM RELAY
    private func fetchPostsFromRelays(_ onComplete: (() -> ())? = nil, limit: Int = 250) {
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
                                                kinds: Set([1,20]),
                                                limit: limit
                                            )
                                           ]
                            ).json() {
                    req(cm)
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
            fr.predicate = NSPredicate(format: "pubkey == %@ AND kind IN {1,20}", self.pubkey)
            fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            
            var items: [GalleryItem] = []
            guard let events = try? bg().fetch(fr) else { return }
            
            for event in events {
                guard let content = event.content else { continue }
                var urls = getImgUrlsFromContent(content)
                
                if urls.isEmpty {
                    urls = event.fastTags.compactMap { imageUrlFromIMetaFastTag($0) }
                }
                
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
    
    @MainActor
    public func load() {
        self.state = .loading
        self.items = []
        self.fetchPostsFromRelays()
    }
    
    // for after account change
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
    
    public enum GalleryState {
        case initializing
        case loading
        case ready
        case timeout
    }
    
    
    private var didFetchMore: Bool = false
    
    @MainActor
    public func fetchMoreIfNeeded(_ index: Int) {
        // fetch more if: index > 12 (next page)
        // or not enough images and last appeared: index <= 12 && index == items.count
        guard (index > 12) || (index <= 12 && index == items.count), !didFetchMore else { return }
        didFetchMore = true
        self.fetchPostsFromRelays(limit: 999)
    }
}
