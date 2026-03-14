//
//  StochasticRelayPlanner.swift
//  Nostur
//
//  Stochastic relay assignment for outbox model.
//  Replaces deterministic `createRequestPlan(skipTopRelays: 3)` with randomized scoring
//  to spread load across relays and avoid permanently skipping any relay.
//

import Foundation
import NostrEssentials

struct RelayAssignment {
    let relayUrl: String
    let pubkeys: Set<String>
}

/// Assigns pubkeys to relays using stochastic scoring.
///
/// For each candidate relay (excluding our own read relays), computes:
///   score = intersectionCount * random(0.01...1.0)
/// then greedily assigns pubkeys to the highest-scoring relay that covers them,
/// with deduplication (each pubkey assigned to exactly one relay).
///
/// - Parameters:
///   - findEventsRelays: From `PreferredRelays.findEventsRelays` — `[relayUrl: Set<pubkey>]`
///   - pubkeys: The set of pubkeys we want events from
///   - ourReadRelays: Our own read relay URLs (excluded from outbox assignments)
///   - aliveRelays: Optional set of relays known to be online (NIP-66). When provided, dead relays are filtered out.
/// - Returns: Array of `RelayAssignment` — relay URL + the pubkeys assigned to it
func stochasticRelayAssignment(
    findEventsRelays: [String: Set<String>],
    pubkeys: Set<String>,
    ourReadRelays: Set<String>,
    aliveRelays: Set<String>? = nil
) -> [RelayAssignment] {
    guard !pubkeys.isEmpty else { return [] }

    // Single-pubkey special case: deterministic, first 2 relays (matching NostrEssentials behavior)
    if pubkeys.count == 1 {
        let thePubkey = pubkeys.first!
        var assignments: [RelayAssignment] = []

        let candidates = findEventsRelays
            .filter { !ourReadRelays.contains($0.key) }
            .filter { $0.value.contains(thePubkey) }
            .sorted { $0.value.count > $1.value.count }

        for (relay, _) in candidates.prefix(2) {
            assignments.append(RelayAssignment(relayUrl: relay, pubkeys: pubkeys))
        }
        return assignments
    }

    // Multi-pubkey: stochastic scoring

    // Step 1: Build candidate list (exclude our own read relays, keep only relays with relevant pubkeys)
    var candidates: [(relay: String, relevantPubkeys: Set<String>)] = findEventsRelays
        .filter { !ourReadRelays.contains($0.key) }
        .compactMap { (relay, relayPubkeys) in
            let intersection = relayPubkeys.intersection(pubkeys)
            guard !intersection.isEmpty else { return nil }
            return (relay, intersection)
        }

    // Step 2: NIP-66 liveness filter (when available)
    if let aliveRelays, !aliveRelays.isEmpty {
        let filtered = candidates.filter { candidate in
            // Preserve .onion relays (can't validate without Tor)
            if candidate.relay.contains(".onion") { return true }
            return aliveRelays.contains(candidate.relay)
        }

        // Safety valve: if filtering would remove >80% of candidates, skip it
        let removalRatio = 1.0 - (Double(filtered.count) / Double(max(candidates.count, 1)))
        if removalRatio <= 0.8 {
            candidates = filtered
        }
    }

    // Step 3: Score and sort stochastically
    let scored: [(relay: String, relevantPubkeys: Set<String>, score: Double)] = candidates.map { candidate in
        let intersectionCount = Double(candidate.relevantPubkeys.count)
        let randomFactor = Double.random(in: 0.01...1.0)
        let score = intersectionCount * randomFactor
        return (candidate.relay, candidate.relevantPubkeys, score)
    }
    .sorted { $0.score > $1.score }

    // Step 4: Greedy assignment with dedup
    var pubkeysAccountedFor: Set<String> = []
    var assignments: [RelayAssignment] = []

    for item in scored {
        let unassigned = item.relevantPubkeys.subtracting(pubkeysAccountedFor)
        guard !unassigned.isEmpty else { continue }

        assignments.append(RelayAssignment(relayUrl: item.relay, pubkeys: unassigned))
        pubkeysAccountedFor.formUnion(unassigned)
    }

    return assignments
}
