import Foundation
import Testing
@testable import Nostur

@Suite("Viewing count subscriptions", .serialized)
struct ViewingSubscriptionsTests {
    private final class Transport {
        struct Sent {
            let relay: String
            let subscriptionId: String
            let ids: [String]
        }
        private let lock = NSLock()
        private var requests: [Sent] = []
        private var operations: [String] = []

        func send(_ relay: String, _ subscriptionId: String, _ ids: [String], _ deadline: TimeInterval) {
            lock.withLock {
                requests.append(Sent(relay: relay, subscriptionId: subscriptionId, ids: ids))
                operations.append("send:" + subscriptionId)
            }
        }
        func close(_ relay: String, _ subscriptionId: String) {
            lock.withLock { operations.append("close:" + subscriptionId) }
        }
        var sent: [Sent] { lock.withLock { requests } }
        var history: [String] { lock.withLock { operations } }
    }

    private func configuration() -> ViewingSubscriptions.Configuration {
        var configuration = ViewingSubscriptions.Configuration()
        configuration.batchInterval = 0.03
        configuration.requestTimeout = 2
        return configuration
    }

    private func scheduler(_ transport: Transport, relays: [String] = ["a"],
                           configuration: ViewingSubscriptions.Configuration? = nil) -> ViewingSubscriptions {
        ViewingSubscriptions(configuration: configuration ?? self.configuration(),
                             targets: { $0(relays) }, send: transport.send, close: transport.close)
    }

    private func snapshot(_ scheduler: ViewingSubscriptions) async -> ViewingSubscriptions.Snapshot {
        await withCheckedContinuation { continuation in
            scheduler.snapshot { continuation.resume(returning: $0) }
        }
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while !(await condition()), ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(await condition())
    }

    @Test("Scrolling batches IDs and deduplicates across callers and in-flight requests")
    func batchesAndDeduplicates() async throws {
        let transport = Transport()
        let scheduler = scheduler(transport, relays: ["a", "b"])
        scheduler.enqueue(ids: ["one", "two"])
        scheduler.enqueue(ids: ["two", "three"])
        try await waitUntil { transport.sent.count == 2 }
        #expect(transport.sent.allSatisfy { Set($0.ids) == ["one", "two", "three"] })
        scheduler.enqueue(ids: ["one", "three"])
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(transport.sent.count == 2)
        #expect(await snapshot(scheduler).active == 2)
    }

    @Test("Each relay has its own concurrency bound; CLOSE precedes the next batch")
    func relayConcurrency() async throws {
        let transport = Transport()
        var config = configuration()
        config.batchSize = 2
        let scheduler = scheduler(transport, relays: ["a", "b"], configuration: config)
        scheduler.enqueue(ids: (0..<12).map(String.init))
        try await waitUntil { transport.sent.count == 4 }
        #expect(transport.sent.filter { $0.relay == "a" }.count == 2)
        let first = transport.sent.first { $0.relay == "a" }!
        scheduler.receiveTerminal(text: "[\"EOSE\",\"\(first.subscriptionId)\"]", relay: "a")
        try await waitUntil { transport.sent.count == 5 }
        #expect(transport.sent.filter { $0.relay == "b" }.count == 2)
        let history = transport.history
        #expect(history.firstIndex(of: "close:" + first.subscriptionId)! < history.firstIndex(of: "send:" + transport.sent.last!.subscriptionId)!)
        #expect(await snapshot(scheduler).peakActivePerRelay == 2)
        #expect(await snapshot(scheduler).active == 4)
    }

    @Test("Successful freshness is per relay and expires")
    func successfulFreshness() async throws {
        let transport = Transport()
        var config = configuration()
        config.freshness = 0.15
        let scheduler = scheduler(transport, relays: ["a", "b"], configuration: config)
        scheduler.enqueue(ids: ["one"])
        try await waitUntil { transport.sent.count == 2 }
        let a = transport.sent.first { $0.relay == "a" }!
        let b = transport.sent.first { $0.relay == "b" }!
        scheduler.receiveTerminal(text: " [ \"EOSE\", \"\(a.subscriptionId)\" ] ", relay: "a")
        scheduler.receiveTerminal(text: "[\"CLOSED\",\"\(b.subscriptionId)\",\"rate-limited: retry\"]", relay: "b")
        scheduler.enqueue(ids: ["one"])
        try await waitUntil { transport.sent.count == 3 }
        #expect(transport.sent.last?.relay == "b")
        try await Task.sleep(nanoseconds: 180_000_000)
        scheduler.enqueue(ids: ["one"])
        try await waitUntil { transport.sent.count == 4 }
        #expect(transport.sent.last?.relay == "a")
        #expect(await snapshot(scheduler).completed == 1)
        #expect(await snapshot(scheduler).rejected == 1)
    }

