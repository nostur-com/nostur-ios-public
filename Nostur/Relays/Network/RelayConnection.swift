//
//  RelayConnection.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/11/2023.
//

import Foundation
import Combine
import Network

public class RelayConnection: NSObject, URLSessionWebSocketDelegate, ObservableObject, Identifiable {
    
    // for views (viewContext)
    @Published private(set) var isConnected = false // don't set directly, set isDeviceConnected or isSocketConnected

    @MainActor
    private func setConnected(_ isConnected: Bool) {
        guard self.isConnected != isConnected else { return }
        self.isConnected = isConnected
        ConnectionPool.shared.updateAnyConnected()
    }
    
    // other (should use queue: "connection-pool"
    public var firstConnection: Bool = true // flag to know if it is connect or reconnect - reconnect will restore some things not needed at first connect in background fetch
    public var url: String { relayData.id }
    public var nreqSubscriptions: Set<String> = []
    public var isNWC: Bool
    public var isNC: Bool
    public var isOutbox: Bool
    
    public var lastMessageReceivedAt: Date? = nil
    private var retryState = RelaySocketRetryState()
    
    
    public var relayData: RelayData
    public var queue: DispatchQueue
    private var urlSession: URLSession?
    
    // For debugging - expose session state
    public var session: URLSession? {
        return urlSession
    }
    private var webSocketTask: URLSessionWebSocketTask?
#if DEBUG
    // Correlate pooled objects separately from successive sockets to the same relay.
    let diagnosticID = String(UUID().uuidString.prefix(8)).lowercased()
    private var diagnosticSocketGeneration = 0
#endif
    private var subscriptions = Set<AnyCancellable>()
    private var outQueue: [SocketMessage] = []
    private var reqDrainScheduled = false
    private var reqSentAt: [Date] = []
    private let maxReqPerSecond = 6
    private let maxOutQueueSize = 40
    private let reqDrainDelay: TimeInterval = 0.2
    
    public func resetExponentialBackOff() {
        queue.async(flags: .barrier) { [weak self] in
            self?.retryState.resetCooldown()
        }
    }
    
    public var stats: RelayConnectionStats {
        if let existingStats = ConnectionPool.shared.connectionStats[self.url] {
            return existingStats
        }
        else {
            let newStats = RelayConnectionStats(id: self.url)
            ConnectionPool.shared.connectionStats[self.url] = newStats
            return newStats
        }
    }
    
    private var isDeviceConnected = false {
        didSet {
#if DEBUG
            L.sockets.debug("connection.isDeviceConnected = \(self.isDeviceConnected) - \(self.url)")
#endif
            if !isDeviceConnected {
                isSocketConnecting = false
                isSocketConnected = false
                Task { @MainActor in
                    self.setConnected(false)
                }
            }
        }
    }
    
    public var isSocketConnecting = false
    
    public var isSocketConnected = false {
        didSet {
            isSocketConnecting = false
            guard oldValue != isSocketConnected else { return }
            let isSocketConnected = isSocketConnected
            let wasConnected = oldValue
            Task { @MainActor in
                // Disconnected? If this is last "disconnect" we should set "VPN detected" to false
                if wasConnected && !isSocketConnected && !ConnectionPool.shared.anyConnected {
                    // Similar as in NetworMonitor.init .isConnectedSubject.sink { }
                    if NetworkMonitor.shared.vpnConfigurationDetected {
                        NetworkMonitor.shared.vpnConfigurationDetected = false
                    }
                    if NetworkMonitor.shared.actualVPNconnectionDetected {
                        NetworkMonitor.shared.actualVPNconnectionDetected = false
                    }
                    if SettingsStore.shared.enableVPNdetection {
#if DEBUG
                        L.og.debug("RelayConnection \(self.url) - last disconnect")
#endif
                        ConnectionPool.shared.disconnectAllAdditional()
                    }
                    sendNotification(.lastDisconnection)
                }
                
                // Or if it is the first connection after all were disconnected,
                // we should reset the exponential back off and connectAll
                else if !wasConnected && isSocketConnected && !ConnectionPool.shared.anyConnected {
#if DEBUG
                    L.og.debug("RelayConnection \(self.url) - first connection after all disconnected")
#endif
//                    ConnectionPool.shared.connectAll(resetExpBackOff: true) // <-- TODO: Causes duplicate connections, at start up .connectAll has first connection, and triggers .connectAll again
                    // Should trigger resume on any visible feed?
                    sendNotification(.firstConnection)
                }
                self.setConnected(isSocketConnected)
            }
#if DEBUG
            L.sockets.debug("🔑 AUTH state reset conn=\(self.diagnosticID) socket=\(self.diagnosticSocketGeneration) relay=\(self.url) connected=\(wasConnected)->\(isSocketConnected) attempts=\(self.recentAuthAttempts) submitted=\(self.didAuth) -[LOG]-")
#endif
            recentAuthAttempts = 0
            didAuth = false
        }
    }
    
