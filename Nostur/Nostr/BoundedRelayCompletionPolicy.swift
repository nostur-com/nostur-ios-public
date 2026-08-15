//
//  BoundedRelayCompletionPolicy.swift
//  Nostur
//
//  Release the loading bar when the live wave is done enough. Relays that
//  never connected are not in play and must not hold the bar or promote
//  the whole fetch to the long deadline.
//

import Foundation

struct BoundedRelayCompletionPolicy {
    static let extraQuorumFraction = 0.8
    static let extraQuorumMinimum = 3

    let coreIds: Set<CanonicalRelayUrl>
    let extraIds: Set<CanonicalRelayUrl>
    let connectedIds: Set<CanonicalRelayUrl>

    var knownIds: Set<CanonicalRelayUrl> {
        coreIds.union(extraIds)
    }

    /// Short deadline as soon as any targeted relay is already up.
    var usesShortDeadline: Bool {
        !connectedIds.intersection(knownIds).isEmpty
    }

    func inPlayIds(finished: Set<CanonicalRelayUrl>) -> Set<CanonicalRelayUrl> {
        // Silent connected extras must not inflate the wait set. They often
        // already have this catch-up sub id locally and never get a new REQ.
        let connectedCore = connectedIds.intersection(coreIds)
        return connectedCore.union(finished.intersection(knownIds))
    }

    func shouldFinish(finished: Set<CanonicalRelayUrl>) -> Bool {
        let inPlay = inPlayIds(finished: finished)
        guard !inPlay.isEmpty else { return false }
        return inPlay.intersection(finished).count >= Self.extraQuorum(for: inPlay.count)
    }

    func unreachableExtras(finished: Set<CanonicalRelayUrl>) -> Set<CanonicalRelayUrl> {
        extraIds.subtracting(connectedIds).subtracting(finished)
    }

    static func extraQuorum(for extraCount: Int) -> Int {
        guard extraCount > 0 else { return 0 }
        let proportional = Int(ceil(Double(extraCount) * extraQuorumFraction))
        return min(extraCount, max(extraQuorumMinimum, proportional))
    }
}
