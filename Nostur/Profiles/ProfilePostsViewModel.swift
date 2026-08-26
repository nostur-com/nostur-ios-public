//
//  ProfilePostsViewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/09/2023.
//

import SwiftUI
@preconcurrency import NostrEssentials
import CoreData
import Combine

let PROFILE_KINDS = Set([1,1222,5,6,20,9802,34235])
let PROFILE_KINDS_REPLIES = Set([1,1111,1244,5])
let ARTICLE_KINDS = Set([30023])
let LIST_KINDS = Set([30000,39089])

// For profile view, try to load first 10 posts as fast as possible
// Then reload remaining later
struct ProfilePostsLoadingPolicy {
    static let firstPaintCount = 3
    static let firstPaintLimit = 10

    enum TerminalDecision: Equatable {
        case revealImportedPosts
        case readyEmpty
        case timeout
    }

    static func shouldReveal(postCount: Int, force: Bool) -> Bool {
        force || postCount >= firstPaintCount
    }

    static func terminalDecision(timedOut: Bool, receivedImport: Bool) -> TerminalDecision {
        if receivedImport { return .revealImportedPosts }
        return timedOut ? .timeout : .readyEmpty
    }

    static func paginationCandidateIds(
        validatedEventIds: Set<String>,
        visibleEventIds: Set<String>
    ) -> Set<String> {
        validatedEventIds.subtracting(visibleEventIds)
    }

    static func shouldIncludeLocalCache(pageCompleted: Bool) -> Bool {
        pageCompleted
    }
}

class ProfilePostsViewModel: ObservableObject {
    enum ProfilePostsType {
        case posts
        case replies
        case articles
        case lists
    }
    
    @Published var state: State
    public var type: ProfilePostsType
    private var pubkey: String
    private var didLoad = false
//    private static let POSTS_LIMIT = 300
    private var subscriptions = Set<AnyCancellable>()
    private var prefetchedIds = Set<String>()
    private var didPrefetchOlderPosts = false
    private var profileRequestTracker: BoundedRelayRequestCompletionTracker?
    private var profileImportSubscription: AnyCancellable?
    private var activeProfileSubscriptionId: String?
    private var importRefreshTask: Task<Void, Never>?
    private var connectionWaitTask: Task<Void, Never>?
    private var activeRequestCompletion: (() -> Void)?
    private var requestGeneration: UInt64 = 0
    private var receivedImportForActiveRequest = false
    private var returnedEventIds = Set<String>()
    private var paginationTracker: BoundedRelayRequestCompletionTracker?
    private var paginationImportSubscription: AnyCancellable?
    private var paginationRefreshTask: Task<Void, Never>?
    private var activePaginationSubscriptionId: String?
        
    @Published var posts: [NRPost] = [] {
        didSet {
            guard !posts.isEmpty else { return }
            if state != .ready {
                self.state = .ready
            }
#if DEBUG
            L.og.debug("Profile posts feed loaded \(self.posts.count) items, pubkey: \(self.pubkey)")
#endif
        }
    }
    
    private var lastFetch: Date?
    
    public init(_ pubkey: String, type: ProfilePostsType) {
        self.type = type
        self.pubkey = pubkey
        self.state = .initializing
        
        guard self.type != .articles else { return }
        
        receiveNotification(.newPostSaved)
            .sink { [weak self] notification in
                bg().perform {
                    let event = notification.object as! Event
                    guard event.pubkey == pubkey else { return }
                    guard (event.replyToId != nil && self?.type == .replies) || (event.replyToId == nil && self?.type == .posts) else { return }
                    
                    EventRelationsQueue.shared.addAwaitingEvent(event, debugInfo: "ProfilePostsViewModel.newPostSaved")
                    let nrPost = NRPost(event: event, cancellationId: event.cancellationId)
                    DispatchQueue.main.async {
                        withAnimation {
                            self?.posts.insert(nrPost, at: 0)
                        }
                }
            }
        }
        .store(in: &subscriptions)
        
        receiveNotification(.unpublishedNRPost).sink { [weak self] notification in
            let nrPost = notification.object as! NRPost
            
            // Remove from view
            DispatchQueue.main.async {
                withAnimation {
                    self?.posts.removeAll(where: { $0.id == nrPost.id })
                }
            }
        }
        .store(in: &subscriptions)
        
    }
    
