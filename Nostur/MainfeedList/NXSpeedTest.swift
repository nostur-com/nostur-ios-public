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
    }

    public func firstFetchStarted() {
        guard timestampFirstFetchStarted == nil else { return }
        timestampFirstFetchStarted = Date()
    }

    public func relayFinished() {
        Task { @MainActor in
            if timestampFirstFetchFinished == nil {
                timestampFirstFetchFinished = Date()
            }
            
            if timestampFinalFirstUpdate == nil {
                relaysFinishedAt.append(Date())
                timestampFinalFirstUpdate = Date()
                setTotalTimeSinceEmptyFeedVisible()
            }
            else {
                relaysFinishedLater.append(Date())
            }
            
        }
    }
    
    public func relayTimedout() {
        relaysTimeouts.append(Date())
    }

    public func setTotalTimeSinceEmptyFeedVisible() {
        guard let timestampFirstEmptyFeedVisible, let timestampFinalFirstUpdate else { return }
        Task { @MainActor in
            totalTimeSinceStarting = timestampFinalFirstUpdate.timeIntervalSince(timestampFirstEmptyFeedVisible)
        }
    }
    
}
