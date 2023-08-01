//
//  NewSocketPool.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/04/2023.
//

import Foundation
import CoreData
import OSLog
import CombineWebSocket
import Combine

// Structure is:
// SocketPool
//  .sockets
//      [NSManagedObjectID.URIRepresentation.absoluteString] = ManagedClient
//                                    .client
//                                    .activeSubscriptions
//
//      [NSManagedObjectID.URIRepresentation.absoluteString] = ManagedClient
//                                    .client
//                                    .activeSubscriptions
//
//      [NSManagedObjectID.URIRepresentation.absoluteString] = ManagedClient
//                                    .client
//                                    .activeSubscriptions
//
//      [NSManagedObjectID.URIRepresentation.absoluteString] = ManagedClient
//                                    .client
//                                    .activeSubscriptions

final class SocketPool: ObservableObject {
    
    static let shared = SocketPool()
    
    @Published var sockets:[String : NewManagedClient] = [:]
    public var connectionQueue = DispatchQueue(label: "com.nostur.connection", qos: .utility, attributes: .concurrent)
    public var websocketQueue = DispatchQueue(label: "com.nostur.websocket", qos: .utility, attributes: .concurrent)
    
    var stayConnectedTimer:Timer?
    
    func setup(_ activeNWCconnectionId:String) {
        DataProvider.shared().viewContext.performAndWait {
            do {
                let fetchRequest: NSFetchRequest<Relay> = Relay.fetchRequest()
                let relays = try fetchRequest.execute()
                let sp = SocketPool.shared
                
                // CONNECT TO RELAYS
                for relay in relays {
                    _ = sp.addSocket(relayId: relay.objectID.uriRepresentation().absoluteString, url: relay.url!, read:relay.read, write: relay.write)
                }
                // If we have NWC relays, connect to those too
                if !activeNWCconnectionId.isEmpty, let nwc = NWCConnection.fetchConnection(activeNWCconnectionId, context: DataProvider.shared().viewContext) {
                    _ = sp.addNWCSocket(connectionId:nwc.connectionId, url: nwc.relay)
                }
            } catch {
                L.sockets.error("🔴🔴🔴 Fail in SocketPool.shared.setup(), \(error)")
            }
        }
    }
    
