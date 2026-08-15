//
//  NXSpeedTest.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/03/2025.
//

import SwiftUI

class NXSpeedTest: ObservableObject {
    public var timestampStart: Date?
    private var firstLoadRemoteStartedAt: Date?
    private var runID = UUID()
    private var timeoutTask: Task<Void, Never>?

    @Published var relaysFinishedAt: [Date] = []
    @Published var relaysTimeouts: [Date] = []

    @Published var resultFirstFetch: TimeInterval = 0
    @Published var resultLastFetch: TimeInterval = 0
    
    // Never set .finished. Last state to set manually is .finalLoad which triggers final animation to .finished
    @Published var loadingBarViewState: LoadingBar.ViewState = .off
#if DEBUG
    @Published var debugSession: FeedFetchDebugSession?
    var debugTrigger: String = "start"
    var debugFeedName: String = ""
#endif
    
    init() { }
    
    deinit {
        timeoutTask?.cancel()
    }
    
#if DEBUG
    public func start(trigger: String, feedName: String) {
        debugTrigger = trigger
        debugFeedName = feedName
        start()
    }
#endif

    public func start() {
        let newRunID = UUID()
        runID = newRunID
        timeoutTask?.cancel()
        timeoutTask = nil
        timestampStart = Date()
        firstLoadRemoteStartedAt = nil

        Task { @MainActor in
            guard self.runID == newRunID else { return }
            relaysFinishedAt = []
            relaysTimeouts = []

            resultFirstFetch = 0
            resultLastFetch = 0
            
            if ConnectionPool.shared.anyConnected {
#if DEBUG
                L.og.debug("🏁🏁 NXSpeedTest.start Setting loadingBarViewState to: .starting")
#endif
                loadingBarViewState = .starting
            }
            else {
                waitingForConnection()
            }
#if DEBUG
            FeedFetchDebug.shared.begin(self, trigger: debugTrigger, feedName: debugFeedName)
#endif
        }
    }

    /// The feed intends to fetch but cannot dispatch a request until a usable relay connects.
    /// Keep this separate from `requestStarted()` so timeout bookkeeping cannot make the bar
    /// claim network fetching has begun before a request is actually sent.
    public func waitingForConnection() {
        guard timestampStart != nil, firstLoadRemoteStartedAt == nil else { return }
#if DEBUG
        L.og.debug("🏁🏁 NXSpeedTest.waitingForConnection Setting loadingBarViewState to: .connecting")
#endif
        loadingBarViewState = .connecting
        ensureTimerForTimeout(runID: runID)
    }

    /// Call only at the request dispatch point, never merely on entry to a load method.
    public func requestStarted() {
        if firstLoadRemoteStartedAt == nil {
            let currentRunID = runID
            firstLoadRemoteStartedAt = Date()
#if DEBUG
            L.og.debug("🏁🏁 NXSpeedTest.requestStarted Setting loadingBarViewState to: .fetching -[LOG]-")
#endif
            loadingBarViewState = .fetching
            ensureTimerForTimeout(runID: currentRunID)
#if DEBUG
            Task { @MainActor in
                FeedFetchDebug.shared.markRequestStarted(self)
            }
#endif
        }
    }

    public func relayFinished() {
        Task { @MainActor in
            guard let timestampStart else { return }
            let currentTimestamp = Date()
            if relaysFinishedAt.isEmpty {
                relaysFinishedAt.append(currentTimestamp)
#if DEBUG
                L.og.debug("🏁🏁 NXSpeedTest.relayFinished Setting loadingBarViewState to: .earlyLoad -[LOG]-")
#endif
                loadingBarViewState = .earlyLoad
                resultFirstFetch = currentTimestamp.timeIntervalSince(timestampStart)
            }
            else {
                relaysFinishedAt.append(currentTimestamp)
                resultLastFetch = currentTimestamp.timeIntervalSince(timestampStart)
                
                if loadingBarViewState == .earlyLoad {
#if DEBUG
                    L.og.debug("🏁🏁 NXSpeedTest.relayFinished Setting loadingBarViewState to: .finalLoad")
                    debugSession?.markEnded()
#endif
                    loadingBarViewState = .finalLoad
                }
            }
        }
    }
    
    /// Bounded catch-up is done. Advance through earlyLoad so the bar does not
    /// sit at 75% waiting for a second per-relay finish that will never come.
    public func fetchCompleted() {
        Task { @MainActor in
            if loadingBarViewState == .fetching {
                loadingBarViewState = .earlyLoad
            }
            if loadingBarViewState == .earlyLoad {
                loadingBarViewState = .finalLoad
            }
#if DEBUG
            debugSession?.markEnded()
#endif
        }
    }

    public func relayTimedout() {
        Task { @MainActor in
            if loadingBarViewState == .fetching || loadingBarViewState == .earlyLoad  {
#if DEBUG
                L.og.debug("🏁🏁 NXSpeedTest.relayTimedout Setting loadingBarViewState to: .finalLoad")
#endif
                loadingBarViewState = .finalLoad
            }
            relaysTimeouts.append(Date())
#if DEBUG
            debugSession?.markEnded()
#endif
        }
    }
    
    let STATES_CAN_TIMEOUT: Set<LoadingBar.ViewState> = Set([.connecting, .starting, .fetching, .earlyLoad, .secondFetching])
    
    public func otherTimeout() {
        Task { @MainActor in
            if STATES_CAN_TIMEOUT.contains(loadingBarViewState) {
#if DEBUG
                L.og.debug("🏁🏁 NXSpeedTest.otherTimeout Setting loadingBarViewState to: .timeout")
#endif
                if loadingBarViewState != .timeout {
                    loadingBarViewState = .timeout
                }
#if DEBUG
                debugSession?.markEnded()
#endif
            }
        }
    }

    @MainActor
    public func finishedWithoutResults() {
        timeoutTask?.cancel()
        loadingBarViewState = .timeout
#if DEBUG
        debugSession?.markEnded()
#endif
    }
    
    private func ensureTimerForTimeout(runID: UUID) {
        guard STATES_CAN_TIMEOUT.contains(loadingBarViewState) else { return }
        guard timeoutTask == nil else { return }
#if DEBUG
        L.og.debug("🏁🏁 NXSpeedTest.ensureTimerForTimeout, now: \(self.loadingBarViewState.rawValue.description) -[LOG]-")
#endif
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.runID == runID else { return }
                L.og.debug("🏁🏁 NXSpeedTest.ensureTimerForTimeout fired, now: \(self.loadingBarViewState.rawValue.description) -[LOG]-")
                guard STATES_CAN_TIMEOUT.contains(loadingBarViewState) else { return }
                self.otherTimeout()
            }
        }
    }
}