    init(_ relayData: RelayData, isNWC: Bool = false, isNC: Bool = false, isOutbox: Bool = false, queue: DispatchQueue) {
        self.relayData = relayData
        self.queue = queue
        self.isNC = isNC
        self.isNWC = isNWC
        self.isOutbox = isOutbox
        self.isDeviceConnected = NetworkMonitor.shared.isConnected
        super.init()
        
        NetworkMonitor.shared.isConnectedSubject
            .receive(on: self.queue)
            .sink { [weak self] isNowConnected in
                self?.queue.async(flags: .barrier) { [weak self] in
                    guard let self = self else { return }
                    let fromDisconnectedToConnected = !self.isDeviceConnected && isNowConnected
                    let fromConnectedToDisconnected = self.isDeviceConnected && !isNowConnected
                    if self.isDeviceConnected != isNowConnected { // Status changed
                        self.isDeviceConnected = isNowConnected
                    }
                    if (fromDisconnectedToConnected) { // Connected
                        if self.relayData.shouldConnect {
                            self.connect(forceConnectionAttempt: true)
                        }
                    }
                    else if fromConnectedToDisconnected { // Disconnected
                        if self.relayData.shouldConnect || self.isConnected {
                            self.disconnect()
                        }
                    }
                }
            }
            .store(in: &subscriptions)
        
        sendAfterAuthSubject
            .debounce(for: .seconds(0.25), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.sendAfterAuth()
            }
            .store(in: &subscriptions)
        
        authSubject
            .throttle(for: .seconds(5.5), scheduler: RunLoop.main, latest: false)
            .sink { [weak self] in
                self?.sendAuthResponse()
            }
            .store(in: &subscriptions)
    }
    
    // To throttle too many auths
    public var authSubject = PassthroughSubject<Void, Never>()
    
    // To delay other messages until after auth
    private var sendAfterAuthSubject = PassthroughSubject<Void, Never>()
    
    public func connect(andSend: String? = nil, forceConnectionAttempt: Bool = false, reason: String = #function) {
#if DEBUG
        if (forceConnectionAttempt) {
            L.sockets.debug("connect(\(andSend != nil ? "andSend" : "")) forceConnectionAttempt: \(forceConnectionAttempt) (\(self.relayData.url)) -[LOG]-")
        }
#endif
        if isOutbox && !vpnGuardOK() { // TODO: Maybe need a small delay so VPN has time to connect first?
#if DEBUG
            L.sockets.debug("📡📡 No VPN: Connection cancelled (\(self.relayData.url)) -[LOG]-"); return
#endif
        }
        DispatchQueue.main.async { [weak self] in
            self?.queue.async(flags: .barrier) { [weak self] in
                guard let self = self else { return }
#if DEBUG
                L.sockets.debug("🔌 CONNECT requested conn=\(self.diagnosticID) socket=\(self.diagnosticSocketGeneration) relay=\(self.url) reason=\(reason) outbox=\(self.isOutbox) publishedConnected=\(self.isConnected) socketConnected=\(self.isSocketConnected) connecting=\(self.isSocketConnecting) force=\(forceConnectionAttempt) queued=\(self.outQueue.count) -[LOG]-")
#endif
                guard !self.isSocketConnected else { return } // queue-owned socket state
                guard self.isDeviceConnected else {
#if DEBUG
                    L.sockets.debug("\(self.url) - No internet, skipping connect() -[LOG]-")
#endif
                    self.isSocketConnecting = false
                    return
                }
                guard !self.isSocketConnecting else {
                    if let andSend {
                        let socketMessage = SocketMessage(text: andSend, subscriptionId: nil)
                        self.outQueue.append(socketMessage)
                    }
                    return
                }
                guard Self.isValidRelayWebSocketURL(self.relayData.url) else {
#if DEBUG
                    L.sockets.notice("Skipping malformed relay URL: \(self.relayData.url) conn=\(self.diagnosticID) reason=\(reason) outbox=\(self.isOutbox) queued=\(self.outQueue.count)")
#endif
                    self.isSocketConnecting = false
                    self.isSocketConnected = false
                    self.webSocketTask?.cancel()
                    self.webSocketTask = nil
                    self.urlSession?.invalidateAndCancel()
                    self.urlSession = nil
                    self.outQueue = []
                    return
                }
                if let andSend {
                    self.outQueue.append(SocketMessage(text: andSend, subscriptionId: nil))
                }
                self.nreqSubscriptions = []
                let remaining = self.retryState.remainingCooldown(now: ProcessInfo.processInfo.systemUptime)
                guard forceConnectionAttempt || remaining == 0 else {
#if DEBUG
                    L.sockets.debug("🔌 Skipping reconnect relay=\(self.url) cooldown=\(remaining)s -[LOG]-")
#endif
                    return
                }
                self.isSocketConnecting = true

                if !self.isSocketConnected {
                    self.urlSession?.invalidateAndCancel()
                    self.urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
                    
                    if let url = URL(string: relayData.url) {
                        var urlRequest = URLRequest(url: url)
                        
                        
                        if #available(iOS 16, *) { } else {
                            // Disable extensions on iOS 15
                            urlRequest.setValue("", forHTTPHeaderField: "Sec-WebSocket-Extensions") // "When websocket-server is sending a large frame data（>1024 bytes) to client(ios15 equipment), client websocket will be closed with an error."
                        }

                        self.webSocketTask = self.urlSession?.webSocketTask(with: urlRequest)
                        self.webSocketTask?.delegate = self
                    }
                    
#if DEBUG
                    self.diagnosticSocketGeneration += 1
                    L.sockets.debug("🔌 SOCKET created conn=\(self.diagnosticID) socket=\(self.diagnosticSocketGeneration) relay=\(self.url) task=\(self.webSocketTask?.taskIdentifier ?? -1) reason=\(reason) -[LOG]-")
#endif
                    if let task = self.webSocketTask {
                        self.retryState.begin(socket: ObjectIdentifier(task))
                        task.resume()
                    }
                }
                
                guard self.webSocketTask != nil, !outQueue.isEmpty else { return }
                
                if self.relayData.auth && !self.didAuth && !(self.didWaitCount > 5) {
                    self.didWaitCount += 1
#if DEBUG
                    L.sockets.debug("\(self.url) relayData.auth == true - didWaitCount: \(self.didWaitCount) -[LOG]-")
#endif
                    self.sendAfterAuthSubject.send()
                    return
                }
            }
        }
    }
    
    public func sendAfterAuth() {
#if DEBUG
        L.sockets.debug("\(self.url) sendAfterAuth() -[LOG]-")
#endif
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            guard let webSocketTask = self.webSocketTask, !outQueue.isEmpty, self.isSocketConnected else { return }
            self.flushOutQueue(using: webSocketTask)
        }
    }
    
    public var eventsThatMayNeedAuth: [String: String] = [:] // [ post id : event message text string ]
    
    public func sendMessage(_ text: String, subscriptionId: String? = nil, bypassQueue: Bool = false) {
        enqueueMessage(text, subscriptionId: subscriptionId, bypassQueue: bypassQueue)
    }

    func sendViewingMessage(_ text: String, subscriptionId: String, expiresAt: TimeInterval) {
        enqueueMessage(text, subscriptionId: subscriptionId, expiresAt: expiresAt)
    }

    private func enqueueMessage(_ text: String, subscriptionId: String? = nil,
                                bypassQueue: Bool = false, expiresAt: TimeInterval? = nil) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            if let expiresAt, ProcessInfo.processInfo.systemUptime >= expiresAt { return }
            if !self.isDeviceConnected {
#if DEBUG
                L.sockets.debug("🔴🔴 No internet. Did not sendMessage \(self.url) -[LOG]-")
#endif
                return
            }

            // CLOSE is a control message: send immediately, never keep in outQueue.
            if Self.isCloseMessage(text) {
                guard self.isSocketConnected, let webSocketTask = self.webSocketTask else {
#if DEBUG
                    L.sockets.debug("🔚🔚 Not connected. Dropping CLOSE for \(self.url): \(text) -[LOG]-")
#endif
                    return
                }
                webSocketTask.send(.string(text)) { error in
                    if let error {
                        self.didReceiveError(error, from: webSocketTask)
                    }
                }
                return
            }
            
            if bypassQueue { // To give prio to stuff like AUTH
                if self.isSocketConnected, let webSocketTask = self.webSocketTask {
#if DEBUG
                L.sockets.debug("🟠🟠🏎️🔌🔌 SEND (bypassQueue) \(self.url) conn=\(self.diagnosticID) socket=\(self.diagnosticSocketGeneration): \(text) -[LOG]-")
#endif
                    webSocketTask.send(.string(text)) { error in
                        if let error {
                            self.didReceiveError(error, from: webSocketTask)
                        }
                    }
                }
                else {
                    let socketMessage = SocketMessage(expiresAt: expiresAt, text: text, subscriptionId: subscriptionId)
                    self.outQueue.insert(socketMessage, at: 0)
                }
                
                return
            }
            
            let socketMessage = SocketMessage(expiresAt: expiresAt, text: text, subscriptionId: subscriptionId)
            if Self.isReqMessage(text), let subscriptionId {
                self.outQueue.removeAll { $0.subscriptionId == subscriptionId && Self.isReqMessage($0.text) }
            }
            self.outQueue.append(socketMessage)
            if self.outQueue.count > self.maxOutQueueSize {
                self.outQueue = Array(self.outQueue.suffix(self.maxOutQueueSize))
            }
