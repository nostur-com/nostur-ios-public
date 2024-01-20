//
//  RelayConnection.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/11/2023.
//

import Foundation
import Combine
//import CombineWebSocket

import Network
import NWWebSocket

public class RelayConnection: NSObject, WebSocketConnectionDelegate, ObservableObject, Identifiable {
    
    // for views (viewContext)
    @Published private(set) var isConnected = false { // don't set directly, set isDeviceConnected or isSocketConnected
        didSet {
            ConnectionPool.shared.objectWillChange.send()
        }
    }
    
    // other (should use queue: "connection-pool"
    public var firstConnection:Bool = true // flag to know if it is connect or reconnect - reconnect will restore some things not needed at first connect in background fetch
    public var url:String { relayData.id }
    public var nreqSubscriptions:Set<String> = []
    public var isNWC:Bool
    public var isNC:Bool
    
    public var lastMessageReceivedAt:Date? = nil
    private var exponentialReconnectBackOff = 0
    private var skipped:Int = 0
    
    
    public var relayData:RelayData
    private var queue:DispatchQueue
    private var webSocket:NWWebSocket?
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
            
           
            if let urlURL = URL(string: relayData.url) {
                let options = NWProtocolWebSocket.Options()
                options.autoReplyPing = true
                self.webSocket = NWWebSocket(url: urlURL, options: options, connectionQueue: self.queue)
                self.webSocket?.delegate = self
            }
            
            self.webSocket?.connect()
            
            if self.exponentialReconnectBackOff >= 512 {
                self.exponentialReconnectBackOff = 512
            }
            else {
                self.exponentialReconnectBackOff = max(1, self.exponentialReconnectBackOff * 2)
            }
            
            
            guard let webSocket = self.webSocket, !outQueue.isEmpty else { return }
                    
            for out in outQueue {
                webSocket.send(string: out.text)
                self.outQueue.removeAll(where: { $0.id == out.id })
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
            
            guard let webSocket = self.webSocket, !outQueue.isEmpty else { return }
                    
            for out in outQueue {
                webSocket.send(string: out.text)
                self.outQueue.removeAll(where: { $0.id == out.id })
            }
        }
    }
    

