//
//  ArticlesFeedViewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/09/2023.
//

import SwiftUI
import NostrEssentials
import Combine

// ArticlesFeed
// Fetch all articles from your follows in the last 1/7/12/31/365 days
class ArticlesFeedViewModel: ObservableObject {
    private var speedTest: NXSpeedTest?
    private var backlog:Backlog
    private var follows:Set<Pubkey>
    private var didLoad = false
    private static let POSTS_LIMIT = 250
    private var subscriptions = Set<AnyCancellable>()
    private var prefetchedIds = Set<String>()
    
    // From DB we always fetch the maximum time frame selected
    private var agoTimestamp:Int {
        return Int(Date.now.addingTimeInterval(Double(ago) * -86400).timeIntervalSince1970)
    }
    
    // From relays we fetch maximum at first, and then from since the last fetch, but not if its outside of time frame
    private var agoFetchTimestamp:Int {
        if let lastFetch, Int(lastFetch.timeIntervalSince1970) < agoTimestamp {
            return Int(lastFetch.timeIntervalSince1970)
        }
        return agoTimestamp
    }
    private var lastFetch:Date?
    
    @Published var articles:[NRPost] = [] {
        didSet {
            guard !articles.isEmpty else { return }
#if DEBUG
            L.og.debug("Article feed loaded \(self.articles.count) articles")
#endif
        }
    }
    
    @AppStorage("feed_articles_ago") var ago:Int = 31 {
        didSet {
            logAction("Article feed time frame changed to \(self.ago) days")
            if ago < oldValue {
                self.articles = []
                self.follows = Nostur.follows()
                self.fetchFromDB {
                    Task { @MainActor in
                        self.speedTest?.loadingBarViewState = .finalLoad
                    }
                }
            }
            else {
                self.articles = []
                lastFetch = nil // need to fetch further back, so remove lastFetch
                self.follows = Nostur.follows()
                self.fetchFromRelays {
                    Task { @MainActor in
                        self.speedTest?.loadingBarViewState = .finalLoad
                    }
                }
            }
        }
    }
    
    @Published var nothingFound = false
    
    var agoText: String {
        switch ago {
        case 1:
            return String(localized: "1d", comment: "Short for 1 day (time frame)")
        case 7:
            return String(localized: "1w", comment: "Short for 1 week (time frame)")
        case 31:
            return String(localized: "1m", comment: "Short for 1 month (time frame)")
        case 365:
            return String(localized: "1y", comment: "Short for 1 year (time frame)")
        default:
            return ""
        }
    }
    
    public init() {
        self.backlog = Backlog(timeout: 5.0, auto: true)
        self.follows = Nostur.follows()
        
        receiveNotification(.blockListUpdated)
            .sink { [weak self] notification in
                guard let self else { return }
                let blockedPubkeys = notification.object as! Set<String>
                self.articles = self.articles.filter { !blockedPubkeys.contains($0.pubkey)  }
            }
            .store(in: &self.subscriptions)
    }

