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
    
    public var lastMessageReceivedAt: Date? = nil
    private var exponentialReconnectBackOff = 0
    private var skipped: Int = 0
    
    
    public var relayData: RelayData
    private var queue: DispatchQueue
    private var session: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var subscriptions = Set<AnyCancellable>()
    private var outQueue: [SocketMessage] = []
    
    
    private var isDeviceConnected = false {
        didSet {
            print("connection.isDeviceConnected = \(self.isDeviceConnected) - \(self.url)")
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
    
    init(_ relayData: RelayData, isNWC: Bool = false, isNC: Bool = false, queue: DispatchQueue) {
        self.relayData = relayData
        self.queue = queue
        self.isNC = isNC
        self.isNWC = isNWC
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
            
            if bypassQueue {
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
                L.sockets.debug("🔴🔴 Not connected. Did not sendMessage \(self.url)")
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
                    }
                }
                self.outQueue.removeAll(where: { $0.id == out.id })
            }
        }
    }
    
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
                        self?.exponentialReconnectBackOff = 0
                        self?.skipped = 0
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
    
    public func didReceiveMessage(string: String) {
        // Respond to a WebSocket connection receiving a `String` message
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
    }
    
    public func didReceiveMessage(data: Data) {
        // Respond to a WebSocket connection receiving a binary `Data` message
        if self.isSocketConnecting {
            self.isSocketConnecting = false
        }
        if !self.isSocketConnected {
            self.isSocketConnected = true
        }
        self.lastMessageReceivedAt = .now
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
        }
        L.sockets.debug("🏎️🏎️🔌🔴🔴 Error \(self.url): \(error.localizedDescription)")
    }
    
    public func didReceivePong() {
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
        }
    }
    
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
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
                    L.sockets.debug("🔴🔴 send error \(self.url): \(error?.localizedDescription ?? "") -- \(out.text)")
                }
                self.outQueue.removeAll(where: { $0.id == out.id })
            }
        }
        L.sockets.debug("🏎️🏎️🔌 CONNECTED \(self.url)")
    }
    
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        
        queue.async(flags: .barrier) { [weak self] in
            self?.session?.invalidateAndCancel()
            self?.nreqSubscriptions = []
            self?.exponentialReconnectBackOff = 0
            self?.skipped = 0
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