    func connectAll() {
        for socket in sockets {
            guard socket.value.read else { continue }
            if !socket.value.isConnecting && !socket.value.isConnected {
                socket.value.activeSubscriptions = []
                socket.value.connect()
            }
        }
        stayConnectedTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true, block: { _ in
            self.stayConnectedPing()
        })
    }
    
    // Connect to relays selected for globalish feed, reuse existing connections
    func connectFeedRelays(relays:Set<Relay>) {
        
        for relay in relays {
            guard let relayUrl = relay.url else { continue }
            guard socketByUrl(relayUrl) == nil else { continue }
        
            // Add connection socket if we don't already have it from our normal connections
            _ = SocketPool.shared.addSocket(relayId: relay.objectID.uriRepresentation().absoluteString, url: relayUrl, read:true, write: false)
        }
        
        // .connect() to the given relays
        let relayUrls = relays.compactMap { $0.url }
        for socket in sockets {
            guard relayUrls.contains(socket.value.client.url) else { continue }
            if !socket.value.isConnecting && !socket.value.isConnected {
                socket.value.activeSubscriptions = []
                socket.value.connect()
            }
        }
    }
    
    private func stayConnectedPing() {
        for socket in sockets {
            guard socket.value.read else { continue }
            guard !socket.value.isNWC else { continue }
            guard !socket.value.isNC else { continue }
            DispatchQueue.main.async { // Maybe fixes deadlock?
                if let lastReceivedMessageAt = socket.value.lastMessageReceivedAt {
                    if Date.now.timeIntervalSince(lastReceivedMessageAt) >= 45 {
                        L.sockets.info("\(socket.value.url) Last message older that 45 seconds, sending ping")
                        socket.value.client.ping()
                    }
                }
                else {
                    L.sockets.info("\(socket.value.url) Last message = nil. (re)connecting..")
                    socket.value.activeSubscriptions = []
                    socket.value.connect()
                }
            }
        }
    }
    
    func disconnectAll() {
        for socket in sockets {
            if socket.value.isConnecting || socket.value.isConnected {
//                socket.value.activeSubscriptions.forEach { subscription in
//                    SocketPool.shared
//                        .sendMessage(ClientMessage(
//                            type: .CLOSE,
//                            message: ClientMessage.close(subscriptionId: subscription)
//                        ))
//                }
                socket.value.disconnect()
            }
        }
    }
    
    func addSocket(relayId:String, url:String, read:Bool = true, write: Bool = false) -> NewManagedClient {
        if (!sockets.keys.contains(relayId)) {
            let urlURL:URL = URL(string: url) ?? URL(string:"wss://localhost:123456/invalid_relay_url")!
            var request = URLRequest(url: urlURL)
            //             request.setValue(["wamp"].joined(separator: ","), forHTTPHeaderField: "Sec-WebSocket-Protocol")
            
            request.timeoutInterval = 15
            
            let client = NewWebSocket(url: url)
            
            let managedClient = NewManagedClient(relayId: relayId, url: url, client:client, read: read, write: write)
            
            client.delegate = managedClient
            
            if (read || write) {
                managedClient.connect()
            }
            sockets[relayId] = managedClient
            return managedClient
        }
        else {
            return sockets[relayId]!
        }
    }
    
    func addNWCSocket(connectionId:String, url:String) -> NewManagedClient {
        if (!sockets.keys.contains(connectionId)) {
            let urlURL:URL = URL(string: url) ?? URL(string:"wss://localhost:123456/invalid_relay_url")!
            var request = URLRequest(url: urlURL)
            //             request.setValue(["wamp"].joined(separator: ","), forHTTPHeaderField: "Sec-WebSocket-Protocol")
            
            request.timeoutInterval = 15
            
            let client = NewWebSocket(url: url)
            
            let managedClient = NewManagedClient(relayId: connectionId, url: url, client:client, read: true, write: true, isNWC: true)
            
            client.delegate = managedClient
            
            managedClient.connect()
            
            sockets[connectionId] = managedClient
            return managedClient
        }
        else {
            return sockets[connectionId]!
        }
    }
    
    func addNCSocket(sessionPublicKey:String, url:String) -> NewManagedClient {
        if (!sockets.keys.contains(sessionPublicKey)) {
            let urlURL:URL = URL(string: url) ?? URL(string:"wss://localhost:123456/invalid_relay_url")!
            var request = URLRequest(url: urlURL)
            //             request.setValue(["wamp"].joined(separator: ","), forHTTPHeaderField: "Sec-WebSocket-Protocol")
            
            request.timeoutInterval = 15
            
            let client = NewWebSocket(url: url)
            
            let managedClient = NewManagedClient(relayId: sessionPublicKey, url: url, client:client, read: true, write: true, isNC: true)
            
            client.delegate = managedClient
            
            managedClient.connect()
            
            sockets[sessionPublicKey] = managedClient
            return managedClient
        }
        else {
            return sockets[sessionPublicKey]!
        }
    }
    
    func socketByUrl(_ url:String) -> NewManagedClient? {
        let managedClient = sockets.filter { relayId, managedClient in
            managedClient.url == url.lowercased()
        }.first?.value
        return managedClient
    }
    
    func isUrlConnected(_ url:String) -> Bool {
        let managedClient = sockets.filter { relayId, managedClient in
            managedClient.url == url.lowercased()
        }.first?.value
        guard managedClient != nil else {
            return false
        }
        return managedClient!.isConnected
    }
    
    func removeSocket(_ relayId:NSManagedObjectID) {
        if (sockets.keys.contains(relayId.uriRepresentation().absoluteString)) {
            sockets.removeValue(forKey: relayId.uriRepresentation().absoluteString)
        }
    }
    
    func removeSocket(_ relayId:String) {
        if (sockets.keys.contains(relayId)) {
            sockets.removeValue(forKey: relayId)
        }
    }
    
    func sendMessage(_ message:ClientMessage, subscriptionId:String? = nil, relays:Set<Relay> = []) {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            print("Canvas.sendMessage: \(message.type) \(message.message)")
            return
        }
        if (message.type == .REQ) {
            let read = !relays.isEmpty ? relays.count : sockets.values.filter { $0.read == true }.count
            if read > 0 && subscriptionId == nil { L.sockets.info("⬇️⬇️ REQ ON \(read) RELAYS: \(message.message)") }
        }
        
        let limitToRelayIds = relays.map({ $0.objectID.uriRepresentation().absoluteString })
        
        Task(priority: .utility) { [unowned self] in
            for (_, managedClient) in self.sockets {
                if managedClient.isNWC || managedClient.isNC { // Logic for N(W)C relay is a bit different, no read/write difference
                    if managedClient.isNWC && !message.onlyForNWCRelay { continue }
                    if managedClient.isNC && !message.onlyForNCRelay { continue }
                    
                    if message.type == .REQ {
                        if (!managedClient.isConnected) {
                            if (!managedClient.isConnecting) {
                                L.og.info("⚡️ sendMessage: not connected yet, connecting to N(W)C relay \(managedClient.url)")
                                managedClient.connect()
                            }
                        }
                        // For NWC we just replace active subscriptions, else doesn't work
                        L.sockets.debug("⬇️⬇️ REQUESTING: \(message.message)")
                        managedClient.client.sendMessage(message.message)
                    }
                    else if  message.type == .CLOSE {
                        if (!managedClient.isConnected) && (!managedClient.isConnecting) {
                            continue
                        }
                        L.sockets.info("🔚🔚 CLOSE: \(message.message)")
                        managedClient.client.sendMessage(message.message)
                    }
                    else if message.type == .EVENT {
                        if (!managedClient.isConnected) && (!managedClient.isConnecting) {
                            managedClient.connect()
                        }
                        L.sockets.info("🚀🚀🚀 PUBLISHING TO \(managedClient.url): \(message.message)")
                        managedClient.client.sendMessage(message.message)
                    }
                }
                
                else {
                    L.og.debug("\(managedClient.url) - activeSubscriptions: \(managedClient.activeSubscriptions.joined(separator: " "))")
                    if message.onlyForNWCRelay || message.onlyForNCRelay { continue }
                    guard limitToRelayIds.isEmpty || limitToRelayIds.contains(managedClient.relayId) else { continue }
                    
                    guard managedClient.read || managedClient.write || limitToRelayIds.contains(managedClient.relayId) else {
                        // Skip if relay is not selected for reading or writing events
                        continue
                    }
                    
                    if message.type == .REQ && (managedClient.read || limitToRelayIds.contains(managedClient.relayId)) { // REQ FOR ALL READ RELAYS
                        if (!managedClient.isConnected) {
                            if (!managedClient.isConnecting) {
                                managedClient.connect()
                            }
                            /// hmm don't continue with .sendMessage (or does it queue until connection??? not sure...)
                            //                        continue
                        }
                        // skip if we already have an active subcription
                        if subscriptionId != nil && managedClient.activeSubscriptions.contains(subscriptionId!) { continue }
                        if (subscriptionId != nil) {
                            DispatchQueue.main.async {
                                managedClient.activeSubscriptions.append(subscriptionId!)
                                L.sockets.info("⬇️⬇️ ADDED SUBSCRIPTION  \(managedClient.url): \(subscriptionId!) - total subs: \(managedClient.activeSubscriptions.count) onlyForNWC: \(message.onlyForNWCRelay) .isNWC: \(managedClient.isNWC) - onlyForNC: \(message.onlyForNCRelay) .isNC: \(managedClient.isNC)")
                            }
                        }
                        L.sockets.debug("⬇️⬇️ REQUESTING: \(message.message)")
                        managedClient.client.sendMessage(message.message)
                    }
                    else if message.type == .CLOSE { // CLOSE FOR ALL RELAYS
                        if (!managedClient.read && !limitToRelayIds.contains(managedClient.relayId)) { continue }
                        if (!managedClient.isConnected) && (!managedClient.isConnecting) {
                            // Already closed? no need to connect and send CLOSE message
                            continue
                            //                        managedClient.connect()
                        }
                        L.sockets.info("🔚🔚 CLOSE: \(message.message)")
                        managedClient.client.sendMessage(message.message)
                    }
                    else if message.type == .EVENT && managedClient.write { // EVENT IS ONLY FOR WRITE RELAYS
                        if (!managedClient.isConnected) && (!managedClient.isConnecting) {
                            managedClient.connect()
                        }
                        L.sockets.info("🚀🚀🚀 PUBLISHING TO \(managedClient.url): \(message.message)")
                        managedClient.client.sendMessage(message.message)
                    }
                }
            }
        }
    }
    
    func sendMessageAfterPing(_ message:ClientMessage, subscriptionId:String? = nil, relays:Set<Relay> = []) {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            print("Canvas.sendMessage: \(message.type) \(message.message)")
            return
        }
        if (message.type == .REQ) {
            let read = !relays.isEmpty ? relays.count : sockets.values.filter { $0.read == true }.count
            if read > 0 && subscriptionId == nil { L.sockets.info("⬇️⬇️🟪 REQ ON \(read) RELAYS: \(message.message)") }
        }
        
        let limitToRelayIds = relays.map({ $0.objectID.uriRepresentation().absoluteString })
        
        Task(priority: .utility) { [unowned self] in
            for (_, managedClient) in self.sockets {
                guard managedClient.read || managedClient.write || limitToRelayIds.contains(managedClient.relayId) else {
                    // Skip if relay is not selected for reading or writing events
                    continue
                }
                if managedClient.isNWC || managedClient.isNC { // Logic for N(W)C relay is a bit different, no read/write difference
                    if managedClient.isNWC && !message.onlyForNWCRelay { continue }
                    if managedClient.isNC && !message.onlyForNCRelay { continue }
                    if message.type == .REQ {
                        if (!managedClient.isConnected) {
                            if (!managedClient.isConnecting) {
                                L.og.info("⚡️ sendMessage: not connected yet, connecting to N(W)C relay \(managedClient.url)")
                                managedClient.connect()
                            }
                        }
                        // skip if we already have an active subcription
                        if subscriptionId != nil && managedClient.activeSubscriptions.contains(subscriptionId!) { continue }
                        if (subscriptionId != nil) {
                            DispatchQueue.main.async {
                                managedClient.activeSubscriptions.append(subscriptionId!)
                                L.sockets.info("⬇️⬇️ ADDED SUBSCRIPTION  \(managedClient.url): \(subscriptionId!) - total subs: \(managedClient.activeSubscriptions.count) onlyForNWC: \(message.onlyForNWCRelay) .isNWC: \(managedClient.isNWC) -- onlyForNC: \(message.onlyForNCRelay) .isNC: \(managedClient.isNC)")
                            }
                        }
                        L.sockets.debug("⬇️⬇️ REQUESTING: \(message.message)")
                        managedClient.client.sendMessageAfterPing(message.message)
                    }
                    else if  message.type == .CLOSE {
                        if (!managedClient.isConnected) && (!managedClient.isConnecting) {
                            continue
                        }
                        L.sockets.info("🔚🔚 CLOSE: \(message.message)")
                        managedClient.client.sendMessageAfterPing(message.message)
                    }
                    else if message.type == .EVENT {
                        if (!managedClient.isConnected) && (!managedClient.isConnecting) {
                            managedClient.connect()
                        }
                        L.sockets.info("🚀🚀🚀 PUBLISHING TO \(managedClient.url): \(message.message)")
                        managedClient.client.sendMessageAfterPing(message.message)
                    }
                }
                else {
                    if message.onlyForNWCRelay || message.onlyForNCRelay { continue }
                    guard limitToRelayIds.isEmpty || limitToRelayIds.contains(managedClient.relayId) else { continue }
                    
                    if message.type == .REQ && (managedClient.read || limitToRelayIds.contains(managedClient.relayId)) { // REQ FOR ALL READ RELAYS
                        if (!managedClient.isConnected) {
                            if (!managedClient.isConnecting) {
                                managedClient.connect()
                            }
                            /// hmm don't continue with .sendMessage (or does it queue until connection??? not sure...)
    //                        continue
                        }
                        // skip if we already have an active subcription
                        if subscriptionId != nil && managedClient.activeSubscriptions.contains(subscriptionId!) { continue }
                        if (subscriptionId != nil) {
                            DispatchQueue.main.async {
                                managedClient.activeSubscriptions.append(subscriptionId!)
                                L.sockets.info("⬇️⬇️ ADDED SUBSCRIPTION  \(managedClient.url): \(subscriptionId!) - total subs: \(managedClient.activeSubscriptions.count) onlyForNWC: \(message.onlyForNWCRelay) .isNWC: \(managedClient.isNWC) -- onlyForNWC: \(message.onlyForNCRelay) .isNWC: \(managedClient.isNC)")
                            }
                        }
                        L.sockets.debug("⬇️⬇️ REQUESTING: \(String(message.message))")
                        managedClient.client.sendMessageAfterPing(message.message)
                    }
                    else if  message.type == .CLOSE { // CLOSE FOR ALL RELAYS
                        if (!managedClient.read && !limitToRelayIds.contains(managedClient.relayId)) { continue }
                        if (!managedClient.isConnected) && (!managedClient.isConnecting) {
                            // Already closed? no need to connect and send CLOSE message
                            continue
                            //                        managedClient.connect()
                        }
                        L.sockets.info("🟪🔚🔚 CLOSE: \(message.message)")
                        // FOR close we dont need to ping first, if it fails we dont care
                        managedClient.client.sendMessage(message.message)
                    }
                    else if message.type == .EVENT && managedClient.write { // EVENT IS ONLY FOR WRITE RELAYS
                        if (!managedClient.isConnected) && (!managedClient.isConnecting) {
                            managedClient.connect()
                        }
                        L.sockets.info("🟪🚀🚀🚀 PUBLISHING TO \(managedClient.url): \(message.message)")
                        managedClient.client.sendMessageAfterPing(message.message)
                    }
                }
            }
        }
    }
    
    func ping() {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            print("ping")
            return
        }
        
        Task(priority: .utility) { [unowned self] in
            for (_, managedClient) in self.sockets {
                guard managedClient.read else {
                    // Skip if relay is not selected for reading or writing events
                    continue
                }
                managedClient.client.ping()

            }
        }
    }
    
    func removeActiveAccountSubscriptions() {
        for socket in sockets {
            socket.value.activeSubscriptions.removeAll { subscriptionId in
                subscriptionId == "Following" || subscriptionId == "Notifications"
            }
            let closeFollowing = ClientMessage(type: .CLOSE, message: ClientMessage.close(subscriptionId: "Following"))
            socket.value.client.sendMessage(closeFollowing.message)
            let closeNotifications = ClientMessage(type: .CLOSE, message: ClientMessage.close(subscriptionId: "Notifications"))
            socket.value.client.sendMessage(closeNotifications.message)
        }
    }
    
    func allowNewFollowingSubscriptions() {
        // removes "Following" from the active subscriptions so when we try a new one when following keys has changed, it would be ignored because didn't pass !contains..
        for socket in sockets {
            socket.value.activeSubscriptions.removeAll { subscriptionId in
                subscriptionId == "Following"
            }
        }
    }
    
    func closeSubscription(_ subscriptionId:String) {
        for socket in sockets {
            guard socket.value.isConnected else { continue }
            
            if socket.value.activeSubscriptions.contains(subscriptionId) {
                let closeSubscription = ClientMessage(type: .CLOSE, message: ClientMessage.close(subscriptionId: subscriptionId))
                socket.value.client.sendMessage(closeSubscription.message)
            }
            
            socket.value.activeSubscriptions.removeAll(where: { activeId in
                activeId == subscriptionId
            })
        }
    }
}

