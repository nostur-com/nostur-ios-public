import Testing
@testable import Nostur

@MainActor
@Suite("Serialized local feed loading")
struct NXLocalLoadCoordinatorTests {
    @Test("Runs local reads one at a time")
    func serializesWork() {
        var started: [Int] = []
        var finishes: [() -> Void] = []
        let coordinator = NXLocalLoadCoordinator<Int>(
            key: String.init,
            perform: { value, finish in
                started.append(value)
                finishes.append(finish)
            }
        )

        coordinator.enqueue(1)
        coordinator.enqueue(2)

        #expect(started == [1])
        finishes[0]()
        #expect(started == [1, 2])
    }

    @Test("Coalescing preserves every completion")
    func preservesCoalescedCompletions() {
        var started: [Int] = []
        var finishes: [() -> Void] = []
        var completed: [String] = []
        let coordinator = NXLocalLoadCoordinator<Int>(
            key: String.init,
            perform: { value, finish in
                started.append(value)
                finishes.append(finish)
            }
        )

        coordinator.enqueue(0)
        coordinator.enqueue(1) { completed.append("first") }
        coordinator.enqueue(1) { completed.append("second") }

        finishes[0]()
        #expect(started == [0, 1])
        finishes[1]()
        #expect(completed == ["first", "second"])
    }

    @Test("Invalidating a feed releases active and pending callers")
    func invalidatingFeedCompletesCallersAndStartsNewWork() {
        var started: [Int] = []
        var finishes: [() -> Void] = []
        var activeCompleted = false
        var pendingCompleted = false
        let coordinator = NXLocalLoadCoordinator<Int>(
            key: String.init,
            perform: { value, finish in
                started.append(value)
                finishes.append(finish)
            }
        )

        coordinator.enqueue(0) { activeCompleted = true }
        coordinator.enqueue(1) { pendingCompleted = true }
        coordinator.cancelAll()

        #expect(started == [0])
        #expect(activeCompleted)
        #expect(pendingCompleted)

        coordinator.enqueue(2)
        #expect(started == [0, 2])

        // A late callback from invalidated work must not finish the new read.
        finishes[0]()
        #expect(started == [0, 2])
        finishes[1]()
    }
}
