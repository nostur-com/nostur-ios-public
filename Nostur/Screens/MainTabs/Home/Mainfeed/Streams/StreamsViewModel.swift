//
//  StreamsViewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 23/01/2026.
//

import SwiftUI
import NostrEssentials
import Combine

// Copy paste from DiscoverLists + LiveEventsModel
class StreamsViewModel: ObservableObject {
    private var speedTest: NXSpeedTest?
    @Published var state: FeedState
    
    private var backlog: Backlog
    private var follows: Set<Pubkey>
    private var didLoad = false
    private static let POSTS_LIMIT = 75
    private var subscriptions = Set<AnyCancellable>()
    private var prefetchedIds = Set<String>()
    
    @Published var streams: [NRLiveEvent] = [] {
        didSet {
            guard !streams.isEmpty else { return }
#if DEBUG
            L.og.debug("Streams feed: loaded \(self.streams.count) posts")
#endif
        }
    }

    public func timeout() {
        speedTest?.loadingBarViewState = .timeout
        self.state = .timeout
    }
    
    public init() {
        self.state = .initializing
        self.backlog = Backlog(timeout: 5.0, auto: true, backlogDebugName: "StreamsViewModel")
        self.follows = resolveFollows()
        
        receiveNotification(.blockListUpdated)
            .sink { [weak self] notification in
                guard let self else { return }
                let blockedPubkeys = notification.object as! Set<String>
                self.streams = self.streams.filter { !blockedPubkeys.contains($0.pubkey)  }
            }
            .store(in: &self.subscriptions)
    }
    
    // STEP 1: FETCH STREAMS FROM FOLLOWS FROM RELAYS
    private func fetchStreamsFromRelays(_ onComplete: (() -> ())? = nil) {
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
            timeout: 3.0,
            subscriptionId: "STREAMS",
            reqCommand: { [weak self] taskId in
                guard let self else { return }
                
                let follows = self.follows.count <= 1950 ? self.follows : Set(self.follows.shuffled().prefix(1950))
                
                nxReq(Filters(
                    authors: follows,
                    kinds: Set([30311]),
                    limit: 500
                ), subscriptionId: taskId)
            },
            processResponseCommand: { [weak self] taskId, relayMessage, _ in
                self?.fetchStreamsFromDB(onComplete)
#if DEBUG
                L.og.debug("Streams feed: ready to process relay response")
#endif
            },
            timeoutCommand: { [weak self] taskId in
                self?.fetchStreamsFromDB(onComplete)
#if DEBUG
                L.og.debug("Streams feed: timeout ")
#endif
            })

        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    // STEP 2: FETCH RECEIVED StREAMS FROM DB
    private func fetchStreamsFromDB(_ onComplete: (() -> ())? = nil) {
        guard let accountPubkey = AccountsState.shared.loggedInAccount?.pubkey else {
            DispatchQueue.main.async { [weak self] in
                self?.state = .ready
                onComplete?()
            }
            return
        }
        self.follows = resolveFollows()
        
        let agoTimestamp: Int = 0 // Int(Date().timeIntervalSince1970 - (14400)) // Only with recent 4 hours
        let blockedPubkeys = blocks()
        let followsAndMe: Set<String> = self.follows.union(Set([accountPubkey]))
        
        let fr2 = Event.fetchRequest()
        fr2.predicate = NSPredicate(format: "(created_at > %i OR pubkey == %@) AND kind = 30311 AND mostRecentId = nil AND NOT pubkey IN %@", agoTimestamp, accountPubkey, blockedPubkeys)
        
        
        bg().perform { [weak self] in
            guard let self else { return }
            let streams = ((try? bg().fetch(fr2)) ?? [])
            
            guard !streams.isEmpty else {
                DispatchQueue.main.async { [weak self] in
                    self?.state = .ready
                    onComplete?()
                }
                return
            }          
            
            let nrLiveEvents: [NRLiveEvent] = streams
                .filter {
                    if $0.isLive() { return true } // IS LIVE
                    if $0.isPlannedNotInPast() { return true } // OR IS PLANNED BUT NOT TOO FAR IN THE PAST                    
                    return false
                }
                
                .filter { hasSpeakerOrHostInFollows($0, follows: followsAndMe) || (AccountsState.shared.bgAccountPubkeys.contains($0.pubkey)) }
                .sorted(by: { $0.created_at > $1.created_at })
                .uniqued(on: { $0.aTag })
                .prefix(Self.POSTS_LIMIT)
                .map { NRLiveEvent(event: $0) }
                .filter { !blockedPubkeys.contains($0.hostPubkey) } // also catch "host" in p-tags blocked
            
            guard !nrLiveEvents.isEmpty else {
                DispatchQueue.main.async { [weak self] in
                    self?.state = .ready
                    onComplete?()
                }
                return
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.streams = nrLiveEvents
                self?.state = .ready
                onComplete?()
            }
        }
    }
    
    public func load(speedTest: NXSpeedTest) {
        guard !didLoad else { return }
        self.didLoad = true
        self.speedTest = speedTest
#if DEBUG
        L.og.debug("Streams feed: load()")
#endif
        self.follows = resolveFollows()
        self.state = .loading
        self.streams = []
        
        self.speedTest?.start()
        self.fetchStreamsFromRelays {
            Task { @MainActor in
                self.speedTest?.loadingBarViewState = .finalLoad
                if self.streams.isEmpty {
#if DEBUG
                    L.og.debug("Streams feed: timeout()")
#endif
                    self.timeout()
                }
            }
        }
    }
    
    // for after account change
    public func reload() {
        self.state = .loading
        self.streams = []
        self.backlog.clear()
        self.follows = resolveFollows()
        
        self.speedTest?.start()
        self.fetchStreamsFromRelays {
            Task { @MainActor in
                self.speedTest?.loadingBarViewState = .finalLoad
                if self.streams.isEmpty {
#if DEBUG
                    L.og.debug("Streams feed: timeout()")
#endif
                    self.timeout()
                }
            }
        }
    }
    
    // pull to refresh
    public func refresh() async {
        self.backlog.clear()
        
        Task { @MainActor in
            self.streams = []
            self.follows = resolveFollows()
            
            await withCheckedContinuation { continuation in
                self.fetchStreamsFromRelays {
                    Task { @MainActor in
                        self.speedTest?.loadingBarViewState = .finalLoad
                        if self.streams.isEmpty {
    #if DEBUG
                            L.og.debug("Streams feed: timeout()")
    #endif
                            self.timeout()
                        }
                    }
                    continuation.resume()
                }
            }
        }
        
        self.speedTest?.start()
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
