//
//  FeedFetchSchedulerTests.swift
//  NosturTests
//

import Foundation
import Testing
@testable import Nostur

@MainActor
@Suite(.serialized)
struct FeedFetchSchedulerTests {
    
    @Test func singleColumnStartsImmediatelyWithoutSlotDelay() async {
        let scheduler = makeScheduler()
        defer { scheduler.shutdown() }
        var slept: [TimeInterval] = []
        scheduler.sleepHandler = { duration in
            slept.append(duration)
        }
        
        let column = MockFeedColumn()
        scheduler.register(column)
        
        var started = false
        scheduler.scheduleNetworkStart(id: column.columnScheduleId) {
            started = true
        }
        await scheduler.waitForScheduledWork()
        
        #expect(started)
        #expect(slept.isEmpty)
        #expect(scheduler.fetchLoopInterval == FETCH_FEED_INTERVAL)
    }
    
    @Test func multipleColumnsResumeOneAtATimeFollowingFirst() async {
        let scheduler = makeScheduler()
        defer { scheduler.shutdown() }
        var slept: [TimeInterval] = []
        scheduler.sleepHandler = { duration in
            slept.append(duration)
        }
        
        let following = MockFeedColumn(prefersFirst: true)
        let listA = MockFeedColumn()
        let listB = MockFeedColumn()
        var order: [UUID] = []
        following.onResume = { order.append(following.columnScheduleId) }
        listA.onResume = { order.append(listA.columnScheduleId) }
        listB.onResume = { order.append(listB.columnScheduleId) }
        
        scheduler.register(listA)
        scheduler.register(following)
        scheduler.register(listB)
        
        scheduler.resumeAll()
        await scheduler.waitForScheduledWork()
        
        #expect(order == [following.columnScheduleId, listA.columnScheduleId, listB.columnScheduleId])
        #expect(following.resumeCount == 1)
        #expect(listA.resumeCount == 1)
        #expect(listB.resumeCount == 1)
        #expect(slept == [scheduler.collectInterval, scheduler.slotInterval, scheduler.slotInterval])
        #expect(scheduler.fetchLoopInterval == FETCH_FEED_INTERVAL / 3)
    }
    
    @Test func resumeAllCoalescesWhileAPassIsQueued() async {
        let scheduler = makeScheduler()
        defer { scheduler.shutdown() }
        scheduler.sleepHandler = { _ in }
        
        let column = MockFeedColumn()
        scheduler.register(column)
        
        scheduler.resumeAll()
        scheduler.resumeAll()
        scheduler.resumeAll()
        await scheduler.waitForScheduledWork()
        
        #expect(column.resumeCount == 1)
    }
    
    @Test func fetchLoopRotatesOneColumnPerTick() {
        let scheduler = makeScheduler()
        defer { scheduler.shutdown() }
        
        let first = MockFeedColumn()
        let second = MockFeedColumn()
        scheduler.register(first)
        scheduler.register(second)
        
        scheduler.tickNextColumn()
        scheduler.tickNextColumn()
        scheduler.tickNextColumn()
        
        #expect(first.tickCount == 2)
        #expect(second.tickCount == 1)
    }
    
    @Test func pausedColumnsAreSkippedByFetchLoop() {
        let scheduler = makeScheduler()
        defer { scheduler.shutdown() }
        
        let active = MockFeedColumn()
        let paused = MockFeedColumn()
        paused.isPausedForScheduling = true
        scheduler.register(active)
        scheduler.register(paused)
        
        scheduler.tickNextColumn()
        scheduler.tickNextColumn()
        
        #expect(active.tickCount == 2)
        #expect(paused.tickCount == 0)
    }
    
    @Test func unregisterDropsColumnFromRotation() {
        let scheduler = makeScheduler()
        defer { scheduler.shutdown() }
        
        let first = MockFeedColumn()
        let second = MockFeedColumn()
        scheduler.register(first)
        scheduler.register(second)
        scheduler.unregister(first)
        
        scheduler.tickNextColumn()
        scheduler.tickNextColumn()
        
        #expect(first.tickCount == 0)
        #expect(second.tickCount == 2)
        #expect(scheduler.visibleColumnCount == 1)
        #expect(scheduler.fetchLoopInterval == FETCH_FEED_INTERVAL)
    }
    
    private func makeScheduler() -> FeedFetchScheduler {
        let scheduler = FeedFetchScheduler()
        scheduler.startsFetchLoop = false
        scheduler.collectInterval = 0.01
        scheduler.slotInterval = 0.02
        scheduler.resumeAllCooldown = 8
        return scheduler
    }
}

@MainActor
private final class MockFeedColumn: FeedColumnScheduling {
    let columnScheduleId = UUID()
    let prefersFirstInRotation: Bool
    var isPausedForScheduling = false
    var resumeCount = 0
    var tickCount = 0
    var onResume: (() -> Void)?
    
    init(prefersFirst: Bool = false) {
        prefersFirstInRotation = prefersFirst
    }
    
    func scheduledResume() {
        resumeCount += 1
        onResume?()
    }
    
    func scheduledFetchTick() {
        tickCount += 1
    }
}
