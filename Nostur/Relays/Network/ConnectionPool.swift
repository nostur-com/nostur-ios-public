//
//  ConnectionPool.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/11/2023.
//

import Foundation
import Combine
import CombineWebSocket
import CoreData

public typealias CanonicalRelayUrl = String

public class ConnectionPool: ObservableObject {
    static public let shared = ConnectionPool()
    public var queue = DispatchQueue(label: "connection-pool", qos: .utility, attributes: .concurrent)
    
    public var connections:[CanonicalRelayUrl: RelayConnection] = [:]
    private var ephemeralConnections:[CanonicalRelayUrl: RelayConnection] = [:]
    
    public var anyConnected:Bool {
        connections.contains(where: { $0.value.isConnected })
    }
    
    private var stayConnectedTimer:Timer?
    
    public func addConnection(_ relayData: RelayData) -> RelayConnection {
        if let existingConnection = connections[relayData.id] {
            return existingConnection
        }
        else {
            let newConnection = RelayConnection(relayData, queue: queue)
            connections[relayData.id] = newConnection
            return newConnection
        }
    }
    
    public func addEphemeralConnection(_ relayData: RelayData) -> RelayConnection {
        if let existingConnection = ephemeralConnections[relayData.id] {
            return existingConnection
        }
        else {
            let newConnection = RelayConnection(relayData, queue: queue)
            ephemeralConnections[relayData.id] = newConnection
            removeAfterDelay(relayData.id)
            return newConnection
        }
    }
    
    public func addNWCConnection(connectionId:String, url:String) -> RelayConnection  {
        if let existingConnection = connections[connectionId] {
            return existingConnection
        }
        else {
            let relayData = RelayData(read: true, url: url, write: true, excludedPubkeys: [])
            let newConnection = RelayConnection(relayData, isNWC: true, queue: queue)
            connections[connectionId] = newConnection
            return newConnection
        }
    }
    
    public func addNCConnection(connectionId:String, url:String) -> RelayConnection {
        if let existingConnection = connections[connectionId] {
            return existingConnection
        }
        else {
            let relayData = RelayData(read: true, url: url, write: true, excludedPubkeys: [])
            let newConnection = RelayConnection(relayData, isNC: true, queue: queue)
            connections[connectionId] = newConnection
            return newConnection
        }
    }
    