class NewManagedClient: NSObject, URLSessionWebSocketDelegate, NewWebSocketDelegate, ObservableObject {
    
    var relayId:String
    var url:String
    var isNWC:Bool
    var isNC:Bool
    var client:NewWebSocket
    
    var _skipped = 0
    var _exponentialReconnectBackOff = 0
    
    
    private var _isConnecting = false
    private var _activeSubscriptions:[String] = []
    
    private var _lastMessageReceivedAt:Date? = nil
    var lastMessageReceivedAt: Date? {
        get {
            return SocketPool.shared.connectionQueue.sync {
                _lastMessageReceivedAt
            }
        }
        set {
            SocketPool.shared.connectionQueue.async(flags: .barrier) {
                self._lastMessageReceivedAt = newValue
            }
        }
    }
    
    var skipped: Int {
        get {
            return SocketPool.shared.connectionQueue.sync {
                _skipped
            }
        }
        set {
            SocketPool.shared.connectionQueue.async(flags: .barrier) {
                self._skipped = newValue
            }
        }
    }
    
    var exponentialReconnectBackOff: Int {
        get {
            return SocketPool.shared.connectionQueue.sync {
                _exponentialReconnectBackOff
            }
        }
        set {
            SocketPool.shared.connectionQueue.async(flags: .barrier) {
                self._exponentialReconnectBackOff = newValue
            }
        }
    }
    
