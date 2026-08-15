import Foundation
import Testing
@testable import Nostur

@Suite("Relay config health")
struct RelayConfigHealthTests {
    @Test("Notification is created only when more than 8 read relays and none exists")
    func createsWhenOverThresholdAndMissing() {
        #expect(RelayConfigHealth.shouldCreateNotification(readCount: 9, hasExisting: false))
        #expect(!RelayConfigHealth.shouldCreateNotification(readCount: 8, hasExisting: false))
        #expect(!RelayConfigHealth.shouldCreateNotification(readCount: 22, hasExisting: true))
        #expect(!RelayConfigHealth.shouldCreateNotification(readCount: 0, hasExisting: false))
        #expect(!RelayConfigHealth.shouldCreateNotification(readCount: 22, hasExisting: false, isSnoozed: true))
    }
    
    @Test("Compact banner stays hidden while snoozed, Relays screen banner is independent")
    func compactBannerRespectsSnooze() {
        #expect(RelayConfigHealth.shouldShowCompactBanner(receiveCount: 13, isSnoozed: false))
        #expect(!RelayConfigHealth.shouldShowCompactBanner(receiveCount: 13, isSnoozed: true))
        #expect(!RelayConfigHealth.shouldShowCompactBanner(receiveCount: 8, isSnoozed: false))
    }
    
    @Test("Snooze lasts one month")
    func snoozeLastsOneMonth() {
        let now = Date(timeIntervalSince1970: 1_776_268_800) // 2026-04-15
        let until = RelayConfigHealth.snoozeUntilDate(from: now)
        let monthLater = Calendar.current.date(byAdding: .month, value: 1, to: now)
        #expect(until == monthLater)
        
        let defaults = UserDefaults(suiteName: "RelayConfigHealthTests.snooze")!
        defaults.removePersistentDomain(forName: "RelayConfigHealthTests.snooze")
        defaults.set(until.timeIntervalSince1970, forKey: RelayConfigHealth.snoozedUntilKey)
        #expect(RelayConfigHealth.isSnoozed(now: now, defaults: defaults))
        #expect(RelayConfigHealth.isSnoozed(now: until.addingTimeInterval(-1), defaults: defaults))
        #expect(!RelayConfigHealth.isSnoozed(now: until, defaults: defaults))
        defaults.removePersistentDomain(forName: "RelayConfigHealthTests.snooze")
    }
    
    @Test("Existing notification is removed once read relays are back within the limit")
    func removesWhenAtOrUnderThreshold() {
        #expect(RelayConfigHealth.shouldRemoveNotification(readCount: 8, hasExisting: true))
        #expect(RelayConfigHealth.shouldRemoveNotification(readCount: 0, hasExisting: true))
        #expect(!RelayConfigHealth.shouldRemoveNotification(readCount: 9, hasExisting: true))
        #expect(!RelayConfigHealth.shouldRemoveNotification(readCount: 8, hasExisting: false))
    }
    
    @Test("Settings Relays screen only shows the banner while not optimal")
    func detailBannerHiddenWhenAlreadyGoodUnlessOpenedFromNotification() {
        #expect(RelayConfigHealth.shouldShowDetailBanner(isNotOptimal: true, showsWhenGood: false))
        #expect(!RelayConfigHealth.shouldShowDetailBanner(isNotOptimal: false, showsWhenGood: false))
        #expect(RelayConfigHealth.shouldShowDetailBanner(isNotOptimal: false, showsWhenGood: true))
    }
    
    @Test("Looks good at the recommended 2-5 receive relays, not above")
    func looksGoodWithinRecommendedRange() {
        #expect(RelayConfigHealth.looksGood(receiveCount: 5))
        #expect(RelayConfigHealth.looksGood(receiveCount: 4))
        #expect(RelayConfigHealth.looksGood(receiveCount: 2))
        #expect(!RelayConfigHealth.looksGood(receiveCount: 6))
        #expect(!RelayConfigHealth.looksGood(receiveCount: 22))
    }
}
