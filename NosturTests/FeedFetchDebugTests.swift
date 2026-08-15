#if DEBUG
import Foundation
import Testing
@testable import Nostur

@Suite("Feed fetch debug session")
@MainActor
struct FeedFetchDebugTests {
    @Test("Relay rows track send, events, empty EOSE, and timeout")
    func recordsPerRelayLifecycle() {
        let session = FeedFetchDebugSession(trigger: "resume", feedName: "Following")
        session.attachRequest(
            subscriptionId: "RESUME-Following-test",
            summary: "test",
            seeds: [
                FeedFetchDebugRelaySeed(
                    relayId: "wss://nos.lol",
                    isConnected: true,
                    isConnecting: false,
                    isFirstConnection: false,
                    isOutbox: false
                ),
                FeedFetchDebugRelaySeed(
                    relayId: "wss://relay.damus.io",
                    isConnected: false,
                    isConnecting: true,
                    isFirstConnection: true,
                    isOutbox: false
                )
            ]
        )

        session.markRequestStarted()
        session.markSent(relayId: "wss://nos.lol", isFirstConnection: false, isOutbox: false)
        session.markEvent(relayId: "wss://nos.lol")
        session.markEvent(relayId: "wss://nos.lol")
        session.markTerminal(relayId: "wss://nos.lol", closed: false)
        session.markQueued(relayId: "wss://relay.damus.io", isFirstConnection: true, isOutbox: false)
        session.markTimeout()
        session.noteAccepted(0)
        session.noteAccepted(3)

        #expect(session.subscriptionId == "RESUME-Following-test")
        #expect(session.relays.count == 2)
        #expect(session.eoseCount == 1)
        #expect(session.eventCount == 2)
        #expect(session.timeoutCount == 1)
        #expect(session.acceptedOnScreen == 3)
        #expect(session.endedAt != nil)

        let nos = session.relays.first { $0.relayId.contains("nos.lol") }
        #expect(nos?.statusLabel == "eose")
        #expect(nos?.eventCount == 2)

        let damus = session.relays.first { $0.relayId.contains("damus") }
        #expect(damus?.statusLabel == "timeout")
        #expect(damus?.isFirstConnection == true)
    }
}
#endif
