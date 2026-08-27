//
//  NotificationNeedsUpdateTests.swift
//  NosturTests
//

import Testing
@testable import Nostur

struct NotificationNeedsUpdateTests {

    @Test func unrelatedKind1DoesNotClearPendingReactionUpdate() {
        let afterReaction = NotificationsViewModel.mergeNeedsUpdate(
            current: true,
            eventIsNotification: false
        )

        #expect(afterReaction.needsUpdate)
        #expect(!afterReaction.shouldCheckNow)
    }

    @Test func firstRelevantReactionArmsImmediateCheck() {
        let firstReaction = NotificationsViewModel.mergeNeedsUpdate(
            current: false,
            eventIsNotification: true
        )

        #expect(firstReaction.needsUpdate)
        #expect(firstReaction.shouldCheckNow)
    }

    @Test func laterRelevantEventsWaitForTheTimer() {
        let laterReaction = NotificationsViewModel.mergeNeedsUpdate(
            current: true,
            eventIsNotification: true
        )

        #expect(laterReaction.needsUpdate)
        #expect(!laterReaction.shouldCheckNow)
    }

    @Test func unrelatedEventsLeaveTheFlagOff() {
        let unrelated = NotificationsViewModel.mergeNeedsUpdate(
            current: false,
            eventIsNotification: false
        )

        #expect(!unrelated.needsUpdate)
        #expect(!unrelated.shouldCheckNow)
    }
}