    private func fetchFromDB(_ onComplete: (() -> ())? = nil) {
        
        Task { @MainActor in
            speedTest?.loadingBarViewState = .finalLoad
        }
        
        let blockedPubkeys = blocks()
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "created_at > %i AND kind == 30023 AND pubkey IN %@ AND flags != \"is_update\" AND NOT pubkey IN %@", agoTimestamp, follows, blockedPubkeys)
        bg().perform { [weak self]  in
            guard let self else { return }
            
            guard let articles = try? bg().fetch(fr) else { return }
            
            var nrPosts:[NRPost] = []
            
            for article in articles.prefix(Self.POSTS_LIMIT) {
                guard article.mostRecentId == nil else { continue }
                guard (article.eventPublishedAt?.timeIntervalSince1970 ?? TimeInterval(article.created_at)) > TimeInterval(self.agoTimestamp) else { continue } // published_At should be within timeframe also
                
                // withReplies for miniPFPs
                nrPosts.append(NRPost(event: article, withParents: true, withReplies: true))
            }
            
            let sortedByPublishedAt = nrPosts.sorted(by: {
                ($0.eventPublishedAt ?? $0.createdAt) > ($1.eventPublishedAt ?? $1.createdAt)
            })
            
            DispatchQueue.main.async { [weak self] in
                onComplete?()
                self?.articles = sortedByPublishedAt
                if sortedByPublishedAt.isEmpty {
                    self?.nothingFound = true
                }
            }
            
            guard !sortedByPublishedAt.isEmpty else { return }
            
            guard SettingsStore.shared.fetchCounts && SettingsStore.shared.rowFooterEnabled else { return }
            for nrPost in sortedByPublishedAt.prefix(5) {
                EventRelationsQueue.shared.addAwaitingEvent(nrPost.event)
            }
            let eventIds = sortedByPublishedAt.prefix(5).map { $0.id }
            L.fetching.info("🔢 Fetching counts for \(eventIds.count) articles")
            fetchStuffForLastAddedNotes(ids: eventIds)
            self.prefetchedIds = self.prefetchedIds.union(Set(eventIds))
        }
    }
    
    public func prefetch(_ post:NRPost) {
        guard SettingsStore.shared.fetchCounts else { return }
        guard !self.prefetchedIds.contains(post.id) else { return }
        guard let index = self.articles.firstIndex(of: post) else { return }
        guard index % 5 == 0 else { return }
        
        let nextIds = self.articles.dropFirst(max(0,index - 1)).prefix(5).map { $0.id }
        guard !nextIds.isEmpty else { return }
        L.fetching.info("🔢 Fetching counts for \(nextIds.count) articles")
        fetchStuffForLastAddedNotes(ids: nextIds)
        self.prefetchedIds = self.prefetchedIds.union(Set(nextIds))
    }
    
    private func fetchFromRelays(_ onComplete: (() -> ())? = nil) {
        
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
            subscriptionId: "ARTICLES",
            reqCommand: { [weak self] taskId in
                guard let self else { return }
                let follows = self.follows.count <= 2000 ? self.follows : Set(self.follows.shuffled().prefix(2000))
                if let cm = NostrEssentials
                            .ClientMessage(type: .REQ,
                                           subscriptionId: taskId,
                                           filters: [
                                            Filters(
                                                authors: follows,
                                                kinds: Set([30023]),
                                                since: self.agoFetchTimestamp,
                                                limit: 9999
                                            )
                                           ]
                            ).json() {
                    req(cm)
                    self.lastFetch = Date.now
                }
                else {
                    L.og.error("Article feed: Problem generating request")
                }
            },
            processResponseCommand: { [weak self] taskId, relayMessage, _ in
                guard let self else { return }
                self.fetchFromDB(onComplete)
                self.backlog.clear()
                L.og.info("Article feed: ready to process relay response")
            },
            timeoutCommand: { [weak self] taskId in
                guard let self else { return }
                self.fetchFromDB(onComplete)
                self.backlog.clear()
                L.og.info("Article feed: timeout")
            })

        backlog.add(reqTask)
        reqTask.fetch()
    }
    
    public func load(speedTest: NXSpeedTest) {
        self.speedTest = speedTest
        guard shouldReload else { return }
        L.og.info("Article feed: load()")
        self.follows = Nostur.follows()
        self.nothingFound = false
        self.articles = []
        
        self.speedTest?.start()
        self.fetchFromRelays {
            Task { @MainActor in
                self.speedTest?.loadingBarViewState = .finalLoad
                if self.articles.isEmpty {
                    self.nothingFound = true
                }
            }
        }
    }
    
    // for after account change
    public func reload() {
        self.nothingFound = false
        self.lastFetch = nil
        self.backlog.clear()
        self.follows = Nostur.follows()
        self.articles = []
        
        self.speedTest?.start()
        self.fetchFromRelays {
            Task { @MainActor in
                self.speedTest?.loadingBarViewState = .finalLoad
                if self.articles.isEmpty {
                    self.nothingFound = true
                }
            }
        }
    }
    
    // pull to refresh
    public func refresh() async {
        self.nothingFound = false
        self.lastFetch = nil
        self.backlog.clear()
        self.follows = Nostur.follows()
        
        self.speedTest?.start()
        await withCheckedContinuation { continuation in
            self.fetchFromRelays {
                Task { @MainActor in
                    self.speedTest?.loadingBarViewState = .finalLoad
                    if self.articles.isEmpty {
                        self.nothingFound = true
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
}
