//
//  NXGapFiller.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/08/2024.
//

import SwiftUI
import Combine

// Catch up - resume feed
// Fetch posts since last time in X hour windows
// Wait Y seconds per window
// Can't know if fetch window has no posts or connection failure
// So before advancing to next window, make sure we have connection
// Note: don't use for "older"
class NXGapFiller {
    private var since: Int64
    private var windowSize: Int // Hours
    private var timeout: Double // Seconds
    private var currentGap: Int // used to calculate nextGapSince
    private weak var columnVM: NXColumnViewModel?
    private var backlog: Backlog
    private var completionTracker: BoundedRelayRequestCompletionTracker?
    private var boundedSubscriptionId: String?
    private var lingerCloseTasks: [String: Task<Void, Never>] = [:]
    private var lateImportSubs: [String: AnyCancellable] = [:]
    private var lateLoadTask: Task<Void, Never>?
    
    private var windowStart: Int { // Depending on older or not we use start/end as since/until
        return Int(since) + (currentGap * 3600 * windowSize)
    }
    private var windowEnd: Int { // Depending on older or not we use start/end as since/until
        windowStart + (3600 * windowSize)
    }
    
    public init(since: Int64, windowSize: Int = 4, timeout: Double = 2, currentGap: Int = 0, columnVM: NXColumnViewModel) {
        self.since = since
        self.windowSize = windowSize
        self.timeout = timeout
        self.currentGap = currentGap
        self.columnVM = columnVM
        self.backlog = Backlog(timeout: timeout, auto: true, backlogDebugName: "NXGapFiller")
    }
    
    @MainActor
    public func fetchGap(since: Int64, currentGap: Int) {
        guard let columnVM, let config = columnVM.config else { return }
        self.since = since
        self.currentGap = currentGap
        
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
        if let (cmd, subId, targets) = columnVM.getFillGapReqStatement(config, since: windowStart, until: windowEnd) {
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
                    L.og.debug("☘️☘️ \(config.name) subId: \(subId) reqCommand currentGap: \(self.currentGap) \(Date(timeIntervalSince1970: TimeInterval(self.windowStart)).formatted()) - \(Date(timeIntervalSince1970: TimeInterval(self.windowEnd)).formatted()) now=\(Date.now.formatted()) -[LOG]-")
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
                            self.columnVM?.loadAnyFlag = true
                            self.fetchGap(since: 1622888074, currentGap: self.currentGap)
                        }
                    }
                    
                    self.currentGap += 1
                    
