//
//  StochasticRelayPlannerTests.swift
//  NosturTests
//

import Foundation
import Testing
@testable import Nostur

struct StochasticRelayPlannerTests {

    // MARK: - Commit 1: Stochastic Relay Scoring

    @Test func testEmptyInputReturnsEmpty() {
        let result = stochasticRelayAssignment(
            findEventsRelays: [:],
            pubkeys: [],
            ourReadRelays: []
        )
        #expect(result.isEmpty)
    }

    @Test func testEmptyPubkeysReturnsEmpty() {
        let result = stochasticRelayAssignment(
            findEventsRelays: ["wss://relay.example.com": Set(["pk1", "pk2"])],
            pubkeys: [],
            ourReadRelays: []
        )
        #expect(result.isEmpty)
    }

    @Test func testSinglePubkeyGetsTwoRelays() {
        let findEventsRelays: [String: Set<String>] = [
            "wss://relay-a.com": Set(["pk1", "pk2", "pk3"]),
            "wss://relay-b.com": Set(["pk1", "pk4"]),
            "wss://relay-c.com": Set(["pk1"]),
        ]

        let result = stochasticRelayAssignment(
            findEventsRelays: findEventsRelays,
            pubkeys: Set(["pk1"]),
            ourReadRelays: []
        )

        // Single pubkey should get at most 2 relays
        #expect(result.count <= 2)
        #expect(result.count >= 1)

        // All assignments should contain pk1
        for assignment in result {
            #expect(assignment.pubkeys.contains("pk1"))
        }

        // Should be deterministic for single pubkey: sorted by relay size, so relay-a first
        #expect(result[0].relayUrl == "wss://relay-a.com")
        if result.count == 2 {
            #expect(result[1].relayUrl == "wss://relay-b.com")
        }
    }

    @Test func testOurReadRelaysExcluded() {
        let findEventsRelays: [String: Set<String>] = [
            "wss://our-relay.com": Set(["pk1", "pk2"]),
            "wss://other-relay.com": Set(["pk1"]),
        ]

        let result = stochasticRelayAssignment(
            findEventsRelays: findEventsRelays,
            pubkeys: Set(["pk1", "pk2"]),
            ourReadRelays: Set(["wss://our-relay.com"])
        )

        // Our relay should be excluded
        let relayUrls = Set(result.map { $0.relayUrl })
        #expect(!relayUrls.contains("wss://our-relay.com"))
    }

    @Test func testAllPubkeysCovered() {
        let findEventsRelays: [String: Set<String>] = [
            "wss://relay-a.com": Set(["pk1", "pk2", "pk3"]),
            "wss://relay-b.com": Set(["pk2", "pk4"]),
            "wss://relay-c.com": Set(["pk3", "pk5"]),
        ]
        let requestedPubkeys: Set<String> = Set(["pk1", "pk2", "pk3", "pk4", "pk5"])

        let result = stochasticRelayAssignment(
            findEventsRelays: findEventsRelays,
            pubkeys: requestedPubkeys,
            ourReadRelays: []
        )

        let coveredPubkeys = result.reduce(into: Set<String>()) { $0.formUnion($1.pubkeys) }
        #expect(coveredPubkeys == requestedPubkeys, "All requested pubkeys should be covered")
    }

    @Test func testNoPubkeyDuplicatedAcrossRelays() {
        let findEventsRelays: [String: Set<String>] = [
            "wss://relay-a.com": Set(["pk1", "pk2", "pk3"]),
            "wss://relay-b.com": Set(["pk2", "pk3", "pk4"]),
            "wss://relay-c.com": Set(["pk3", "pk4", "pk5"]),
        ]

        let result = stochasticRelayAssignment(
            findEventsRelays: findEventsRelays,
            pubkeys: Set(["pk1", "pk2", "pk3", "pk4", "pk5"]),
            ourReadRelays: []
        )

        // Check no pubkey appears in more than one assignment
        var seen: Set<String> = []
        for assignment in result {
            let overlap = seen.intersection(assignment.pubkeys)
            #expect(overlap.isEmpty, "Pubkey(s) \(overlap) duplicated across relays")
            seen.formUnion(assignment.pubkeys)
        }
    }

