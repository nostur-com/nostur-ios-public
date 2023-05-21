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
//      [NSManagedObjectID] = ManagedClient
//                                    .client
//                                    .activeSubscriptions
//
//      [NSManagedObjectID] = ManagedClient
//                                    .client
//                                    .activeSubscriptions
//
//      [NSManagedObjectID] = ManagedClient
//                                    .client
//                                    .activeSubscriptions
//
//      [NSManagedObjectID] = ManagedClient
//                                    .client
//                                    .activeSubscriptions

final class SocketPool: ObservableObject {
    
    static let shared = SocketPool()
    
    @Published var sockets:[NSManagedObjectID : NewManagedClient] = [:]
    
    func setup() {
        DataProvider.shared().viewContext.performAndWait {
            do {
                let fetchRequest: NSFetchRequest<Relay> = Relay.fetchRequest()
                let relays = try fetchRequest.execute()
                let sp = SocketPool.shared
                
                // CONNECT TO RELAYS
                for relay in relays {
                    _ = sp.addSocket(relayId: relay.objectID, url: relay.url!, read:relay.read, write: relay.write)
                }
            } catch {
                print("🔴🔴🔴 Fail in SocketPool.shared.setup(), \(error)")
            }
        }
    }
    
    func connectAll() {
        for socket in sockets {
            guard socket.value.read else { continue }
            if !socket.value.isConnecting && !socket.value.isConnected {
                socket.value.connect()
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
    
    func addSocket(relayId:NSManagedObjectID, url:String, read:Bool = true, write: Bool = false) -> NewManagedClient {
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
        if (sockets.keys.contains(relayId)) {
            sockets.removeValue(forKey: relayId)
        }
    }
    
    func sendMessage(_ message:ClientMessage, subscriptionId:String? = nil) {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            print("Canvas.sendMessage: \(message.type) \(message.message)")
            return
        }
        if (message.type == .REQ) {
            let read = sockets.values.filter { $0.read == true }.count
            if read > 0 && subscriptionId == nil {
                print("⬇️⬇️ REQ ON \(read) RELAYS: \(String(message.message.prefix(260)))")
            }
            //            print("⬇️⬇️ REQ ON \(read) RELAYS: \(String(message.message))")
        }
        
        Task(priority: .utility) { [unowned self] in
            for (_, managedClient) in self.sockets {
                //                print("active subscriptions \(managedClient.url): \(managedClient.activeSubscriptions.count)")
                guard managedClient.read || managedClient.write else {
                    // Skip if relay is not selected for reading or writing events
                    continue
                }
                
                if message.type == .REQ && managedClient.read { // REQ FOR ALL READ RELAYS
                    if (!managedClient.isConnected) {
                        if (!managedClient.isConnecting) {
                            managedClient.connect()
                        }
                        /// hmm don't continue with .sendMessage (or does it queue until connection??? not sure...)
                        continue
                    }
                    // skip if we already have an active subcription
                    if subscriptionId != nil && managedClient.activeSubscriptions.contains(subscriptionId!) { continue }
                    if (subscriptionId != nil) {
                        DispatchQueue.main.async {
                            managedClient.activeSubscriptions.append(subscriptionId!)
                            print("🏎️🏎️⬇️⬇️ ADDED SUBSCRIPTION  \(managedClient.url): \(subscriptionId!) - total subs: \(managedClient.activeSubscriptions.count)")
                        }
                    }
                    if subscriptionId != nil {
                        print(" ⬇️⬇️ REQUESTING: \(String(message.message.prefix(260)))")
                    }
//                    print("⬇️⬇️ REQUESTING: \(String(message.message))")
                    managedClient.client.sendMessage(message.message)
                }
                else if  message.type == .CLOSE { // CLOSE FOR ALL RELAYS
                    if (!managedClient.read) { continue }
                    if (!managedClient.isConnected) && (!managedClient.isConnecting) {
                        // Already closed? no need to connect and send CLOSE message
                        continue
                        //                        managedClient.connect()
                    }
                    //                    print("🔚🔚 CLOSE: \(String(message.message.prefix(260)))")
                    managedClient.client.sendMessage(message.message)
                }
                else if message.type == .EVENT && managedClient.write { // EVENT IS ONLY FOR WRITE RELAYS
                    if (!managedClient.isConnected) && (!managedClient.isConnecting) {
                        managedClient.connect()
                    }
                    print("🚀🚀🚀 PUBLISHING TO \(managedClient.url): \(message.message)")
                    managedClient.client.sendMessage(message.message)
                }
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
            guard socket.value.isConnected && socket.value.read else { continue }
            socket.value.activeSubscriptions.removeAll(where: { activeId in
                activeId == subscriptionId
            })
            let closeSubscription = ClientMessage(type: .CLOSE, message: ClientMessage.close(subscriptionId: subscriptionId))
            socket.value.client.sendMessage(closeSubscription.message)
        }
    }
}

class NewManagedClient: NSObject, URLSessionWebSocketDelegate, NewWebSocketDelegate, ObservableObject {
    
    var relayId:NSManagedObjectID
    var url:String
    var client:NewWebSocket
    var exponentialReconnectBackOff = 0
    var _skipped = 0
    
    private var connectionQueue = DispatchQueue(label: "com.nostur.connection")
    private var _isConnecting = false
    private var _activeSubscriptions:[String] = []
    
    var skipped: Int {
        get {
            return connectionQueue.sync {
                _skipped
            }
        }
        set {
            connectionQueue.async(flags: .barrier) {
                self._skipped = newValue
            }
        }
    }
    
    var isConnecting: Bool {
        get {
            return connectionQueue.sync {
                _isConnecting
            }
        }
        set {
            connectionQueue.async(flags: .barrier) {
                self._isConnecting = newValue
            }
        }
    }
    
    @Published var isConnected = false
    @Published var read = true
    @Published var write = false
    
    var activeSubscriptions:[String] {
        get {
            return connectionQueue.sync {
                _activeSubscriptions
            }
        }
        set {
            connectionQueue.async(flags: .barrier) {
                self._activeSubscriptions = newValue
            }
        }
    }
    
    init(relayId: NSManagedObjectID, url: String, client:NewWebSocket, read: Bool = true, write: Bool = false) {
        self.relayId = relayId
        self.url = url.lowercased()
        self.read = read
        self.write = write
        self.client = client
    }
    
    func connect(_ forceConnectionAttempt:Bool = false) {
        guard forceConnectionAttempt || self.skipped == self.exponentialReconnectBackOff else { // Should be 0 == 0 to continue, or 2 == 2 etc..
            self.skipped = skipped + 1
            print("🏎️🏎️🔌🔴 Skipping reconnect. \(self.url) EB: (\(exponentialReconnectBackOff)) skipped: \(skipped)")
            return
        }
        if !isConnecting {
            self.skipped = 0
            self.isConnecting = true
            self.client.connect()
        }
    }
    
    func disconnect() {
        DispatchQueue.main.async {
            self.isConnecting = false
            self.isConnected = false
        }
        self.client.disconnect()
    }
    
    func didDisconnect() {
        DispatchQueue.main.async {
            SocketPool.shared.objectWillChange.send()
            self.isConnecting = false
            self.isConnected = false
        }
        self.activeSubscriptions = []
        print("🏎️🏎️🔌 DISCONNECTED \(self.url)")
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
        self.exponentialReconnectBackOff = max(1, self.exponentialReconnectBackOff * 2)
        print("🏎️🏎️🔌🔴 DISCONNECTED WITH ERROR \(self.url): \(error.localizedDescription)")
        DispatchQueue.main.async {
            sendNotification(.socketNotification, "Disconnected: \(self.url)")
        }
    }
    
    func didReceiveMessage(_ text:String) {
//        print("🟠🟠🏎️🔌 RECEIVED: \(self.url): \(String(text.prefix(260)))")
        MessageParser.shared.socketReceivedMessage(text: text, relayUrl: self.url, client:client)
    }
    
    func didReceiveData(_ data:Data) {
        print("🔌 RECEIVED DATA \(self.url): \(data.count)")
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
        print("🏎️🏎️🔌 CONNECTED \(self.url)")
        LVMManager.shared.restoreSubscriptions()
        //                print("🔌 CONNECTED \(self.url): \(headers)")
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
        DispatchQueue.main.async {
            sendNotification(.socketNotification, "Disconnected: \(self.url)")
        }
        print("🏎️🏎️🔌 DISCONNECTED \(self.url): with code: \(closeCode.rawValue) \(String(describing: reason != nil ? String(data: reason!, encoding: .utf8) : "") )")
        
    }
}

protocol NewWebSocketDelegate: URLSessionWebSocketDelegate {
    func didReceiveData(_ data:Data)
    
    func didReceiveMessage(_ text:String)
    
    func didDisconnect()
    
    func didDisconnectWithError(_ error:Error)
}


class NewWebSocket {
    let url:String
    var socketQueue = OperationQueue()
    private var websocketQueue = DispatchQueue(label: "com.nostur.websocket")
    var webSocket_:WebSocket?
    var connection_:AnyCancellable?

    var delegate:NewWebSocketDelegate?
    
    var connection:AnyCancellable? {
        get {
            websocketQueue.sync {
                self.connection_
            }
        }
        set {
            websocketQueue.async(flags: .barrier) {
                self.connection_ = newValue
            }
        }
    }
    
    
    var webSocket:WebSocket? {
        get {
            websocketQueue.sync {
                self.webSocket_
            }
        }
        set {
            websocketQueue.async(flags: .barrier) {
                self.webSocket_ = newValue
            }
        }
    }
    
    init(url:String) {
        self.url = url
        self.socketQueue.name = "nostur.socketqueue"
        self.socketQueue.qualityOfService = .utility
        self.socketQueue.maxConcurrentOperationCount = 1
        //        connect()
        //        startPinger()
    }
    
    func sendMessage(_ text:String) {
        guard let webSocket = webSocket else {
            print("🔴🔴 Not connected. Did not sendMessage \(self.url)")
            return
        }
//        print("🟠🟠🏎️🔌🔌 SEND \(self.url): \(text)")
        let _ = webSocket.send(text)
            .sink(receiveCompletion: {
                print($0)
                print("WHAT")
            }, receiveValue: {
                print($0)
                print("WHAT OK")
            } )
    }
    
    func connect() {
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: socketQueue)
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
                print("Removing ephemeral relay \(url)")
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
    
    func connect() {
        self.client.connect()
    }
    
    func disconnect() {
        self.client.disconnect()
    }
    
    func didDisconnect() {
        print("🏎️🏎️🔌 DISCONNECTED \(self.url)")
    }
    
    func didDisconnectWithError(_ error: Error) {
        DispatchQueue.main.async {
            let shortURL = URL(string: self.url)?.baseURL?.description ?? self.url
            sendNotification(.socketNotification, "Error: \(shortURL) \(error.localizedDescription)")
        }
        print("🏎️🏎️🔌🔴 DISCONNECTED WITH ERROR \(self.url): \(error.localizedDescription)")
    }
    
    func didReceiveMessage(_ text:String) {
        print("🔌 RECEIVED TEXT \(self.url): \(text)")
        MessageParser.shared.socketReceivedMessage(text: text, relayUrl: self.url, client:client)
    }
    
    func didReceiveData(_ data:Data) {
        print("🔌 RECEIVED DATA \(self.url): \(data.count)")
    }
    
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("🔌 CONNECTED \(self.url)")
    }
    
    
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("🏎️🏎️🔌 DISCONNECTED \(self.url): with code: \(closeCode.rawValue) \(String(describing: reason != nil ? String(data: reason!, encoding: .utf8) : "") )")
    }
}



func fetchEventFromRelayHint(_ eventId:String, fastTags:[(String, String, String?)]) {
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