    // STEP 1: FETCH POSTS FROM RELAYS
    // Profile navigation is interactive. Prefixing this request with `prio-`
    // lets its events bypass feed backfill in the importer. Completion is based
    // on relay terminals plus an importer settle period, not the first event.
    @MainActor
    private func fetchPostsFromRelays(_ onComplete: (() -> ())? = nil) {
        cancelActiveRequest()
        activeRequestCompletion = onComplete
        receivedImportForActiveRequest = false
        returnedEventIds = []
        let generation = requestGeneration

        let kinds = switch self.type {
        case .posts:
            PROFILE_KINDS
        case .replies:
            PROFILE_KINDS_REPLIES
        case .articles:
            ARTICLE_KINDS
        case .lists:
            LIST_KINDS
        }

        let subscriptionId = "prio-PROFILEPOSTS-" + UUID().uuidString
        let clientMessage = NostrEssentials.ClientMessage(
            type: .REQ,
            subscriptionId: subscriptionId,
            filters: [
                Filters(
                    authors: Set([self.pubkey]),
                    kinds: kinds,
                    limit: 25
                )
            ]
        )
        activeProfileSubscriptionId = subscriptionId
        lastFetch = Date.now
        profileImportSubscription = Importer.shared.importedPrioMessagesFromSubscriptionId
            .filter { $0.subscriptionId == subscriptionId }
            // The publisher sends on the event's background context. Snapshot
            // the value here; never carry its NSManagedObject onto MainActor.
            .map { $0.event.id }
            .receive(on: RunLoop.main)
            .sink { [weak self] eventId in
                guard let self, self.requestGeneration == generation else { return }
                self.returnedEventIds.insert(eventId)
                self.receivedImportForActiveRequest = true
                self.scheduleImportRefresh(generation: generation)
            }

        // A profile can be opened while the app's read relays are still
        // reconnecting. Kick connection setup now, then start the response
        // deadline only after at least one planned target is ready.
        ConnectionPool.shared.connectAll()

        let installRequest: @MainActor @Sendable (ConnectionPool.RequestTargetSnapshot) -> Void = { [weak self] targets in
            guard let self,
                  self.requestGeneration == generation,
                  self.activeProfileSubscriptionId == subscriptionId
            else { return }

            self.profileRequestTracker = BoundedRelayRequestCompletionTracker(
                subscriptionId: subscriptionId,
                targets: targets,
                onImport: {},
                onCompletion: { [weak self] outcome in
                    guard let self, self.requestGeneration == generation else { return }
                    self.finishRelayRequest(
                        outcome: outcome,
                        subscriptionId: subscriptionId,
                        generation: generation
                    )
                }
            )
            self.profileRequestTracker?.start()
            outboxReq(clientMessage, activeSubscriptionId: subscriptionId)
        }

        // requestTargetSnapshot serializes against connection-pool bookkeeping.
        // Resolve it away from MainActor so opening a profile always returns
        // immediately, even while relay connections are being reconfigured.
        DispatchQueue.global(qos: .userInitiated).async {
            let targets = ConnectionPool.shared.requestTargetSnapshot(
                for: clientMessage,
                includeOutbox: true
            )
            if !targets.connectedIds.isEmpty || targets.relayIds.isEmpty {
                Task { @MainActor in
                    installRequest(targets)
                }
                return
            }

            let waitTask = Task.detached(priority: .userInitiated) {
                _ = await ConnectionPool.shared.waitForAnyConnectedRelay(
                    in: targets.relayIds
                )
                guard !Task.isCancelled else { return }
                let refreshedTargets = ConnectionPool.shared.requestTargetSnapshot(
                    for: clientMessage,
                    includeOutbox: true
                )
                await installRequest(refreshedTargets)
            }
            Task { @MainActor [weak self] in
                guard let self, self.requestGeneration == generation else {
                    waitTask.cancel()
                    return
                }
                self.connectionWaitTask = waitTask
            }
        }
    }
    
