//
//  NXAlreadySeenNewerPosts.swift
//  Nostur
//

import Foundation

struct NXAlreadySeenNewerPostCandidate: Hashable, Sendable {
    let id: String
    let createdAt: Int64
}

enum NXAlreadySeenNewerPosts {
    static let staleFeedInterval: TimeInterval = 30 * 60

    static func candidateIDs(
        from candidates: [NXAlreadySeenNewerPostCandidate],
        visibleCreatedAt: [Int64],
        excludingIDs: Set<String> = [],
        now: Date = Date()
    ) -> [String] {
        guard let newestVisibleCreatedAt = visibleCreatedAt.max(),
              Date(timeIntervalSince1970: TimeInterval(newestVisibleCreatedAt))
                < now.addingTimeInterval(-staleFeedInterval)
        else {
            return []
        }

        return candidates
            .filter {
                $0.createdAt > newestVisibleCreatedAt
                    && !excludingIDs.contains($0.id)
            }
            .sorted { $0.createdAt > $1.createdAt }
            .map(\.id)
    }
}