//    public func sendMessageAfterPing(_ text:String) {
//            L.sockets.info("🟪 sendMessageAfterPing  \(text)")
//            queue.async(flags: .barrier) { [weak self] in
//                guard let self = self else { return }
//                if !self.isDeviceConnected {
//                    L.sockets.info("🔴🔴 No internet. Did not sendMessage \(self.url)")
//                    return
//                }
//                guard let webSocket = self.webSocket else {
//                    L.sockets.info("🟪🔴🔴 Not connected.  \(self.url)")
//                    return
//                }
//                let socketMessage = SocketMessage(text: text)
//                self.outQueue.append(socketMessage)
//    
//                webSocket.ping()
//                    .subscribe(Subscribers.Sink(
//                        receiveCompletion: { [weak self] completion in
//                            guard let self = self else { return }
//                            switch completion {
//                            case .failure(let error):
//                                // Handle the failure case
//                                #if DEBUG
//                                L.sockets.info("🟪 \(self.url) Ping Failure: \(error), trying to reconnect")
//                                #endif
//                                self.connect(andSend:text)
//                            case .finished:
//                                // The ping completed successfully
//                                L.sockets.info("🟪 Ping succeeded on \(self.url). Sending \(text)")
//                                L.sockets.debug("🟠🟠🏎️🔌🔌 SEND \(self.url): \(text)")
//                                webSocket.send(text)
//                                    .subscribe(Subscribers.Sink(
//                                        receiveCompletion: { [weak self] completion in
//                                            switch completion {
//                                            case .finished:
//                                                self?.queue.async(flags: .barrier) {
//                                                    self?.outQueue.removeAll(where: { $0.id == socketMessage.id })
//                                                }
//                                            case .failure(let error):
//                                                L.og.error("🟪🔴🔴 Error sending \(error): \(text)")
//                                            }
//                                        },
//                                        receiveValue: { _ in }
//                                    ))
//                            }
//                        },
//                        receiveValue: { _ in }
//                    ))
//            }
//        }
    
    
    public func disconnect() {
        queue.async(flags: .barrier) { [weak self] in
            self?.webSocket?.disconnect()
            self?.exponentialReconnectBackOff = 0
            self?.skipped = 0
            self?.firstConnection = true
            self?.nreqSubscriptions = []
            self?.lastMessageReceivedAt = nil
            self?.isSocketConnected = false
        }
    }
        
    public func ping() {
        L.sockets.info("Trying to ping: \(self.url)")
        queue.async { [weak self] in
            guard let self = self else { return }
            if webSocket == nil {
                L.sockets.info("🔴🔴 Not connected. ????? \(self.url)")
                return
            }
            self.webSocket?.ping()
        }
    }
    
    public func webSocketDidReceiveMessage(connection: WebSocketConnection, string: String) {
        // Respond to a WebSocket connection receiving a `String` message
        if self.isSocketConnecting {
            self.isSocketConnecting = false
        }
        if !self.isSocketConnected {
            self.isSocketConnected = true
        }
        L.sockets.debug("🟠🟠🏎️🔌 RECEIVED: \(self.url.replacingOccurrences(of: "wss://", with: "").replacingOccurrences(of: "ws://", with: "").prefix(25)): \(string)")
        MessageParser.shared.socketReceivedMessage(text: string, relayUrl: self.url, client: self)
        self.lastMessageReceivedAt = .now
    }
    
    public func webSocketDidReceiveMessage(connection: WebSocketConnection, data: Data) {
        // Respond to a WebSocket connection receiving a binary `Data` message
        if self.isSocketConnecting {
            self.isSocketConnecting = false
        }
        if !self.isSocketConnected {
            self.isSocketConnected = true
        }
        self.lastMessageReceivedAt = .now
    }

    public func webSocketDidReceiveError(connection: WebSocketConnection, error: NWError) {
        // Respond to a WebSocket error event
        queue.async(flags: .barrier) { [weak self] in
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
        L.sockets.info("🏎️🏎️🔌🔴🔴 DISCONNECTED WITH ERROR \(self.url): \(error.localizedDescription)")
    }

    public func webSocketDidReceivePong(connection: WebSocketConnection) {
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
    
    public func webSocketDidConnect(connection: WebSocketConnection) {
            // Respond to a WebSocket connection event
        
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
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
                        LVMManager.shared.restoreSubscriptions()
                        NotificationsViewModel.shared.restoreSubscriptions()
                    }
                    sendNotification(.socketConnected, "Connected: \(self?.url ?? "?")")
                }
            }
            self.firstConnection = false
           
            
            guard let webSocket = self.webSocket, !outQueue.isEmpty else { return }
                    
            for out in outQueue {
                webSocket.send(string: out.text)
                self.outQueue.removeAll(where: { $0.id == out.id })
            }
        }
        L.sockets.info("🏎️🏎️🔌 CONNECTED \(self.url)")
    }
    
    public func webSocketDidDisconnect(connection: WebSocketConnection,
                                closeCode: NWProtocolWebSocket.CloseCode, reason: Data?) {
        // Respond to a WebSocket disconnection event
        queue.async(flags: .barrier) { [weak self] in
            self?.nreqSubscriptions = []
            self?.exponentialReconnectBackOff = 0
            self?.skipped = 0
            self?.lastMessageReceivedAt = .now
            self?.isSocketConnected = false
            DispatchQueue.main.async {
                sendNotification(.socketNotification, "Disconnected: \(self?.url ?? "")")
            }
        }
        L.sockets.info("🏎️🏎️🔌 DISCONNECTED \(self.url): \(String(describing: reason != nil ? String(data: reason!, encoding: .utf8) : "") )")
    }
    
    public func webSocketViabilityDidChange(connection: WebSocketConnection, isViable: Bool) {
        // Respond to a WebSocket connection viability change event
    }

    public func webSocketDidAttemptBetterPathMigration(result: Result<WebSocketConnection, NWError>) {
        // Respond to when a WebSocket connection migrates to a better network path
        // (e.g. A device moves from a cellular connection to a Wi-Fi connection)
    }

}
