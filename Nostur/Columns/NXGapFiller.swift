//
//  NXGapFiller.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/08/2024.
//

import SwiftUI
import Combine

enum NXRememberOnCatchUp {
    static let maxAge: TimeInterval = 86_400

    /// Remember-on catch-up asks for the newest events since `since`.
    /// Never bound `until` — a 4-hour slice starting 24h ago returns day-old
    /// notes and hides everything more recent until later windows finish.
    static func requestRange(
        since: Int64,
        now: Int64 = Int64(Date().timeIntervalSince1970),
        maxAge: TimeInterval = maxAge
    ) -> (since: Int, until: Int?) {
        let oldest = max(Int(since), Int(now) - Int(maxAge))
        return (oldest, nil)
    }
}

// Catch up - resume feed.
// Ask relays for everything since the last fetch (capped at 24h) with no `until`.
// A 4-hour `until` starting at `since` returned day-old notes first and hid
// the last hours until later windows finished — or forever if the first timed out.
// Note: don't use for "older"
class NXGapFiller {
    private var since: Int64
    private var timeout: Double // Seconds
    private var currentGap: Int
    private weak var columnVM: NXColumnViewModel?
    private var backlog: Backlog
    private var completionTracker: BoundedRelayRequestCompletionTracker?
    private var boundedSubscriptionId: String?

    @MainActor
    var hasActiveLatestRequest: Bool {
        boundedSubscriptionId != nil || completionTracker != nil
    }
    
    private var didAttemptUnscopedCatchUp = false
    
    public init(since: Int64, windowSize: Int = 4, timeout: Double = 2, currentGap: Int = 0, columnVM: NXColumnViewModel) {
        self.since = since
        self.timeout = timeout
        _ = windowSize
        self.currentGap = currentGap
        self.columnVM = columnVM
        self.backlog = Backlog(timeout: timeout, auto: true, backlogDebugName: "NXGapFiller")
    }
    
    @MainActor
    public func fetchGap(since: Int64, currentGap: Int) {
        guard let columnVM, let config = columnVM.config else { return }
        self.since = since
        self.currentGap = currentGap
        if currentGap == 0 {
            didAttemptUnscopedCatchUp = false
        }
        let range = NXRememberOnCatchUp.requestRange(since: since)
        
        guard ConnectionPool.shared.anyConnected else {
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) 🔴🔴 Not connected, skipping fetchGap, setting watchForFirstConnection = true -[LOG]-")
#endif
            if let speedTest = columnVM.speedTest, speedTest.timestampStart != nil {
                speedTest.waitingForConnection()
            }
            columnVM.watchForFirstConnection = true
            return
        }
        
        // Check if paused
        guard !columnVM.isPaused else {
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) 🔴🔴 paused, skipping fetchGap -[LOG]-")
#endif
            return
        }
                
#if DEBUG
        latestDebugSummary = "\(config.name) catch-up \(Date(timeIntervalSince1970: TimeInterval(range.since)).formatted()) → now"