    var isConnecting: Bool {
        get {
            return SocketPool.shared.connectionQueue.sync {
                _isConnecting
            }
        }
        set {
            SocketPool.shared.connectionQueue.async(flags: .barrier) {
                self._isConnecting = newValue
            }
        }
    }
    
    @Published var isConnected = false
    @Published var read = true
    @Published var write = false
    
    var activeSubscriptions:[String] {
        get {
            return SocketPool.shared.connectionQueue.sync {
                _activeSubscriptions
            }
        }
        set {
            SocketPool.shared.connectionQueue.async(flags: .barrier) {
                self._activeSubscriptions = newValue
            }
        }
    }
    
    init(relayId: String, url: String, client:NewWebSocket, read: Bool = true, write: Bool = false, isNWC:Bool = false, isNC:Bool = false) {
        self.relayId = relayId
        self.url = url.lowercased()
        self.read = read
        self.write = write
        self.client = client
        self.isNWC = isNWC
        self.isNC = isNC
    }
    
    func didReceivePong() {
        self.lastMessageReceivedAt = .now
    }
    
    func connect(_ forceConnectionAttempt:Bool = false) {
        guard self.exponentialReconnectBackOff > 512 || self.exponentialReconnectBackOff == 1 || forceConnectionAttempt || self.skipped == self.exponentialReconnectBackOff else { // Should be 0 == 0 to continue, or 2 == 2 etc..
            self.skipped = skipped + 1
            L.sockets.info("🏎️🏎️🔌🔴 Skipping reconnect. \(self.url) EB: (\(self.exponentialReconnectBackOff)) skipped: \(self.skipped)")
            return
        }
        if !isConnecting {
            self.skipped = 0
            self.isConnecting = true
            self.client.connect()
            if self.exponentialReconnectBackOff >= 512 {
                self.exponentialReconnectBackOff = 512
            }
            else {
                self.exponentialReconnectBackOff = max(1, self.exponentialReconnectBackOff * 2)
            }
        }
    }
    
