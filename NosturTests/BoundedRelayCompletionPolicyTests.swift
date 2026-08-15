import Foundation
import Testing
@testable import Nostur

@Suite("Bounded relay completion policy")
struct BoundedRelayCompletionPolicyTests {
    @Test("A fast majority finishes without silent connected extras")
    func fiftyThreeOfSixtySixFinishes() {
        var extraIds = Set<CanonicalRelayUrl>()
        var connected = Set<CanonicalRelayUrl>(["wss://core.one"])
        var finished = Set<CanonicalRelayUrl>(["wss://core.one"])
        for index in 1...65 {
            extraIds.insert("wss://extra.\(index)")
            connected.insert("wss://extra.\(index)")
        }
        for index in 1...52 {
            finished.insert("wss://extra.\(index)")
        }

        let policy = BoundedRelayCompletionPolicy(
            coreIds: ["wss://core.one"],
            extraIds: extraIds,
            connectedIds: connected
        )

        #expect(policy.usesShortDeadline)
        #expect(policy.shouldFinish(finished: finished))
        #expect(!policy.inPlayIds(finished: finished).contains("wss://extra.65"))
    }

    @Test("Silent connected extras do not stay in play")
    func silentConnectedExtrasAreNotInPlay() {
        let policy = BoundedRelayCompletionPolicy(
            coreIds: ["wss://core.one"],
            extraIds: ["wss://extra.fast", "wss://extra.silent"],
            connectedIds: ["wss://core.one", "wss://extra.fast", "wss://extra.silent"]
        )

        let finished: Set<CanonicalRelayUrl> = ["wss://core.one", "wss://extra.fast"]
        #expect(!policy.inPlayIds(finished: finished).contains("wss://extra.silent"))
        #expect(policy.shouldFinish(finished: finished))
    }

    @Test("Unconnected extras never enter the in-play set")
    func unconnectedExtrasAreIgnored() {
        let policy = BoundedRelayCompletionPolicy(
            coreIds: ["wss://core.one"],
            extraIds: ["wss://extra.fast", "wss://extra.dead"],
            connectedIds: ["wss://core.one", "wss://extra.fast"]
        )

        #expect(!policy.inPlayIds(finished: ["wss://core.one", "wss://extra.fast"]).contains("wss://extra.dead"))
        #expect(policy.shouldFinish(finished: ["wss://core.one", "wss://extra.fast"]))
        #expect(policy.unreachableExtras(finished: ["wss://core.one", "wss://extra.fast"]) == ["wss://extra.dead"])
    }

    @Test("Unconnected core relays do not force the long deadline")
    func unconnectedCoreDoesNotForceLongDeadline() {
        let policy = BoundedRelayCompletionPolicy(
            coreIds: ["wss://core.up", "wss://core.down"],
            extraIds: ["wss://extra.one"],
            connectedIds: ["wss://core.up"]
        )

        #expect(policy.usesShortDeadline)
        #expect(policy.shouldFinish(finished: ["wss://core.up"]))
    }

    @Test("Long deadline only when nothing targeted is connected")
    func longDeadlineWhenNothingIsUp() {
        let policy = BoundedRelayCompletionPolicy(
            coreIds: ["wss://core.one"],
            extraIds: ["wss://extra.one"],
            connectedIds: []
        )

        #expect(!policy.usesShortDeadline)
        #expect(!policy.shouldFinish(finished: []))
        #expect(policy.shouldFinish(finished: ["wss://core.one"]))
    }
}
