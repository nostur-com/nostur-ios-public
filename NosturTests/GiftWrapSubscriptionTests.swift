import Foundation
import CoreData
import NostrEssentials
import Testing
@testable import Nostur

@Suite("Gift wrap subscription recovery", .serialized)
struct GiftWrapSubscriptionTests {
    private let subscriptionId = "-OPEN-59-test"

    private func connection(queue: DispatchQueue) -> Nostur.RelayConnection {
        Nostur.RelayConnection(
            RelayData(read: true, write: false, search: false, auth: false, url: "wss://giftwrap.example.invalid", excludedPubkeys: []),
            queue: queue
        )
    }

    @Test("EOSE preserves the live subscription; CLOSED clears it")
    func relayTerminalMessages() async throws {
        let queue = DispatchQueue(label: "test-giftwrap-subscription")
        let client = connection(queue: queue)
        await withCheckedContinuation { continuation in
            queue.async {
                client.nreqSubscriptions.insert(subscriptionId)
                continuation.resume()
            }
        }
        MessageParser.shared.socketReceivedMessage(
            text: "[\"EOSE\",\"\(subscriptionId)\"]", relayUrl: client.url, client: client
        )
        // Parser delivery enters the background context before the connection queue.
        await bg().perform {}
        let afterEOSE = await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: client.nreqSubscriptions.contains(subscriptionId)) }
        }
        #expect(afterEOSE)

        MessageParser.shared.socketReceivedMessage(
            text: "[\"CLOSED\",\"\(subscriptionId)\",\"error: shutting down idle subscription\"]",
            relayUrl: client.url, client: client
        )
        await bg().perform {}
        let afterCLOSED = await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: client.nreqSubscriptions.contains(subscriptionId)) }
        }
        #expect(!afterCLOSED)
    }

    @Test("Auth-required CLOSED exposes the subscription ID for recovery")
    func authRequiredClosed() throws {
        let message = try nxParseRelayMessage(
            text: "[\"CLOSED\",\"\(subscriptionId)\",\"auth-required: authenticate first\"]",
            relay: "wss://giftwrap.example.invalid"
        )
        #expect(message.subscriptionId == subscriptionId)
        #expect(message.id == subscriptionId)
    }

    @Test("Recovery sends REQ only to the relay that lost its subscription")
    func recoverySkipsHealthyRelay() async {
        let pool = ConnectionPool()
        pool.queue = DispatchQueue(label: "test-giftwrap-pool")
        let healthy = RecordingGiftWrapConnection(
            RelayData.new(url: "wss://healthy.example.invalid", read: true), queue: pool.queue
        )
        let lost = RecordingGiftWrapConnection(
            RelayData.new(url: "wss://lost.example.invalid", read: true), queue: pool.queue
        )
        await withCheckedContinuation { continuation in
            pool.queue.async {
                pool.connections = [healthy.url: healthy, lost.url: lost]
                healthy.nreqSubscriptions.insert(subscriptionId)
                lost.nreqSubscriptions.insert(subscriptionId)
                continuation.resume()
            }
        }
        healthy.completeReqSubscription(subscriptionId, keepActive: true)
        lost.completeReqSubscription(subscriptionId)
        let request = NosturClientMessage(
            clientMessage: ClientMessage(type: .REQ, subscriptionId: subscriptionId),
            relayType: .READ,
            message: "[\"REQ\",\"\(subscriptionId)\",{\"kinds\":[1059]}]"
        )
        // The first check restores the missing relay; further checks send nothing.
        pool.sendMessage(request, subscriptionId: subscriptionId)
        pool.sendMessage(request, subscriptionId: subscriptionId)
        let counts = await withCheckedContinuation { continuation in
            pool.queue.async { continuation.resume(returning: (healthy.requestCount, lost.requestCount)) }
        }
        #expect(counts.0 == 0)
        #expect(counts.1 == 1)
    }

    @MainActor
    @Test("Closing a subscription returns promptly with the relay queue held")
    func closeDoesNotBlockUI() async {
        let queue = DispatchQueue(label: "test-held-giftwrap-queue")
        let client = connection(queue: queue)
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
            queue.async {
                started.resume()
                _ = release.wait(timeout: .now() + 5)
            }
        }
        let start = ProcessInfo.processInfo.systemUptime
        client.closeAndDropSubscription(subscriptionId)
        #expect(ProcessInfo.processInfo.systemUptime - start < 0.1)
    }
}

// Pool delivery runs on the test queue. Avoid creating real sockets in this test.
private final class RecordingGiftWrapConnection: Nostur.RelayConnection {
    var requestCount = 0

    override func connect(andSend: String? = nil, forceConnectionAttempt: Bool = false, reason: String = #function) {}

    override func sendMessage(_ text: String, subscriptionId: String? = nil, bypassQueue: Bool = false) {
        requestCount += 1
    }
}
