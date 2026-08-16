//
//  FeedFetchDebug.swift
//  Nostur
//
//  Live per-fetch ledger for the feed loading overlay. DEBUG only.
//

#if DEBUG
import Foundation
import Combine
import NostrEssentials

struct FeedFetchDebugRelaySeed {
    let relayId: CanonicalRelayUrl
    let isConnected: Bool
    let isConnecting: Bool
    let isFirstConnection: Bool
    let isOutbox: Bool
}

struct FeedFetchDebugRelayRow: Identifiable {
    var id: String { relayId }
    let relayId: CanonicalRelayUrl
    var isOutbox: Bool = false
    var isFirstConnection: Bool = false
    var isConnected: Bool = false
    var isConnecting: Bool = false
    var queued: Bool = false
    var sentAt: Date?
    var firstEventAt: Date?
    var eventCount: Int = 0
    var eoseAt: Date?
    var closed: Bool = false
    var timedOut: Bool = false
    var abandoned: Bool = false
    var lingerEnded: Bool = false
    var lingerEndedAt: Date?
    var lateEventCount: Int = 0

    var shortHost: String {
        relayId
            .replacingOccurrences(of: "wss://", with: "")
            .replacingOccurrences(of: "ws://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    func elapsed(from start: Date, _ date: Date?) -> String? {
        guard let date else { return nil }
        return String(format: "%.2fs", date.timeIntervalSince(start))
    }

    var statusLabel: String {
        if timedOut { return "timeout" }
        if abandoned { return "skipped" }
        if lingerEnded && sentAt == nil { return isConnected ? "nosend" : "nocon" }
        if lingerEnded || (closed && eoseAt == nil) { return "closed" }
        if eoseAt != nil { return eventCount == 0 ? "eose empty" : "eose" }
        if firstEventAt != nil { return "events" }
        if sentAt != nil { return "waiting" }
        if queued { return "queued" }
        if isConnecting { return "connecting" }
        if isConnected { return "connected" }
        return "expected"
    }
}

@MainActor
final class FeedFetchDebugSession: ObservableObject {
    let runID = UUID()
    let startedAt = Date()
    let trigger: String
    let feedName: String

    private(set) var subscriptionId: String?
    private(set) var reqSummary: String?
    private(set) var acceptedOnScreen: Int = 0
    private(set) var requestStartedAt: Date?
    private(set) var endedAt: Date?
    private(set) var lateEventCount: Int = 0
    private(set) var lastLateEventAt: Date?
    private(set) var targetSnapshot: ConnectionPool.RequestTargetSnapshot?

    @Published private(set) var relays: [FeedFetchDebugRelayRow] = []

    private var relayIndex: [CanonicalRelayUrl: Int] = [:]
    private var publishTask: Task<Void, Never>?

    init(trigger: String, feedName: String) {
        self.trigger = trigger
        self.feedName = feedName
    }

    var eoseCount: Int { relays.count { $0.eoseAt != nil } }
    var timeoutCount: Int { relays.count { $0.timedOut } }
    var eventCount: Int { relays.reduce(0) { $0 + $1.eventCount } }
    var waitingCount: Int {
        relays.count { $0.eoseAt == nil && !$0.timedOut && !$0.closed && !$0.abandoned && !$0.lingerEnded }
    }

    func attachRequest(
        subscriptionId: String,
        summary: String?,
        seeds: [FeedFetchDebugRelaySeed],
        targetSnapshot: ConnectionPool.RequestTargetSnapshot?
    ) {
        self.subscriptionId = subscriptionId
        self.targetSnapshot = targetSnapshot
        if let summary {
            reqSummary = summary
        }
        for seed in seeds {
            upsert(seed.relayId) { row in
                row.isOutbox = seed.isOutbox
                row.isFirstConnection = seed.isFirstConnection
                row.isConnected = seed.isConnected
                row.isConnecting = seed.isConnecting
            }
        }
        publishNow()
    }

