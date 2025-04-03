//
//  DiscoverListsViewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/04/2025.
//

import SwiftUI
import NostrEssentials
import Combine

// Discover feed
// Fetch all likes and reposts from your follows in the last 24/12/8/4/2 hours
// Sort posts by unique (pubkey) likes/reposts
// Exclude people you already follow
class DiscoverListsViewModel: ObservableObject {
    private var speedTest: NXSpeedTest?
    @Published var state: FeedState
    
    private var backlog: Backlog
    private var follows: Set<Pubkey>
    private var didLoad = false
    private static let POSTS_LIMIT = 75
    private var subscriptions = Set<AnyCancellable>()
    private var prefetchedIds = Set<String>()
    
    @Published var discoverLists: [NRPost] = [] {
        didSet {
            guard !discoverLists.isEmpty else { return }
            L.og.info("Discover lists feed: loaded \(self.discoverLists.count) posts")
        }
    }

    public func timeout() {
        speedTest?.loadingBarViewState = .timeout
        self.state = .timeout
    }
    
    public init() {
        self.state = .initializing

        self.backlog = Backlog(timeout: 5.0, auto: true)
        self.follows = Nostur.follows()
        
        receiveNotification(.blockListUpdated)
            .sink { [weak self] notification in
                guard let self else { return }
                let blockedPubkeys = notification.object as! Set<String>
                self.discoverLists = self.discoverLists.filter { !blockedPubkeys.contains($0.pubkey)  }
            }
            .store(in: &self.subscriptions)
    }
    
    // STEP 1: FETCH LISTS FROM FOLLOWS FROM RELAYS
    private func fetchListsFromRelays(_ onComplete: (() -> ())? = nil) {
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
            subscriptionId: "DISCOVERLISTS",
            reqCommand: { [weak self] taskId in
                guard let self else { return }
                if let cm = NostrEssentials
                            .ClientMessage(type: .REQ,
                                           subscriptionId: taskId,
                                           filters: [
                                            Filters(
                                                authors: self.follows,
                                                kinds: [30000],
                                                limit: 9999
                                            )
                                           ]
                            ).json() {
                    req(cm) // TODO: Make outbox req
                }
                else {
                    L.og.error("Discover lists feed: Problem generating request")
                }
            },
            processResponseCommand: { [weak self] taskId, relayMessage, _ in
                guard let self else { return }
                self.backlog.clear()
                self.fetchListsFromDB(onComplete)

                L.og.info("Discover lists feed: ready to process relay response")
            },
            timeoutCommand: { [weak self] taskId in
                guard let self else { return }
                self.backlog.clear()
                self.fetchListsFromDB(onComplete)
                L.og.info("Discover lists feed: timeout ")
            })

        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    // STEP 2: FETCH RECEIVED LISTS FROM DB
    private func fetchListsFromDB(_ onComplete: (() -> ())? = nil) {
        let yearAgo = Int(Date().timeIntervalSince1970 - 31536000)
        let garbage: Set<String> = ["mute", "allowlist"]
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind = 30000 AND created_at > %i AND pubkey IN %@ AND dTag != nil AND flags != \"is_update\" AND NOT dTag IN %@", yearAgo, follows, garbage)
        bg().perform { [weak self] in
            guard let self else { return }
            guard let lists = try? bg().fetch(fr) else {
                DispatchQueue.main.async { [weak self] in
                    onComplete?()
                    self?.state = .ready
                }
                return
            }
            
            let listsWithLessGarbage = lists.filter { list in
                list.fastPs.count > 2
            }
            
            guard listsWithLessGarbage.count > 0 else {
                DispatchQueue.main.async { [weak self] in
                    onComplete?()
                    self?.state = .ready
                }
                return
            }
            
            let nrLists: [NRPost] = listsWithLessGarbage
                .sorted { $0.fastPs.count > $1.fastPs.count }
                .prefix(Self.POSTS_LIMIT)
                .map { NRPost(event: $0) }
            
            DispatchQueue.main.async { [weak self] in
                onComplete?()
                self?.discoverLists = nrLists
                self?.state = .ready
            }
        }
    }
    
    public func load(speedTest: NXSpeedTest) {
        self.speedTest = speedTest
        L.og.info("Discover lists feed: load()")
        self.follows = Nostur.follows()
        self.state = .loading
        self.discoverLists = []
        
        self.speedTest?.start()
        self.fetchListsFromRelays {
            Task { @MainActor in
                self.speedTest?.loadingBarViewState = .finalLoad
            }
        }
    }
    
    // for after account change
    public func reload() {
        self.state = .loading
        self.discoverLists = []
        self.backlog.clear()
        self.follows = Nostur.follows()
        self.discoverLists = []
        
        self.speedTest?.start()
        self.fetchListsFromRelays {
            Task { @MainActor in
                self.speedTest?.loadingBarViewState = .finalLoad
            }
        }
    }
    
    // pull to refresh
    public func refresh() async {
        self.discoverLists = []
        self.backlog.clear()
        self.follows = Nostur.follows()
        
        self.speedTest?.start()
        await withCheckedContinuation { continuation in
            self.fetchListsFromRelays {
                Task { @MainActor in
                    self.speedTest?.loadingBarViewState = .finalLoad
                }
                continuation.resume()
            }
        }
    }
    
    public enum FeedState {
        case initializing
        case loading
        case ready
        case timeout
    }
}
