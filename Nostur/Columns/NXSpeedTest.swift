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

    @Published var relaysFinishedAt: [Date] = []
    @Published var relaysTimeouts: [Date] = []

    @Published var resultFirstFetch: TimeInterval = 0
    @Published var resultLastFetch: TimeInterval = 0
    
    // Never set .finished. Last state to set manually is .finalLoad which triggers final animation to .finished
    @Published var loadingBarViewState: LoadingBar.ViewState = .off
    
    init() { }
    
    public func start() {
        timestampStart = Date()
        firstLoadRemoteStartedAt = nil

        Task { @MainActor in
            relaysFinishedAt = []
            relaysTimeouts = []

            resultFirstFetch = 0
            
            if !ConnectionPool.shared.anyConnected {
#if DEBUG
                L.og.debug("🏁🏁 NXSpeedTest.start Setting loadingBarViewState to: .connecting")
#endif
                loadingBarViewState = .connecting
            }
        }
    }

    public func loadRemoteStarted() { // called by loadRemote()
        if firstLoadRemoteStartedAt == nil {
            firstLoadRemoteStartedAt = Date()
#if DEBUG
            L.og.debug("🏁🏁 NXSpeedTest.loadRemoteStarted Setting loadingBarViewState to: .fetching -[LOG]-")
#endif
            loadingBarViewState = .fetching
            self.setTimerForTimeout()
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
            print("WHAT 3")
            if STATES_CAN_TIMEOUT.contains(loadingBarViewState) {
                print("WHAT 4")
#if DEBUG
                L.og.debug("🏁🏁 NXSpeedTest.otherTimeout Setting loadingBarViewState to: .timeout")
#endif
                if loadingBarViewState != .timeout {
                    print("WHAT 5")
                    loadingBarViewState = .timeout
                }
                print("WHAT 6")
            }
        }
    }
    
    private func setTimerForTimeout() {
        guard STATES_CAN_TIMEOUT.contains(loadingBarViewState) else { return }
#if DEBUG
        L.og.debug("🏁🏁 NXSpeedTest.setTimerForTimeout, now: \(self.loadingBarViewState.rawValue.description) -[LOG]-")
#endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) { [weak self] in
            print("WHAT 1")
            guard let self else { return }
            L.og.debug("🏁🏁 NXSpeedTest.setTimerForTimeout??? now: \(self.loadingBarViewState.rawValue.description) -[LOG]-")
            guard STATES_CAN_TIMEOUT.contains(loadingBarViewState) else { return }
            print("WHAT 2")
            self.otherTimeout()
        }
    }
}
