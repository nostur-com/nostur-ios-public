import Foundation

/// Shared count prefetching for feed/profile rows. No Core Data or main-actor work
/// runs on this queue, including expiry and relay terminal handling.
final class ViewingSubscriptions {
    static let shared = ViewingSubscriptions(
        targets: { completion in ConnectionPool.shared.viewingRelayTargets(completion) },
        send: { relay, subscriptionId, ids, deadline in
            ConnectionPool.shared.sendViewingRequest(relay: relay, subscriptionId: subscriptionId, ids: ids, deadline: deadline)
        },
        close: { relay, subscriptionId in
            ConnectionPool.shared.closeViewingRequest(relay: relay, subscriptionId: subscriptionId)
        }
    )

    struct Configuration {
        var batchInterval: TimeInterval = 0.25
        var requestTimeout: TimeInterval = 12
        var pendingLifetime: TimeInterval = 30
        var freshness: TimeInterval = 60
        var batchSize = 5
        var concurrency = 2
        var recentLimit = 2_000
    }

    struct Snapshot {
        var batches = 0
        var requestedIds = 0
        var events = 0
        var completed = 0
        var rejected = 0
        var timedOut = 0
        var peakActivePerRelay = 0
        var active = 0
        var pending = 0
    }

    private struct Request {
        let ids: [String]
        let started: TimeInterval
        var events = 0
    }

    private struct RelayState {
        var pending: [String: TimeInterval] = [:]
        var active: [String: Request] = [:]
        var recent: [String: TimeInterval] = [:]
    }

    private let queue = DispatchQueue(label: "com.nostur.viewing-subscriptions", qos: .utility)
    private let configuration: Configuration
    private let targets: (@escaping ([String]) -> Void) -> Void
    private let send: (String, String, [String], TimeInterval) -> Void
    private let close: (String, String) -> Void
    private var incoming: Set<String> = []
    private var relays: [String: RelayState] = [:]
    private var tickScheduled = false
    private var resolvingTargets = false
    private var metrics = Snapshot()

    init(configuration: Configuration = Configuration(),
         targets: @escaping (@escaping ([String]) -> Void) -> Void,
         send: @escaping (String, String, [String], TimeInterval) -> Void,
         close: @escaping (String, String) -> Void) {
        precondition(configuration.batchInterval > 0 && configuration.requestTimeout > 0)
        precondition(configuration.batchSize > 0 && configuration.concurrency > 0)
        self.configuration = configuration
        self.targets = targets
        self.send = send
        self.close = close
    }