    // STEP 2: FETCH RECEIVED POSTS FROM DB
    private func fetchPostsFromDB(
        generation: UInt64,
        forceReveal: Bool,
        onComplete: (() -> ())? = nil
    ) {
        let validatedEventIds = returnedEventIds
        let cancellationIds: [String:UUID] = Dictionary(uniqueKeysWithValues: Unpublisher.shared.queue.map { ($0.nEvent.id, $0.cancellationId) })
        
        bg().perform { [weak self] in
            guard let self else { return }
            var postsForStats: [NRPost] = []
            
            // Fetch lists
            if self.type == .lists {
                let garbage: Set<String> = ["mute", "allowlist", "mutelists"]
                
                // Old kind 30000, needs some cleaning and filtering
                let fr = Event.fetchRequest()
                fr.predicate = NSPredicate(format: "id IN %@ AND kind = 30000 AND pubkey == %@ AND mostRecentId == nil AND content == \"\" AND NOT dTag IN %@", validatedEventIds, self.pubkey, garbage)
                
                // New 39089 follow pack
                let fr2 = Event.fetchRequest()
                fr2.predicate = NSPredicate(format: "id IN %@ AND kind = 39089 AND pubkey == %@ AND dTag != nil AND mostRecentId == nil", validatedEventIds, self.pubkey)
                
                let followSets = (try? bg().fetch(fr)) ?? []
                let followPacks = ((try? bg().fetch(fr2)) ?? [])
                    .filter { !$0.fastPs.isEmpty }
                
                // Only followSets with between 2 and 500 pubkeys
                let followSetsWithLessGarbage = followSets.filter { list in
                    list.fastPs.count > 2 && list.fastPs.count <= 500 && noGarbageDtag(list.dTag)
                }
                
                let nrLists: [NRPost] = (followPacks + followSetsWithLessGarbage)
                    .sorted { $0.created_at > $1.created_at }
                    .map { NRPost(event: $0) }
                
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.requestGeneration == generation else { return }
                    if ProfilePostsLoadingPolicy.shouldReveal(postCount: nrLists.count, force: forceReveal) {
                        self.posts = Array(nrLists.prefix(ProfilePostsLoadingPolicy.firstPaintLimit))
                        self.state = .ready
                    }
                    onComplete?()
                }
            }
            else { // Fetch others
            
                let fr = Event.fetchRequest()
                
                if self.type == .articles {
                    fr.predicate = NSPredicate(format: "id IN %@ AND pubkey == %@ AND kind IN %@ AND mostRecentId == nil", validatedEventIds, self.pubkey, ARTICLE_KINDS)
                }
                else if self.type == .posts {
                    fr.predicate = NSPredicate(format: "id IN %@ AND pubkey == %@ AND kind IN %@ AND replyToId == nil AND replyToRootId == nil", validatedEventIds, self.pubkey, PROFILE_KINDS.subtracting([5]))
                }
                else {
                    fr.predicate = NSPredicate(format: "id IN %@ AND pubkey == %@ AND kind IN %@ AND (replyToId != nil OR replyToRootId != nil)", validatedEventIds, self.pubkey, PROFILE_KINDS_REPLIES.subtracting([5]))
                }
                fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
                fr.fetchOffset = 0
                fr.fetchLimit = 10
            
                var posts: [NRPost] = []
                let events = (try? bg().fetch(fr)) ?? []
                
                for event in events {
                    posts.append(NRPost(event: event, cancellationId: cancellationIds[event.id] ?? event.cancellationId))
                }
                postsForStats = posts
                
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.requestGeneration == generation else { return }
                    if ProfilePostsLoadingPolicy.shouldReveal(postCount: posts.count, force: forceReveal) {
                        self.posts = Array(posts.prefix(ProfilePostsLoadingPolicy.firstPaintLimit))
                        self.state = .ready
                    }
                    onComplete?()
                }
            }
            