#endif
        // send REQ
        if let (cmd, subId, targets) = columnVM.getFillGapReqStatement(config, since: range.since, until: range.until) {
            if let targets {
                runBoundedRequest(config: config, command: cmd, subscriptionId: subId, targets: targets())
                return
            }
            
            let reqTask = ReqTask(
                timeout: 8.5,
                subscriptionId: subId,
                reqCommand: { [weak self] subId in
                    guard let self else { return }
                    self.columnVM?.speedTest?.requestStarted()
#if DEBUG
                    L.og.debug("☘️☘️ \(config.name) subId: \(subId) catch-up since \(Date(timeIntervalSince1970: TimeInterval(range.since)).formatted()) until=nil now=\(Date.now.formatted()) -[LOG]-")
                    self.attachFetchDebug(subscriptionId: subId, config: config, targets: nil)
#endif
                    cmd()
                },
                processResponseCommand: { [weak self] subId, _, _ in
                    guard let self else { return }
                    self.columnVM?.feed?.lastLocalFetchAt = Date()

                    self.columnVM?.speedTest?.relayFinished()
                    
                    self.columnVM?.loadLocal(config, older: false) {
                        if self.columnVM?.currentNRPostsOnScreen.isEmpty ?? false {
                            self.retryUnscopedCatchUpIfNeeded(config: config)
                            return
                        }
#if DEBUG
                        self.columnVM?.recordFeedAction("initial newer pass finished")
#endif
                    }
                },
                timeoutCommand: { [weak self] subId in
#if DEBUG
                    L.og.debug("☘️☘️⏭️🔴🔴 \(columnVM.id ?? "?") subId: \(subId) timeout in fetchGap -[LOG]-")
#endif
                    Task { @MainActor in

                        self?.columnVM?.speedTest?.relayTimedout()

                        self?.columnVM?.loadLocal(config) { [weak self] in
#if DEBUG
                            self?.columnVM?.recordFeedAction("initial newer pass timed out")
#endif
                        }
                    }
                })

            self.backlog.add(reqTask)
            reqTask.fetch()
        }
    }

    @MainActor
    private func retryUnscopedCatchUpIfNeeded(config: NXColumnConfig) {
        guard !didAttemptUnscopedCatchUp else { return }
        didAttemptUnscopedCatchUp = true
        columnVM?.loadAnyFlag = true
        fetchGap(since: 1622888074, currentGap: 1)
    }
    
    private enum LatestPhase: Equatable {
        case firstPaint
        case fill
        case newer
    }

    private var didLatestFirstPaint = false
    private var didStartLatestFill = false
    private var latestAppendOlder = false
    private var latestFillLimit = 75
    private var latestFirstPaintTask: Task<Void, Never>?
    private var latestQuietOlderTask: Task<Void, Never>?
    private var latestSessionGeneration: UInt64 = 0
#if DEBUG
    private var latestDebugSummary: String?