#if DEBUG
            if Self.isReqMessage(text), let subscriptionId, !self.isSocketConnected {
                FeedFetchDebug.recordSend(
                    subscriptionId: subscriptionId,
                    relay: self.url,
                    queued: true,
                    isFirstConnection: self.firstConnection,
                    isOutbox: self.isOutbox
                )
            }
#endif
            
            if self.webSocketTask == nil || !self.isSocketConnected {
#if DEBUG
                if self.retryState.remainingCooldown(now: ProcessInfo.processInfo.systemUptime) == 0 {
                    L.sockets.debug("🔴🔴 Not connected. \(self.url) (queued): \(text.prefix(215)) -[LOG]-")
                }
#endif
                return
            }
            
            if self.relayData.auth && !self.didAuth && !(self.didWaitCount > 5) {
                self.didWaitCount += 1
#if DEBUG
                L.sockets.debug("\(self.url) relayData.auth == true. Waiting 0.25 sec - didWaitCount: \(self.didWaitCount) - : \(text.prefix(155)) -[LOG]-")
#endif
                self.sendAfterAuthSubject.send()
                return
            }
            
            guard let webSocketTask = self.webSocketTask, !outQueue.isEmpty else { return }
            self.flushOutQueue(using: webSocketTask)
        }
    }
    
    /// Drop a queued REQ, send CLOSE if it was active, and forget the sub id
    /// so a late connect cannot flush a stale catch-up request.
    public func closeAndDropSubscription(_ subscriptionId: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            let hadActive = self.nreqSubscriptions.contains(subscriptionId)
            self.outQueue.removeAll { message in
                if message.subscriptionId == subscriptionId { return true }
                return message.text.contains("\"\(subscriptionId)\"")
            }
            self.nreqSubscriptions.remove(subscriptionId)
            guard hadActive, self.isSocketConnected, let webSocketTask = self.webSocketTask else { return }
            let closeMessage = ClientMessage.close(subscriptionId: subscriptionId)
            webSocketTask.send(.string(closeMessage)) { error in
                if let error {
                    self.didReceiveError(error, from: webSocketTask)
                }
            }
        }
    }

    public func completeReqSubscription(_ subscriptionId: String, keepActive: Bool = false) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            // EOSE ends the history query, not an OPEN-59 live subscription.
            if !keepActive {
                self.nreqSubscriptions.remove(subscriptionId)
            }
            guard let webSocketTask = self.webSocketTask, self.isSocketConnected else { return }
            self.flushOutQueue(using: webSocketTask)
        }
    }
    
    private func flushOutQueue(using webSocketTask: URLSessionWebSocketTask) {
        guard !outQueue.isEmpty else { return }

        if outQueue.count > maxOutQueueSize {
            let dropped = outQueue.count - maxOutQueueSize
            outQueue = Array(outQueue.suffix(maxOutQueueSize))
#if DEBUG
            L.sockets.debug("🟠🟠🏎️🔌🔌 \(self.url): outQueue overflow, dropped oldest \(dropped), keeping latest \(self.maxOutQueueSize) -[LOG]-")
#endif
        }

        while !outQueue.isEmpty {
            // A delayed connect/auth or a saturated relay queue must not flush
            // count-prefetch REQs whose scheduler deadline has already passed.
            if let expiresAt = outQueue[0].expiresAt, ProcessInfo.processInfo.systemUptime >= expiresAt {
                outQueue.removeFirst()
                continue
            }
            let now = Date()
            trimReqSendHistory(now: now)

            let reqRateLimited = reqSentAt.count >= maxReqPerSecond
            var sendIndex = 0

            if reqRateLimited && Self.isReqMessage(outQueue[0].text) {
                if let closeIndex = outQueue.firstIndex(where: { Self.isCloseMessage($0.text) }) {
                    sendIndex = closeIndex
                }
                else {
                    let delay = nextReqDrainDelay(now: now)
#if DEBUG
                    L.sockets.debug("🟠🟠🏎️🔌🔌 \(self.url): req rate limited \(self.reqSentAt.count)/\(self.maxReqPerSecond) (outQueue: \(self.outQueue.count)) -[LOG]-")
#endif
                    scheduleReqDrain(after: delay)
                    break
                }
            }

            let out = outQueue[sendIndex]

#if DEBUG
            L.sockets.debug("🟠🟠🏎️🔌🔌 SENDING FROM OUTQUEUE \(self.url): \(out.text.prefix(255)) -[LOG]-")
#endif
            if Self.isReqMessage(out.text) {
                if let subscriptionId = out.subscriptionId { nreqSubscriptions.insert(subscriptionId) }
                reqSentAt.append(now)
                if let subscriptionId = out.subscriptionId {
                    self.stats.recordTrackedReqSent(subscriptionId: subscriptionId, nowUptimeNs: DispatchTime.now().uptimeNanoseconds)
#if DEBUG
                    FeedFetchDebug.recordSend(
                        subscriptionId: subscriptionId,
                        relay: self.url,
                        queued: false,
                        isFirstConnection: self.firstConnection,
                        isOutbox: self.isOutbox
                    )
#endif
                }
            }

            webSocketTask.send(.string(out.text)) { error in
                if let error {
                    self.didReceiveError(error, from: webSocketTask, retryMessage: out)
                }
            }
            outQueue.remove(at: sendIndex)
        }
    }

    private func scheduleReqDrain(after delay: TimeInterval = 0.20) {
        guard !reqDrainScheduled, let scheduledSocket = webSocketTask else { return }
        reqDrainScheduled = true
        queue.asyncAfter(deadline: .now() + max(0.05, delay)) { [weak self] in
            guard let self, scheduledSocket === self.webSocketTask,
                  self.retryState.isCurrent(socket: ObjectIdentifier(scheduledSocket)) else { return }
            self.reqDrainScheduled = false
            guard self.isSocketConnected else { return }
            self.flushOutQueue(using: scheduledSocket)
        }
    }

    private func trimReqSendHistory(now: Date) {
        reqSentAt.removeAll(where: { now.timeIntervalSince($0) >= 1.0 })
    }

    private func nextReqDrainDelay(now: Date) -> TimeInterval {
        guard let oldest = reqSentAt.first else { return reqDrainDelay }
        return max(reqDrainDelay, 1.0 - now.timeIntervalSince(oldest))
    }

    private static func isReqMessage(_ message: String) -> Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[\"REQ\"")
    }

    private static func isEventMessage(_ message: String) -> Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[\"EVENT\"")
    }

    private static func isLatencyResponseMessage(_ message: String) -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("[\"EVENT\"")
            || trimmed.hasPrefix("[\"EOSE\"")
            || trimmed.hasPrefix("[\"CLOSED\"")
    }

    private static func subscriptionIdForLatencyResponse(from message: String) -> String? {
        guard isLatencyResponseMessage(message) else { return nil }
        return extractSecondStringElement(from: message)
    }

    // Fast-path parser for relay frames like ["EVENT","subId",...], ["EOSE","subId"], ["CLOSED","subId",...]
    private static func extractSecondStringElement(from message: String) -> String? {
        let bytes = message.utf8
        guard !bytes.isEmpty else { return nil }

        var start = bytes.startIndex
        var end = bytes.endIndex

        while start < end, isJSONWhitespace(bytes[start]) {
            start = bytes.index(after: start)
        }

        while start < end {
            let beforeEnd = bytes.index(before: end)
            guard isJSONWhitespace(bytes[beforeEnd]) else { break }
            end = beforeEnd
        }

        guard start < end else { return nil }

        var quoteCount = 0
        var i = start

        while i < end {
            if bytes[i] == 0x22 {
                quoteCount += 1
                if quoteCount == 3 {
                    var j = bytes.index(after: i)
                    var valueBytes: [UInt8] = []
                    valueBytes.reserveCapacity(64)

                    while j < end {
                        let c = bytes[j]
                        if c == 0x5C {
                            j = bytes.index(after: j)
                            guard j < end else { return nil }
                            valueBytes.append(bytes[j])
                            j = bytes.index(after: j)
                            continue
                        }

                        if c == 0x22 {
                            return String(decoding: valueBytes, as: UTF8.self)
                        }

                        valueBytes.append(c)
                        j = bytes.index(after: j)
                    }

                    return nil
                }
            }

            i = bytes.index(after: i)
        }

        return nil
    }

    private static func isJSONWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }

    private static func isCloseMessage(_ message: String) -> Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[\"CLOSE\"")
    }

    // Guard against malformed relay hints being treated as a single URL
    // (for example concatenated strings containing multiple ws/wss prefixes).
    private static func isValidRelayWebSocketURL(_ relayUrl: String) -> Bool {
        let trimmed = relayUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let lower = trimmed.lowercased()
        guard lower.hasPrefix("wss://") || lower.hasPrefix("ws://") else { return false }

        let schemeOccurrences = lower.components(separatedBy: "wss://").count - 1
            + lower.components(separatedBy: "ws://").count - 1
        guard schemeOccurrences == 1 else { return false }

        // Reject obvious malformed values like pasted lists with encoded spaces.
        guard !lower.contains("%20ws://"), !lower.contains("%20wss://") else { return false }

        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              (scheme == "wss" || scheme == "ws"),
              let host = components.host,
              !host.isEmpty
        else {
            return false
        }

        return true
    }
    
    // Planned disconnect invalidates callbacks and resets the retry cooldown.
    public func disconnect() {
#if DEBUG
        L.og.debug("🔴 Disconnecting: \(self.url) conn=\(self.diagnosticID) -[LOG]-")
#endif
        queue.async(flags: .barrier) { [weak self] in
            self?.retryState = RelaySocketRetryState()
            self?.webSocketTask?.cancel(with: .normalClosure, reason: nil)
            self?.webSocketTask = nil
            
            self?.urlSession?.invalidateAndCancel() 
            self?.urlSession = nil
            
            self?.firstConnection = true
            self?.nreqSubscriptions = []
            self?.reqSentAt = []
            self?.reqDrainScheduled = false
            self?.lastMessageReceivedAt = nil
            self?.isSocketConnected = false
            self?.outQueue = [] // Clear any pending messages
        }
    }
    
    deinit {
#if DEBUG
        L.og.debug("🗑️ Deinitializing RelayConnection: \(self.url) -[LOG]-")
#endif
        // Ensure cleanup even if disconnect() wasn't called
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        subscriptions.removeAll()
        outQueue.removeAll()
        nreqSubscriptions.removeAll()
        reqSentAt.removeAll()
    }
    
    public func ping() {
#if DEBUG
        L.sockets.debug("PING: \(self.url) -[LOG]-")
#endif
        queue.async { [weak self] in
            if self?.webSocketTask == nil {
#if DEBUG
                L.sockets.debug("🔴🔴 PING: Not connected. ????? \(self?.url ?? "") -[LOG]-")
#endif
                Task { @MainActor [weak self] in
                    self?.setConnected(false)
                }
                return
            }
            guard let self, let webSocketTask = self.webSocketTask else { return }
            guard self.retryState.isCurrent(socket: ObjectIdentifier(webSocketTask)) else { return }
            webSocketTask.sendPing { [weak self] error in
                if let error {
                    self?.didReceiveError(error, from: webSocketTask)
                } else {
                    self?.didReceivePong(from: webSocketTask)
                }
            }
        }
    }
    
    // didBecomeInvalidWithError
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {
        guard let error else { return }
        queue.async(flags: .barrier) { [weak self] in
            guard let self, session === self.urlSession, let task = self.webSocketTask else { return }
            self.didReceiveError(error, from: task)
        }
    }
    
    // didReceiveInformationalResponse
    @available(iOS 17.0, *)
    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceiveInformationalResponse response: HTTPURLResponse) {
#if DEBUG
        L.sockets.debug("🔴🔴 didReceiveInformationalResponse: \(self.url.replacingOccurrences(of: "wss://", with: "").replacingOccurrences(of: "ws://", with: "").prefix(25)): \(response.statusCode.description) -[LOG]-")
#endif
    }
    
    // didCompleteWithError
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error, let webSocketTask = task as? URLSessionWebSocketTask {
            self.didReceiveError(error, from: webSocketTask)
        }
    }
    
    private func didReceiveMessage(string: String, from webSocketTask: URLSessionWebSocketTask) {
        // Respond to a WebSocket connection receiving a `String` message
        queue.async(flags: .barrier) { [weak self] in
            guard let self, self.retryState.isCurrent(socket: ObjectIdentifier(webSocketTask)) else { return }
            if self.isSocketConnecting {
                self.isSocketConnecting = false
            }
            if !self.isSocketConnected {
                self.isSocketConnected = true
            }
#if DEBUG
            let noLog = if string.contains("\"EOSE\"") || (string.contains("\"RM.getAuthorContactsList")) || (string.contains("\"CLOSE\"")) || (string.contains("\"Following-")) || (string.contains("\"List-")) || (string.contains("\"RESUME-")) || (string.contains("\"UM-")) || (string.contains("\"AC-")) || (string.contains("\"PAGE-")) || (string.contains("\"VIEWING-")) || (string.contains("\"Notifications")) {
                "-[LOG]-"
            } else { "" }
            L.sockets.debug("🟠🟠🏎️🔌 RECEIVED: \(self.url.replacingOccurrences(of: "wss://", with: "").replacingOccurrences(of: "ws://", with: "").prefix(25)): \(noLog) \(string)")
#endif
            MessageParser.shared.socketReceivedMessage(text: string, relayUrl: self.url, client: self)
            self.lastMessageReceivedAt = .now
            self.retryState.receivedResponse(now: ProcessInfo.processInfo.systemUptime)
            if Self.isEventMessage(string) {
                self.stats.messages += 1
            }
            if let subscriptionId = Self.subscriptionIdForLatencyResponse(from: string) {
                self.stats.recordTrackedReqResponse(subscriptionId: subscriptionId)
#if DEBUG
                if Self.isEventMessage(string) {
                    ViewingSubscriptions.shared.recordEvent(relay: self.url, subscriptionId: subscriptionId)
                }
#endif
            }
            
        }
    }
    
    private func didReceiveMessage(data: Data, from webSocketTask: URLSessionWebSocketTask) {
        // Respond to a WebSocket connection receiving a binary `Data` message
        queue.async(flags: .barrier) { [weak self] in
            guard let self, self.retryState.isCurrent(socket: ObjectIdentifier(webSocketTask)) else { return }
            if self.isSocketConnecting {
                self.isSocketConnecting = false
            }
            if !self.isSocketConnected {
                self.isSocketConnected = true
            }
            self.lastMessageReceivedAt = .now
            self.retryState.receivedResponse(now: ProcessInfo.processInfo.systemUptime)

        }
    }
    
    private func didReceiveError(_ error: Error, from webSocketTask: URLSessionWebSocketTask, retryMessage: SocketMessage? = nil) {
        DispatchQueue.main.async { [weak self] in
            let anyConnected = ConnectionPool.shared.anyConnected
            self?.queue.async(flags: .barrier) { [weak self] in
                guard let self,
                      let delay = self.retryState.fail(socket: ObjectIdentifier(webSocketTask), now: ProcessInfo.processInfo.systemUptime)
                else { return } // Duplicate failure or callback from a replaced/planned-disconnect socket.

                self.outQueue = retryMessage.map { [$0] } ?? []
                webSocketTask.cancel()
                self.reqDrainScheduled = false
                self.nreqSubscriptions = []
                self.lastMessageReceivedAt = nil
                self.isSocketConnected = false
                if retryMessage != nil {
                    // Preserve the failed send's retry without bypassing cooldown.
                    self.queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                        guard let self, webSocketTask === self.webSocketTask,
                              !DisabledRelaysStore.isDisabled(self.url),
                              !ConnectionPool.shared.penaltybox.contains(self.url),
                              !self.isOutbox || SettingsStore.shared.enableOutboxRelays else { return }
                        self.connect(reason: "retry failed send")
                    }
                }
#if DEBUG
                L.sockets.debug("🔌 SOCKET failure conn=\(self.diagnosticID) socket=\(self.diagnosticSocketGeneration) relay=\(self.url) domain=\((error as NSError).domain) code=\((error as NSError).code) error=\(error.localizedDescription) retryAfter=\(delay)s")
#endif
                DispatchQueue.main.async {
                    sendNotification(.socketNotification, "Error: \(self.url) \(error.localizedDescription)")
                }
                let code = (error as NSError).code
                if Set([-999,53,54,57]).contains(code) {
                    // Transient socket failures still enter cooldown, but do not
                    // permanently penalize an otherwise reachable outbox relay.
                    return
                }

                self.stats.errors += 1
                self.stats.addErrorMessage(error.localizedDescription)
                
                guard self.isOutbox else { return } // Only outbox relays can go in penalty box, not normal relays
                guard SettingsStore.shared.enableOutboxRelays else { return }
                guard ConnectionPool.shared.canPutInPenaltyBox(self.url) else { return }
                
                if Set([-1200,-1003,-1011,100,-1202]).contains(code) { // Error codes to put directly in penalty box
                    // -1200 An SSL error has occurred and a secure connection to the server cannot be made.
                    // -1003 A server with the specified hostname could not be found.
                    // -1011 There was a bad response from the server.
                    // -1202 The certificate for this server is invalid. You might be connecting to a server that is pretending to be “nostr.zebedee.cloud” which could put your confidential information at risk.
                    // 100 The operation couldn’t be completed. Protocol error
                    ConnectionPool.shared.penaltybox.insert(self.url)
                }
                // if other relays do respond, but this gives error, continue error handling, but if no relays respond, the problem is not relay but something else, so dont put in penalty box
                else if Set([-1001,-1005]).contains(code) && (self.stats.connected == 0) && anyConnected {
                    // -1005 The network connection was lost.
                    // -1001 The request timed out.
                    
                    ConnectionPool.shared.penaltybox.insert(self.url)
                }
                else if (self.stats.errors > 3) && (self.stats.connected == 0) { // other errors, put in penalty box if too many and no success connection ever
                    ConnectionPool.shared.penaltybox.insert(self.url)
                }
            }
        }
    }
    
    private func didReceivePong(from webSocketTask: URLSessionWebSocketTask) {
//        L.sockets.debug("PING: Did receive PONG: \(self.url)")
        // Respond to a WebSocket connection receiving a Pong from the peer
        queue.async(flags: .barrier) { [weak self] in
            guard let self, self.retryState.isCurrent(socket: ObjectIdentifier(webSocketTask)) else { return }
            if self.isSocketConnecting {
                self.isSocketConnecting = false
            }
            if !self.isSocketConnected {
                self.isSocketConnected = true
            }
            self.lastMessageReceivedAt = .now
            self.retryState.receivedResponse(now: ProcessInfo.processInfo.systemUptime)
        }
    }
    
    // didOpenWithProtocol
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        self.queue.async(flags: .barrier) { [weak self] in
            guard let self, self.retryState.isCurrent(socket: ObjectIdentifier(webSocketTask)) else { return }
#if DEBUG
            L.sockets.debug("🔌 SOCKET opened conn=\(self.diagnosticID) socket=\(self.diagnosticSocketGeneration) relay=\(self.url) task=\(webSocketTask.taskIdentifier) currentTask=\(webSocketTask === self.webSocketTask) firstConnection=\(self.firstConnection) outbox=\(self.isOutbox) queued=\(self.outQueue.count) -[LOG]-")
#endif
            self.stats.connected += 1
            self.retryState.opened(now: ProcessInfo.processInfo.systemUptime)
            self.startReceiving(from: webSocketTask)
            self.nreqSubscriptions = []
            self.lastMessageReceivedAt = .now
            self.isSocketConnected = true
            if self.firstConnection {
                DispatchQueue.main.async { [weak self] in
                    sendNotification(.socketConnected, "Connected: \(self?.url ?? "?")")
                }
            }
            else { 
                // restore subscriptions
#if DEBUG
                L.sockets.debug("🔌 Subscription restore after reconnect conn=\(self.diagnosticID) socket=\(self.diagnosticSocketGeneration) relay=\(self.url) restore=\(!self.isOutbox) -[LOG]-")
#endif
                if !isOutbox {
                    DispatchQueue.main.async { [weak self] in
                        if IS_CATALYST || !AppState.shared.appIsInBackground {
                            if self?.relayData.auth ?? false {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    FeedsCoordinator.shared.resumeFeeds()
                                    NotificationsViewModel.restoreSubscriptions()
                                    DMsVM.restoreSubscriptions()
                                }
                            }
                            else {
                                FeedsCoordinator.shared.resumeFeeds()
                                NotificationsViewModel.restoreSubscriptions()
                                DMsVM.restoreSubscriptions()
                            }
                        }
                        sendNotification(.socketConnected, "Connected: \(self?.url ?? "?")")
                    }
                }
            }
            self.firstConnection = false

            guard let webSocketTask = self.webSocketTask, !outQueue.isEmpty else { return }
            
            if self.relayData.auth && !self.didAuth && !(self.didWaitCount > 5) {
                self.didWaitCount += 1
#if DEBUG
                L.sockets.debug("relayData.auth == true but did not auth yet, waiting 0.25 secs - didWaitCount: \(self.didWaitCount) -[LOG]-")
#endif
                self.sendAfterAuthSubject.send()
                return
            }
            else {
                self.flushOutQueue(using: webSocketTask)
            }
        }
