import Foundation
import Testing
@testable import Nostur

@MainActor
@Suite("Request backlog ordering")
struct BacklogTests {
    @Test("Task is registered before add returns")
    func addIsSynchronous() {
        let backlog = Backlog(timeout: 1, auto: false, backlogDebugName: "BacklogTests")
        var wasRegisteredWhenFetchStarted = false

        let task = ReqTask(
            reqCommand: { subscriptionId in
                wasRegisteredWhenFetchStarted = backlog.containsTask(with: subscriptionId)
            },
            processResponseCommand: { _, _, _ in }
        )

        backlog.add(task)
        task.fetch()

        #expect(wasRegisteredWhenFetchStarted)
        backlog.clear()
    }

    @Test("Adding a task does not wait for feed imports")
    func addDoesNotWaitForBackgroundContext() {
        let backlog = Backlog(timeout: 1, auto: false, backlogDebugName: "BacklogTests")
        let backgroundWorkStarted = DispatchSemaphore(value: 0)
        let releaseBackgroundWork = DispatchSemaphore(value: 0)

        bg().perform {
            backgroundWorkStarted.signal()
            _ = releaseBackgroundWork.wait(timeout: .now() + 1)
        }
        #expect(backgroundWorkStarted.wait(timeout: .now() + 1) == .success)

        let task = ReqTask(
            reqCommand: { _ in },
            processResponseCommand: { _, _, _ in }
        )
        let startedAt = Date()
        backlog.add(task)
        let elapsed = Date().timeIntervalSince(startedAt)

        releaseBackgroundWork.signal()
        #expect(elapsed < 0.1)
        backlog.clear()
    }
}
