import XCTest
@testable import Nostur

final class BrowserActionPermissionsTests: XCTestCase {
    func testTodayExpiresAtCalendarMidnightAndGrantsAreScopedAndRevocable() throws {
        let name = "browser.action-permissions.test." + UUID().uuidString
        let prefs = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { prefs.removePersistentDomain(forName: name) }
        let permissions = BrowserActionPermissions(preferences: prefs)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Amsterdam"))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 12)))
        let midnight = try XCTUnwrap(calendar.dateInterval(of: .day, for: today)?.end)
        permissions.allow(kind: 3, account: "account-a", origin: "https://one.test", duration: .today, now: today, calendar: calendar)
        XCTAssertEqual(permissions.grants(account: "account-a", origin: "https://one.test", now: today).first?.expiresAt, midnight)
        XCTAssertTrue(permissions.grants(account: "account-b", origin: "https://one.test", now: today).isEmpty)
        XCTAssertTrue(permissions.grants(account: "account-a", origin: "https://two.test", now: today).isEmpty)
        XCTAssertTrue(permissions.grants(account: "account-a", origin: "https://one.test", now: midnight).isEmpty)
        permissions.allow(kind: 10002, account: "account-a", origin: "https://one.test", duration: .always, now: today)
        let reopened = BrowserActionPermissions(preferences: prefs)
        XCTAssertEqual(reopened.grants(account: "account-a", origin: "https://one.test", now: midnight).map(\.kind), [10002])
        permissions.revoke(kind: 10002, account: "account-a", origin: "https://one.test")
        XCTAssertTrue(reopened.grants(account: "account-a", origin: "https://one.test", now: midnight).isEmpty)
    }

    func testGrantsNeverBypassInputProtocolOrProtectedKindChecks() {
        let now: Int64 = 1_800_000_000
        func reject(_ event: BrowserUnsignedEvent, grants: Set<Int>) -> String? {
            BrowserSigningPolicy.rejection(for: event, origin: "https://primal.net", social: false, allowedKinds: grants, now: now)
        }
        let following = BrowserUnsignedEvent(created_at: now, kind: 3, tags: [], content: "")
        XCTAssertNil(reject(following, grants: [3]))
        XCTAssertNotNil(reject(following, grants: [10002]))
        for kind in [4, 13, 14, 1059, 24133, 22242, 65535] {
            XCTAssertFalse(BrowserSigningPolicy.canGrant(kind))
            XCTAssertNotNil(reject(BrowserUnsignedEvent(created_at: now, kind: kind, tags: [], content: ""), grants: [kind]))
        }
        let auth = BrowserUnsignedEvent(created_at: now, kind: 27235, tags: [["u", "https://service.example/upload"], ["method", "POST"]], content: "")
        XCTAssertNil(reject(auth, grants: [27235]))
        let badAuth = BrowserUnsignedEvent(created_at: now, kind: 27235, tags: [["u", "http://service.example/upload"], ["method", "DELETE"]], content: "")
        XCTAssertNotNil(reject(badAuth, grants: [27235]))
        let upload = BrowserUnsignedEvent(created_at: now, kind: 24242,
            tags: [["t", "upload"], ["x", String(repeating: "a", count: 64)], ["expiration", String(now + 300)]], content: "")
        XCTAssertNil(reject(upload, grants: [24242]))
        let deletion = BrowserUnsignedEvent(created_at: now, kind: 24242,
            tags: [["t", "delete"], ["x", String(repeating: "a", count: 64)], ["expiration", String(now + 300)]], content: "")
        XCTAssertNotNil(reject(deletion, grants: [24242]))
        XCTAssertNotNil(reject(BrowserUnsignedEvent(created_at: now, kind: 3, tags: [], content: String(repeating: "a", count: 65537)), grants: [3]))
        XCTAssertNotNil(reject(BrowserUnsignedEvent(created_at: now, kind: 3, tags: [["delegation", "key"]], content: ""), grants: [3]))
        XCTAssertNotNil(reject(BrowserUnsignedEvent(created_at: now - 301, kind: 3, tags: [], content: ""), grants: [3]))
    }
}