    public func connectAll() {
        queue.async {
            for (_, connection) in self.connections {
                guard connection.relayData.read || connection.relayData.write else { continue }
                guard !connection.isSocketConnected else { continue }
                connection.connect()
            }
        }
        
        stayConnectedTimer?.invalidate()
        stayConnectedTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true, block: { _ in
            if NetworkMonitor.shared.isConnected {
                self.stayConnectedPing()
            }
        })
    }
    
    public func connectAllWrite() {
        queue.async {
            for (_, connection) in self.connections {
                guard connection.relayData.write else { continue }
                guard !connection.isSocketConnected else { continue }
                connection.connect()
            }
        }
        
        stayConnectedTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true, block: { _ in
            self.stayConnectedPing()
        })
    }
    
    private func stayConnectedPing() {
        queue.async {
            for (_, connection) in self.connections {
                guard connection.relayData.read || connection.relayData.write else { continue }
                guard !connection.isNWC else { continue }
                guard !connection.isNC else { continue }
                
                if let lastReceivedMessageAt = connection.lastMessageReceivedAt {
                    if Date.now.timeIntervalSince(lastReceivedMessageAt) >= 45 {
                        L.sockets.info("\(connection.url) Last message older that 45 seconds, sending ping")
                        connection.ping()
                    }
                }
                else {
                    L.sockets.info("\(connection.url) Last message = nil. (re)connecting.. connection.isSocketConnecting: \(connection.isSocketConnecting) ")
                    connection.connect()
                }
            }
        }
    }
    
    // Connect to relays selected for globalish feed, reuse existing connections
    func connectFeedRelays(relays:Set<RelayData>) {
        for relay in relays {
            guard !relay.url.isEmpty else { continue }
            guard connectionByUrl(relay.url) == nil else { continue }
            
            // Add connection socket if we don't already have it from our normal connections
            _ = self.addConnection(relay)
        }
        
        // .connect() to the given relays
        let relayUrls = relays.compactMap { $0.url }
        for (_, connection) in connections {
            guard relayUrls.contains(connection.url) else { continue }
            if !connection.isConnected {
                connection.connect()
            }
        }
    }
    
    func connectionByUrl(_ url:String) -> RelayConnection? {
        let relayConnection = connections.filter { relayId, relayConnection in
            relayConnection.url == url.lowercased()
        }.first?.value
        return relayConnection
    }
    
    // For view?
    func isUrlConnected(_ url:String) -> Bool {
        let relayConnection = connections.filter { relayId, relayConnection in
            relayConnection.url == url.lowercased()
        }.first?.value
        guard relayConnection != nil else {
            return false
        }
        return relayConnection!.isConnected
    }
    
    func removeConnection(_ relayId: String) {
        if let connection = connections[relayId] {
            connection.disconnect()
            connections.removeValue(forKey: relayId)
        }
    }
    
    func disconnectAll() {
        stayConnectedTimer?.invalidate()
        stayConnectedTimer = nil
        
        for (_, connection) in connections {
            connection.disconnect()
        }
    }
    
    func ping() {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            print("ping")
            return
        }
        
        for (_, connection) in connections {
            guard connection.relayData.read else { continue }
            connection.ping()
        }
    }
    
    func removeActiveAccountSubscriptions() {
        for (_, connection) in connections {
            let closeFollowing = ClientMessage(type: .CLOSE, message: ClientMessage.close(subscriptionId: "Following"))
            connection.sendMessage(closeFollowing.message)
            let closeNotifications = ClientMessage(type: .CLOSE, message: ClientMessage.close(subscriptionId: "Notifications"))
            connection.sendMessage(closeNotifications.message)
            
            queue.async {
                if !connection.nreqSubscriptions.isDisjoint(with: Set(["Following", "Notifications"])) {
                    self.queue.async(flags: .barrier) {
                        connection.nreqSubscriptions.subtract(Set(["Following", "Notifications"]))
                    }
                }
            }
        }
    }
    
    func allowNewFollowingSubscriptions() {
        // removes "Following" from the active subscriptions so when we try a new one when following keys has changed, it would be ignored because didn't pass !contains..
        queue.async {
            for (_, connection) in self.connections {
                if connection.nreqSubscriptions.contains("Following") {
                    self.queue.async(flags: .barrier) {
                        connection.nreqSubscriptions.remove("Following")
                    }
                }
            }
        }
    }
    
    func closeSubscription(_ subscriptionId:String) {
        queue.async {
            for (_, connection) in self.connections {
                guard connection.isSocketConnected else { continue }
                
                if connection.nreqSubscriptions.contains(subscriptionId) {
                    L.lvm.info("Closing subscriptions for .relays - subscriptionId: \(subscriptionId)");
                    let closeSubscription = ClientMessage(type: .CLOSE, message: ClientMessage.close(subscriptionId: subscriptionId))
                    connection.sendMessage(closeSubscription.message)
                    self.queue.async(flags: .barrier) {
                        connection.nreqSubscriptions.remove(subscriptionId)
                    }
                }
            }
        }
    }
    
    private func removeAfterDelay(_ url:String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(60)) { [weak self] in
            if let (_ ,connection) = self?.ephemeralConnections.first(where: { (key: String, value: RelayConnection) in
                key == url
            }) {
                L.sockets.info("Removing ephemeral relay \(url)")
                connection.disconnect()
                if (self?.connections.keys.contains(url) ?? false) {
                    self?.connections.removeValue(forKey: url)
                }
            }
        }
    }
    
    
    func sendMessage(_ message:ClientMessage, subscriptionId:String? = nil, relays:Set<RelayData> = [], accountPubkey:String? = nil, afterPing:Bool = false) {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            print("Canvas.sendMessage: \(message.type) \(message.message)")
            return
        }
        if (message.type == .REQ) {
            let read = !relays.isEmpty ? relays.count : connections.values.filter { $0.relayData.read == true }.count
            if read > 0 && subscriptionId == nil { L.sockets.info("⬇️⬇️ REQ \(subscriptionId ?? "") ON \(read) RELAYS: \(message.message)") }
        }
        
        let limitToRelayIds = relays.map({ $0.id })
        
        queue.async {
            for (_, connection) in self.connections {
                if connection.isNWC || connection.isNC { // Logic for N(W)C relay is a bit different, no read/write difference
                    if connection.isNWC && !message.onlyForNWCRelay { continue }
                    if connection.isNC && !message.onlyForNCRelay { continue }
                    
                    if message.type == .REQ {
                        if (!connection.isSocketConnected) {
                            if (!connection.isSocketConnecting) {
                                L.og.info("⚡️ sendMessage \(subscriptionId): not connected yet, connecting to N(W)C relay \(connection.url)")
                                connection.connect()
                            }
                        }
                        // For NWC we just replace active subscriptions, else doesn't work
                        L.sockets.debug("⬇️⬇️ REQUESTING \(subscriptionId): \(message.message)")
                        if afterPing {
                            connection.sendMessageAfterPing(message.message)
                        }
                        else {
                            connection.sendMessage(message.message)
                        }
                    }
                    else if  message.type == .CLOSE {
                        if (!connection.isSocketConnected) && (!connection.isSocketConnecting) {
                            continue
                        }
                        L.sockets.info("🔚🔚 CLOSE: \(message.message)")
                        connection.sendMessage(message.message)
                    }
                    else if message.type == .EVENT {
                        if let accountPubkey = accountPubkey, connection.relayData.excludedPubkeys.contains(accountPubkey) {
                            L.sockets.info("sendMessage: \(accountPubkey) excluded from \(connection.url) - not publishing here isNC:\(connection.isNC.description) - isNWC: \(connection.isNWC.description)")
                            continue
                        }
                        if (!connection.isSocketConnected) && (!connection.isSocketConnecting) {
                            connection.connect()
                        }
                        L.sockets.info("🚀🚀🚀 PUBLISHING TO \(connection.url): \(message.message)")
                        if afterPing {
                            connection.sendMessageAfterPing(message.message)
                        }
                        else {
                            connection.sendMessage(message.message)
                        }
                    }
                }
                
                else {
                    //                    L.og.debug("\(managedClient.url) - activeSubscriptions: \(managedClient.activeSubscriptions.joined(separator: " "))")
                    if message.onlyForNWCRelay || message.onlyForNCRelay { continue }
                    guard limitToRelayIds.isEmpty || limitToRelayIds.contains(connection.url) else { continue }
                    
                    guard connection.relayData.read || connection.relayData.write || limitToRelayIds.contains(connection.url) else {
                        // Skip if relay is not selected for reading or writing events
                        continue
                    }
                    
                    if message.type == .REQ && (connection.relayData.read || limitToRelayIds.contains(connection.url)) { // REQ FOR ALL READ RELAYS
                        if (!connection.isSocketConnected) {
                            if (!connection.isSocketConnecting) {
                                connection.connect()
                            }
                            /// hmm don't continue with .sendMessage (or does it queue until connection??? not sure...)
                            //                        continue
                        }
                        // skip if we already have an active subcription
                        if subscriptionId != nil && connection.nreqSubscriptions.contains(subscriptionId!) { continue }
                        if (subscriptionId != nil) {
                            self.queue.async(flags: .barrier) {
                                connection.nreqSubscriptions.insert(subscriptionId!)
                            }
                            L.sockets.info("⬇️⬇️ ADDED SUBSCRIPTION  \(connection.url): \(subscriptionId!) - total subs: \(connection.nreqSubscriptions.count) onlyForNWC: \(message.onlyForNWCRelay) .isNWC: \(connection.isNWC) - onlyForNC: \(message.onlyForNCRelay) .isNC: \(connection.isNC)")
                        }
                        L.sockets.debug("⬇️⬇️ REQUESTING \(subscriptionId): \(message.message)")
                        if afterPing {
                            connection.sendMessageAfterPing(message.message)
                        }
                        else {
                            connection.sendMessage(message.message)
                        }
                    }
                    else if message.type == .CLOSE { // CLOSE FOR ALL RELAYS
                        if (!connection.relayData.read && !limitToRelayIds.contains(connection.url)) { continue }
                        if (!connection.isSocketConnected) && (!connection.isSocketConnecting) {
                            // Already closed? no need to connect and send CLOSE message
                            continue
                            //                        managedClient.connect()
                        }
                        L.sockets.info("🔚🔚 CLOSE: \(message.message)")
                        connection.sendMessage(message.message)
                    }
                    else if message.type == .EVENT && connection.relayData.write { // EVENT IS ONLY FOR WRITE RELAYS
                        if let accountPubkey = accountPubkey, connection.relayData.excludedPubkeys.contains(accountPubkey) {
                            L.sockets.info("sendMessage: \(accountPubkey) excluded from \(connection.url) - not publishing here isNC:\(connection.isNC.description) - isNWC: \(connection.isNWC.description) ")
                            continue
                        }
                        if (!connection.isSocketConnected) && (!connection.isSocketConnecting) {
                            connection.connect()
                        }
                        L.sockets.info("🚀🚀🚀 PUBLISHING TO \(connection.url): \(message.message)")
                        if afterPing {
                            connection.sendMessageAfterPing(message.message)
                        }
                        else {
                            connection.sendMessage(message.message)
                        }
                    }
                }
            }
        }
    }
    
    func sendEphemeralMessage(_ message:String, relay:String) {
        let connection = addEphemeralConnection(RelayData(read: true, url: relay, write: false, excludedPubkeys: []))
        connection.connect(andSend: message)
    }
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
                    if self.relayData.read || self.relayData.write {
                        self.connect(forceConnectionAttempt: true)
                    }
                }
                else if fromConnectedToDisconnected {
                    if self.relayData.read || self.relayData.write {
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
            
            self.webSocketSub?.cancel()
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
            if self.webSocket == nil || !self.isSocketConnected {
                L.sockets.info("🔴🔴 Not connected. Did not sendMessage \(self.url)")
                return
            }
            let socketMessage = SocketMessage(text: text)
            self.outQueue.append(socketMessage)
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
            self.webSocketSub?.cancel()
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
        L.sockets.debug("🟠🟠🏎️🔌 RECEIVED: \(self.url): \(text)")
        MessageParser.shared.socketReceivedMessage(text: text, relayUrl: self.url, client: self)
        self.lastMessageReceivedAt = .now
    }
    
    func didDisconnect() {
        queue.async(flags: .barrier) {
            self.nreqSubscriptions = []
            self.lastMessageReceivedAt = nil
            self.isSocketConnected = false
            self.webSocketSub?.cancel()
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
            self.webSocketSub?.cancel()
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
                sendNotification(.socketConnected, "Connected: \(self.url)")
            }
        }
        L.sockets.info("🏎️🏎️🔌 CONNECTED \(self.url)")
        LVMManager.shared.restoreSubscriptions()
    }
    
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        queue.async(flags: .barrier) {
            self.nreqSubscriptions = []
            self.exponentialReconnectBackOff = 0
            self.skipped = 0
            self.lastMessageReceivedAt = .now
            self.isSocketConnected = false
            self.webSocketSub?.cancel()
            self.webSocketSub = nil
            DispatchQueue.main.async {
                sendNotification(.socketNotification, "Disconnected: \(self.url)")
            }
        }
        L.sockets.info("🏎️🏎️🔌 DISCONNECTED \(self.url): with code: \(closeCode.rawValue) \(String(describing: reason != nil ? String(data: reason!, encoding: .utf8) : "") )")

    }
}


func fetchEventFromRelayHint(_ eventId:String, fastTags:[(String, String, String?, String?)]) {
    // EventRelationsQueue.shared.addAwaitingEvent(event) <-- not needed, should already be awaiting
    //    [
    //      "e",
    //      "437743753045cd4b3335b0b8c921eaf301f65862d74b737b40278d9e4e3b1b88",
    //      "wss://relay.mostr.pub",
    //      "reply"
    //    ],
    if let relay = fastTags.filter({ $0.0 == "e" && $0.1 == eventId }).first?.2 {
        if relay.prefix(6) == "wss://" || relay.prefix(5) == "ws://" {
            ConnectionPool.shared.sendEphemeralMessage(
                RM.getEvent(id: eventId),
                relay: relay
            )
        }
    }
}


protocol RelayConnectionDelegate: URLSessionWebSocketDelegate {
    func didReceiveData(_ data:Data)
    
    func didReceiveMessage(_ text:String)
    
    func didDisconnect()
    
    func didDisconnectWithError(_ error:Error)
    
    func didReceivePong()
}

struct SocketMessage {
    let id = UUID()
    let text:String
}
