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
    @Published private(set) var isConnected = false { // don't set directly, set isDeviceConnected or isSocketConnected
        willSet {
            ConnectionPool.shared.updateAnyConnected()
        }
    }
    
    // other (should use queue: "connection-pool"
    public var firstConnection: Bool = true // flag to know if it is connect or reconnect - reconnect will restore some things not needed at first connect in background fetch
    public var url: String { relayData.id }
    public var nreqSubscriptions: Set<String> = []
    public var isNWC: Bool
    public var isNC: Bool
    public var isOutbox: Bool
    
    public var lastMessageReceivedAt: Date? = nil
    private var exponentialReconnectBackOff = 0
    private var skipped: Int = 0
    
    
    public var relayData: RelayData
    public var queue: DispatchQueue
    private var urlSession: URLSession?
    
    // For debugging - expose session state
    public var session: URLSession? {
        return urlSession
    }
    private var webSocketTask: URLSessionWebSocketTask?
    private var subscriptions = Set<AnyCancellable>()
    private var outQueue: [SocketMessage] = []
    
    public func resetExponentialBackOff() {
        self.exponentialReconnectBackOff = 0
        self.skipped = 0
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
                    self.objectWillChange.send()
                    self.isConnected = false
                }
            }
        }
    }
    
    public var isSocketConnecting = false
    
    public var isSocketConnected = false {
        didSet {
            isSocketConnecting = false
            let isSocketConnected = isSocketConnected
            let wasConnected = oldValue
            Task { @MainActor in
                self.objectWillChange.send()
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
                self.isConnected = isSocketConnected
            }
            self.queue.async(flags: .barrier) { [weak self] in
                self?.recentAuthAttempts = 0
                self?.didAuth = false
            }
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
                guard let self = self else { return }
                let fromDisconnectedToConnected = !self.isDeviceConnected && isNowConnected
                let fromConnectedToDisconnected = self.isDeviceConnected && !isNowConnected
                if self.isDeviceConnected != isNowConnected { // Status changed
                    self.queue.async(flags: .barrier) { [weak self] in
                        self?.isDeviceConnected = isNowConnected
                    }
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
    
    public func connect(andSend: String? = nil, forceConnectionAttempt: Bool = false) {
#if DEBUG
        if (forceConnectionAttempt) {
            L.sockets.debug("connect(\(andSend != nil ? "andSend" : "")) forceConnectionAttempt: \(forceConnectionAttempt) (\(self.relayData.url))")
        }
#endif
        if isOutbox && !vpnGuardOK() { // TODO: Maybe need a small delay so VPN has time to connect first?
#if DEBUG
            L.sockets.debug("📡📡 No VPN: Connection cancelled (\(self.relayData.url)"); return
#endif
        }
        DispatchQueue.main.async { [weak self] in
            let anyConnected = ConnectionPool.shared.anyConnected
            
            self?.queue.async(flags: .barrier) { [weak self] in
                guard let self = self else { return }
                guard !self.isConnected else { return } // already connected
                guard self.isDeviceConnected else {
#if DEBUG
                    L.sockets.debug("\(self.url) - No internet, skipping connect()")
#endif
                    self.isSocketConnecting = false
                    return
                }
                guard !self.isSocketConnecting || forceConnectionAttempt else {
                    if let andSend {
                        let socketMessage = SocketMessage(text: andSend)
                        self.outQueue.append(socketMessage)
                    }
                    return
                }
                self.nreqSubscriptions = []
                self.isSocketConnecting = true
                
                guard self.stats.errors == 0 || self.exponentialReconnectBackOff > 512 || self.exponentialReconnectBackOff == 1 || forceConnectionAttempt || self.skipped == self.exponentialReconnectBackOff else { // Should be 0 == 0 to continue, or 2 == 2 etc..
                    self.skipped = self.skipped + 1
                    self.isSocketConnecting = false
                    
                    if self.skipped > 4 { // Skipped too many times, keep only the last message in outQueue (other messages are too old now)
                        if !self.outQueue.isEmpty {
                            let last = self.outQueue.removeLast()
                            self.outQueue = [last]
                        }
                    }
                    
#if DEBUG
                    L.sockets.debug("🏎️🏎️🔌 Skipping reconnect. \(self.url) EB: (\(self.exponentialReconnectBackOff)) skipped: \(self.skipped) -[LOG]-")
#endif
                    return
                }
                self.skipped = 0
                
                if let andSend = andSend {
                    self.outQueue.append(SocketMessage(text: andSend))
                }
                
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
                    
                    self.webSocketTask?.resume()
                    
                    if self.exponentialReconnectBackOff >= 512 {
                        self.exponentialReconnectBackOff = 512
                    }
                    else if anyConnected { // Only increase if we have any connection
                        self.exponentialReconnectBackOff = max(1, self.exponentialReconnectBackOff * 2)
                    }
                    //            else if !self.isSocketConnecting  {
                    //                self.exponentialReconnectBackOff = max(1, self.exponentialReconnectBackOff * 2)
                    //            }
                }
                
                guard let webSocketTask = self.webSocketTask, !outQueue.isEmpty else { return }
                
                if self.relayData.auth {
#if DEBUG
                    L.sockets.debug("\(self.url) relayData.auth == true")
#endif
                    self.sendAfterAuthSubject.send()
                    return
                }
            }
        }
    }
    
    public func sendAfterAuth() {
#if DEBUG
        L.sockets.debug("\(self.url) sendAfterAuth()")
#endif
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            guard let webSocketTask = self.webSocketTask, !outQueue.isEmpty, self.isSocketConnected else { return }
            for out in self.outQueue {
#if DEBUG
                L.sockets.debug("🟠🟠🏎️🔌🔌 SENDING FROM OUTQUEUE (AFTER AUTH) \(self.url): \(out.text.prefix(155))")
#endif
                webSocketTask.send(.string(out.text)) { error in
                    if let error {
                        self.didReceiveError(error)
                    }
                }
                self.outQueue.removeAll(where: { $0.id == out.id })
            }
        }
    }
    
    public var eventsThatMayNeedAuth: [String: String] = [:] // [ post id : event message text string ]
    
    public func sendMessage(_ text: String, bypassQueue: Bool = false) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            if !self.isDeviceConnected {
#if DEBUG
                L.sockets.debug("🔴🔴 No internet. Did not sendMessage \(self.url)")
#endif
                return
            }
            
            if bypassQueue { // To give prio to stuff like AUTH
                if self.isSocketConnected {
#if DEBUG
                L.sockets.debug("🟠🟠🏎️🔌🔌 SEND (bypassQueue) \(self.url): \(text)")
#endif
                    webSocketTask?.send(.string(text)) { error in
                        if let error {
                            self.didReceiveError(error)
                        }
                    }
                }
                else {
                    let socketMessage = SocketMessage(text: text)
                    self.outQueue.insert(socketMessage, at: 0)
                }
                
                return
            }
            
            let socketMessage = SocketMessage(text: text)
            self.outQueue.append(socketMessage)
            
            if self.webSocketTask == nil || !self.isSocketConnected {
#if DEBUG
                if self.exponentialReconnectBackOff <= 2 {
                    L.sockets.debug("🔴🔴 Not connected. Did not sendMessage \(self.url). (Message queued): \(text.prefix(155))")
                }
#endif
                return
            }
            
            if self.relayData.auth && !self.didAuth {
#if DEBUG
                L.sockets.debug("\(self.url) relayData.auth == true. Waiting 0.25 sec for: \(text.prefix(155))")
#endif
                self.sendAfterAuthSubject.send()
                return
            }
            

            guard let webSocketTask = self.webSocketTask, !outQueue.isEmpty else { return }
            
            for out in outQueue {
#if DEBUG
                L.sockets.debug("🟠🟠🏎️🔌🔌 SENDING FROM OUTQUEUE (A) \(self.url): \(out.text.prefix(155))")
#endif
                webSocketTask.send(.string(out.text)) { error in
                    if let error {
                        self.didReceiveError(error)
                        self.connect(andSend: out.text)
                    }
                }
                self.outQueue.removeAll(where: { $0.id == out.id })
            }
        }
    }
    
    // (Planned) disconnect, so exponetional backoff and skipped is reset
    public func disconnect() {
#if DEBUG
        L.og.debug("🔴 Disconnecting: \(self.url)")
#endif
        queue.async(flags: .barrier) { [weak self] in
            self?.webSocketTask?.cancel(with: .normalClosure, reason: nil)
            self?.webSocketTask = nil
            
            self?.urlSession?.invalidateAndCancel() 
            self?.urlSession = nil
            
            self?.exponentialReconnectBackOff = 0
            self?.skipped = 0
            self?.firstConnection = true
            self?.nreqSubscriptions = []
            self?.lastMessageReceivedAt = nil
            self?.isSocketConnected = false
            self?.outQueue = [] // Clear any pending messages
        }
    }
    
    deinit {
#if DEBUG
        L.og.debug("🗑️ Deinitializing RelayConnection: \(self.url)")
#endif
        // Ensure cleanup even if disconnect() wasn't called
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        subscriptions.removeAll()
        outQueue.removeAll()
        nreqSubscriptions.removeAll()
    }
    
    public func ping() {
#if DEBUG
        L.sockets.debug("PING: \(self.url) -[LOG]-")
#endif
        queue.async { [weak self] in
            if self?.webSocketTask == nil {
#if DEBUG
                L.sockets.debug("🔴🔴 PING: Not connected. ????? \(self?.url ?? "")")
#endif
                Task { @MainActor [weak self] in
                    self?.isConnected = false
                }
                return
            }
            self?.webSocketTask?.sendPing(pongReceiveHandler: { [weak self] error in
                if let error {
                    self?.queue.async(flags: .barrier) { [weak self] in
                        guard let self else { return }
                        self.urlSession?.invalidateAndCancel()
                        self.nreqSubscriptions = []
                        self.lastMessageReceivedAt = nil
                        self.isSocketConnected = false
                        Task { @MainActor [weak self] in
                            self?.isConnected = false
                        }
                    }
#if DEBUG
                    L.sockets.debug("🔴🔴 PING: No pong \(self?.url ?? ""): \(error)")
#endif
                }
                else {
                    self?.didReceivePong()
                }
            })
        }
    }
    
    // didBecomeInvalidWithError
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {
        if let error {
#if DEBUG
            L.sockets.debug("🔴🔴 urlSession.didBecomeInvalidWithError: \(self.url.replacingOccurrences(of: "wss://", with: "").replacingOccurrences(of: "ws://", with: "").prefix(25)): \(error.localizedDescription)")
#endif
            self.didReceiveError(error)
        }
    }
    
    // didReceiveInformationalResponse
    @available(iOS 17.0, *)
    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceiveInformationalResponse response: HTTPURLResponse) {
#if DEBUG
        L.sockets.debug("🔴🔴 didReceiveInformationalResponse: \(self.url.replacingOccurrences(of: "wss://", with: "").replacingOccurrences(of: "ws://", with: "").prefix(25)): \(response.statusCode.description)")
#endif
    }
    
    // didCompleteWithError
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        // TODO: Should we handle different from didBecomeInvalidWithError or not???
        if let error {
#if DEBUG
            let code = (error as NSError).code
            L.sockets.debug("🔴🔴 didCompleteWithError: \(self.url.replacingOccurrences(of: "wss://", with: "").replacingOccurrences(of: "ws://", with: "").prefix(25)): \(code.description) - \(error.localizedDescription)")
#endif
            self.didReceiveError(error)
        }
    }
    
    public func didReceiveMessage(string: String) {
        // Respond to a WebSocket connection receiving a `String` message
        queue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            if self.isSocketConnecting {
                self.isSocketConnecting = false
            }
            if !self.isSocketConnected {
                self.isSocketConnected = true
            }
#if DEBUG
            L.sockets.debug("🟠🟠🏎️🔌 RECEIVED: \(self.url.replacingOccurrences(of: "wss://", with: "").replacingOccurrences(of: "ws://", with: "").prefix(25)): \(string)")
#endif
            MessageParser.shared.socketReceivedMessage(text: string, relayUrl: self.url, client: self)
            self.lastMessageReceivedAt = .now
            self.exponentialReconnectBackOff = 0
            self.skipped = 0
            
            self.stats.messages += 1
        }
    }
    
    public func didReceiveMessage(data: Data) {
        // Respond to a WebSocket connection receiving a binary `Data` message
        queue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            if self.isSocketConnecting {
                self.isSocketConnecting = false
            }
            if !self.isSocketConnected {
                self.isSocketConnected = true
            }
            self.lastMessageReceivedAt = .now
            self.exponentialReconnectBackOff = 0
            self.skipped = 0

            self.stats.messages += 1
        }
    }
    
    public func didReceiveError(_ error: Error) {
        // Respond to a WebSocket error event
        DispatchQueue.main.async { [weak self] in
            let anyConnected = ConnectionPool.shared.anyConnected
            self?.queue.async(flags: .barrier) { [weak self] in
                // always clear outqueue after error/disconnect
                self?.outQueue = []
                
                self?.webSocketTask?.cancel()
//                self?.session?.invalidateAndCancel()
                self?.nreqSubscriptions = []
                self?.lastMessageReceivedAt = nil
                if (self?.exponentialReconnectBackOff ?? 0) >= 512 {
                    self?.exponentialReconnectBackOff = 512
                }
                else if anyConnected {
                    self?.exponentialReconnectBackOff = max(1, (self?.exponentialReconnectBackOff ?? 0) * 2)
                }
                self?.isSocketConnected = false
                if let url = self?.url {
                    let shortURL = URL(string: url)?.baseURL?.description ?? url
                    DispatchQueue.main.async {
                        sendNotification(.socketNotification, "Error: \(shortURL) \(error.localizedDescription)")
                    }
                }
                guard let self else { return }
                
                let code = (error as NSError).code
                if Set([-999,53,54,57]).contains(code) {
                    // standard 57 "The operation couldn’t be completed. Socket is not connected"
                    // not really error just standard websocket garbage
                    // dont continue as if actual error
                    // also -999 cancelled
                    // No pong 53 "Software caused connection abort"
                    // 54 The operation couldn’t be completed. Connection reset by peer
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
    
    public func didReceivePong() {
//        L.sockets.debug("PING: Did receive PONG: \(self.url)")
        // Respond to a WebSocket connection receiving a Pong from the peer
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            if self.isSocketConnecting {
                self.isSocketConnecting = false
            }
            if !self.isSocketConnected {
                self.isSocketConnected = true
            }
            self.lastMessageReceivedAt = .now
            self.exponentialReconnectBackOff = 0
            self.skipped = 0
        }
    }
    
    // didOpenWithProtocol
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        self.queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.stats.connected += 1
            self.startReceiving()
            self.nreqSubscriptions = []
            self.exponentialReconnectBackOff = 0
            self.skipped = 0
            self.lastMessageReceivedAt = .now
            self.isSocketConnected = true
            if self.firstConnection {
                DispatchQueue.main.async { [weak self] in
                    sendNotification(.socketConnected, "Connected: \(self?.url ?? "?")")
                }
            }
            else { 
                // restore subscriptions
                if !isOutbox {
                    DispatchQueue.main.async { [weak self] in
                        if IS_CATALYST || !AppState.shared.appIsInBackground {
                            if self?.relayData.auth ?? false {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    FeedsCoordinator.shared.resumeFeeds()
                                    NotificationsViewModel.restoreSubscriptions()
                                }
                            }
                            else {
                                FeedsCoordinator.shared.resumeFeeds()
                                NotificationsViewModel.restoreSubscriptions()
                            }
                        }
                        sendNotification(.socketConnected, "Connected: \(self?.url ?? "?")")
                    }
                }
            }
            self.firstConnection = false

            guard let webSocketTask = self.webSocketTask, !outQueue.isEmpty else { return }
            
            if self.relayData.auth && !self.didAuth {
#if DEBUG
                L.sockets.debug("relayData.auth == true but did not auth yet, waiting 0.25 secs")
#endif
                self.sendAfterAuthSubject.send()
                return
            }
            else {
                for out in outQueue {
#if DEBUG
                    L.sockets.debug("🟠🟠🏎️🔌🔌 SENDING FROM OUTQUEUE (B) \(self.url): \(out.text.prefix(155))")
#endif
                    webSocketTask.send(.string(out.text)) { error in
                        if let error {
                            self.didReceiveError(error)
                        }
                    }
                    self.outQueue.removeAll(where: { $0.id == out.id })
                }
            }
        }
#if DEBUG
        L.sockets.debug("🏎️🏎️🔌 CONNECTED \(self.url) - didOpenWithProtocol -[LOG]-")
#endif
    }
    
    // didCloseWith
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        
        queue.async(flags: .barrier) { [weak self] in
//            self?.session?.invalidateAndCancel()
            self?.nreqSubscriptions = []
            self?.lastMessageReceivedAt = nil
            self?.isSocketConnected = false
            DispatchQueue.main.async {
                sendNotification(.socketNotification, "Disconnected: \(self?.url ?? "")")
            }
        }