    func enqueue(ids: [String]) {
        guard !ids.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.incoming.formUnion(ids)
            self.scheduleTick()
        }
    }

    /// Called before MessageParser enters the importer context. CLOSED does not
    /// count as success; retries of rejected/expired IDs must remain possible.
    /// Returns true only when the frame needs no further parser delivery.
    @discardableResult
    func receiveTerminal(text: String, relay: String) -> Bool {
        let header = text.drop(while: { $0 == "[" || $0.isWhitespace })
        guard header.hasPrefix("\"EOSE\"") || header.hasPrefix("\"CLOSED\""),
              text.contains("VIEWING-"),
              let data = text.data(using: .utf8),
              let frame = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let type = frame.first as? String, type == "EOSE" || type == "CLOSED",
              frame.count >= 2, let subscriptionId = frame[1] as? String,
              subscriptionId.hasPrefix("VIEWING-") else { return false }
        queue.async { [weak self] in
            guard let self else { return }
            self.finish(relay: relay, subscriptionId: subscriptionId, success: type == "EOSE", timedOut: false)
            self.drain(relay: relay)
        }
        // Preserve normal CLOSED error/auth handling after releasing capacity.
        return type == "EOSE"
    }

    func recordEvent(relay: String, subscriptionId: String) {
        guard subscriptionId.hasPrefix("VIEWING-") else { return }
        queue.async { [weak self] in
            guard let self, self.relays[relay]?.active[subscriptionId] != nil else { return }
            self.relays[relay]?.active[subscriptionId]?.events += 1
            self.metrics.events += 1
        }
    }

    func snapshot(_ completion: @escaping (Snapshot) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            var snapshot = self.metrics
            snapshot.active = self.relays.values.reduce(0) { $0 + $1.active.count }
            snapshot.pending = self.incoming.count + self.relays.values.reduce(0) { $0 + $1.pending.count }
            completion(snapshot)
        }
    }

    private func scheduleTick() {
        guard !tickScheduled else { return }
        tickScheduled = true
        queue.asyncAfter(deadline: .now() + configuration.batchInterval) { [weak self] in
            guard let self else { return }
            self.tickScheduled = false
            self.tick()
        }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        for relay in Array(relays.keys) {
            let expired = relays[relay]!.active.filter { now - $0.value.started >= configuration.requestTimeout }.map(\.key)
            for subscriptionId in expired {
                finish(relay: relay, subscriptionId: subscriptionId, success: false, timedOut: true)
            }
            var state = relays[relay]!
            state.pending = state.pending.filter { $0.value > now }
            state.recent = state.recent.filter { $0.value > now }
            relays[relay] = state
            drain(relay: relay)
            if relays[relay]!.active.isEmpty && relays[relay]!.pending.isEmpty && relays[relay]!.recent.isEmpty {
                relays.removeValue(forKey: relay)
            }
        }

        if !incoming.isEmpty && !resolvingTargets {
            let ids = incoming
            incoming.removeAll()
            resolvingTargets = true
            targets { [weak self] relayIds in
                guard let self else { return }
                self.queue.async {
                    self.resolvingTargets = false
                    let now = ProcessInfo.processInfo.systemUptime
                    for relay in Set(relayIds) {
                        var state = self.relays[relay] ?? RelayState()
                        let activeIds = Set(state.active.values.flatMap(\.ids))
                        for id in ids where !activeIds.contains(id) && (state.recent[id] ?? 0) <= now {
                            if state.pending[id] == nil {
                                state.pending[id] = now + self.configuration.pendingLifetime
                            }
                        }
                        self.relays[relay] = state
                        self.drain(relay: relay)
                    }
                    self.scheduleTick()
                }
            }
        }
        if !incoming.isEmpty || resolvingTargets || relays.values.contains(where: { !$0.active.isEmpty || !$0.pending.isEmpty }) {
            scheduleTick()
        }
    }

    private func drain(relay: String) {
        guard var state = relays[relay] else { return }
        let now = ProcessInfo.processInfo.systemUptime
        state.pending = state.pending.filter { $0.value > now }
        while state.active.count < configuration.concurrency && !state.pending.isEmpty {
            // Oldest queued IDs first; sorting also makes batch selection stable.
            let ids = state.pending.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value }
                .prefix(configuration.batchSize).map(\.key)
            let subscriptionId = "VIEWING-" + UUID().uuidString
            ids.forEach { state.pending.removeValue(forKey: $0) }
            state.active[subscriptionId] = Request(ids: ids, started: now)
            metrics.batches += 1
            metrics.requestedIds += ids.count
            metrics.peakActivePerRelay = max(metrics.peakActivePerRelay, state.active.count)
            relays[relay] = state
            send(relay, subscriptionId, ids, now + configuration.requestTimeout)
        }
        relays[relay] = state
    }

    private func finish(relay: String, subscriptionId: String, success: Bool, timedOut: Bool) {
        guard let request = relays[relay]?.active.removeValue(forKey: subscriptionId) else { return }
        // Transport drops queued REQs as well as closing requests already sent.
        // Enqueue cleanup before allowing another batch onto this relay.
        close(relay, subscriptionId)
        let now = ProcessInfo.processInfo.systemUptime
        if success {
            metrics.completed += 1
            for id in request.ids {
                relays[relay]?.recent[id] = now + configuration.freshness
            }
            if let recent = relays[relay]?.recent, recent.count > configuration.recentLimit {
                let oldest = recent.sorted { $0.value < $1.value }.prefix(recent.count - configuration.recentLimit)
                for entry in oldest { relays[relay]?.recent.removeValue(forKey: entry.key) }
            }
        }
        else if timedOut { metrics.timedOut += 1 }
        else { metrics.rejected += 1 }
#if DEBUG
        L.sockets.debug("🔢 VIEWING \(relay): ids=\(request.ids.count) events=\(request.events) elapsed=\(now - request.started)s success=\(success) timeout=\(timedOut) batches=\(self.metrics.batches) peak=\(self.metrics.peakActivePerRelay)")
#endif
    }
}
