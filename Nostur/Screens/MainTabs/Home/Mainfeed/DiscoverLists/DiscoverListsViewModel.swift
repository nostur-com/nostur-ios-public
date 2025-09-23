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
#if DEBUG
            L.og.debug("Discover lists feed: loaded \(self.discoverLists.count) posts")
#endif
        }
    }

    public func timeout() {
        speedTest?.loadingBarViewState = .timeout
        self.state = .timeout
    }
    
    public init() {
        self.state = .initializing

        self.backlog = Backlog(timeout: 5.0, auto: true, backlogDebugName: "DiscoverListsViewModel")
        
        self.follows = resolveFollows()
        
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
                
                let follows = self.follows.count <= 2000 ? self.follows : Set(self.follows.shuffled().prefix(2000))
                
                if let cm = NostrEssentials
                            .ClientMessage(type: .REQ,
                                           subscriptionId: taskId,
                                           filters: [
                                            Filters(
                                                authors: follows,
                                                kinds: [30000,39089],
                                                limit: 9999
                                            )
                                           ]
                            ).json() {
                    req(cm) // TODO: Make outbox req
                }
                else {
#if DEBUG
                    L.og.error("Discover lists feed: Problem generating request")
#endif
                }
            },
            processResponseCommand: { [weak self] taskId, relayMessage, _ in
                guard let self else { return }
                self.backlog.clear()
                self.fetchListsFromDB(onComplete)
#if DEBUG
                L.og.debug("Discover lists feed: ready to process relay response")
#endif
            },
            timeoutCommand: { [weak self] taskId in
                guard let self else { return }
                self.backlog.clear()
                self.fetchListsFromDB(onComplete)
#if DEBUG
                L.og.debug("Discover lists feed: timeout ")
#endif
            })

        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    // STEP 2: FETCH RECEIVED LISTS FROM DB
    private func fetchListsFromDB(_ onComplete: (() -> ())? = nil) {
        let yearAgo = Int(Date().timeIntervalSince1970 - 31536000)
        let garbage: Set<String> = ["mute", "allowlist", "mutelists"]
        
        // Old kind 30000, needs some cleaning and filtering
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "kind = 30000 AND created_at > %i AND pubkey IN %@ AND dTag != nil AND mostRecentId == nil AND content == \"\" AND NOT dTag IN %@", yearAgo, follows, garbage)
        
        // New 39089 follow pack
        let fr2 = Event.fetchRequest()
        fr2.predicate = NSPredicate(format: "kind = 39089 AND pubkey IN %@ AND dTag != nil AND mostRecentId == nil AND content == \"\"", follows)
        
        
        bg().perform { [weak self] in
            guard let self else { return }
            
            let followSets = (try? bg().fetch(fr)) ?? []
            let followPacks = ((try? bg().fetch(fr2)) ?? [])
                .filter { !$0.fastPs.isEmpty }
            
            guard !followSets.isEmpty || !followPacks.isEmpty  else {
                DispatchQueue.main.async { [weak self] in
                    onComplete?()
                    self?.state = .ready
                }
                return
            }
            
            // Only followSets with between 2 and 500 pubkeys
            let followSetsWithLessGarbage = followSets.filter { list in
                list.fastPs.count > 2 && list.fastPs.count <= 500 && noGarbageDtag(list.dTag)
            }
            
            // If there are too many lists, hide lists that have 5 or more pubkeys that we already follow
            let followSetssWithoutAlreadyKnown = if followSetsWithLessGarbage.count > 75 {
                followSetsWithLessGarbage.filter { list in
                    Set(list.fastPs.map { $0.1 }).intersection(self.follows).count < 5
                }
            }
            else {
                followSetsWithLessGarbage
            }
            
            guard followSetssWithoutAlreadyKnown.count > 0 || !followPacks.isEmpty else {
                DispatchQueue.main.async { [weak self] in
                    onComplete?()
                    self?.state = .ready
                }
                return
            }
            
            let nrLists: [NRPost] = (followPacks + followSetssWithoutAlreadyKnown)
                .sorted { $0.fastPs.count > $1.fastPs.count }
                .sorted { $0.kind == 39089 && $1.kind != 39089 }
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
        guard !didLoad else { return }
        self.didLoad = true
        self.speedTest = speedTest
#if DEBUG
        L.og.debug("Discover lists feed: load()")
#endif
        self.follows = resolveFollows()
        self.state = .loading
        self.discoverLists = []
        
        self.speedTest?.start()
        self.fetchListsFromRelays {
            Task { @MainActor in
                self.speedTest?.loadingBarViewState = .finalLoad
                if self.discoverLists.isEmpty {
#if DEBUG
                    L.og.debug("Discover lists feed: timeout()")
#endif
                    self.timeout()
                }
            }
        }
    }
    
    // for after account change
    public func reload() {
        self.state = .loading
        self.discoverLists = []
        self.backlog.clear()
        self.follows = resolveFollows()
        self.discoverLists = []
        
        self.speedTest?.start()
        self.fetchListsFromRelays {
            Task { @MainActor in
                self.speedTest?.loadingBarViewState = .finalLoad
                if self.discoverLists.isEmpty {
#if DEBUG
                    L.og.debug("Discover lists feed: timeout()")
#endif
                    self.timeout()
                }
            }
        }
    }
    
    // pull to refresh
    public func refresh() async {
        Task { @MainActor in
            self.discoverLists = []
        }
        self.backlog.clear()
        self.follows = resolveFollows()
        
        self.speedTest?.start()
        await withCheckedContinuation { continuation in
            self.fetchListsFromRelays {
                Task { @MainActor in
                    self.speedTest?.loadingBarViewState = .finalLoad
                    if self.discoverLists.isEmpty {
#if DEBUG
                        L.og.debug("Discover lists feed: timeout()")
#endif
                        self.timeout()
                    }
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


fileprivate func resolveFollows() -> Set<String> {
    let accountFollows: Set<String> = Nostur.follows()

    // Use guest account follows if we don't have enough to discover lists
    return if accountFollows.count < 20, let guestAccount = try? CloudAccount.fetchAccount(publicKey: GUEST_ACCOUNT_PUBKEY, context: viewContext()) {
        (guestAccount.getFollowingPublicKeys(includeBlocked: true).count > 10) ? guestAccount.getFollowingPublicKeys(includeBlocked: true) : GUEST_FOLLOWS_FALLBACK
    } else {
        accountFollows.count > 20 ? accountFollows : GUEST_FOLLOWS_FALLBACK
    }
}