    func disconnect() {
        DispatchQueue.main.async {
            self.isConnecting = false
            self.isConnected = false
        }
        self.client.disconnect()
        self.activeSubscriptions = []
        self.lastMessageReceivedAt = nil
    }
    
    func didDisconnect() {
        DispatchQueue.main.async {
            SocketPool.shared.objectWillChange.send()
            self.isConnecting = false
            self.isConnected = false
        }
        self.activeSubscriptions = []
        self.lastMessageReceivedAt = nil
        L.sockets.info("🏎️🏎️🔌 DISCONNECTED \(self.url)")
        DispatchQueue.main.async {
            sendNotification(.socketNotification, "Disconnected: \(self.url)")
        }
    }
    
    func didDisconnectWithError(_ error: Error) {
        DispatchQueue.main.async {
            SocketPool.shared.objectWillChange.send()
            self.isConnecting = false
            self.isConnected = false
            let shortURL = URL(string: self.url)?.baseURL?.description ?? self.url
            sendNotification(.socketNotification, "Error: \(shortURL) \(error.localizedDescription)")
        }
        self.activeSubscriptions = []
        self.lastMessageReceivedAt = nil
        self.exponentialReconnectBackOff = max(1, self.exponentialReconnectBackOff * 2)
        L.sockets.info("🏎️🏎️🔌🔴 DISCONNECTED WITH ERROR \(self.url): \(error.localizedDescription)")
        DispatchQueue.main.async {
            sendNotification(.socketNotification, "Disconnected: \(self.url)")
        }
    }
    