#if DEBUG
        L.sockets.debug("🏎️🏎️🔌 CONNECTED \(self.url) - didOpenWithProtocol -[LOG]-")
#endif
    }
    
    // didCloseWith
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {

        let description = "WebSocket closed (\(closeCode.rawValue)): \(reason.flatMap { String(data: $0, encoding: .utf8) } ?? "no reason")"
        didReceiveError(NSError(domain: NSPOSIXErrorDomain, code: 57, userInfo: [NSLocalizedDescriptionKey: description]), from: webSocketTask)
    }

    private func startReceiving(from webSocketTask: URLSessionWebSocketTask) {
        webSocketTask.receive { [weak self] result in
            guard let self else { return }
            self.queue.async(flags: .barrier) { [weak self] in
                guard let self, self.retryState.isCurrent(socket: ObjectIdentifier(webSocketTask)) else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .data(let data):
                        self.didReceiveMessage(data: data, from: webSocketTask)
                    case .string(let text):
                        self.didReceiveMessage(string: text, from: webSocketTask)
                    @unknown default:
                        break
                    }
                    self.startReceiving(from: webSocketTask)
                case .failure(let error):
                    self.didReceiveError(error, from: webSocketTask)
                }
            }
        }
    }

    private var lastAuthChallenge: String?
    public var recentAuthAttempts: Int = 0
    private var didAuth: Bool = false
    private var didWaitCount: Int = 0 // relayData.auth == true. Waiting 0.25 sec (if this happens too much, we don't wait anymore)
    
    public func handleAuth(_ message: String, accountPubkey: String? = nil, whenSubmitted: ((String) -> Void)? = nil) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            guard let messageData = message.data(using: .utf8) else { return }

            let decoder = JSONDecoder()
            guard let authMessage: [String] = try? decoder.decode([String].self, from: messageData),
                  authMessage.count >= 2,
                  authMessage[0] == "AUTH"
            else { return }

