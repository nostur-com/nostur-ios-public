import Foundation
import Testing
@testable import Nostur

@MainActor
@Suite("Request backlog ordering", .serialized)
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

    @Test("Core Data-free timeout bookkeeping is not starved by feed imports")
    func immediateTimeoutDoesNotWaitForBackgroundContext() {
        let backlog = Backlog(timeout: 0.1, auto: false, backlogDebugName: "BacklogTests")
        let backgroundWorkStarted = DispatchSemaphore(value: 0)
        let releaseBackgroundWork = DispatchSemaphore(value: 0)
        let resultLock = NSLock()
        var didTimeout = false

        bg().perform {
            backgroundWorkStarted.signal()
            _ = releaseBackgroundWork.wait(timeout: .now() + 2)
        }
        #expect(backgroundWorkStarted.wait(timeout: .now() + 1) == .success)

        let task = ReqTask(
            reqCommand: { _ in },
            processResponseCommand: { _, _, _ in },
            timeoutCommand: { _ in
                resultLock.lock()
                didTimeout = true
                resultLock.unlock()
            },
            timeoutDelivery: .immediate
        )
        backlog.add(task)

        RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        resultLock.lock()
        let timedOutWhileImporterWasBusy = didTimeout
        resultLock.unlock()

        releaseBackgroundWork.signal()
        #expect(timedOutWhileImporterWasBusy)
        backlog.clear()
    }

    @Test("Timeout callbacks default to the background context queue")
    func timeoutUsesBackgroundContextByDefault() {
        let backlog = Backlog(timeout: 0.1, auto: false, backlogDebugName: "BacklogContextTests")
        let backgroundWorkStarted = DispatchSemaphore(value: 0)
        let releaseBackgroundWork = DispatchSemaphore(value: 0)
        let resultLock = NSLock()
        var didTimeout = false

        bg().perform {
            backgroundWorkStarted.signal()
            _ = releaseBackgroundWork.wait(timeout: .now() + 2)
        }
        #expect(backgroundWorkStarted.wait(timeout: .now() + 1) == .success)

        let task = ReqTask(
            reqCommand: { _ in },
            processResponseCommand: { _, _, _ in },
            timeoutCommand: { _ in
                // This managed-context access is valid only if ReqTask delivered
                // the callback through bg().perform.
                _ = bg().registeredObjects.count
                resultLock.lock()
                didTimeout = true
                resultLock.unlock()
            }
        )
        backlog.add(task)

        RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        resultLock.lock()
        let ranWhileContextWasBlocked = didTimeout
        resultLock.unlock()
        #expect(!ranWhileContextWasBlocked)

        releaseBackgroundWork.signal()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        resultLock.lock()
        let ranAfterContextWasReleased = didTimeout
        resultLock.unlock()

        #expect(ranAfterContextWasReleased)
        backlog.clear()
    }

    @Test("A timed-out request ignores late responses and repeated timeouts")
    func timeoutWinsCompletion() async throws {
        var callbacks = [String]()
        let task = ReqTask(debounceTime: 0.001, reqCommand: { _ in },
            processResponseCommand: { _, _, _ in callbacks.append("response") },
            timeoutCommand: { _ in callbacks.append("timeout") }, timeoutDelivery: .immediate)
        task.onTimeout()
        task.onTimeout()
        task.process()
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(callbacks == ["timeout"])
    }

    @Test("A pending response keeps ownership of completion")
    func responseWinsCompletion() async throws {
        var callbacks = [String]()
        let task = ReqTask(debounceTime: 0.001, reqCommand: { _ in },
            processResponseCommand: { _, _, _ in callbacks.append("response") },
            timeoutCommand: { _ in callbacks.append("timeout") }, timeoutDelivery: .immediate)
        task.process()
        task.onTimeout()
        try await Task.sleep(nanoseconds: 50_000_000)
        task.onTimeout()
        #expect(callbacks == ["response"])
    }

    @Test("Expiration completes the background task only once")
    func expirationWinsCompletion() {
        var results = [Bool]()
        let completion = BackgroundRefreshCompletion { results.append($0) }
        completion.finish(false)
        completion.finish(true)
        #expect(results == [false])
    }

    @Test("Cancellation before installing a notification wait is preserved")
    func earlyCancellation() async {
        let wait = BackgroundNotificationWait()
        wait.finish(false)
        let result = await withCheckedContinuation { wait.install($0) }
        wait.finish(true)
        #expect(!result)
    }

    @Test("Notification cancellation returns promptly while imports are blocked")
    func cancellationDoesNotWaitForImporter() async {
        let release = DispatchSemaphore(value: 0)
        await withCheckedContinuation { started in
            bg().perform {
                started.resume()
                _ = release.wait(timeout: .now() + 3)
            }
        }
        defer { release.signal() }
        let account = AccountData(publicKey: String(repeating: "a", count: 64),
            lastSeenPostCreatedAt: 0, lastSeenRepostCreatedAt: 0,
            lastSeenReactionCreatedAt: 0, lastSeenZapCreatedAt: 0,
            followingPubkeys: [], privateFollowingPubkeys: [], followingHashtags: [],
            flags: [], isNC: false, anyName: "Cancellation test")
        let work = Task { await checkForDMNotifications(accountData: account) }
        // Let the real request register while its send is queued behind imports.
        try? await Task.sleep(nanoseconds: 50_000_000)
        let started = Date()
        work.cancel()
        await work.value
        #expect(Date().timeIntervalSince(started) < 0.5)
    }
}
