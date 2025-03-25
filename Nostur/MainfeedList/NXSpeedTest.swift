//
//  NXSpeedTest.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/03/2025.
//

import SwiftUI

class NXSpeedTest: ObservableObject {
    private var timestampFirstEmptyFeedVisible: Date?

    public var timestampFirstFetchStarted: Date?
    @Published var timestampFirstFetchFinished: Date?
    private var timestampFinalFirstUpdate: Date?

    @Published var relaysFinishedAt: [Date] = []
    @Published var relaysFinishedLater: [Date] = []
    @Published var relaysTimeouts: [Date] = []

    @Published var totalTimeSinceStarting: TimeInterval = 0
    
    @Published var loadingBarViewState: LoadingBar.ViewState = .off
    
    private var _didPutOnScreen = false // first .putOnScreen() can be a bit slow, so don't finish loading bar before first .putOnScreen()
    
    public func didPutOnScreen() {
        guard !_didPutOnScreen else { return }
        self._didPutOnScreen = true
        if case .fetching = loadingBarViewState {
            loadingBarViewState = .earlyLoad
        }
        else {
            loadingBarViewState = .finalLoad
        }
    }
    
    init() { }
    
    public func reset() {
        timestampFirstEmptyFeedVisible = nil

        timestampFirstFetchStarted = nil
        timestampFirstFetchFinished = nil
        timestampFinalFirstUpdate = nil

        relaysFinishedAt = []
        relaysFinishedLater = []
        relaysTimeouts = []

        totalTimeSinceStarting = 0
    }

    public func firstEmptyFeedVisibleFinished() {
        guard timestampFirstEmptyFeedVisible == nil else { return }
        timestampFirstEmptyFeedVisible = Date()
        loadingBarViewState = .idle
    }

    public func firstFetchStarted() {
        guard timestampFirstFetchStarted == nil else { return }
        timestampFirstFetchStarted = Date()
        loadingBarViewState = .fetching
    }

    public func relayFinished() {
        Task { @MainActor in
            guard loadingBarViewState != .finished else { return }
            if timestampFirstFetchFinished == nil {
                timestampFirstFetchFinished = Date()
            }
            if timestampFinalFirstUpdate == nil {
                relaysFinishedAt.append(Date())
                timestampFinalFirstUpdate = Date()
                setTotalTimeSinceEmptyFeedVisible()
                loadingBarViewState = .earlyLoad
            }
            else {
                relaysFinishedLater.append(Date())
                guard _didPutOnScreen else { return }
                loadingBarViewState = .finalLoad
            }
            
        }
    }
    
    public func relayTimedout() {
        relaysTimeouts.append(Date())
        guard loadingBarViewState != .finished else { return }
        loadingBarViewState = .finalLoad
    }

    public func setTotalTimeSinceEmptyFeedVisible() {
        guard let timestampFirstEmptyFeedVisible, let timestampFinalFirstUpdate else { return }
        Task { @MainActor in
            totalTimeSinceStarting = timestampFinalFirstUpdate.timeIntervalSince(timestampFirstEmptyFeedVisible)
            guard _didPutOnScreen else { return }
            loadingBarViewState = .finalLoad
        }
    }
    
}