                    if self.windowStart < Int(Date().timeIntervalSince1970) {
#if DEBUG
                        L.og.debug("☘️☘️⏭️ \(columnVM.id ?? "?") subId: \(subId) processResponseCommand.fetchGap self.currentGap + 1: \(self.currentGap + 1) -[LOG]-")
#endif
                        self.fetchGap(since: self.since, currentGap: self.currentGap) // next gap (no since param)
                    }
                    else {
                        self.currentGap = 0
                    }
                },
                timeoutCommand: { [weak self] subId in
#if DEBUG
                    L.og.debug("☘️☘️⏭️🔴🔴 \(columnVM.id ?? "?") subId: \(subId) timeout in fetchGap -[LOG]-")
#endif
                    Task { @MainActor in

                        self?.columnVM?.speedTest?.relayTimedout()

                        self?.columnVM?.loadLocal(config)
                    }
                })

            self.backlog.add(reqTask)
            reqTask.fetch()
        }
    }
    
    @MainActor
    public func fetchSimple(limit: Int) {
        guard let columnVM, let config = columnVM.config else { return }
        let latestSince = Int(Date().addingTimeInterval(-86_400).timeIntervalSince1970)

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
        if let (cmd, subId, targets) = columnVM.getFillGapReqStatement(config, since: latestSince, latestLimit: limit) {
            if let targets {
                runBoundedRequest(config: config, command: cmd, subscriptionId: subId, targets: targets(), advanceWindows: false)
                return
            }
            
            let reqTask = ReqTask(
                timeout: 8.5,
                subscriptionId: subId,
                reqCommand: { [weak self] subId in
                    guard let self else { return }
                    self.columnVM?.speedTest?.requestStarted()
#if DEBUG
                    L.og.debug("☘️☘️ \(config.name) subId: \(subId) fetchSimple since=\(Date(timeIntervalSince1970: TimeInterval(latestSince)).formatted()) limit=\(limit) -[LOG]-")
                    self.attachFetchDebug(subscriptionId: subId, config: config, targets: nil)
#endif
                    cmd()
                },
                processResponseCommand: { [weak self] _, _, _ in
                    guard let self else { return }
                    self.columnVM?.feed?.lastLocalFetchAt = Date()
                    self.columnVM?.speedTest?.relayFinished()
                    self.columnVM?.loadLocal(config, older: false)
                },
                timeoutCommand: { [weak self] subId in
#if DEBUG
                    L.og.debug("☘️☘️⏭️🔴🔴 \(columnVM.id ?? "?") subId: \(subId) timeout in fetchSimple -[LOG]-")
#endif
                    Task { @MainActor in
                        self?.columnVM?.speedTest?.relayTimedout()
                        self?.columnVM?.loadLocal(config)
                    }
                })

            self.backlog.add(reqTask)
            reqTask.fetch()
        }
    }

    @MainActor
    private func runBoundedRequest(
        config: NXColumnConfig,
        command: @escaping () -> Void,
        subscriptionId: String,
        targets: ConnectionPool.RequestTargetSnapshot,
        advanceWindows: Bool = true
    ) {
        if let boundedSubscriptionId {
            lingerCloseTasks[boundedSubscriptionId]?.cancel()
            lingerCloseTasks[boundedSubscriptionId] = nil
            lateImportSubs[boundedSubscriptionId]?.cancel()
            lateImportSubs[boundedSubscriptionId] = nil
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
                onCompletion: { [weak self] outcome in
                    guard let self, let columnVM = self.columnVM else { return }
                    self.completionTracker = nil
                    self.boundedSubscriptionId = nil
                    self.scheduleLingerClose(subscriptionId)
                    if outcome == .finished {
                        self.watchLateImports(subscriptionId: subscriptionId, config: config)
                    }

                    switch outcome {
                    case .finished:
                        columnVM.feed?.lastLocalFetchAt = Date()
                        columnVM.speedTest?.fetchCompleted()
                        if config.mediaFeedSourceSnapshot != nil,
                           columnVM.currentNRPostsOnScreen.isEmpty {
                            // A bounded media response is not necessarily newer than
                            // the normal eight-hour local window (Divine batches in
                            // particular often contain older videos). Query all local
                            // history on the first completion so the events just
                            // imported by this request are immediately eligible.
                            columnVM.loadAnyFlag = true
                        }
                        columnVM.loadLocal(config, older: false) { [weak self] in
                            guard let self else { return }
                            guard advanceWindows else { return }
                            if self.columnVM?.currentNRPostsOnScreen.isEmpty ?? false {
                                self.columnVM?.loadAnyFlag = true
                                self.fetchGap(since: 1622888074, currentGap: self.currentGap)
                                return
                            }

                            if self.windowStart < Int(Date().timeIntervalSince1970) {
                                self.fetchGap(since: self.since, currentGap: self.currentGap)
                            }
                            else {
                                self.currentGap = 0
                            }
                        }

                        if advanceWindows {
                            self.currentGap += 1
                        }

                    case .timedOut:
                        columnVM.speedTest?.relayTimedout()
                        if config.mediaFeedSourceSnapshot != nil,
                           columnVM.currentNRPostsOnScreen.isEmpty {
                            // Imports may finish just as the bounded tracker expires.
                            // Do the same authoritative all-history read before the
                            // outer UI decides that no matching posts exist.
                            columnVM.loadAnyFlag = true
                        }
                        columnVM.loadLocal(config)
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

    @MainActor
    /// Keep the REQ open after the bar finishes so slower relays can still deliver.
    private static let lingerAfterBarNanoseconds: UInt64 = 8_000_000_000

    private func scheduleLingerClose(_ subscriptionId: String) {
        lingerCloseTasks[subscriptionId]?.cancel()
        lingerCloseTasks[subscriptionId] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.lingerAfterBarNanoseconds)
            guard !Task.isCancelled else { return }
            self?.lateImportSubs[subscriptionId]?.cancel()
            self?.lateImportSubs[subscriptionId] = nil
            self?.lingerCloseTasks[subscriptionId] = nil
            ConnectionPool.shared.closeSubscription(subscriptionId)
#if DEBUG
            FeedFetchDebug.shared.markLingerClosed(subscriptionId: subscriptionId)
#endif
        }
    }

    private func watchLateImports(subscriptionId: String, config: NXColumnConfig) {
        lateImportSubs[subscriptionId] = Importer.shared.importedMessagesFromSubscriptionIds
            .filter { $0.contains(subscriptionId) }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleLateLoad(config)
            }
    }

    private func scheduleLateLoad(_ config: NXColumnConfig) {
        lateLoadTask?.cancel()
        lateLoadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.columnVM?.loadLocal(config)
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
        let summary = "\(config.name) gap \(Date(timeIntervalSince1970: TimeInterval(windowStart)).formatted()) – \(Date(timeIntervalSince1970: TimeInterval(windowEnd)).formatted())"
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