    @Test("Missing EOSE expires, releases capacity, and permits retry; late EOSE is harmless")
    func timeoutAndRetry() async throws {
        let transport = Transport()
        var config = configuration()
        config.requestTimeout = 0.12
        config.concurrency = 1
        config.batchSize = 1
        let scheduler = scheduler(transport, configuration: config)
        scheduler.enqueue(ids: ["one", "two"])
        try await waitUntil { transport.sent.count == 2 }
        let first = transport.sent[0]
        #expect(transport.history.contains("close:" + first.subscriptionId))
        scheduler.receiveTerminal(text: "[\"EOSE\",\"\(first.subscriptionId)\"]", relay: "a")
        #expect(await snapshot(scheduler).completed == 0)
        scheduler.enqueue(ids: first.ids)
        try await waitUntil { transport.sent.count >= 3 }
        #expect(transport.sent[2].ids == first.ids)
        #expect(await snapshot(scheduler).peakActivePerRelay == 1)
    }

    @Test("Continuous scrolling flushes without waiting for scrolling to stop")
    func continuousScrolling() async throws {
        let transport = Transport()
        let scheduler = scheduler(transport)
        for index in 0..<20 {
            scheduler.enqueue(ids: [String(index)])
            try await Task.sleep(nanoseconds: 10_000_000)
            if index == 10 { #expect(!transport.sent.isEmpty) }
        }
        #expect(await snapshot(scheduler).peakActivePerRelay <= 2)
    }

    @Test("Pending IDs expire rather than draining stale work after a slow relay")
    func pendingExpiry() async throws {
        let transport = Transport()
        var config = configuration()
        config.requestTimeout = 0.18
        config.pendingLifetime = 0.06
        config.concurrency = 1
        config.batchSize = 1
        let scheduler = scheduler(transport, configuration: config)
        scheduler.enqueue(ids: ["one", "two", "three"])
        try await waitUntil { await snapshot(scheduler).timedOut == 1 }
        #expect(transport.sent.count == 1)
        #expect(await snapshot(scheduler).pending == 0)
    }

    @MainActor
    @Test("UI enqueue, EOSE cleanup, and deadlines complete while imports are held")
    func importerDoesNotBlockUIOrCleanup() async throws {
        let transport = Transport()
        var config = configuration()
        config.requestTimeout = 0.15
        let scheduler = scheduler(transport, configuration: config)
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
            bg().perform {
                started.resume()
                _ = release.wait(timeout: .now() + 5)
            }
        }
        let start = ProcessInfo.processInfo.systemUptime
        scheduler.enqueue(ids: ["one"])
        #expect(ProcessInfo.processInfo.systemUptime - start < 0.1)
        try await waitUntil { transport.sent.count == 1 }
        let first = transport.sent[0]
        let terminalStart = ProcessInfo.processInfo.systemUptime
        #expect(scheduler.receiveTerminal(text: "[\"EOSE\",\"\(first.subscriptionId)\"]", relay: "a"))
        #expect(ProcessInfo.processInfo.systemUptime - terminalStart < 0.1)
        try await waitUntil { await snapshot(scheduler).completed == 1 }
        #expect(transport.history.contains("close:" + first.subscriptionId))
        scheduler.enqueue(ids: ["two"])
        try await waitUntil { await snapshot(scheduler).timedOut == 1 }
        #expect(await snapshot(scheduler).active == 0)
        #expect(ProcessInfo.processInfo.systemUptime - start < 1.5)
    }

