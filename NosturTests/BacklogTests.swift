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
}