    func didReceiveMessage(_ text:String) {
        L.sockets.info("🟠🟠🏎️🔌 RECEIVED: \(self.url): \(text)")
        self.lastMessageReceivedAt = .now
        MessageParser.shared.socketReceivedMessage(text: text, relayUrl: self.url, client:client)
    }
    
    func didReceiveData(_ data:Data) {
        self.lastMessageReceivedAt = .now
        L.sockets.info("🔌 RECEIVED DATA \(self.url): \(data.count)")
    }
    
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async {
            SocketPool.shared.objectWillChange.send()
            self.isConnecting = false
            self.isConnected = true
        }
        self.activeSubscriptions = []
        self.exponentialReconnectBackOff = 0
        self.skipped = 0
        L.sockets.info("🏎️🏎️🔌 CONNECTED \(self.url)")
        self.lastMessageReceivedAt = .now
        DispatchQueue.main.async {
            sendNotification(.socketConnected, "Connected: \(self.url)")
        }
        LVMManager.shared.restoreSubscriptions()
    }
    
    
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async {
            SocketPool.shared.objectWillChange.send()
            self.isConnecting = false
            self.isConnected = false
        }
        self.activeSubscriptions = []
        self.exponentialReconnectBackOff = 0
        self.skipped = 0
        self.lastMessageReceivedAt = nil
        DispatchQueue.main.async {
            sendNotification(.socketNotification, "Disconnected: \(self.url)")
        }
        L.sockets.info("🏎️🏎️🔌 DISCONNECTED \(self.url): with code: \(closeCode.rawValue) \(String(describing: reason != nil ? String(data: reason!, encoding: .utf8) : "") )")
        
    }
}

protocol NewWebSocketDelegate: URLSessionWebSocketDelegate {
    func didReceiveData(_ data:Data)
    
    func didReceiveMessage(_ text:String)
    
    func didDisconnect()
    
    func didDisconnectWithError(_ error:Error)
    
    func didReceivePong()
}


class NewWebSocket {
    let url:String
    var socketQueue = OperationQueue()
    
    var delegate_:NewWebSocketDelegate?
    var delegate:NewWebSocketDelegate? {
        get {
            SocketPool.shared.websocketQueue.sync {
                self.delegate_
            }
        }
        set {
            SocketPool.shared.websocketQueue.sync {
                self.delegate_ = newValue
                self.session = URLSession(configuration: .default, delegate: self.delegate_, delegateQueue: self.socketQueue)
            }
        }
    }
    
    var subscriptions_ = Set<AnyCancellable>()
    var subscriptions:Set<AnyCancellable> {
        get {
            SocketPool.shared.websocketQueue.sync {
                self.subscriptions_
            }
        }
        set {
            SocketPool.shared.websocketQueue.async(flags: .barrier) {
                self.subscriptions_ = newValue
            }
        }
    }
    