    func markRequestStarted() {
        if requestStartedAt == nil {
            requestStartedAt = Date()
        }
        publishNow()
    }

    func markQueued(relayId: String, isFirstConnection: Bool, isOutbox: Bool) {
        upsert(relayId) { row in
            guard !row.lingerEnded else { return }
            if row.sentAt == nil {
                row.queued = true
            }
            row.isFirstConnection = isFirstConnection
            row.isOutbox = isOutbox
            row.isConnecting = !row.isConnected
        }
    }

    func markSent(relayId: String, isFirstConnection: Bool, isOutbox: Bool) {
        upsert(relayId) { row in
            guard !row.lingerEnded else { return }
            if row.sentAt == nil {
                row.sentAt = Date()
            }
            row.queued = false
            row.isConnected = true
            row.isConnecting = false
            row.isFirstConnection = isFirstConnection
            row.isOutbox = isOutbox
        }
    }

    func markEvent(relayId: String) {
        let isLate = endedAt != nil
        var accepted = false
        upsert(relayId) { row in
            guard !row.lingerEnded else { return }
            accepted = true
            if row.firstEventAt == nil {
                row.firstEventAt = Date()
            }
            row.eventCount += 1
            if isLate {
                row.lateEventCount += 1
            }
            row.isConnected = true
            row.isConnecting = false
        }
        if accepted && isLate {
            lateEventCount += 1
            lastLateEventAt = Date()
        }
    }

    func markTerminal(relayId: String, closed: Bool) {
        upsert(relayId) { row in
            guard !row.lingerEnded else { return }
            if closed {
                row.closed = true
            }
            else if row.eoseAt == nil {
                row.eoseAt = Date()
            }
            row.isConnected = true
            row.isConnecting = false
        }
    }

    func markTimeout() {
        for index in relays.indices where relays[index].eoseAt == nil && !relays[index].closed {
            relays[index].timedOut = true
        }
        markEnded()
    }

    func markAbandoned() {
        for index in relays.indices where relays[index].eoseAt == nil && !relays[index].closed && !relays[index].timedOut {
            relays[index].abandoned = true
        }
        markEnded()
    }

    func markEnded() {
        if endedAt == nil {
            endedAt = Date()
        }
        publishNow()
    }

    /// Linger window is over. Unfinished relays get a final status so they
    /// do not sit blank after we close or stop waiting.
    func markLingerClosed() {
        let now = Date()
        for index in relays.indices {
            let row = relays[index]
            guard row.eoseAt == nil, !row.timedOut, !row.abandoned, !row.lingerEnded else { continue }
            relays[index].lingerEnded = true
            relays[index].lingerEndedAt = now
            if row.sentAt != nil {
                relays[index].closed = true
            }
        }
        publishNow()
    }

    func noteAccepted(_ count: Int) {
        acceptedOnScreen += count
        publishNow()
    }

    private func upsert(_ relayId: String, mutate: (inout FeedFetchDebugRelayRow) -> Void) {
        let id = normalizeRelayUrl(relayId)
        if let index = relayIndex[id] {
            mutate(&relays[index])
        }
        else {
            var row = FeedFetchDebugRelayRow(relayId: id)
            mutate(&row)
            relayIndex[id] = relays.count
            relays.append(row)
        }
        schedulePublish()
    }

    private func schedulePublish() {
        guard publishTask == nil else { return }
        publishTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            self.objectWillChange.send()
            self.publishTask = nil
        }
    }

    private func publishNow() {
        publishTask?.cancel()
        publishTask = nil
        objectWillChange.send()
    }
}

@MainActor
final class FeedFetchDebug: ObservableObject {
    static let shared = FeedFetchDebug()
    static let defaultsKey = "feed_fetch_debug_overlay"

    /// Overlay visibility only. Recording always runs in DEBUG.
    @Published private(set) var isEnabled: Bool

