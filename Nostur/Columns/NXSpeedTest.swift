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
    
    init() { }
    
    deinit {
        timeoutTask?.cancel()
    }
    
    public func start() {
        let newRunID = UUID()
        runID = newRunID
        timeoutTask?.cancel()
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
#if DEBUG
                L.og.debug("🏁🏁 NXSpeedTest.start Setting loadingBarViewState to: .connecting")
#endif
                loadingBarViewState = .connecting
            }
        }
    }

    public func loadRemoteStarted() { // called by loadRemote()
        if firstLoadRemoteStartedAt == nil {
            let currentRunID = runID
            firstLoadRemoteStartedAt = Date()
#if DEBUG
            L.og.debug("🏁🏁 NXSpeedTest.loadRemoteStarted Setting loadingBarViewState to: .fetching -[LOG]-")
#endif
            loadingBarViewState = .fetching
            self.setTimerForTimeout(runID: currentRunID)
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
#endif
                    loadingBarViewState = .finalLoad
                }
            }
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
        }
    }
    
    let STATES_CAN_TIMEOUT: Set<LoadingBar.ViewState> = Set([.connecting, .starting, .fetching])
    
    public func otherTimeout() {
        Task { @MainActor in
            if STATES_CAN_TIMEOUT.contains(loadingBarViewState) {
#if DEBUG
                L.og.debug("🏁🏁 NXSpeedTest.otherTimeout Setting loadingBarViewState to: .timeout")
#endif
                if loadingBarViewState != .timeout {
                    loadingBarViewState = .timeout
                }
            }
        }
    }
    
    private func setTimerForTimeout(runID: UUID) {
        guard STATES_CAN_TIMEOUT.contains(loadingBarViewState) else { return }
#if DEBUG
        L.og.debug("🏁🏁 NXSpeedTest.setTimerForTimeout, now: \(self.loadingBarViewState.rawValue.description) -[LOG]-")
#endif
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.runID == runID else { return }
                L.og.debug("🏁🏁 NXSpeedTest.setTimerForTimeout??? now: \(self.loadingBarViewState.rawValue.description) -[LOG]-")
                guard STATES_CAN_TIMEOUT.contains(loadingBarViewState) else { return }
                self.otherTimeout()
            }
        }
    }
}