    @Test func testStochasticVariability() {
        let findEventsRelays: [String: Set<String>] = [
            "wss://relay-a.com": Set(["pk1", "pk2", "pk3", "pk4", "pk5"]),
            "wss://relay-b.com": Set(["pk1", "pk2", "pk3", "pk4"]),
            "wss://relay-c.com": Set(["pk1", "pk2", "pk3"]),
            "wss://relay-d.com": Set(["pk1", "pk2"]),
        ]
        let requestedPubkeys: Set<String> = Set(["pk1", "pk2", "pk3", "pk4", "pk5"])

        // Run 50 times and collect the first relay chosen each time
        var firstRelays: Set<String> = []
        for _ in 0..<50 {
            let result = stochasticRelayAssignment(
                findEventsRelays: findEventsRelays,
                pubkeys: requestedPubkeys,
                ourReadRelays: []
            )
            if let first = result.first {
                firstRelays.insert(first.relayUrl)
            }
        }

        // With stochastic scoring, we should see more than 1 distinct first relay over 50 runs
        #expect(firstRelays.count > 1, "Stochastic scoring should produce varied relay ordering")
    }

    @Test func testUnroutablePubkeysNotInResult() {
        // pk_orphan is not in any relay's pubkey set
        let findEventsRelays: [String: Set<String>] = [
            "wss://relay-a.com": Set(["pk1"]),
        ]

        let result = stochasticRelayAssignment(
            findEventsRelays: findEventsRelays,
            pubkeys: Set(["pk1", "pk_orphan"]),
            ourReadRelays: []
        )

        let coveredPubkeys = result.reduce(into: Set<String>()) { $0.formUnion($1.pubkeys) }
        #expect(coveredPubkeys.contains("pk1"))
        #expect(!coveredPubkeys.contains("pk_orphan"), "Unroutable pubkey should not appear in assignments")
    }

    // MARK: - Commit 2: NIP-66 Liveness Filter

    @Test func testAliveRelaysFiltersCandidates() {
        let findEventsRelays: [String: Set<String>] = [
            "wss://alive-relay.com": Set(["pk1", "pk2"]),
            "wss://dead-relay.com": Set(["pk1", "pk3"]),
            "wss://also-alive.com": Set(["pk3"]),
        ]
        let aliveRelays: Set<String> = Set(["wss://alive-relay.com", "wss://also-alive.com"])

        let result = stochasticRelayAssignment(
            findEventsRelays: findEventsRelays,
            pubkeys: Set(["pk1", "pk2", "pk3"]),
            ourReadRelays: [],
            aliveRelays: aliveRelays
        )

        let relayUrls = Set(result.map { $0.relayUrl })
        #expect(!relayUrls.contains("wss://dead-relay.com"), "Dead relay should be filtered out")
    }

    @Test func testNilAliveRelaysSkipsFilter() {
        let findEventsRelays: [String: Set<String>] = [
            "wss://relay-a.com": Set(["pk1"]),
            "wss://relay-b.com": Set(["pk2"]),
        ]

        let result = stochasticRelayAssignment(
            findEventsRelays: findEventsRelays,
            pubkeys: Set(["pk1", "pk2"]),
            ourReadRelays: [],
            aliveRelays: nil
        )

        let coveredPubkeys = result.reduce(into: Set<String>()) { $0.formUnion($1.pubkeys) }
        #expect(coveredPubkeys == Set(["pk1", "pk2"]), "With nil aliveRelays, all relays should be used")
    }

    @Test func testSafetyValveSkipsOverAggressiveFilter() {
        // 10 relays, but aliveRelays only contains 1 → would remove >80%, so safety valve should skip filtering
        var findEventsRelays: [String: Set<String>] = [:]
        for i in 1...10 {
            findEventsRelays["wss://relay-\(i).com"] = Set(["pk\(i)"])
        }
        let requestedPubkeys = Set((1...10).map { "pk\($0)" })
        let aliveRelays: Set<String> = Set(["wss://relay-1.com"]) // Only 1 of 10 alive

        let result = stochasticRelayAssignment(
            findEventsRelays: findEventsRelays,
            pubkeys: requestedPubkeys,
            ourReadRelays: [],
            aliveRelays: aliveRelays
        )

        let coveredPubkeys = result.reduce(into: Set<String>()) { $0.formUnion($1.pubkeys) }
        // Safety valve should preserve all relays since >80% would be removed
        #expect(coveredPubkeys == requestedPubkeys, "Safety valve should skip over-aggressive filtering")
    }

    @Test func testOnionRelaysPreservedByLivenessFilter() {
        let findEventsRelays: [String: Set<String>] = [
            "wss://normal-relay.com": Set(["pk1"]),
            "wss://hidden.onion": Set(["pk2"]),
        ]
        let aliveRelays: Set<String> = Set(["wss://normal-relay.com"]) // onion not in alive set

        let result = stochasticRelayAssignment(
            findEventsRelays: findEventsRelays,
            pubkeys: Set(["pk1", "pk2"]),
            ourReadRelays: [],
            aliveRelays: aliveRelays
        )

        let relayUrls = Set(result.map { $0.relayUrl })
        #expect(relayUrls.contains("wss://hidden.onion"), ".onion relays should be preserved regardless of liveness data")
    }
}
