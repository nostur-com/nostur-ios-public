import Foundation
import Testing
@testable import Nostur

@Suite("Outbox relay-list refresh policy")
struct OutboxRefreshPolicyTests {
    @Test("Missing authors exclude locally stored relay lists")
    func missingAuthors() {
        let all: Set<String> = ["alice", "bob", "carol"]
        let stored: Set<String> = ["alice", "carol", "unrelated"]

        #expect(OutboxRefreshPolicy.missingAuthors(allAuthors: all, storedAuthors: stored) == ["bob"])
    }

    @Test("Authors are split into bounded batches without loss")
    func batches() {
        let authors = Set((0..<361).map { "author-\($0)" })
        let batches = OutboxRefreshPolicy.batches(from: authors, size: 150)

        #expect(batches.map(\.count) == [150, 150, 61])
        #expect(batches.reduce(into: Set<String>()) { $0.formUnion($1) } == authors)
    }

    @Test("Audit becomes due after one day")
    func auditInterval() {
        let now = Date(timeIntervalSince1970: 200_000)

        #expect(OutboxRefreshPolicy.shouldAudit(lastAttempt: nil, now: now))
        #expect(!OutboxRefreshPolicy.shouldAudit(lastAttempt: now.addingTimeInterval(-23 * 60 * 60), now: now))
        #expect(OutboxRefreshPolicy.shouldAudit(lastAttempt: now.addingTimeInterval(-25 * 60 * 60), now: now))
    }
}