            guard !postsForStats.isEmpty else { return }
            guard SettingsStore.shared.fetchCounts && SettingsStore.shared.rowFooterEnabled else { return }
            for post in postsForStats.prefix(5) {
                EventRelationsQueue.shared.addAwaitingEvent(post.event)
            }
            let eventIds = postsForStats.prefix(5).map { $0.id }
#if DEBUG
            L.fetching.debug("🔢 Fetching counts for \(eventIds.count) posts, pubkey: \(self.pubkey)")
#endif
            fetchStuffForLastAddedNotes(ids: eventIds)
            self.prefetchedIds = self.prefetchedIds.union(Set(eventIds))
        }
    }

    @MainActor
    private func scheduleImportRefresh(generation: UInt64) {
        guard state == .loading || state == .initializing else { return }
        importRefreshTask?.cancel()
        importRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled, let self, self.requestGeneration == generation else { return }
            self.fetchPostsFromDB(generation: generation, forceReveal: false)
        }
    }

    @MainActor
    private func finishRelayRequest(
        outcome: BoundedRelayRequestCompletionTracker.Outcome,
        subscriptionId: String,
        generation: UInt64
    ) {
        importRefreshTask?.cancel()
        importRefreshTask = nil
        connectionWaitTask?.cancel()
        connectionWaitTask = nil
        profileRequestTracker = nil
        profileImportSubscription?.cancel()
        profileImportSubscription = nil
        activeProfileSubscriptionId = nil
        ConnectionPool.shared.closeSubscription(subscriptionId)

        let timedOut = switch outcome {
        case .finished: false
        case .timedOut: true
        }
        switch ProfilePostsLoadingPolicy.terminalDecision(
            timedOut: timedOut,
            receivedImport: receivedImportForActiveRequest
        ) {
        case .timeout:
            state = .timeout
            finishActiveRequestCompletion()
        case .readyEmpty:
            posts = []
            state = .ready
            finishActiveRequestCompletion()
        case .revealImportedPosts:
            fetchPostsFromDB(generation: generation, forceReveal: true) { [weak self] in
                self?.finishActiveRequestCompletion()
            }
        }
    }

    @MainActor
    private func finishActiveRequestCompletion() {
        let completion = activeRequestCompletion
        activeRequestCompletion = nil
        completion?()
    }

    @MainActor
    private func cancelActiveRequest() {
        requestGeneration &+= 1
        importRefreshTask?.cancel()
        importRefreshTask = nil
        connectionWaitTask?.cancel()
        connectionWaitTask = nil
        profileRequestTracker?.cancel()
        profileRequestTracker = nil
        profileImportSubscription?.cancel()
        profileImportSubscription = nil
        if let activeProfileSubscriptionId {
            ConnectionPool.shared.closeSubscription(activeProfileSubscriptionId)
        }
        activeProfileSubscriptionId = nil
        cancelPaginationRequest()
        receivedImportForActiveRequest = false
        returnedEventIds = []
        finishActiveRequestCompletion()
    }
    
    // Fetch post stats (if enabled)
    // And: after user scrolls we prefetch the next 50 posts
    // We detect this by using .task on the 6th post
    public func prefetch(_ post: NRPost, at index: Int) {
        guard self.posts[safe: index]?.id == post.id else { return }
        
        if index == 5 {
            self.prefetchOnSixthPost()
        }
        
        self.fetchPostStats(index, postId:post.id)
    }
    
    private func prefetchOnSixthPost() {
        guard !didPrefetchOlderPosts else { return }
        guard let oldestPostDate = self.posts.last?.createdAt else { return }
        didPrefetchOlderPosts = true
        let kinds = switch self.type {
        case .posts:
            PROFILE_KINDS
        case .replies:
            PROFILE_KINDS_REPLIES
        case .articles:
            ARTICLE_KINDS
        case .lists:
            LIST_KINDS
        }
        outboxReq(NostrEssentials
                    .ClientMessage(type: .REQ,
                                   filters: [
                                    Filters(
                                        authors: Set([self.pubkey]),
                                        kinds: kinds,
                                        until: Int(oldestPostDate.timeIntervalSince1970),
                                        limit: 50
                                    )
                                   ]
        ))
    }
    
    private func fetchPostStats(_ index:Int, postId:String) {
        guard self.type != .lists else { return }
        guard SettingsStore.shared.fetchCounts && SettingsStore.shared.rowFooterEnabled else { return }
        guard !self.prefetchedIds.contains(postId) else { return }
        
        guard index % 5 == 0 else { return }
        
        let nextIds = self.posts.dropFirst(max(0,index - 1)).prefix(5).map { $0.id }
        guard !nextIds.isEmpty else { return }
#if DEBUG
        L.fetching.debug("🔢 Fetching counts for \(nextIds.count) posts, pubkey: \(self.pubkey)")
#endif
        fetchStuffForLastAddedNotes(ids: nextIds)
        self.prefetchedIds = self.prefetchedIds.union(Set(nextIds))
    }
    
    @MainActor
    public func load() {
        guard shouldReload else { return }
        self.state = .loading
        self.posts = []
        self.fetchPostsFromRelays()
    }
    
    // for after acocunt change
    @MainActor
    public func reload() {
        self.state = .loading
        self.posts = []
        self.fetchPostsFromRelays()
    }

    @MainActor
    public func cancel() {
        let wasLoading = state == .loading || state == .initializing
        cancelActiveRequest()
        if wasLoading {
            lastFetch = nil
            state = .initializing
        }
    }
    
    // pull to refresh
    @MainActor
    public func refresh() async {
        self.state = .loading
        await withCheckedContinuation { continuation in
            self.fetchPostsFromRelays {
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
    
    @MainActor
    private func loadMore(
        amount: Int,
        until: Int,
        includeLocalCache: Bool
    ) {
        let cancellationIds:[String:UUID] = Dictionary(uniqueKeysWithValues: Unpublisher.shared.queue.map { ($0.nEvent.id, $0.cancellationId) })
        let generation = requestGeneration
        let currentVisibleIds = Set(self.posts.map { $0.id })
        let candidateIds = ProfilePostsLoadingPolicy.paginationCandidateIds(
            validatedEventIds: returnedEventIds,
            visibleEventIds: currentVisibleIds
        )
        guard includeLocalCache || !candidateIds.isEmpty else { return }
        
        bg().perform { [weak self] in
            guard let self else { return }
            let fr = Event.fetchRequest()
            var predicates: [NSPredicate] = [
                NSPredicate(format: "pubkey == %@", self.pubkey)
            ]
            if includeLocalCache {
                predicates.append(NSPredicate(format: "created_at <= %i", until))
            }
            else {
                predicates.append(NSPredicate(format: "id IN %@", candidateIds))
            }

            if self.type == .lists {
                let garbage: Set<String> = ["mute", "allowlist", "mutelists"]
                predicates.append(NSPredicate(format: "kind IN %@ AND mostRecentId == nil AND content == \"\" AND NOT dTag IN %@", LIST_KINDS, garbage))
            }
            else if self.type == .articles {
                predicates.append(NSPredicate(format: "kind IN %@ AND mostRecentId == nil", ARTICLE_KINDS))
            }
            else if self.type == .posts {
                predicates.append(NSPredicate(format: "kind IN %@ AND replyToRootId == nil AND replyToId == nil", PROFILE_KINDS.subtracting([5])))
            }
            else {
                predicates.append(NSPredicate(format: "kind IN %@ AND (replyToRootId != nil OR replyToId != nil)", PROFILE_KINDS_REPLIES.subtracting([5])))
            }
            fr.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            fr.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            // A cache-supplement query includes already-visible rows near the
            // cursor. Leave room for them so it can still contribute `amount`
            // older candidates after de-duplication.
            fr.fetchLimit = includeLocalCache ? amount + currentVisibleIds.count : amount
            
            var posts: [NRPost] = []
            guard let events = try? bg().fetch(fr) else { return }
            
            let filteredEvents = if self.type == .lists {
                // Only lists with between 2 and 500 pubkeys
                events.filter { list in
                    list.fastPs.count > 2 && list.fastPs.count <= 500 && noGarbageDtag(list.dTag)
                }
            }
            else {
                events
            }

            for event in filteredEvents {
                guard !currentVisibleIds.contains(event.id) else { continue }
                posts.append(NRPost(event: event, cancellationId: cancellationIds[event.id] ?? event.cancellationId))
            }
            
            guard !posts.isEmpty else { return }
            
            DispatchQueue.main.async { [weak self] in
                guard let self, self.requestGeneration == generation else { return }
                let stillVisibleIds = Set(self.posts.map(\.id))
                let additions = posts.filter { !stillVisibleIds.contains($0.id) }
                guard !additions.isEmpty else { return }
                // Relay results may fill holes above a cached candidate. Merge
                // and sort instead of appending so the outer event timeline is
                // always descending.
                self.posts = (self.posts + additions).sorted {
                    $0.created_at > $1.created_at
                }
            }
            
            guard SettingsStore.shared.fetchCounts && SettingsStore.shared.rowFooterEnabled else { return }
            for post in posts.prefix(5) {
                EventRelationsQueue.shared.addAwaitingEvent(post.event)
            }
            let eventIds = posts.prefix(5).map { $0.id }
#if DEBUG
            L.fetching.debug("🔢 Fetching counts for \(eventIds.count) posts, pubkey: \(self.pubkey)")
#endif
            fetchStuffForLastAddedNotes(ids: eventIds)
            self.prefetchedIds = self.prefetchedIds.union(Set(eventIds))
        }
    }
    
    @MainActor
    public func fetchMore(after: NRPost, amount: Int) {
        guard activePaginationSubscriptionId == nil else { return }
        let kinds = switch self.type {
        case .posts:
            PROFILE_KINDS
        case .replies:
            PROFILE_KINDS_REPLIES
        case .articles:
            ARTICLE_KINDS
        case .lists:
            LIST_KINDS
        }
        let generation = requestGeneration
        let paginationUntil = Int(after.created_at)
        let subscriptionId = "prio-PROFILEPOSTS-PAGE-" + UUID().uuidString
        let clientMessage = NostrEssentials.ClientMessage(
            type: .REQ,
            subscriptionId: subscriptionId,
            filters: [
                Filters(
                    authors: Set([self.pubkey]),
                    kinds: kinds,
                    until: paginationUntil,
                    limit: amount
                )
            ]
        )
        activePaginationSubscriptionId = subscriptionId
        paginationImportSubscription = Importer.shared.importedPrioMessagesFromSubscriptionId
            .filter { $0.subscriptionId == subscriptionId }
            .map { $0.event.id }
            .receive(on: RunLoop.main)
            .sink { [weak self] eventId in
                guard let self, self.requestGeneration == generation else { return }
                self.returnedEventIds.insert(eventId)
                self.paginationRefreshTask?.cancel()
                self.paginationRefreshTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    guard !Task.isCancelled, let self, self.requestGeneration == generation else { return }
                    self.loadMore(
                        amount: 10,
                        until: paginationUntil,
                        includeLocalCache: ProfilePostsLoadingPolicy.shouldIncludeLocalCache(pageCompleted: false)
                    )
                }
            }

        DispatchQueue.global(qos: .userInitiated).async {
            let targets = ConnectionPool.shared.requestTargetSnapshot(
                for: clientMessage,
                includeOutbox: true
            )
            Task { @MainActor [weak self] in
                guard let self,
                      self.requestGeneration == generation,
                      self.activePaginationSubscriptionId == subscriptionId
                else { return }
                self.paginationTracker = BoundedRelayRequestCompletionTracker(
                    subscriptionId: subscriptionId,
                    targets: targets,
                    onCompletion: { [weak self] _ in
                        guard let self, self.requestGeneration == generation else { return }
                        self.loadMore(
                            amount: 10,
                            until: paginationUntil,
                            includeLocalCache: ProfilePostsLoadingPolicy.shouldIncludeLocalCache(pageCompleted: true)
                        )
                        self.cancelPaginationRequest()
                    }
                )
                self.paginationTracker?.start()
                outboxReq(clientMessage, activeSubscriptionId: subscriptionId)
            }
        }
    }

    @MainActor
    private func cancelPaginationRequest() {
        paginationRefreshTask?.cancel()
        paginationRefreshTask = nil
        paginationTracker?.cancel()
        paginationTracker = nil
        paginationImportSubscription?.cancel()
        paginationImportSubscription = nil
        if let activePaginationSubscriptionId {
            ConnectionPool.shared.closeSubscription(activePaginationSubscriptionId)
        }
        activePaginationSubscriptionId = nil
    }
    
    public enum State {
        case initializing
        case loading
        case ready
        case timeout
    }
}


func noGarbageDtag(_ dTag: String) -> Bool {
    if dTag.starts(with: "notifications/") { return false }
    if dTag.starts(with: "chats/") { return false }
    if dTag.starts(with: "notifications/") { return false }
    if dTag.starts(with: "notifications/") { return false }
    return true
}
