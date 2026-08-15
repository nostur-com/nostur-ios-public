//
//  FeedFetchScheduler.swift
//  Nostur
//
//  Rotates network work across visible columns so Mac multi-column
//  layouts don't REQ every feed at once. A single visible column
//  (iPhone / iPad) is scheduled immediately with no stagger.
//

import Foundation

@MainActor
protocol FeedColumnScheduling: AnyObject {
    var columnScheduleId: UUID { get }
    var prefersFirstInRotation: Bool { get }
    var isPausedForScheduling: Bool { get }
    func scheduledResume()
    func scheduledFetchTick()
}

@MainActor
final class FeedFetchScheduler {
    var slotInterval: TimeInterval = 1.0
    var collectInterval: TimeInterval = 0.15
    var fullCycleInterval: TimeInterval = FETCH_FEED_INTERVAL
    var resumeAllCooldown: TimeInterval = 8.0
    var startsFetchLoop = true
    /// Mac multi-column launch can register siblings a moment after the first
    /// start is queued. iPhone/iPad stay false so a single column is not delayed.
    var usesDesktopCollectWindow = false
    var sleepHandler: (TimeInterval) async -> Void = { duration in
        let nanoseconds = UInt64(max(duration, 0) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
    
    private struct WeakColumn {
        let id: UUID
        let prefersFirst: Bool
        weak var column: FeedColumnScheduling?
    }
    
    private struct WorkItem {
        let id: UUID
        let work: () -> Void
    }
    
    private var columns: [WeakColumn] = []
    private var workQueue: [WorkItem] = []
    private var isDraining = false
    private var drainTask: Task<Void, Never>?
    private var fetchLoopTimer: Timer?
    private var rotationIndex = 0
    private var lastResumeAllAt: Date?
    
    var visibleColumnCount: Int {
        prune()
        return columns.count
    }
    
    var hasMultipleVisibleColumns: Bool {
        visibleColumnCount > 1
    }
    
    var fetchLoopInterval: TimeInterval {
        let count = max(columns.count, 1)
        return count <= 1 ? fullCycleInterval : fullCycleInterval / Double(count)
    }
    
    deinit {
        fetchLoopTimer?.invalidate()
    }
    
    func register(_ column: FeedColumnScheduling) {
        prune()
        guard !columns.contains(where: { $0.id == column.columnScheduleId }) else { return }
        columns.append(WeakColumn(
            id: column.columnScheduleId,
            prefersFirst: column.prefersFirstInRotation,
            column: column
        ))
#if DEBUG
        L.og.debug("☘️☘️ FeedFetchScheduler register \(column.columnScheduleId) count=\(self.columns.count) -[LOG]-")
#endif
        refreshFetchLoop()
    }
    
    func unregister(_ column: FeedColumnScheduling) {
        unregister(id: column.columnScheduleId)
    }
    
    func unregister(id: UUID) {
        columns.removeAll { $0.id == id }
        workQueue.removeAll { $0.id == id }
        prune()
        if rotationIndex >= columns.count {
            rotationIndex = 0
        }
        refreshFetchLoop()
    }
    
    func resumeAll() {
        prune()
        if shouldCoalesceResumeAll() {
#if DEBUG
            L.og.debug("☘️☘️ FeedFetchScheduler resumeAll coalesced -[LOG]-")
#endif
            return
        }
        lastResumeAllAt = Date()
        for column in orderedColumns() {
            enqueue(id: column.columnScheduleId) { [weak column] in
                column?.scheduledResume()
            }
        }
#if DEBUG
        L.og.debug("☘️☘️ FeedFetchScheduler resumeAll queued \(self.workQueue.count) columns -[LOG]-")
#endif
        drainIfNeeded()
    }
    
    func scheduleNetworkStart(id: UUID, work: @escaping () -> Void) {
        enqueue(id: id, work: work)
        drainIfNeeded()
    }
    
    func tickNextColumn() {
        prune()
        guard !isDraining else { return }
        let ordered = orderedColumns().filter { !$0.isPausedForScheduling }
        guard !ordered.isEmpty else { return }
        if rotationIndex >= ordered.count {
            rotationIndex = 0
        }
        let column = ordered[rotationIndex]
        rotationIndex = (rotationIndex + 1) % ordered.count
        column.scheduledFetchTick()
    }
    
    func waitForScheduledWork() async {
        await drainTask?.value
    }
    
    func shutdown() {
        drainTask?.cancel()
        drainTask = nil
        fetchLoopTimer?.invalidate()
        fetchLoopTimer = nil
        workQueue.removeAll()
        columns.removeAll()
        isDraining = false
        rotationIndex = 0
        lastResumeAllAt = nil
    }
    
    private func shouldCoalesceResumeAll() -> Bool {
        if isDraining || !workQueue.isEmpty { return true }
        if let lastResumeAllAt, Date().timeIntervalSince(lastResumeAllAt) < resumeAllCooldown {
            return true
        }
        return false
    }
    
    private func enqueue(id: UUID, work: @escaping () -> Void) {
        if workQueue.contains(where: { $0.id == id }) { return }
        workQueue.append(WorkItem(id: id, work: work))
    }
    
    private func drainIfNeeded() {
        guard !isDraining else { return }
        isDraining = true
        drainTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if self.shouldCollectBeforeDrain {
                await self.sleepHandler(self.collectInterval)
            }
            await self.drain()
            self.isDraining = false
        }
    }
    
    private var shouldCollectBeforeDrain: Bool {
        columns.count > 1 || workQueue.count > 1 || usesDesktopCollectWindow
    }
    
    private func drain() async {
        while !workQueue.isEmpty {
            if Task.isCancelled { break }
            let item = workQueue.removeFirst()
            item.work()
            if columns.count > 1 && !workQueue.isEmpty {
                await sleepHandler(slotInterval)
            }
        }
    }
    
    private func orderedColumns() -> [FeedColumnScheduling] {
        prune()
        return columns
            .sorted { lhs, rhs in
                if lhs.prefersFirst == rhs.prefersFirst { return false }
                return lhs.prefersFirst && !rhs.prefersFirst
            }
            .compactMap(\.column)
    }
    
    private func prune() {
        columns.removeAll { $0.column == nil }
    }
    
    private func refreshFetchLoop() {
        fetchLoopTimer?.invalidate()
        fetchLoopTimer = nil
        prune()
        guard startsFetchLoop, !columns.isEmpty else { return }
        let interval = fetchLoopInterval
        fetchLoopTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickNextColumn()
            }
        }
        fetchLoopTimer?.tolerance = min(2.0, interval * 0.25)
    }
}
