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
            ],
            targetSnapshot: nil
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

    @Test("Events after the bar finishes are counted as late")
    func recordsLateEventsAfterBarFinished() {
        let session = FeedFetchDebugSession(trigger: "firstLoad", feedName: "Following")
        session.attachRequest(
            subscriptionId: "RESUME-Following-late",
            summary: "test",
            seeds: [
                FeedFetchDebugRelaySeed(
                    relayId: "wss://slow.example",
                    isConnected: true,
                    isConnecting: false,
                    isFirstConnection: false,
                    isOutbox: true
                )
            ],
            targetSnapshot: nil
        )
        session.markRequestStarted()
        session.markSent(relayId: "wss://slow.example", isFirstConnection: false, isOutbox: true)
        session.markEnded()
        session.markEvent(relayId: "wss://slow.example")
        session.markEvent(relayId: "wss://slow.example")
        session.markEvent(relayId: "wss://slow.example")

        #expect(session.lateEventCount == 3)
        #expect(session.lastLateEventAt != nil)
        let slow = session.relays.first { $0.relayId.contains("slow.example") }
        #expect(slow?.eventCount == 3)
        #expect(slow?.lateEventCount == 3)
        #expect(slow?.abandoned == false)
    }

    @Test("Linger close gives unfinished relays a final note")
    func lingerCloseMarksUnfinishedRelays() {
        let session = FeedFetchDebugSession(trigger: "firstLoad", feedName: "Following")
        session.attachRequest(
            subscriptionId: "RESUME-Following-linger",
            summary: "test",
            seeds: [
                FeedFetchDebugRelaySeed(
                    relayId: "wss://fast.example",
                    isConnected: true,
                    isConnecting: false,
                    isFirstConnection: false,
                    isOutbox: false
                ),
                FeedFetchDebugRelaySeed(
                    relayId: "wss://silent.example",
                    isConnected: false,
                    isConnecting: false,
                    isFirstConnection: true,
                    isOutbox: true
                )
            ],
            targetSnapshot: nil
        )
        session.markSent(relayId: "wss://fast.example", isFirstConnection: false, isOutbox: false)
        session.markTerminal(relayId: "wss://fast.example", closed: false)
        session.markEnded()
        session.markLingerClosed()

        let fast = session.relays.first { $0.relayId.contains("fast.example") }
        let silent = session.relays.first { $0.relayId.contains("silent.example") }
        #expect(fast?.lingerEnded == false)
        #expect(fast?.eoseAt != nil)
        #expect(silent?.lingerEnded == true)
        #expect(silent?.statusLabel == "nocon")
        #expect(session.waitingCount == 0)
    }

    @Test("CLOSE is not recorded as EOSE, and linger ignores later sends")
    func closeIsNotEoseAndLingerIgnoresStaleSend() {
        let session = FeedFetchDebugSession(trigger: "firstLoad", feedName: "Following")
        session.attachRequest(
            subscriptionId: "RESUME-Following-stale",
            summary: "test",
            seeds: [
                FeedFetchDebugRelaySeed(
                    relayId: "wss://late.example",
                    isConnected: false,
                    isConnecting: true,
                    isFirstConnection: true,
                    isOutbox: true
                )
            ],
            targetSnapshot: nil
        )
        session.markEnded()
        session.markLingerClosed()
        session.markSent(relayId: "wss://late.example", isFirstConnection: true, isOutbox: true)
        session.markTerminal(relayId: "wss://late.example", closed: true)

        let late = session.relays.first { $0.relayId.contains("late.example") }
        #expect(late?.sentAt == nil)
        #expect(late?.eoseAt == nil)
        #expect(late?.lingerEnded == true)
        #expect(late?.statusLabel == "nocon")
    }
}
#endif
