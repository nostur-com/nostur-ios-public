//
//  RelayConnectionStats.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/07/2024.
//

import Foundation

enum TrackedReqPrefix: String, CaseIterable {
    case following = "Following-"
    case list = "List-"
    case resume = "RESUME-"
    case ss = "SS-"
    case um = "UM-"
    case detail = "DETAIL-"
    case viewing = "VIEWING-"
}

func trackedReqPrefix(for subscriptionId: String) -> TrackedReqPrefix? {
    for prefix in TrackedReqPrefix.allCases where subscriptionId.starts(with: prefix.rawValue) {
        return prefix
    }
    return nil
}

private struct PendingTrackedReq {
    let sentAtUptimeNs: UInt64
}

private struct LatencyBucket {
    var epoch: Int64 = -1
    var count: Int = 0
    var sumLatencyMs: Double = 0
}

private struct LatencyWindow {
    private let slotDurationNs: UInt64
    private var buckets: [LatencyBucket]

    init(slotDurationNs: UInt64, slotCount: Int = 60) {
        self.slotDurationNs = slotDurationNs
        self.buckets = Array(repeating: LatencyBucket(), count: slotCount)
    }

    mutating func addSample(latencyMs: Double, nowUptimeNs: UInt64) {
        guard !buckets.isEmpty else { return }
        let epoch = Int64(nowUptimeNs / slotDurationNs)
        let index = Int(epoch % Int64(buckets.count))

        if buckets[index].epoch != epoch {
            buckets[index] = LatencyBucket(epoch: epoch, count: 0, sumLatencyMs: 0)
        }

        buckets[index].count += 1
        buckets[index].sumLatencyMs += latencyMs
    }

    func average(nowUptimeNs: UInt64) -> Double? {
        let stats = summary(nowUptimeNs: nowUptimeNs)
        guard stats.count > 0 else { return nil }
        return stats.sumLatencyMs / Double(stats.count)
    }

    func sampleCount(nowUptimeNs: UInt64) -> Int {
        summary(nowUptimeNs: nowUptimeNs).count
    }

    private func summary(nowUptimeNs: UInt64) -> (count: Int, sumLatencyMs: Double) {
        guard !buckets.isEmpty else { return (0, 0) }
        let currentEpoch = Int64(nowUptimeNs / slotDurationNs)
        let minEpoch = currentEpoch - Int64(buckets.count) + 1

        var count = 0
        var sumLatencyMs = 0.0

        for bucket in buckets where bucket.epoch >= minEpoch && bucket.epoch <= currentEpoch {
            count += bucket.count
            sumLatencyMs += bucket.sumLatencyMs
        }
        return (count, sumLatencyMs)
    }
}

public struct RelayLatencyAverages {
    public let avg5mMs: Double?
    public let avg15mMs: Double?
    public let avg1hMs: Double?
    public let samples5m: Int
    public let samples15m: Int
    public let samples1h: Int

    public var bestAvailableMs: Double? {
        avg5mMs ?? avg15mMs ?? avg1hMs
    }
}

public class RelayConnectionStats: Identifiable {
    public let id: String // should be relay url
    
    public var errors: Int = 0
    public var messages: Int = 0
    public var connected: Int = 0
    
    public var lastErrorMessages: [String] = []
    public var lastNoticeMessages: [String] = []
    
    // Pubkeys actually received from this relay
    public var receivedPubkeys: Set<String> = []

    private var pendingTrackedReqBySubId: [String: PendingTrackedReq] = [:]
    private var latency5m = LatencyWindow(slotDurationNs: 5_000_000_000)        // 60 x 5s
    private var latency15m = LatencyWindow(slotDurationNs: 15_000_000_000)      // 60 x 15s
    private var latency1h = LatencyWindow(slotDurationNs: 60_000_000_000)       // 60 x 60s
    private let maxLatencyMs: Double = 30_000
    private let stalePendingReqTimeoutNs: UInt64 = 30_000_000_000

    init(id: String) {
        self.id = id
    }
    
    public func addErrorMessage(_ message: String) {
//        31.00 ms    0.2%    25.00 ms           closure #1 in RelayConnection.didReceiveError(_:)
//        5.00 ms    0.0%    3.00 ms            RelayConnectionStats.addErrorMessage(_:)
        lastErrorMessages = Array(([String(format: "%@: %@", Date().ISO8601Format(), message)] + lastErrorMessages).prefix(10))
    }
    
    public func addNoticeMessage(_ message: String) {
        lastNoticeMessages = Array(([String(format: "%@: %@", Date().ISO8601Format(), message)] + lastNoticeMessages).prefix(10))
    }

    public func recordTrackedReqSent(subscriptionId: String, nowUptimeNs: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        guard trackedReqPrefix(for: subscriptionId) != nil else { return }
        cleanupStalePending(nowUptimeNs: nowUptimeNs)
        pendingTrackedReqBySubId[subscriptionId] = PendingTrackedReq(sentAtUptimeNs: nowUptimeNs)
    }

    public func recordTrackedReqResponse(subscriptionId: String, nowUptimeNs: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        guard let pending = pendingTrackedReqBySubId.removeValue(forKey: subscriptionId) else { return }
        let latencyMs = min(Double(nowUptimeNs - pending.sentAtUptimeNs) / 1_000_000.0, maxLatencyMs)
        latency5m.addSample(latencyMs: latencyMs, nowUptimeNs: nowUptimeNs)
        latency15m.addSample(latencyMs: latencyMs, nowUptimeNs: nowUptimeNs)
        latency1h.addSample(latencyMs: latencyMs, nowUptimeNs: nowUptimeNs)
    }

    public func latencyAverages(nowUptimeNs: UInt64 = DispatchTime.now().uptimeNanoseconds) -> RelayLatencyAverages {
        RelayLatencyAverages(
            avg5mMs: latency5m.average(nowUptimeNs: nowUptimeNs),
            avg15mMs: latency15m.average(nowUptimeNs: nowUptimeNs),
            avg1hMs: latency1h.average(nowUptimeNs: nowUptimeNs),
            samples5m: latency5m.sampleCount(nowUptimeNs: nowUptimeNs),
            samples15m: latency15m.sampleCount(nowUptimeNs: nowUptimeNs),
            samples1h: latency1h.sampleCount(nowUptimeNs: nowUptimeNs)
        )
    }

    private func cleanupStalePending(nowUptimeNs: UInt64) {
        pendingTrackedReqBySubId = pendingTrackedReqBySubId.filter { _, pending in
            nowUptimeNs - pending.sentAtUptimeNs <= stalePendingReqTimeoutNs
        }
    }
}

func updateConnectionStats(receivedPubkey pubkey: String, fromRelay relay: String) {
    // Only track pubkey we follow
    guard AccountsState.shared.loggedInAccount?.followingPublicKeys.contains(pubkey) ?? false else { return }
    ConnectionPool.shared.queue.async(flags: .barrier) {
        guard let relayStats = ConnectionPool.shared.connectionStats[relay] else { return }
        relayStats.receivedPubkeys.insert(pubkey)
    }
}