    private var sessionsBySpeedTest: [ObjectIdentifier: FeedFetchDebugSession] = [:]
    private var sessionBySubscription: [String: FeedFetchDebugSession] = [:]
    private var terminalSub: AnyCancellable?

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.defaultsKey)
        terminalSub = MessageParser.shared.requestTerminalSub
            .receive(on: RunLoop.main)
            .sink { [weak self] response in
                self?.markTerminal(subscriptionId: response.subscriptionId, relay: response.relay, closed: false)
            }
    }

    func toggle() {
        setEnabled(!isEnabled)
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.defaultsKey)
    }

    func begin(_ speedTest: NXSpeedTest, trigger: String, feedName: String) {
        let key = ObjectIdentifier(speedTest)
        if let previous = sessionsBySpeedTest[key], let subId = previous.subscriptionId {
            sessionBySubscription[subId] = nil
        }
        let session = FeedFetchDebugSession(trigger: trigger, feedName: feedName)
        sessionsBySpeedTest[key] = session
        speedTest.debugSession = session
    }

    func attach(
        _ speedTest: NXSpeedTest?,
        subscriptionId: String,
        summary: String?,
        seeds: [FeedFetchDebugRelaySeed],
        targetSnapshot: ConnectionPool.RequestTargetSnapshot? = nil
    ) {
        guard let speedTest, let session = speedTest.debugSession else { return }
        if let previous = session.subscriptionId {
            sessionBySubscription[previous] = nil
        }
        session.attachRequest(
            subscriptionId: subscriptionId,
            summary: summary,
            seeds: seeds,
            targetSnapshot: targetSnapshot
        )
        sessionBySubscription[subscriptionId] = session
    }

    func markRequestStarted(_ speedTest: NXSpeedTest?) {
        speedTest?.debugSession?.markRequestStarted()
    }

    func noteAccepted(_ speedTest: NXSpeedTest?, count: Int) {
        guard count > 0, speedTest?.debugSession?.requestStartedAt != nil else { return }
        speedTest?.debugSession?.noteAccepted(count)
    }

    func markTimeout(subscriptionId: String) {
        sessionBySubscription[subscriptionId]?.markTimeout()
    }

    func markEnded(subscriptionId: String) {
        sessionBySubscription[subscriptionId]?.markEnded()
    }

    func markLingerClosed(subscriptionId: String) {
        sessionBySubscription[subscriptionId]?.markLingerClosed()
    }

    func markAbandoned(subscriptionId: String) {
        sessionBySubscription[subscriptionId]?.markAbandoned()
    }

    nonisolated static func recordSend(
        subscriptionId: String,
        relay: String,
        queued: Bool,
        isFirstConnection: Bool,
        isOutbox: Bool
    ) {
        Task { @MainActor in
            shared.applySend(
                subscriptionId: subscriptionId,
                relay: relay,
                queued: queued,
                isFirstConnection: isFirstConnection,
                isOutbox: isOutbox
            )
        }
    }

    nonisolated static func recordEvent(subscriptionId: String, relay: String) {
        Task { @MainActor in
            shared.sessionBySubscription[subscriptionId]?.markEvent(relayId: relay)
        }
    }

    nonisolated static func recordTerminal(subscriptionId: String, relay: String, closed: Bool) {
        Task { @MainActor in
            shared.markTerminal(subscriptionId: subscriptionId, relay: relay, closed: closed)
        }
    }

    private func applySend(
        subscriptionId: String,
        relay: String,
        queued: Bool,
        isFirstConnection: Bool,
        isOutbox: Bool
    ) {
        guard let session = sessionBySubscription[subscriptionId] else { return }
        if queued {
            session.markQueued(relayId: relay, isFirstConnection: isFirstConnection, isOutbox: isOutbox)
        }
        else {
            session.markSent(relayId: relay, isFirstConnection: isFirstConnection, isOutbox: isOutbox)
        }
    }

    private func markTerminal(subscriptionId: String, relay: String, closed: Bool) {
        sessionBySubscription[subscriptionId]?.markTerminal(relayId: relay, closed: closed)
    }
}
#endif