#if DEBUG
        L.sockets.debug("🏎️🏎️🔌 DISCONNECTED \(self.url): \(String(describing: reason != nil ? String(data: reason!, encoding: .utf8) : "") )")
#endif
    }
    
    private func startReceiving() {
        self.webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
                case .success(let message):
                    switch message {
                        case .data(let data):
                            self.didReceiveMessage(data: data)
                        case .string(let text):
                            self.didReceiveMessage(string: text)
                        @unknown default:
                            break
                    }
                    self.startReceiving()
                case .failure(let error):
                    self.didReceiveError(error)
                }
        }
    }
    
    private var lastAuthChallenge: String?
    public var recentAuthAttempts: Int = 0
    private var didAuth: Bool = false
    
    public func handleAuth(_ message: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            guard let messageData = message.data(using: .utf8) else { return }

            let decoder = JSONDecoder()
            guard let authMessage: [String] = try? decoder.decode([String].self, from: messageData),
                  authMessage.count >= 2,
                  authMessage[0] == "AUTH"
            else { return }

            self.lastAuthChallenge = authMessage[1]
            self.authSubject.send()
        }
    }

    public func sendAuthResponse(usingAccount: CloudAccount? = nil, force: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let authAccount = resolveAuthAccount(relayData, usingAccount: usingAccount) else { return }
            guard !self.relayData.excludedPubkeys.contains(authAccount.publicKey) else { return }
            
#if DEBUG
            L.sockets.debug("🔑🔑 Auth resolved to account: \(authAccount.anyName) - \(self.relayData.id)")
#endif
            
            self.queue.async { [weak self] in
                guard let self else { return }
                
                guard let challenge = self.lastAuthChallenge else { return }
                guard force || self.recentAuthAttempts < 5 else { return }
                
                var authResponse = NEvent(content: "")
                authResponse.kind = .auth
                authResponse.tags.append(NostrTag(["relay", relayData.url]))
                authResponse.tags.append(NostrTag(["challenge", challenge]))
                
                DispatchQueue.main.async {
                    if authAccount.isNC {
                        authResponse = authResponse.withId()
                        NSecBunkerManager.shared.requestSignature(forEvent: authResponse, usingAccount: authAccount, whenSigned: { signedAuthResponse in
                            self.sendMessage(ClientMessage.auth(event: signedAuthResponse), bypassQueue: true)
                            self.queue.async(flags: .barrier) { [weak self] in
                                guard let self else { return }
                                self.recentAuthAttempts = self.recentAuthAttempts + 1
                                self.didAuth = true
                            }
                        })
                    }
                    else if let signedAuthResponse = try? authAccount.signEvent(authResponse) {
                        self.sendMessage(ClientMessage.auth(event: signedAuthResponse), bypassQueue: true)
                        self.queue.async(flags: .barrier) { [weak self] in
                            guard let self else { return }
                            self.recentAuthAttempts = self.recentAuthAttempts + 1
                            self.didAuth = true
                        }
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