    @Test("Read-relay transport preserves filters, deadlines, and relay-scoped cleanup")
    func transportRouting() async throws {
        let pool = ConnectionPool()
        pool.queue = DispatchQueue(label: "test-viewing-pool")
        let a = RecordingViewingConnection(RelayData.new(url: "wss://viewing-a.example.invalid", read: true), queue: pool.queue)
        let b = RecordingViewingConnection(RelayData.new(url: "wss://viewing-b.example.invalid", read: true), queue: pool.queue)
        let writeOnly = RecordingViewingConnection(RelayData.new(url: "wss://viewing-write.example.invalid", read: false), queue: pool.queue)
        await withCheckedContinuation { continuation in
            pool.queue.async {
                pool.connections = [a.url: a, b.url: b, writeOnly.url: writeOnly]
                continuation.resume()
            }
        }
        let targets: [String] = await withCheckedContinuation { continuation in
            pool.viewingRelayTargets { continuation.resume(returning: $0) }
        }
        #expect(Set(targets) == [a.url, b.url])
        let deadline = ProcessInfo.processInfo.systemUptime + 12
        pool.sendViewingRequest(relay: a.url, subscriptionId: "VIEWING-test", ids: ["one", "two"], deadline: deadline)
        pool.sendViewingRequest(relay: b.url, subscriptionId: "VIEWING-expired", ids: ["one"], deadline: 0)
        pool.sendViewingRequest(relay: writeOnly.url, subscriptionId: "VIEWING-write", ids: ["one"], deadline: deadline)
        pool.closeViewingRequest(relay: a.url, subscriptionId: "VIEWING-test")
        let result = await withCheckedContinuation { continuation in
            pool.queue.async {
                continuation.resume(returning: (a.messages, a.deadlines, a.closed, b.messages.count, b.closed.count, writeOnly.messages.count))
            }
        }
        #expect(result.0.count == 1)
        #expect(result.1 == [deadline])
        #expect(result.2 == ["VIEWING-test"])
        #expect(result.3 == 0 && result.4 == 0 && result.5 == 0)
        let data = try #require(result.0.first?.data(using: .utf8))
        let frame = try #require(JSONSerialization.jsonObject(with: data) as? [Any])
        #expect(frame[0] as? String == "REQ")
        let e = try #require(frame[2] as? [String: Any])
        let q = try #require(frame[3] as? [String: Any])
        #expect(Set(e["#e"] as? [String] ?? []) == ["one", "two"])
        #expect(Set(q["#q"] as? [String] ?? []) == ["one", "two"])
        #expect(Set(e["kinds"] as? [Int] ?? []) == [1,1244,1111,6,16,7,9735])
        #expect(Set(q["kinds"] as? [Int] ?? []) == [1,1111,30023])
        #expect(e["limit"] as? Int == 5000 && q["limit"] as? Int == 5000)
    }

    @MainActor
    @Test("UI transport entry points return while the connection queue is held")
    func heldConnectionQueue() async {
        let pool = ConnectionPool()
        pool.queue = DispatchQueue(label: "test-viewing-held-queue")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
            pool.queue.async {
                started.resume()
                _ = release.wait(timeout: .now() + 5)
            }
        }
        let start = ProcessInfo.processInfo.systemUptime
        pool.viewingRelayTargets { _ in }
        pool.sendViewingRequest(relay: "a", subscriptionId: "VIEWING-held", ids: ["one"], deadline: start + 12)
        pool.closeViewingRequest(relay: "a", subscriptionId: "VIEWING-held")
        #expect(ProcessInfo.processInfo.systemUptime - start < 0.1)
    }

    @Test("Other subscriptions and EVENT frames retain normal parser delivery")
    func terminalRouting() {
        let scheduler = scheduler(Transport())
        #expect(!scheduler.receiveTerminal(text: "[\"EOSE\",\"Following-test\"]", relay: "a"))
        #expect(!scheduler.receiveTerminal(text: "[\"CLOSED\",\"VIEWING-test\",\"auth-required: authenticate\"]", relay: "a"))
        #expect(!scheduler.receiveTerminal(text: "[\"EVENT\",\"VIEWING-test\",{}]", relay: "a"))
        #expect(!scheduler.receiveTerminal(text: "[\"EOSE\",\"VIEWING-test\"", relay: "a"))
    }
}

// No real sockets: all recorded state is confined to the test pool queue.
private final class RecordingViewingConnection: Nostur.RelayConnection {
    var messages: [String] = []
    var deadlines: [TimeInterval] = []
    var closed: [String] = []

    override func connect(andSend: String? = nil, forceConnectionAttempt: Bool = false, reason: String = #function) {}

    override func sendViewingMessage(_ text: String, subscriptionId: String, expiresAt: TimeInterval) {
        messages.append(text)
        deadlines.append(expiresAt)
    }

    override func closeAndDropSubscription(_ subscriptionId: String) {
        closed.append(subscriptionId)
    }
}
