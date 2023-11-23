//
//  RelayConnection.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/11/2023.
//

import Foundation
import Combine
import CombineWebSocket

protocol RelayConnectionDelegate: URLSessionWebSocketDelegate {
    func didReceiveData(_ data:Data)
    
    func didReceiveMessage(_ text:String)
    
    func didDisconnect()
    
    func didDisconnectWithError(_ error:Error)
    
    func didReceivePong()
}

public class RelayConnection: NSObject, RelayConnectionDelegate, ObservableObject {
    
    // for views (viewContext)
    @Published private(set) var isConnected = false { // don't set directly, set isDeviceConnected or isSocketConnected
        didSet {
            ConnectionPool.shared.objectWillChange.send()
        }
    }
    
    // other (should use queue: "connection-pool"
    public var url:String { relayData.id }
    public var nreqSubscriptions:Set<String> = []
    public var isNWC:Bool
    public var isNC:Bool
    
    public var lastMessageReceivedAt:Date? = nil
    private var exponentialReconnectBackOff = 0
    private var skipped:Int = 0
    
    
    public var relayData:RelayData
    private var session:URLSession?
    private var queue:DispatchQueue
    private var webSocket:WebSocket?
    private var webSocketSub:AnyCancellable?
    private var subscriptions = Set<AnyCancellable>()
    private var outQueue:[SocketMessage] = []
    
    
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
        }
    }
    
    init(_ relayData: RelayData, isNWC:Bool = false, isNC:Bool = false, queue: DispatchQueue) {
        self.relayData = relayData
        self.queue = queue
        self.isNC = isNC
        self.isNWC = isNWC
        
        super.init()
        
        NetworkMonitor.shared.isConnectedSubject
            .receive(on: self.queue)
            .sink { isNowConnected in
                let fromDisconnectedToConnected = !self.isDeviceConnected && isNowConnected
                let fromConnectedToDisconnected = self.isDeviceConnected && !isNowConnected
                if self.isDeviceConnected != isNowConnected {
                    self.queue.async(flags: .barrier) {
                        self.isDeviceConnected = isNowConnected
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
    
    public func connect(andSend:String? = nil, forceConnectionAttempt:Bool = false) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            guard self.isDeviceConnected else {
                L.sockets.debug("\(self.url) - No internet, skipping connect()")
                return
            }
            guard !self.isSocketConnecting else {
                L.sockets.debug("\(self.url) - Already connecting, skipping connect()")
                return
            }
            self.nreqSubscriptions = []
            self.isSocketConnecting = true
            
            guard self.exponentialReconnectBackOff > 512 || self.exponentialReconnectBackOff == 1 || forceConnectionAttempt || self.skipped == self.exponentialReconnectBackOff else { // Should be 0 == 0 to continue, or 2 == 2 etc..
                self.skipped = self.skipped + 1
                self.isSocketConnecting = false
                L.sockets.info("🏎️🏎️🔌 Skipping reconnect. \(self.url) EB: (\(self.exponentialReconnectBackOff)) skipped: \(self.skipped)")
                return
            }
            self.skipped = 0

            if let andSend = andSend {
                self.outQueue.append(SocketMessage(text: andSend))
            }
            
//            self.webSocketSub?.cancel() // .cancel() gives Data race? Maybe not even needed.
            self.webSocketSub = nil
            
            self.session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            
            if let urlURL = URL(string: relayData.url) {
                let urlRequest = URLRequest(url: urlURL)
                self.webSocket = session?.webSocket(with: urlRequest)
            }
            
            guard let webSocket = webSocket else {
                self.isSocketConnecting = false
                return
            }
            
            // Subscribe to the WebSocket. This will connect to the remote server and start listening
            // for messages (URLSessionWebSocketTask.Message).
            // URLSessionWebSocketTask.Message is an enum for either Data or String
            self.webSocketSub = webSocket.publisher
                .receive(on: queue)
                .sink(receiveCompletion: { [weak self] completion in
                    switch completion {
                    case .finished:
                        self?.didDisconnect()
                    case .failure(let error):
                        self?.didDisconnectWithError(error)
                    }
                },
                receiveValue: { [weak self] message in
                    switch message {
                    case .data(let data):
                        // Handle Data message
                        self?.didReceiveData(data)
                    case .string(let string):
                        // Handle String message
                        self?.didReceiveMessage(string)
                    @unknown default:
                        L.og.debug("dunno")
                    }
                })
            
            if self.exponentialReconnectBackOff >= 512 {
                self.exponentialReconnectBackOff = 512
            }
            else {
                self.exponentialReconnectBackOff = max(1, self.exponentialReconnectBackOff * 2)
            }
            
            guard !outQueue.isEmpty else { return }
            for out in outQueue {
                webSocket.send(out.text)
                    .subscribe(Subscribers.Sink(
                        receiveCompletion: { [weak self] completion in
                            switch completion {
                            case .finished:
                                self?.queue.async(flags: .barrier) {
                                    self?.outQueue.removeAll(where: { $0.id == out.id })
                                }
                            case .failure(let error):
                                L.og.error("🟪🔴🔴 Error sending \(error): \(out.text)")
                            }
                        },
                        receiveValue: { _ in }
                    ))
            }
        }
    }
    
    public func sendMessage(_ text:String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            if !self.isDeviceConnected {
                L.sockets.info("🔴🔴 No internet. Did not sendMessage \(self.url)")
                return
            }
            
            let socketMessage = SocketMessage(text: text)
            self.outQueue.append(socketMessage)
            
            if self.webSocket == nil || !self.isSocketConnected {
                L.sockets.info("🔴🔴 Not connected. Did not sendMessage \(self.url)")
                return
            }
            L.sockets.debug("🟠🟠🏎️🔌🔌 SEND \(self.url): \(text)")
            self.webSocket?.send(text)
                .subscribe(Subscribers.Sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            self.queue.async(flags: .barrier) {
                                self.outQueue.removeAll(where: { $0.id == socketMessage.id })
                            }
                        case .failure(let error):
                            L.og.error("🟪🔴🔴 Error sending \(error): \(text)")
                        }
                    },
                    receiveValue: { _ in }
                ))
        }
    }
    
    public func sendMessageAfterPing(_ text:String) {
            L.sockets.info("🟪 sendMessageAfterPing  \(text)")
            queue.async(flags: .barrier) { [weak self] in
                guard let self = self else { return }
                if !self.isDeviceConnected {
                    L.sockets.info("🔴🔴 No internet. Did not sendMessage \(self.url)")
                    return
                }
                guard let webSocket = self.webSocket else {
                    L.sockets.info("🟪🔴🔴 Not connected.  \(self.url)")
                    return
                }
                let socketMessage = SocketMessage(text: text)
                self.outQueue.append(socketMessage)
    
                webSocket.ping()
                    .subscribe(Subscribers.Sink(
                        receiveCompletion: { [weak self] completion in
                            guard let self = self else { return }
                            switch completion {
                            case .failure(let error):
                                // Handle the failure case
                                #if DEBUG
                                L.sockets.info("🟪 \(self.url) Ping Failure: \(error), trying to reconnect")
                                #endif
                                self.connect(andSend:text)
                            case .finished:
                                // The ping completed successfully
                                L.sockets.info("🟪 Ping succeeded on \(self.url). Sending \(text)")
                                L.sockets.debug("🟠🟠🏎️🔌🔌 SEND \(self.url): \(text)")
                                webSocket.send(text)
                                    .subscribe(Subscribers.Sink(
                                        receiveCompletion: { [weak self] completion in
                                            switch completion {
                                            case .finished:
                                                self?.queue.async(flags: .barrier) {
                                                    self?.outQueue.removeAll(where: { $0.id == socketMessage.id })
                                                }
                                            case .failure(let error):
                                                L.og.error("🟪🔴🔴 Error sending \(error): \(text)")
                                            }
                                        },
                                        receiveValue: { _ in }
                                    ))
                            }
                        },
                        receiveValue: { _ in }
                    ))
            }
        }
    
    
    public func disconnect() {
        queue.async(flags: .barrier) {
            self.nreqSubscriptions = []
            self.lastMessageReceivedAt = nil
            self.isSocketConnected = false
//            self.webSocketSub?.cancel() // .cancel() gives Data race? Maybe not even needed.
            self.webSocketSub = nil
        }
    }
    
    public func ping() {
        L.sockets.info("Trying to ping: \(self.url)")
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let webSocket = self.webSocket else {
                L.sockets.info("🔴🔴 Not connected. ????? \(self.url)")
                return
            }

            webSocket.ping()
                .subscribe(Subscribers.Sink(
                    receiveCompletion: { [weak self] completion in
                        switch completion {
                        case .failure(let error):
                            // Handle the failure case
                            let _url = self?.url ?? ""
                            let _error = error
                            L.sockets.info("\(_url) Ping Failure: \(_error), trying to reconnect")
                            self?.connect()
                        case .finished:
                            // The ping completed successfully
                            let _url = self?.url ?? ""
                            L.sockets.info("\(_url) Ping succeeded")
                            self?.didReceivePong()
                        }
                    },
                    receiveValue: { _ in }
                ))
        }
    }
    
    // -- MARK: URLSessionWebSocketDelegate
    
    func didReceiveData(_ data:Data) {
        if self.isSocketConnecting {
            self.isSocketConnecting = false
        }
        if !self.isSocketConnected {
            self.isSocketConnected = true
        }
        self.lastMessageReceivedAt = .now
    }
    
    func didReceiveMessage(_ text:String) {
        if self.isSocketConnecting {
            self.isSocketConnecting = false
        }
        if !self.isSocketConnected {
            self.isSocketConnected = true
        }
        L.sockets.debug("🟠🟠🏎️🔌 RECEIVED: \(self.url.replacingOccurrences(of: "wss://", with: "").replacingOccurrences(of: "ws://", with: "").prefix(25)): \(text)")
        MessageParser.shared.socketReceivedMessage(text: text, relayUrl: self.url, client: self)
        self.lastMessageReceivedAt = .now
    }
    
    func didDisconnect() {
        queue.async(flags: .barrier) {
            self.nreqSubscriptions = []
            self.lastMessageReceivedAt = nil
            self.isSocketConnected = false
//            self.webSocketSub?.cancel() // .cancel() gives Data race? Maybe not even needed.
            self.webSocketSub = nil
            DispatchQueue.main.async {
                sendNotification(.socketNotification, "Disconnected: \(self.url)")
            }
        }
        L.sockets.info("🏎️🏎️🔌 DISCONNECTED \(self.url)")
    }
    
    func didDisconnectWithError(_ error: Error) {
        queue.async(flags: .barrier) {
            self.nreqSubscriptions = []
            self.lastMessageReceivedAt = nil
            if self.exponentialReconnectBackOff >= 512 {
                self.exponentialReconnectBackOff = 512
            }
            else {
                self.exponentialReconnectBackOff = max(1, self.exponentialReconnectBackOff * 2)
            }
            self.isSocketConnected = false
//            self.webSocketSub?.cancel() // .cancel() gives Data race? Maybe not even needed.
            self.webSocketSub = nil
            let shortURL = URL(string: self.url)?.baseURL?.description ?? self.url
            DispatchQueue.main.async {
                sendNotification(.socketNotification, "Error: \(shortURL) \(error.localizedDescription)")
            }
        }
        L.sockets.info("🏎️🏎️🔌🔴🔴 DISCONNECTED WITH ERROR \(self.url): \(error.localizedDescription)")
    }
    
    func didReceivePong() {
        queue.sync(flags: .barrier) {
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
        queue.async(flags: .barrier) {
            self.nreqSubscriptions = []
            self.exponentialReconnectBackOff = 0
            self.skipped = 0
            self.lastMessageReceivedAt = .now
            self.isSocketConnected = true
            DispatchQueue.main.async {
                LVMManager.shared.restoreSubscriptions()
                NotificationsViewModel.shared.restoreSubscriptions()
                sendNotification(.socketConnected, "Connected: \(self.url)")
            }
        }
        L.sockets.info("🏎️🏎️🔌 CONNECTED \(self.url)")
    }
    
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        queue.async(flags: .barrier) {
            self.nreqSubscriptions = []
            self.exponentialReconnectBackOff = 0
            self.skipped = 0
            self.lastMessageReceivedAt = .now
            self.isSocketConnected = false
//            self.webSocketSub?.cancel() // .cancel() gives Data race? Maybe not even needed.
            self.webSocketSub = nil
            DispatchQueue.main.async {
                sendNotification(.socketNotification, "Disconnected: \(self.url)")
            }
        }
        L.sockets.info("🏎️🏎️🔌 DISCONNECTED \(self.url): with code: \(closeCode.rawValue) \(String(describing: reason != nil ? String(data: reason!, encoding: .utf8) : "") )")

    }
}