    var connection_:AnyCancellable?
    var connection:AnyCancellable? {
        get {
            SocketPool.shared.websocketQueue.sync {
                self.connection_
            }
        }
        set {
            SocketPool.shared.websocketQueue.async(flags: .barrier) {
                self.connection_ = newValue
            }
        }
    }
    
    var pinger_:AnyCancellable?
    var pinger:AnyCancellable? {
        get {
            SocketPool.shared.websocketQueue.sync {
                self.pinger_
            }
        }
        set {
            SocketPool.shared.websocketQueue.async(flags: .barrier) {
                self.pinger_ = newValue
            }
        }
    }
    
    var webSocket_:WebSocket?
    var webSocket:WebSocket? {
        get {
            SocketPool.shared.websocketQueue.sync {
                self.webSocket_
            }
        }
        set {
            SocketPool.shared.websocketQueue.async(flags: .barrier) {
                self.webSocket_ = newValue
            }
        }
    }
    
    var session:URLSession?
    
    init(url:String) {
        self.url = url
    }
    
    func sendMessageAfterPing(_ text:String) {
        L.sockets.info("🟪 sendMessageAfterPing  \(text)")
        guard let webSocket = webSocket else {
            L.sockets.info("🟪🔴🔴 Not connected.  \(self.url)")
            return
        }
        webSocket.ping()
            .sink(receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        // Handle the failure case
                        let _url = self.url
                        let _error = error
                        L.sockets.info("🟪 \(_url) Ping Failure: \(_error), trying to reconnect")
                        DispatchQueue.main.async {
                            self.connect(andSend:text)
                        }
                    case .finished:
                        // The ping completed successfully
                        L.sockets.info("🟪 Ping succeeded on \(self.url). Sending \(text)")
                        L.sockets.debug("🟠🟠🏎️🔌🔌 SEND \(self.url): \(text)")
                        let _ = webSocket.send(text)
                            .sink(receiveCompletion: {
                                print($0)
                                L.sockets.info("🟪 WHAT")
                            }, receiveValue: {
                                print($0)
                                L.sockets.info("🟪 WHAT OK")
                            })
                        sendNotification(.pong)
                    }
                }, receiveValue: { _ in
                    // Handle the received value (optional, based on your requirements)
//                    L.sockets.info("Received value during ping")
                })
            .store(in: &subscriptions)
    }
    
    func ping() {
        L.sockets.info("Trying to ping: \(self.url)")
        guard let webSocket = webSocket else {
            L.sockets.info("🔴🔴 Not connected. ????? \(self.url)")
            return
        }
        webSocket.ping()
            .sink(receiveCompletion: { [weak self] completion in
                guard let self = self else { return }
                    switch completion {
                    case .failure(let error):
                        // Handle the failure case
                        let _url = self.url
                        let _error = error
                        L.sockets.info("\(_url) Ping Failure: \(_error), trying to reconnect")
                        DispatchQueue.main.async {
                            self.connect()
                        }
                    case .finished:
                        // The ping completed successfully
                        let _url = self.url
                        L.sockets.info("\(_url) Ping succeeded")
                        self.delegate?.didReceivePong()
                        sendNotification(.pong)
                    }
                }, receiveValue: { _ in
                    // Handle the received value (optional, based on your requirements)
//                    L.sockets.info("Received value during ping")
                })
            .store(in: &subscriptions)
    }
    
    func sendMessage(_ text:String) {
        guard let webSocket = webSocket else {
            L.sockets.info("🔴🔴 Not connected. Did not sendMessage \(self.url)")
            return
        }
        L.sockets.debug("🟠🟠🏎️🔌🔌 SEND \(self.url): \(text)")
        let _ = webSocket.send(text)
            .sink(receiveCompletion: { _ in
                L.sockets.info("sendMessage receiveCompletion")
            }, receiveValue: {
                L.sockets.info("sendMessage receiveValue")
            } )
    }
    
    func connect(andSend:String? = nil) {
        guard let session = session else { return }
        let urlRequest = URLRequest(url: URL(string: url) ?? URL(string: "wss://localhost:123456/invalid_relay_url")!)
        
        // Create the WebSocket instance. This is the entry-point for sending and receiving messages
        webSocket = session.webSocket(with: urlRequest)
        
        // Subscribe to the WebSocket. This will connect to the remote server and start listening
        // for messages (URLSessionWebSocketTask.Message).
        // URLSessionWebSocketTask.Message is an enum for either Data or String
        if let webSocket {
            connection = webSocket
                .publisher
                .sink(receiveCompletion: { completion in
                    switch completion {
                        case .finished:
                            self.delegate?.didDisconnect()
                        case .failure(let error):
                            self.delegate?.didDisconnectWithError(error)
                    }
                },
                      receiveValue: { message in
                    switch message {
                        case .data(let data):
                            // Handle Data message
                            self.delegate?.didReceiveData(data)
                        case .string(let string):
                            // Handle String message
                            self.delegate?.didReceiveMessage(string)
                        @unknown default:
                            print("dunno")
                    }
                })
            
            guard let andSend = andSend else { return }
            let _ = webSocket.send(andSend)
                .sink(receiveCompletion: { _ in
                    L.sockets.info("andSend completion")
                }, receiveValue: {
                    L.sockets.info("andSend receiveValue")
                } )
        }
    }
    
    func disconnect() {
        guard webSocket != nil else { return }
        // You can stop the WebSocket subscription, disconnecting from remote server.
//        pinger?.cancel()
//        pingOnceSub?.cancel()
        connection?.cancel()
    }
}




