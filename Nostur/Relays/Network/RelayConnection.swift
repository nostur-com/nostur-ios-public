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
        didSet {
            ConnectionPool.shared.objectWillChange.send()
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
    private var session: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var subscriptions = Set<AnyCancellable>()
    private var outQueue: [SocketMessage] = []
    
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
            L.sockets.debug("connection.isDeviceConnected = \(self.isDeviceConnected) - \(self.url)")
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
            Task { @MainActor in
                self.objectWillChange.send()
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
                if self.isDeviceConnected != isNowConnected {
                    self.queue.async(flags: .barrier) { [weak self] in
                        self?.isDeviceConnected = isNowConnected
                    }
                }
                if (fromDisconnectedToConnected) {
                    if self.relayData.shouldConnect {
                        self.connect(forceConnectionAttempt: true)
                    }
                }
                else if fromConnectedToDisconnected {
                    if self.relayData.shouldConnect {
                        self.disconnect()
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    public func connect(andSend: String? = nil, forceConnectionAttempt: Bool = false) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            guard self.isDeviceConnected else {
                L.sockets.debug("\(self.url) - No internet, skipping connect()")
                self.isSocketConnecting = false
                return
            }
            guard !self.isSocketConnecting || forceConnectionAttempt else {
                L.sockets.debug("\(self.url) - Already connecting, skipping connect()")
                self.isSocketConnecting = false
                if let andSend {
                    self.sendMessage(andSend)
                }
                return
            }
            self.nreqSubscriptions = []
            self.isSocketConnecting = true
            
            guard self.exponentialReconnectBackOff > 512 || self.exponentialReconnectBackOff == 1 || forceConnectionAttempt || self.skipped == self.exponentialReconnectBackOff else { // Should be 0 == 0 to continue, or 2 == 2 etc..
                self.skipped = self.skipped + 1
                self.isSocketConnecting = false
                L.sockets.debug("🏎️🏎️🔌 Skipping reconnect. \(self.url) EB: (\(self.exponentialReconnectBackOff)) skipped: \(self.skipped)")
                return
            }
            self.skipped = 0
            
            if let andSend = andSend {
                self.outQueue.append(SocketMessage(text: andSend))
            }
            
            self.session?.invalidateAndCancel()
            self.session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            
            if let url = URL(string: relayData.url) {
                let urlRequest = URLRequest(url: url)
                self.webSocketTask = self.session?.webSocketTask(with: urlRequest)
                self.webSocketTask?.delegate = self
            }
            
            self.webSocketTask?.resume()
            
            if self.exponentialReconnectBackOff >= 512 {
                self.exponentialReconnectBackOff = 512
            }
            else {
                self.exponentialReconnectBackOff = max(1, self.exponentialReconnectBackOff * 2)
            }
//            else if !self.isSocketConnecting  {
//                self.exponentialReconnectBackOff = max(1, self.exponentialReconnectBackOff * 2)
//            }
            
            
            guard let webSocketTask = self.webSocketTask, !outQueue.isEmpty else { return }
            
            if self.relayData.auth {
                L.sockets.debug("relayData.auth == true")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self.sendAfterAuth()
                }
                return
            }
            
            for out in self.outQueue {
                webSocketTask.send(.string(out.text)) { error in
                    if let error {
                        self.didReceiveError(error)
                    }
                }
                self.outQueue.removeAll(where: { $0.id == out.id })
            }
        }
    }
    
    public func sendAfterAuth() {
        L.sockets.debug("sendAfterAuth()")
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            guard let webSocketTask = self.webSocketTask, !outQueue.isEmpty else { return }
            for out in self.outQueue {
                webSocketTask.send(.string(out.text)) { error in
                    if let error {
                        self.didReceiveError(error)
                    }
                }
                self.outQueue.removeAll(where: { $0.id == out.id })
            }
        }
    }
    
    public func sendMessage(_ text: String, bypassQueue: Bool = false) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            if !self.isDeviceConnected {
                L.sockets.debug("🔴🔴 No internet. Did not sendMessage \(self.url)")
                return
            }
            
            if bypassQueue { // To give prio to stuff like AUTH
                #if DEBUG
                L.sockets.debug("🟠🟠🏎️🔌🔌 SEND \(self.url): \(text)")
                #endif
                webSocketTask?.send(.string(text)) { error in
                    if let error {
                        self.didReceiveError(error)
                    }
                }
                return
            }
            
            let socketMessage = SocketMessage(text: text)
            self.outQueue.append(socketMessage)
            
            if self.webSocketTask == nil || !self.isSocketConnected {
                L.sockets.debug("🔴🔴 Not connected. Did not sendMessage \(self.url). (Message queued)")
                return
            }
            
            if self.relayData.auth && !self.didAuth {
                L.sockets.debug("relayData.auth == true \(text)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self.sendAfterAuth()
                }
                return
            }
            
            
            #if DEBUG
            L.sockets.debug("🟠🟠🏎️🔌🔌 SEND \(self.url): \(text)")
            #endif
            guard let webSocketTask = self.webSocketTask, !outQueue.isEmpty else { return }
            
            for out in outQueue {
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
        queue.async(flags: .barrier) { [weak self] in
            self?.webSocketTask?.cancel()
            self?.session?.invalidateAndCancel()
            self?.exponentialReconnectBackOff = 0
            self?.skipped = 0
            self?.firstConnection = true
            self?.nreqSubscriptions = []
            self?.lastMessageReceivedAt = nil
            self?.isSocketConnected = false
        }
    }
    
    public func ping() {
        L.sockets.debug("PING: Trying to ping: \(self.url)")
        queue.async { [weak self] in
            if self?.webSocketTask == nil {
                L.sockets.debug("🔴🔴 PING: Not connected. ????? \(self?.url ?? "")")
                return
            }
            self?.webSocketTask?.sendPing(pongReceiveHandler: { [weak self] error in
                if let error {
                    self?.queue.async(flags: .barrier) { [weak self] in
                        self?.session?.invalidateAndCancel()
                        self?.nreqSubscriptions = []
//                        self?.exponentialReconnectBackOff = 0
//                        self?.skipped = 0
                        self?.lastMessageReceivedAt = nil
                        self?.isSocketConnected = false
                    }
                    L.sockets.debug("🔴🔴 PING: No pong \(self?.url ?? ""): \(error)")
                }
                else {
                    self?.didReceivePong()
                }
            })
        }
    }
    
    // didBecomeInvalidWithError
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {
    #if DEBUG
        L.sockets.debug("🔴🔴 didBecomeInvalidWithError: \(self.url.replacingOccurrences(of: "wss://", with: "").replacingOccurrences(of: "ws://", with: "").prefix(25)): \(error?.localizedDescription ?? "")")
    #endif
        if let error {
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
#if DEBUG
    L.sockets.debug("🔴🔴 didCompleteWithError: \(self.url.replacingOccurrences(of: "wss://", with: "").replacingOccurrences(of: "ws://", with: "").prefix(25)): \(error?.localizedDescription ?? "")")
#endif
        
        // TODO: Should we handle different from didBecomeInvalidWithError or not???
        if let error {
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
        queue.async(flags: .barrier) { [weak self] in
            self?.webSocketTask?.cancel()
            self?.session?.invalidateAndCancel()
            self?.nreqSubscriptions = []
            self?.lastMessageReceivedAt = nil
            if (self?.exponentialReconnectBackOff ?? 0) >= 512 {
                self?.exponentialReconnectBackOff = 512
            }
            else {
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
            if Set([57,-999,53,54]).contains(code) {
                // standard "The operation couldn’t be completed. Socket is not connected"
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
            else if Set([-1001,-1005]).contains(code) && (self.stats.connected == 0) && ConnectionPool.shared.anyConnected {
                // -1005 The network connection was lost.
                // -1001 The request timed out.
                
                ConnectionPool.shared.penaltybox.insert(self.url)
            }
            else if (self.stats.errors > 3) && (self.stats.connected == 0) { // other errors, put in penalty box if too many and no success connection ever
                ConnectionPool.shared.penaltybox.insert(self.url)
            }
        }
        let code = (error as NSError).code
        L.sockets.debug("🏎️🏎️🔌🔴🔴 Error \(self.url): \(code.description) \(error.localizedDescription)")
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
        queue.async(flags: .barrier) { [weak self] in
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
            else { // restore subscriptions
                DispatchQueue.main.async { [weak self] in
                    if IS_CATALYST || !NRState.shared.appIsInBackground {
                        if self?.relayData.auth ?? false {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                LVMManager.shared.restoreSubscriptions()
                                NotificationsViewModel.shared.restoreSubscriptions()
                            }
                        }
                        else {
                            LVMManager.shared.restoreSubscriptions()
                            NotificationsViewModel.shared.restoreSubscriptions()
                        }
                    }
                    sendNotification(.socketConnected, "Connected: \(self?.url ?? "?")")
                }
            }
            self.firstConnection = false

            guard let webSocketTask = self.webSocketTask, !outQueue.isEmpty else { return }
            
            if self.relayData.auth && !self.didAuth {
                L.sockets.debug("relayData.auth == true but did not auth yet, waiting 0.25 secs")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self.sendAfterAuth()
                }
                return
            }
            
            for out in outQueue {
                webSocketTask.send(.string(out.text)) { error in
                    if let error {
                        self.didReceiveError(error)
                    }
                }
                self.outQueue.removeAll(where: { $0.id == out.id })
            }
        }
        L.sockets.debug("🏎️🏎️🔌 CONNECTED \(self.url)")
    }
    
    // didCloseWith
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        
        queue.async(flags: .barrier) { [weak self] in
            self?.session?.invalidateAndCancel()
            self?.nreqSubscriptions = []
//            self?.exponentialReconnectBackOff = 0
//            self?.skipped = 0
            self?.lastMessageReceivedAt = nil
            self?.isSocketConnected = false
            DispatchQueue.main.async {
                sendNotification(.socketNotification, "Disconnected: \(self?.url ?? "")")
            }
        }
        L.sockets.debug("🏎️🏎️🔌 DISCONNECTED \(self.url): \(String(describing: reason != nil ? String(data: reason!, encoding: .utf8) : "") )")
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
    private var recentAuthAttempts: Int = 0
    private var didAuth: Bool = false
    
    public func handleAuth(_ message: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            guard relayData.auth else { return }
            guard let messageData = message.data(using: .utf8) else { return }

            let decoder = JSONDecoder()
            guard let authMessage: [String] = try? decoder.decode([String].self, from: messageData),
                  authMessage.count >= 2,
                  authMessage[0] == "AUTH"
            else { return }

            self.lastAuthChallenge = authMessage[1]
            self.sendAuthResponse()
        }
    }

    public func sendAuthResponse() {
        guard self.relayData.auth else { return }
        
        DispatchQueue.main.async {
            guard let account = Nostur.account(), account.isFullAccount else { return }
            guard !self.relayData.excludedPubkeys.contains(account.publicKey) else { return }
            
            self.queue.async { [weak self] in
                guard let self else { return }
                
                guard let challenge = self.lastAuthChallenge else { return }
                guard self.recentAuthAttempts < 5 else { return }
                
                
                var authResponse = NEvent(content: "")
                authResponse.kind = .auth
                authResponse.tags.append(NostrTag(["relay", relayData.url]))
                authResponse.tags.append(NostrTag(["challenge", challenge]))

                DispatchQueue.main.async {
                    guard let signedAuthResponse = try? account.signEvent(authResponse) else { return }
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
