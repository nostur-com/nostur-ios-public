//
//  RelayScoreStore.swift
//  Nostur
//
//  Thompson sampling for relay quality estimation.
//  Maintains per-relay (successes, failures) counts and samples from the Beta distribution
//  to stochastically weight relay scoring in the outbox planner.
//

import Foundation

class RelayScoreStore {
    static let shared = RelayScoreStore()

    struct RelayScore: Codable {
        var successes: Int
        var failures: Int
    }

    // Only read/written from ConnectionPool.queue — no additional synchronization needed.
    private var scores: [String: RelayScore] = [:]

    private let persistFileName = "relay-thompson-scores.json"
    private var lastSeenDates: [String: Date] = [:]

    private var persistFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent(persistFileName)
    }

    /// Returns a snapshot copy of scores for use outside the queue.
    func scoresSnapshot() -> [String: RelayScore]? {
        let s = scores
        return s.isEmpty ? nil : s
    }

    // MARK: - Persistence

    func load() {
        guard FileManager.default.fileExists(atPath: persistFileURL.path) else { return }
        guard let data = try? Data(contentsOf: persistFileURL) else { return }

        struct PersistedData: Codable {
            let scores: [String: RelayScore]
            let lastSeen: [String: Date]?
        }

        guard let persisted = try? JSONDecoder().decode(PersistedData.self, from: data) else { return }

        var loadedScores = persisted.scores
        let loadedLastSeen = persisted.lastSeen ?? [:]
        let now = Date()
        let thirtyDays: TimeInterval = 30 * 24 * 3600

        // Prune entries not seen in 30 days
        for (relay, lastSeen) in loadedLastSeen {
            if now.timeIntervalSince(lastSeen) > thirtyDays {
                loadedScores.removeValue(forKey: relay)
            }
        }

        // Decay: halve scores when sum > 1000
        for (relay, score) in loadedScores {
            if score.successes + score.failures > 1000 {
                loadedScores[relay] = RelayScore(successes: score.successes / 2, failures: score.failures / 2)
            }
        }

        self.scores = loadedScores
        self.lastSeenDates = loadedLastSeen

#if DEBUG
        L.sockets.debug("📊 Thompson: Loaded scores for \(loadedScores.count) relays")
#endif
    }

    func persist() {
        struct PersistedData: Codable {
            let scores: [String: RelayScore]
            let lastSeen: [String: Date]
        }

        let data = PersistedData(scores: scores, lastSeen: lastSeenDates)
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        try? encoded.write(to: persistFileURL)
    }

    // MARK: - Score Updates

    /// Compare requested pubkeys per relay against pubkeys received this cycle.
    /// Uses `receivedPubkeysThisCycle` (populated alongside the durable `receivedPubkeys`)
    /// and clears it after reading, so each cycle measures actual current delivery.
    /// Should only be called from ConnectionPool.queue.
    func updateScores(
        requestedPubkeysPerRelay: [String: Set<String>],
        connectionStats: [String: RelayConnectionStats]
    ) {
        let now = Date()

        for (relay, requestedPubkeys) in requestedPubkeysPerRelay {
            let receivedThisCycle = connectionStats[relay]?.receivedPubkeysThisCycle ?? []
            let hits = requestedPubkeys.intersection(receivedThisCycle).count
            let misses = requestedPubkeys.count - hits

            var score = scores[relay] ?? RelayScore(successes: 1, failures: 1) // Beta(1,1) prior
            score.successes += hits
            score.failures += misses
            scores[relay] = score
            lastSeenDates[relay] = now
        }

        // Drain all cycle buffers, not just requested relays — prevents stale
        // hits from surviving no-request windows and being misattributed later
        for (_, relayStats) in connectionStats {
            relayStats.receivedPubkeysThisCycle = []
        }

        persist()
    }

    // MARK: - Beta Sampling

    /// Sample from Beta(successes+1, failures+1) distribution using Marsaglia-Tsang gamma method.
    /// Output is clamped to [0.01, 1.0] to prevent NaN/Inf from propagating.
    static func sampleBeta(successes: Int, failures: Int) -> Double {
        let alpha = Double(max(successes, 0)) + 1.0
        let beta = Double(max(failures, 0)) + 1.0
        let x = sampleGamma(shape: alpha)
        let y = sampleGamma(shape: beta)
        let sum = x + y
        guard sum > 0 else { return 0.5 } // Fallback for degenerate case
        let result = x / sum
        return min(max(result, 0.01), 1.0)
    }

    /// Marsaglia-Tsang method for sampling from Gamma(shape, 1) distribution.
    private static func sampleGamma(shape: Double) -> Double {
        if shape < 1.0 {
            // For shape < 1, use the transformation: Gamma(a) = Gamma(a+1) * U^(1/a)
            let u = Double.random(in: 0.0..<1.0)
            return sampleGamma(shape: shape + 1.0) * pow(u, 1.0 / shape)
        }

        let d = shape - 1.0 / 3.0
        let c = 1.0 / sqrt(9.0 * d)

        while true {
            var x: Double
            var v: Double
            repeat {
                x = sampleStandardNormal()
                v = 1.0 + c * x
            } while v <= 0

            v = v * v * v
            let u = Double.random(in: 0.0..<1.0)

            if u < 1.0 - 0.0331 * (x * x) * (x * x) {
                return d * v
            }
            if log(u) < 0.5 * x * x + d * (1.0 - v + log(v)) {
                return d * v
            }
        }
    }

    /// Box-Muller transform for standard normal sampling.
    private static func sampleStandardNormal() -> Double {
        let u1 = Double.random(in: Double.leastNonzeroMagnitude..<1.0)
        let u2 = Double.random(in: 0.0..<1.0)
        return sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
    }
}