final class EphemeralSocketPool: ObservableObject {
    
    static let shared = EphemeralSocketPool()
    
    @Published var sockets:[String : NewEphemeralClient] = [:]
    
    func addSocket(url:String) -> NewEphemeralClient {
        let urlLower = url.lowercased()
        removeAfterDelay(urlLower)
        if (!sockets.keys.contains(urlLower)) {
            let urlURL:URL = URL(string: urlLower) ?? URL(string:"wss://localhost:123456/invalid_relay_url")!
            var request = URLRequest(url: urlURL)
            request.timeoutInterval = 15
            
            let client = NewWebSocket(url: url)
            
            let managedClient = NewEphemeralClient(url: urlLower, client: client)
            
            client.delegate = managedClient
            
            managedClient.connect()
            sockets[urlLower] = managedClient
            return managedClient
        }
        else {
            return sockets[urlLower]!
        }
    }
    
    private func removeAfterDelay(_ url:String) {
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(60)) { [weak self] in
            if let socket = self?.sockets.first(where: { (key: String, value: NewEphemeralClient) in
                key == url
            }) {
                L.sockets.info("Removing ephemeral relay \(url)")
                socket.value.disconnect()
                self?.sockets.removeValue(forKey: url)
            }
        }
    }
    
    func socketByUrl(_ url:String) -> NewEphemeralClient? {
        let managedClient = sockets.filter { url, managedClient in
            managedClient.url == url.lowercased()
        }.first?.value
        return managedClient
    }
    
    func removeSocket(_ url:String) {
        if (sockets.keys.contains(url)) {
            sockets.removeValue(forKey: url)
        }
    }
    
    func sendMessage(_ message:String, relay:String) {
        Task(priority: .utility) {
            let socket = addSocket(url: relay)
            socket.connect()
            socket.client.sendMessage(message)
        }
    }
}

// Copied NewManagedClient and removed everything that is not needed for a one-off fetch
class NewEphemeralClient: NSObject, URLSessionWebSocketDelegate, NewWebSocketDelegate, ObservableObject {
    
    var url:String
    var client:NewWebSocket
    
    init(url: String, client:NewWebSocket) {
        self.url = url.lowercased()
        self.client = client
    }
    
    func didReceivePong() {
        
    }
    
    func connect() {
        self.client.connect()
    }
    
    func disconnect() {
        self.client.disconnect()
    }
    
    func didDisconnect() {
        L.sockets.info("🏎️🏎️🔌 DISCONNECTED \(self.url)")
    }
    
    func didDisconnectWithError(_ error: Error) {
        DispatchQueue.main.async {
            let shortURL = URL(string: self.url)?.baseURL?.description ?? self.url
            sendNotification(.socketNotification, "Error: \(shortURL) \(error.localizedDescription)")
        }
        L.sockets.info("🏎️🏎️🔌🔴 DISCONNECTED WITH ERROR \(self.url): \(error.localizedDescription)")
    }
    
    func didReceiveMessage(_ text:String) {
        L.sockets.info("🔌 RECEIVED TEXT \(self.url): \(text)")
        MessageParser.shared.socketReceivedMessage(text: text, relayUrl: self.url, client:client)
    }
    
    func didReceiveData(_ data:Data) {
        L.sockets.info("🔌 RECEIVED DATA \(self.url): \(data.count)")
    }
    
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        L.sockets.info("🔌 CONNECTED \(self.url)")
    }
    
    
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
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
            EphemeralSocketPool.shared.sendMessage(RM.getEvent(id: eventId), relay: relay)
        }
    }
}