#if DEBUG
            L.sockets.debug("🔑 AUTH challenge conn=\(self.diagnosticID) socket=\(self.diagnosticSocketGeneration) relay=\(self.url) repeated=\(self.lastAuthChallenge == authMessage[1]) attempts=\(self.recentAuthAttempts) submitted=\(self.didAuth) connected=\(self.isSocketConnected) outbox=\(self.isOutbox) -[LOG]-")
#endif
            self.lastAuthChallenge = authMessage[1]
            if let whenSubmitted {
                self.sendAuthResponse(accountPubkey: accountPubkey, whenSubmitted: whenSubmitted)
            } else {
                self.authSubject.send()
            }
        }
    }

    public func sendAuthResponse(usingAccount: CloudAccount? = nil, force: Bool = false, accountPubkey: String? = nil, whenSubmitted: ((String) -> Void)? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let requestedAccount = accountPubkey.flatMap { pubkey in
                AccountsState.shared.accounts.first { $0.publicKey == pubkey && $0.isFullAccount }
            }
            guard accountPubkey == nil || requestedAccount != nil,
                  let authAccount = resolveAuthAccount(relayData, usingAccount: requestedAccount ?? usingAccount) else {
#if DEBUG
                L.sockets.debug("🔑 AUTH skipped conn=\(self.diagnosticID) relay=\(self.url) reason=no eligible account")
#endif
                return
            }
            guard !self.relayData.excludedPubkeys.contains(authAccount.publicKey) else { return }
            
#if DEBUG
            L.sockets.debug("🔑 AUTH account selected: \(authAccount.anyName) - \(self.relayData.id) conn=\(self.diagnosticID) force=\(force)")
#endif
            
            self.queue.async { [weak self] in
                guard let self else { return }
                
                guard let challenge = self.lastAuthChallenge else {
#if DEBUG
                    L.sockets.debug("🔑 AUTH skipped conn=\(self.diagnosticID) socket=\(self.diagnosticSocketGeneration) reason=no challenge")
#endif
                    return
                }
                guard force || self.recentAuthAttempts < 5 else {
#if DEBUG
                    L.sockets.debug("🔑 AUTH skipped conn=\(self.diagnosticID) socket=\(self.diagnosticSocketGeneration) reason=attempt limit attempts=\(self.recentAuthAttempts)")
#endif
                    return
                }
#if DEBUG
                L.sockets.debug("🔑 AUTH signing conn=\(self.diagnosticID) socket=\(self.diagnosticSocketGeneration) relay=\(self.url) attempt=\(self.recentAuthAttempts + 1) submitted=\(self.didAuth) challenge=\(challenge)")
#endif
                
                var authResponse = NEvent(content: "")
                authResponse.kind = .auth
                authResponse.tags.append(NostrTag(["relay", relayData.url]))
                authResponse.tags.append(NostrTag(["challenge", challenge]))
                
                DispatchQueue.main.async {
                    if authAccount.isNC {
                        authResponse = authResponse.withId()
                        RemoteSignerManager.shared.requestSignature(forEvent: authResponse, usingAccount: authAccount, whenSigned: { signedAuthResponse in
#if DEBUG
                            L.sockets.debug("🔑 AUTH submitting conn=\(self.diagnosticID) relay=\(self.url) event=\(signedAuthResponse.id) remoteSigner=true")
#endif
                            whenSubmitted?(signedAuthResponse.id)
                            self.sendMessage(ClientMessage.auth(event: signedAuthResponse), bypassQueue: true)
                            self.queue.async(flags: .barrier) { [weak self] in
                                guard let self else { return }
                                self.recentAuthAttempts = self.recentAuthAttempts + 1
                                self.didAuth = true
                            }
                        })
                    }
                    else if let signedAuthResponse = try? authAccount.signEvent(authResponse) {
#if DEBUG
                        L.sockets.debug("🔑 AUTH submitting conn=\(self.diagnosticID) relay=\(self.url) event=\(signedAuthResponse.id) remoteSigner=false")
#endif
                        whenSubmitted?(signedAuthResponse.id)
                        self.sendMessage(ClientMessage.auth(event: signedAuthResponse), bypassQueue: true)
                        self.queue.async(flags: .barrier) { [weak self] in
                            guard let self else { return }
                            self.recentAuthAttempts = self.recentAuthAttempts + 1
                            self.didAuth = true
                        }
                    }
                    else {
#if DEBUG
                        L.sockets.debug("🔑 AUTH signing failed conn=\(self.diagnosticID) relay=\(self.url)")
#endif
                    }
                }
            }
        }
    }
    
}

// Returns account to auth with, or nil if we should not auth.
func resolveAuthAccount(_ relayData: RelayData, usingAccount: CloudAccount? = nil) -> CloudAccount? {
    
    // usingAccount: for Lock post to relay, ["-"] restricted post
    // overrides relayData.auth: false
    if let usingAccount, usingAccount.isFullAccount {
        return usingAccount
    }
    
    // Auth disabled, but relay + account is in relayFeedAuthPubkeyMap (added by NXColumnView / relay-feed)
    if !relayData.auth, let accountPubkey = ConnectionPool.shared.relayFeedAuthPubkeyMap[relayData.id] {
        if let signingAccount = AccountsState.shared.accounts.first(where: { $0.publicKey == accountPubkey }),
            signingAccount.isFullAccount {
            return signingAccount
        }
    }
    
    // if auth toggle is enabled in app relay settings, auth with active logged in account
    let activeAccountPubkey = AccountsState.shared.activeAccountPublicKey
    if relayData.auth, let activeAccount = AccountsState.shared.accounts.first(where: { $0.publicKey == activeAccountPubkey }), activeAccount.isFullAccount {
        return activeAccount
    }
    
    // else don't auth
    return nil
}