#endif

    @MainActor
    public func fetchSimple(limit: Int) {
        cancelLatestSession()
        didLatestFirstPaint = false
        didStartLatestFill = false
        latestAppendOlder = false
        latestFillLimit = limit
        columnVM?.beginLatestFirstPaint()
        if let config = columnVM?.config {
            // Paint from local immediately. Debounced tryLatestFirstPaint left
            // the screen empty longer than the p1 timestamp.
            columnVM?.loadLocal(config) { [weak self] in
                self?.considerLatestReveal(config: config)
            }
        }
        startLatestFetch(phase: .firstPaint)
    }

    /// Keep the current screen and prepend posts newer than `since`.
    @MainActor
    public func fetchNewer(since: Int, limit: Int) {
        cancelLatestSession()
        didLatestFirstPaint = true
        didStartLatestFill = true
        latestAppendOlder = false
        latestFillLimit = limit
        columnVM?.beginLatestIncrementalFetch()
        columnVM?.allowLatestLivePrepend()
        startLatestFetch(phase: .newer, sinceOverride: since)
    }

    @MainActor
    func cancelLatestSession() {
        latestSessionGeneration &+= 1
        latestFirstPaintTask?.cancel()
        latestFirstPaintTask = nil
        latestQuietOlderTask?.cancel()
        latestQuietOlderTask = nil
        completionTracker?.cancel()
        completionTracker = nil

        if let boundedSubscriptionId {
            ConnectionPool.shared.closeSubscription(boundedSubscriptionId)
        }
        boundedSubscriptionId = nil
    }

    @MainActor
    private func startLatestFetch(phase: LatestPhase, sinceOverride: Int? = nil) {
        guard let columnVM, let config = columnVM.config else { return }
        let sessionGeneration = latestSessionGeneration
        let window = phase == .fill ? LATEST_FEED_FILL_WINDOW : LATEST_FEED_FIRST_PAINT_WINDOW
        let latestSince = sinceOverride ?? Int(Date().addingTimeInterval(-window).timeIntervalSince1970)
        let limit = phase == .firstPaint ? LATEST_FEED_FIRST_PAINT_LIMIT : latestFillLimit
        let includeOutbox = true
#if DEBUG
        let phaseLabel = switch phase {
        case .firstPaint: "p1"
        case .fill: "fill"
        case .newer: "newer"
        }
        latestDebugSummary = "latest \(phaseLabel) \(Date(timeIntervalSince1970: TimeInterval(latestSince)).formatted()) limit=\(limit) outbox"
#endif

        guard ConnectionPool.shared.anyConnected else {
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) 🔴🔴 Not connected, skipping fetchGap, setting watchForFirstConnection = true -[LOG]-")
#endif
            if let speedTest = columnVM.speedTest, speedTest.timestampStart != nil {
                speedTest.waitingForConnection()
            }
            columnVM.watchForFirstConnection = true
            return
        }
        
        // Check if paused
        guard !columnVM.isPaused else {
#if DEBUG
            L.og.debug("☘️☘️ \(config.name) 🔴🔴 paused, skipping fetchGap -[LOG]-")
#endif
            return
        }
                
        // send REQ
        if let (cmd, subId, targets) = columnVM.getFillGapReqStatement(
            config,
            since: latestSince,
            latestLimit: limit,
            includeOutbox: includeOutbox
        ) {
            if let targets {
                runBoundedRequest(
                    config: config,
                    command: cmd,
                    subscriptionId: subId,
                    targets: targets(),
                    advanceWindows: false,
                    latestPhase: phase
                )
                return
            }
            
            let reqTask = ReqTask(
                timeout: 8.5,
                subscriptionId: subId,
                reqCommand: { [weak self] subId in
                    guard let self else { return }
                    self.columnVM?.speedTest?.requestStarted()
#if DEBUG
                    L.og.debug("☘️☘️ \(config.name) subId: \(subId) latest \(phase == .firstPaint ? "firstPaint" : "fill") since=\(Date(timeIntervalSince1970: TimeInterval(latestSince)).formatted()) limit=\(limit) outbox=\(includeOutbox) -[LOG]-")
                    self.attachFetchDebug(subscriptionId: subId, config: config, targets: nil)
#endif
                    cmd()
                },
                processResponseCommand: { [weak self] _, _, _ in
                    guard let self, self.latestSessionGeneration == sessionGeneration else { return }
                    self.columnVM?.feed?.lastLocalFetchAt = Date()
                    self.handleLatestPhaseResponse(config: config, phase: phase, timedOut: false)
                },
                timeoutCommand: { [weak self] subId in
#if DEBUG
                    L.og.debug("☘️☘️⏭️🔴🔴 \(columnVM.id ?? "?") subId: \(subId) timeout in latest fetch -[LOG]-")
#endif
                    Task { @MainActor in
                        guard let self, self.latestSessionGeneration == sessionGeneration else { return }
                        self.handleLatestPhaseResponse(config: config, phase: phase, timedOut: true)
                    }
                })

            self.backlog.add(reqTask)
            reqTask.fetch()
        }
    }

    @MainActor
    private func tryLatestFirstPaint(config: NXColumnConfig) {
        // After the first screen is up, don't rebuild older rows on every import.
        // A deferred quiet append (and later fill) picks those up.
        guard !didLatestFirstPaint else { return }
        latestFirstPaintTask?.cancel()
        latestFirstPaintTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            self?.loadAfterLatestImport(config: config) {
                self?.considerLatestReveal(config: config)
            }
        }
    }

    @MainActor
    private func latestReadyCount() -> Int {
        max(columnVM?.currentNRPostsOnScreen.count ?? 0, columnVM?.latestHeldPostCount ?? 0)
    }

    @MainActor
    private func loadAfterLatestImport(config: NXColumnConfig, completion: (() -> Void)? = nil) {
        let older = latestAppendOlder && !(columnVM?.currentNRPostsOnScreen.isEmpty ?? true)
        // After first paint, fill/late imports stay in the DB. Putting 20–40
        // NRPosts on screen here is the hang. Scroll pagination loads more.
        if older,
           !(columnVM?.latestUserLoadMore ?? false),
           didLatestFirstPaint || (columnVM?.currentNRPostsOnScreen.count ?? 0) >= LATEST_FEED_INITIAL_VISIBLE {
            completion?()
            return
        }
        columnVM?.loadLocal(config, older: older, completion: completion)
    }

    @MainActor
    private func considerLatestReveal(config: NXColumnConfig, force: Bool = false) {
        let ready = latestReadyCount()
        guard force || ready >= LATEST_FEED_FIRST_PAINT_COUNT else { return }
        guard !didLatestFirstPaint else { return }
        didLatestFirstPaint = true
        latestFirstPaintTask?.cancel()
        latestAppendOlder = true
#if DEBUG
        FeedFetchDebug.shared.markPhase1Finished(columnVM?.speedTest)
#endif
        columnVM?.endLatestFirstPaintHold()
        columnVM?.speedTest?.fetchCompleted()
        // Let the first 10/6 settle before appending older rows. An immediate
        // loadLocal(older:) of ~20 parent-heavy posts is the 3–4s hang after paint.
        scheduleQuietOlderAppend(config: config)
    }

    @MainActor
    private func scheduleQuietOlderAppend(config: NXColumnConfig) {
        if config.continue { return }
        columnVM?.latestQuietOlderAppend = true
        latestQuietOlderTask?.cancel()
        latestQuietOlderTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.columnVM?.loadLocal(config, older: true) { [weak self] in
                self?.columnVM?.latestQuietOlderAppend = false
                self?.columnVM?.schedulePrefetchOlderPage()
            }
        }
    }

    @MainActor
    private func startLatestFillIfNeeded() {
        guard !didStartLatestFill else { return }
        didStartLatestFill = true
#if DEBUG
        FeedFetchDebug.shared.markFillStarted(columnVM?.speedTest)
#endif
        startLatestFetch(phase: .fill)
    }

    @MainActor
    private func handleLatestPhaseResponse(config: NXColumnConfig, phase: LatestPhase, timedOut: Bool) {
        switch phase {
        case .firstPaint:
            considerLatestReveal(config: config)
            startLatestFillIfNeeded()
            if didLatestFirstPaint {
                columnVM?.speedTest?.fetchCompleted()
            }
            else {
                // First screen is not up yet — keep trying from local.
                // After paint, skip this: the quiet older append owns the next load.
                loadAfterLatestImport(config: config)
            }
        case .fill:
            let alreadyPainted = didLatestFirstPaint
            considerLatestReveal(config: config, force: !didLatestFirstPaint)
#if DEBUG
            FeedFetchDebug.shared.markFillFinished(columnVM?.speedTest)
#endif
            columnVM?.allowLatestLivePrepend()
            if didLatestFirstPaint {
                if timedOut {
                    columnVM?.speedTest?.relayTimedout()
                }
                else {
                    columnVM?.speedTest?.fetchCompleted()
                }
            }
            if alreadyPainted || !didLatestFirstPaint {
                loadAfterLatestImport(config: config)
            }
        case .newer:
#if DEBUG
            FeedFetchDebug.shared.markFillFinished(columnVM?.speedTest)
#endif
            if timedOut {
                columnVM?.speedTest?.relayTimedout()
            }
            else {
                columnVM?.speedTest?.fetchCompleted()
            }
            columnVM?.loadLocal(config, older: false)
        }
    }

    @MainActor
    private func runBoundedRequest(
        config: NXColumnConfig,
        command: @escaping () -> Void,
        subscriptionId: String,
        targets: ConnectionPool.RequestTargetSnapshot,
        advanceWindows: Bool = true,
        latestPhase: LatestPhase? = nil
    ) {
        if let boundedSubscriptionId {
            ConnectionPool.shared.closeSubscription(boundedSubscriptionId)
#if DEBUG
            FeedFetchDebug.shared.markLingerClosed(subscriptionId: boundedSubscriptionId)
#endif
        }
        completionTracker?.cancel()
        boundedSubscriptionId = subscriptionId

        Task { @MainActor [weak self] in
            guard let self else { return }
            var requestTargets = targets
            if config.mediaFeedSourceSnapshot == .selectedRelays {
                self.columnVM?.speedTest?.waitingForConnection()
                _ = await ConnectionPool.shared.waitForAnyConnectedRelay(
                    in: config.mediaRelaysSnapshot
                )
                guard self.boundedSubscriptionId == subscriptionId else { return }
                requestTargets = ConnectionPool.shared.requestTargetSnapshot(
                    relays: config.mediaRelaysSnapshot
                )
            }

            guard self.boundedSubscriptionId == subscriptionId else { return }
            self.completionTracker = BoundedRelayRequestCompletionTracker(
                subscriptionId: subscriptionId,
                targets: requestTargets,
                extendQuietPeriodOnImport: advanceWindows,
                onImport: { [weak self] in
                    self?.tryLatestFirstPaint(config: config)
                },
                onCompletion: { [weak self] outcome in
                    guard let self, let columnVM = self.columnVM else { return }
                    self.completionTracker = nil
                    self.boundedSubscriptionId = nil
                    // The tracker has already waited for relay quorum and for the
                    // importer to settle. Keeping unfinished relays subscribed after
                    // this point consumes scarce relay subscription slots and can
                    // starve unrelated lookups (thread parents, profiles, embeds).
                    ConnectionPool.shared.closeSubscription(subscriptionId)
#if DEBUG
                    FeedFetchDebug.shared.markLingerClosed(subscriptionId: subscriptionId)
#endif

                    switch outcome {
                    case .finished:
                        columnVM.feed?.lastLocalFetchAt = Date()
                        if config.mediaFeedSourceSnapshot != nil,
                           columnVM.currentNRPostsOnScreen.isEmpty {
                            // A bounded media response is not necessarily newer than
                            // the normal eight-hour local window (Divine batches in
                            // particular often contain older videos). Query all local
                            // history on the first completion so the events just
                            // imported by this request are immediately eligible.
                            columnVM.loadAnyFlag = true
                        }
                        if let latestPhase {
                            self.handleLatestPhaseResponse(
                                config: config,
                                phase: latestPhase,
                                timedOut: false
                            )
                            return
                        }
                        columnVM.speedTest?.fetchCompleted()
                        columnVM.loadLocal(config, older: false) { [weak self] in
                            guard let self else { return }
                            if self.columnVM?.currentNRPostsOnScreen.isEmpty ?? false {
                                self.retryUnscopedCatchUpIfNeeded(config: config)
                                return
                            }

#if DEBUG
                            self.columnVM?.recordFeedAction("initial newer pass finished")
#endif
                        }

                    case .timedOut:
                        if config.mediaFeedSourceSnapshot != nil,
                           columnVM.currentNRPostsOnScreen.isEmpty {
                            // Imports may finish just as the bounded tracker expires.
                            // Do the same authoritative all-history read before the
                            // outer UI decides that no matching posts exist.
                            columnVM.loadAnyFlag = true
                        }
                        if let latestPhase {
                            self.handleLatestPhaseResponse(
                                config: config,
                                phase: latestPhase,
                                timedOut: true
                            )
                            return
                        }
                        columnVM.speedTest?.relayTimedout()
                        columnVM.loadLocal(config) { [weak self] in
#if DEBUG
                            self?.columnVM?.recordFeedAction("initial newer pass timed out")
#endif
                        }
                    }
                }
            )
            self.completionTracker?.start()
            self.columnVM?.speedTest?.requestStarted()
#if DEBUG
            self.attachFetchDebug(subscriptionId: subscriptionId, config: config, targets: requestTargets)
#endif
            command()
        }
    }

#if DEBUG
    @MainActor
    private func attachFetchDebug(
        subscriptionId: String,
        config: NXColumnConfig,
        targets: ConnectionPool.RequestTargetSnapshot?
    ) {
        let relayIds = targets?.relayIds ?? ConnectionPool.shared.requestTargetSnapshot().relayIds
        let summary = latestDebugSummary
            ?? "\(config.name) catch-up \(Date(timeIntervalSince1970: TimeInterval(NXRememberOnCatchUp.requestRange(since: since).since)).formatted()) → now"
        FeedFetchDebug.shared.attach(
            columnVM?.speedTest,
            subscriptionId: subscriptionId,
            summary: summary,
            seeds: ConnectionPool.shared.feedFetchDebugSeeds(
                for: relayIds,
                outboxIds: targets?.extraIds ?? []
            ),
            targetSnapshot: targets
        )
    }
#endif
}
