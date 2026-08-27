//
//  NXRememberOnCatchUpTests.swift
//  NosturTests
//

import Testing
@testable import Nostur

struct NXRememberOnCatchUpTests {

    @Test func twoDayOldSinceOpensTheLast24HoursWithNoUntil() {
        let now: Int64 = 1_800_000_000
        let twoDaysAgo = now - 172_800
        let range = NXRememberOnCatchUp.requestRange(since: twoDaysAgo, now: now)

        #expect(range.since == Int(now) - 86_400)
        #expect(range.until == nil)
    }

    @Test func recentSinceIsKeptAndStillHasNoUntil() {
        let now: Int64 = 1_800_000_000
        let oneHourAgo = now - 3_600
        let range = NXRememberOnCatchUp.requestRange(since: oneHourAgo, now: now)

        #expect(range.since == Int(oneHourAgo))
        #expect(range.until == nil)
    }

    @Test func fourHourSliceStartingAtSinceIsNotUsed() {
        let now: Int64 = 1_800_000_000
        let twentyFourHoursAgo = now - 86_400
        let range = NXRememberOnCatchUp.requestRange(since: twentyFourHoursAgo, now: now)

        #expect(range.since == Int(twentyFourHoursAgo))
        #expect(range.until != Int(twentyFourHoursAgo) + 4 * 3600)
        #expect(range.until == nil)
    }
}
