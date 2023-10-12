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
    public var poolQueue = DispatchQueue(label: "com.nostur.poolQueue", qos: .utility, attributes: .concurrent)
    
    var stayConnectedTimer:Timer?
    
    func setup(_ activeNWCconnectionId:String) {
        DataProvider.shared().viewContext.performAndWait {
            do {
                let fetchRequest: NSFetchRequest<Relay> = Relay.fetchRequest()
                let relays = try fetchRequest.execute()
                let sp = SocketPool.shared
                
                // CONNECT TO RELAYS
                for relay in relays {
                    _ = sp.addSocket(relayId: relay.objectID.uriRepresentation().absoluteString, url: relay.url!, read:relay.read, write: relay.write, excludedPubkeys: relay.excludedPubkeys)
                }
                // If we have NWC relays, connect to those too
                if !activeNWCconnectionId.isEmpty, let nwc = NWCConnection.fetchConnection(activeNWCconnectionId, context: DataProvider.shared().viewContext) {
                    _ = sp.addNWCSocket(connectionId:nwc.connectionId, url: nwc.relay)
                }
                
                self._afterConnect()
            } catch {
                L.sockets.error("🔴🔴🔴 Fail in SocketPool.shared.setup(), \(error)")
            }
        }
    }
    
    func connectAll() {
        shouldBeMain()
        for socket in sockets {
            guard socket.value.read else { continue }
            guard !socket.value.isConnected else { continue }
            socket.value.mcq.async(flags: .barrier) {
                socket.value.connect()
            }
        }
        stayConnectedTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true, block: { _ in
            self.stayConnectedPing()
        })
        self._afterConnect()
    }
    
    
    // Called 2.5 seconds after trying to connect
    public func afterConnect() {
        //        guard let account = NosturState.shared.account else { return }
        //        NosturState.shared.loadWoT(account)
    }
    
    // Called 5.0 seconds after trying to connect
    public func afterConnectLater() {
        
    }
    
    private func _afterConnect() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            self.afterConnect()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            self.afterConnectLater()
        }
    }
    
    // Connect to relays selected for globalish feed, reuse existing connections
    func connectFeedRelays(relays:Set<Relay>) {
        
        for relay in relays {
            guard let relayUrl = relay.url else { continue }
            guard socketByUrl(relayUrl) == nil else { continue }
            
            // Add connection socket if we don't already have it from our normal connections
            _ = SocketPool.shared.addSocket(relayId: relay.objectID.uriRepresentation().absoluteString, url: relayUrl, read:true, write: false, excludedPubkeys: relay.excludedPubkeys)
        }
        
        // .connect() to the given relays
        let relayUrls = relays.compactMap { $0.url }
        for socket in sockets {
            guard relayUrls.contains(socket.value.client.url) else { continue }
            if !socket.value.isConnected {
                socket.value.connect()
            }
        }
    }
    
    private func stayConnectedPing() {
        for socket in sockets {
            guard socket.value.read else { continue }
            guard !socket.value.isNWC else { continue }
            guard !socket.value.isNC else { continue }
            
            socket.value.mcq.async(flags: .barrier) {
                if let lastReceivedMessageAt = socket.value._lastMessageReceivedAt {
                    if Date.now.timeIntervalSince(lastReceivedMessageAt) >= 45 {
                        L.sockets.info("\(socket.value.url) Last message older that 45 seconds, sending ping")
                        socket.value.client.ping()
                    }
                }
                else {
                    L.sockets.info("\(socket.value.url) Last message = nil. (re)connecting..")
                    socket.value.connect()
                }
            }
        }
    }
    
    var anyConnected:Bool {
        sockets.contains(where: { $0.value.isConnected })
    }
    
    func disconnectAll() {
        stayConnectedTimer?.invalidate()
        stayConnectedTimer = nil
        
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
    
    func addSocket(relayId:String, url:String, read:Bool = true, write: Bool = false, excludedPubkeys:Set<String> = []) -> NewManagedClient {
        if (!sockets.keys.contains(relayId)) {
            let urlURL:URL = URL(string: url) ?? URL(string:"wss://localhost:123456/invalid_relay_url")!
            var request = URLRequest(url: urlURL)
            //             request.setValue(["wamp"].joined(separator: ","), forHTTPHeaderField: "Sec-WebSocket-Protocol")
            
            request.timeoutInterval = 15
            
            let client = NewWebSocket(url: url)
            let managedClient = NewManagedClient(relayId: relayId, url: url, client:client, read: read, write: write, excludedPubkeys: excludedPubkeys)
            
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
    
    func sendMessage(_ message:ClientMessage, subscriptionId:String? = nil, relays:Set<Relay> = [], accountPubkey:String? = nil) {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            print("Canvas.sendMessage: \(message.type) \(message.message)")
            return
        }
        if (message.type == .REQ) {
            let read = !relays.isEmpty ? relays.count : sockets.values.filter { $0.read == true }.count
            if read > 0 && subscriptionId == nil { L.sockets.info("⬇️⬇️ REQ \(subscriptionId) ON \(read) RELAYS: \(message.message)") }
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
                                L.og.info("⚡️ sendMessage \(subscriptionId): not connected yet, connecting to N(W)C relay \(managedClient.url)")
                                managedClient.connect()
                            }
                        }
                        // For NWC we just replace active subscriptions, else doesn't work
                        L.sockets.debug("⬇️⬇️ REQUESTING \(subscriptionId): \(message.message)")
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
                        if let accountPubkey = accountPubkey, managedClient.excludedPubkeys.contains(accountPubkey) {
                            L.sockets.info("sendMessage: \(accountPubkey) excluded from \(managedClient.url) - not publishing here isNC:\(managedClient.isNC.description) - isNWC: \(managedClient.isNWC.description)")
                            continue
                        }
                        if (!managedClient.isConnected) && (!managedClient.isConnecting) {
                            managedClient.connect()
                        }
                        L.sockets.info("🚀🚀🚀 PUBLISHING TO \(managedClient.url): \(message.message)")
                        managedClient.client.sendMessage(message.message)
                    }
                }
                
                else {
                    //                    L.og.debug("\(managedClient.url) - activeSubscriptions: \(managedClient.activeSubscriptions.joined(separator: " "))")
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
                        if subscriptionId != nil && managedClient.getActiveSubscriptions().contains(subscriptionId!) { continue }
                        if (subscriptionId != nil) {
                            managedClient.mcq.async(flags: .barrier) {
                                managedClient._activeSubscriptions.append(subscriptionId!)
                                L.sockets.info("⬇️⬇️ ADDED SUBSCRIPTION  \(managedClient.url): \(subscriptionId!) - total subs: \(managedClient._activeSubscriptions.count) onlyForNWC: \(message.onlyForNWCRelay) .isNWC: \(managedClient.isNWC) - onlyForNC: \(message.onlyForNCRelay) .isNC: \(managedClient.isNC)")
                            }
                        }
                        L.sockets.debug("⬇️⬇️ REQUESTING \(subscriptionId): \(message.message)")
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
                        if let accountPubkey = accountPubkey, managedClient.excludedPubkeys.contains(accountPubkey) {
                            L.sockets.info("sendMessage: \(accountPubkey) excluded from \(managedClient.url) - not publishing here isNC:\(managedClient.isNC.description) - isNWC: \(managedClient.isNWC.description) ")
                            continue
                        }
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
    
    func sendMessageAfterPing(_ message:ClientMessage, subscriptionId:String? = nil, relays:Set<Relay> = [], accountPubkey:String? = nil) {
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
                                L.og.info("⚡️ sendMessage \(subscriptionId): not connected yet, connecting to N(W)C relay \(managedClient.url)")
                                managedClient.connect()
                            }
                        }
                        // skip if we already have an active subcription
                        if subscriptionId != nil && managedClient.getActiveSubscriptions().contains(subscriptionId!) { continue }
                        if (subscriptionId != nil) {
                            managedClient.mcq.async {
                                managedClient._activeSubscriptions.append(subscriptionId!)
                                L.sockets.info("⬇️⬇️ ADDED SUBSCRIPTION  \(managedClient.url): \(subscriptionId!) - total subs: \(managedClient._activeSubscriptions.count) onlyForNWC: \(message.onlyForNWCRelay) .isNWC: \(managedClient.isNWC) -- onlyForNC: \(message.onlyForNCRelay) .isNC: \(managedClient.isNC)")
                            }
                        }
                        L.sockets.debug("⬇️⬇️ REQUESTING \(subscriptionId): \(message.message)")
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
                        if let accountPubkey = accountPubkey, managedClient.excludedPubkeys.contains(accountPubkey) {
                            L.sockets.info("sendMessage: \(accountPubkey) excluded from \(managedClient.url) - not publishing here isNC:\(managedClient.isNC.description) - isNWC: \(managedClient.isNWC.description) ")
                            continue
                        }
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
                        if subscriptionId != nil && managedClient.getActiveSubscriptions().contains(subscriptionId!) { continue }
                        if (subscriptionId != nil) {
                            managedClient.mcq.async(flags: .barrier) {
                                managedClient._activeSubscriptions.append(subscriptionId!)
                                L.sockets.info("⬇️⬇️ ADDED SUBSCRIPTION  \(managedClient.url): \(subscriptionId!) - total subs: \(managedClient._activeSubscriptions.count) onlyForNWC: \(message.onlyForNWCRelay) .isNWC: \(managedClient.isNWC) -- onlyForNWC: \(message.onlyForNCRelay) .isNWC: \(managedClient.isNC)")
                            }
                        }
                        L.sockets.debug("⬇️⬇️ REQUESTING \(subscriptionId): \(String(message.message))")
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
                        if let accountPubkey = accountPubkey, managedClient.excludedPubkeys.contains(accountPubkey) {
                            L.sockets.info("sendMessage: \(accountPubkey) excluded from \(managedClient.url) - not publishing here isNC:\(managedClient.isNC.description) - isNWC: \(managedClient.isNWC.description) ")
                            continue
                        }
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
            socket.value.mcq.async(flags: .barrier) {
                socket.value._activeSubscriptions.removeAll { subscriptionId in
                    subscriptionId == "Following" || subscriptionId == "Notifications"
                }
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
            socket.value.mcq.async(flags: .barrier) {
                socket.value._activeSubscriptions.removeAll { subscriptionId in
                    subscriptionId == "Following"
                }
            }
        }
    }
    
    func closeSubscription(_ subscriptionId:String) {
        for socket in sockets {
            guard socket.value.isConnected else { continue }
            
            if socket.value.getActiveSubscriptions().contains(subscriptionId) {
                let closeSubscription = ClientMessage(type: .CLOSE, message: ClientMessage.close(subscriptionId: subscriptionId))
                socket.value.client.sendMessage(closeSubscription.message)
            }
            
            socket.value.mcq.async(flags: .barrier) {
                socket.value._activeSubscriptions.removeAll(where: { activeId in
                    activeId == subscriptionId
                })
            }
        }
    }
}

class NewManagedClient: NSObject, URLSessionWebSocketDelegate, NewWebSocketDelegate, ObservableObject {
    
    var relayId:String
    var url:String
    var isNWC:Bool
    var isNC:Bool
    var client:NewWebSocket
    
    // Managed Client Queue
    public var mcq = DispatchQueue(label: "com.nostur.managed-client", qos: .utility, attributes: .concurrent)
    
    private var _skipped = 0
    public func getSkipped() async -> Int {
        await withCheckedContinuation { continuation in
            mcq.async { continuation.resume(returning: self._skipped) }
        }
    }
    public func setSkipped(_ skipped:Int) {
        mcq.async(flags: .barrier) { self._skipped = skipped }
    }
    
    
    private var _exponentialReconnectBackOff = 0
    public func getExponentialBackoff() async -> Int {
        await withCheckedContinuation { continuation in
            mcq.async { continuation.resume(returning: self._skipped) }
        }
    }
    public func setExponentialBackoff(_ exponentialReconnectBackOff:Int) {
        mcq.async(flags: .barrier) { self._exponentialReconnectBackOff = exponentialReconnectBackOff }
    }
    
    
    public var isConnecting = false // mcq
    
    public var _activeSubscriptions:[String] = []
    public func getActiveSubscriptions() -> [String] {
        mcq.sync { self._activeSubscriptions }
    }
    public func setActiveSubscriptions(_ activeSubscriptions:[String] ) {
        mcq.async(flags: .barrier) { self._activeSubscriptions = activeSubscriptions }
    }
    
    public var _lastMessageReceivedAt:Date? = nil
    public func getLastMessageReceivedAt() async -> Date? {
        await withCheckedContinuation { continuation in
            mcq.async { continuation.resume(returning: self._lastMessageReceivedAt) }
        }
    }
    public func setLastMessageReceivedAt(_ date:Date? = nil) {
        mcq.async(flags: .barrier) { self._lastMessageReceivedAt = date }
    }
    
    @Published var isConnected = false
    @Published var read = true
    @Published var write = false
    
    var excludedPubkeys:Set<String>
    
    init(relayId: String, url: String, client:NewWebSocket, read: Bool = true, write: Bool = false, isNWC:Bool = false, isNC:Bool = false, excludedPubkeys:Set<String> = []) {
        self.relayId = relayId
        self.url = url.lowercased()
        self.read = read
        self.write = write
        self.client = client
        self.isNWC = isNWC
        self.isNC = isNC
        self.excludedPubkeys = excludedPubkeys
    }
    
    func didReceivePong() {
        self.setLastMessageReceivedAt(.now)
    }
    
    func connect(_ forceConnectionAttempt:Bool = false) {
        mcq.async(flags: .barrier) {
            self._activeSubscriptions = []
            guard !self.isConnecting else { return }
            guard self._exponentialReconnectBackOff > 512 || self._exponentialReconnectBackOff == 1 || forceConnectionAttempt || self._skipped == self._exponentialReconnectBackOff else { // Should be 0 == 0 to continue, or 2 == 2 etc..
                self._skipped = self._skipped + 1
                L.sockets.info("🏎️🏎️🔌 Skipping reconnect. \(self.url) EB: (\(self._exponentialReconnectBackOff)) skipped: \(self._skipped)")
                return
            }
            self._skipped = 0
            self.isConnecting = true
            DispatchQueue.main.async {
                self.client.connect()
            }
            
            if self._exponentialReconnectBackOff >= 512 {
                self._exponentialReconnectBackOff = 512
            }
            else {
                self._exponentialReconnectBackOff = max(1, self._exponentialReconnectBackOff * 2)
            }
        }
    }
    
    func disconnect() {
        mcq.async(flags: .barrier) {
            self.isConnecting = false
            self._activeSubscriptions = []
            self._lastMessageReceivedAt = nil
        }
        DispatchQueue.main.async {
            self.isConnected = false
            self.client.disconnect()
        }
    }
    
    func didDisconnect() {
        mcq.async(flags: .barrier) {
            self.isConnecting = false
            self._activeSubscriptions = []
            self._lastMessageReceivedAt = nil
        }
        DispatchQueue.main.async {
            self.isConnected = false
            sendNotification(.socketNotification, "Disconnected: \(self.url)")
        }
        L.sockets.info("🏎️🏎️🔌 DISCONNECTED \(self.url)")
    }
    
    func didDisconnectWithError(_ error: Error) {
        mcq.async(flags: .barrier) {
            self.isConnecting = false
            self._activeSubscriptions = []
            self._lastMessageReceivedAt = nil
            if self._exponentialReconnectBackOff >= 512 {
                self._exponentialReconnectBackOff = 512
            }
            else {
                self._exponentialReconnectBackOff = max(1, self._exponentialReconnectBackOff * 2)
            }
        }
        let shortURL = URL(string: self.url)?.baseURL?.description ?? self.url
        DispatchQueue.main.async {
            self.isConnected = false
            sendNotification(.socketNotification, "Error: \(shortURL) \(error.localizedDescription)")
        }
        L.sockets.info("🏎️🏎️🔌🔴🔴 DISCONNECTED WITH ERROR \(self.url): \(error.localizedDescription)")
    }
    
    func didReceiveMessage(_ text:String) {
        L.sockets.debug("🟠🟠🏎️🔌 RECEIVED: \(self.url): \(text)")
        MessageParser.shared.socketReceivedMessage(text: text, relayUrl: self.url, client:client)
        self.setLastMessageReceivedAt(.now)
    }
    
    func didReceiveData(_ data:Data) {
        self.setLastMessageReceivedAt(.now)
        L.sockets.info("🔌 RECEIVED DATA \(self.url): \(data.count)")
    }
    
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        mcq.async(flags: .barrier) {
            self.isConnecting = false
            self._activeSubscriptions = []
            self._exponentialReconnectBackOff = 0
            self._skipped = 0
            self._lastMessageReceivedAt = .now
        }
        DispatchQueue.main.async {
            self.isConnected = true
            sendNotification(.socketConnected, "Connected: \(self.url)")
        }
        
        L.sockets.info("🏎️🏎️🔌 CONNECTED \(self.url)")
        LVMManager.shared.restoreSubscriptions()
    }
    
    
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        mcq.async(flags: .barrier) {
            self.isConnecting = false
            self._activeSubscriptions = []
            self._exponentialReconnectBackOff = 0
            self._skipped = 0
            self._lastMessageReceivedAt = .now
        }
        DispatchQueue.main.async {
            self.isConnected = false
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

struct SocketMessage {
    let id = UUID()
    let text:String
}


class NewWebSocket {
    let url:String
    private var outQueue:[SocketMessage] = []
    private var wsq:DispatchQueue
    
    var delegate:NewWebSocketDelegate? {
        didSet {
            self.session = URLSession(configuration: .default, delegate: self.delegate, delegateQueue: nil)
        }
    }
    
    var subscriptions = Set<AnyCancellable>()
    var connection:AnyCancellable?
    var pinger:AnyCancellable?
        
    var webSocket:WebSocket?
    var session:URLSession?
    
    init(url:String) {
        self.url = url
        self.wsq = DispatchQueue(label: self.url, qos: .utility)
    }
    
    public func connect(andSend:String? = nil) {
        wsq.async { [weak self] in
            guard let self = self else { return }
            guard let session = session else { return }
            guard let urlURL = URL(string: url) else { return }
            let urlRequest = URLRequest(url: urlURL)
            
            if let andSend = andSend {
                self.outQueue.append(SocketMessage(text: andSend))
            }
            
            // Create the WebSocket instance. This is the entry-point for sending and receiving messages
            webSocket = session.webSocket(with: urlRequest)
            
            guard let webSocket = webSocket else { return }
            
            // Subscribe to the WebSocket. This will connect to the remote server and start listening
            // for messages (URLSessionWebSocketTask.Message).
            // URLSessionWebSocketTask.Message is an enum for either Data or String
            self.connection = webSocket.publisher
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
                        L.og.debug("dunno")
                    }
                })
            
            guard !outQueue.isEmpty else { return }
            for out in outQueue {
                webSocket.send(out.text)
                    .subscribe(Subscribers.Sink(
                        receiveCompletion: { completion in
                            switch completion {
                            case .finished:
                                self.wsq.async {
                                    self.outQueue.removeAll(where: { $0.id == out.id })
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
    
    func sendMessageAfterPing(_ text:String) {
        L.sockets.info("🟪 sendMessageAfterPing  \(text)")
        wsq.async { [weak self] in
            guard let self = self else { return }
            guard let webSocket = self.webSocket else {
                L.sockets.info("🟪🔴🔴 Not connected.  \(self.url)")
                return
            }
            let socketMessage = SocketMessage(text: text)
            outQueue.append(socketMessage)
            
            webSocket.ping()
                .subscribe(Subscribers.Sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .failure(let error):
                            // Handle the failure case
                            #if DEBUG
                            let _url = self.url
                            let _error = error
                            L.sockets.info("🟪 \(_url) Ping Failure: \(_error), trying to reconnect")
                            #endif
                            self.connect(andSend:text)
                        case .finished:
                            // The ping completed successfully
                            L.sockets.info("🟪 Ping succeeded on \(self.url). Sending \(text)")
                            L.sockets.debug("🟠🟠🏎️🔌🔌 SEND \(self.url): \(text)")
                            webSocket.send(text)
                                .subscribe(Subscribers.Sink(
                                    receiveCompletion: { completion in
                                        switch completion {
                                        case .finished:
                                            self.wsq.async {
                                                self.outQueue.removeAll(where: { $0.id == socketMessage.id })
                                            }
                                        case .failure(let error):
                                            L.og.error("🟪🔴🔴 Error sending \(error): \(text)")
                                        }
                                    },
                                    receiveValue: { _ in }
                                ))
        //                    sendNotification(.pong)
                        }
                    },
                    receiveValue: { _ in }
                ))
        }
    }
    
    func ping() {
        L.sockets.info("Trying to ping: \(self.url)")
        wsq.async { [weak self] in
            guard let self = self else { return }
            guard let webSocket = self.webSocket else {
                L.sockets.info("🔴🔴 Not connected. ????? \(self.url)")
                return
            }

            webSocket.ping()
                .subscribe(Subscribers.Sink(
                    receiveCompletion: { completion in
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
        //                    sendNotification(.pong)
                        }
                    },
                    receiveValue: { _ in }
                ))
        }
    }
    
    func sendMessage(_ text:String) {
        wsq.async { [weak self] in
            guard let self = self else { return }
            guard let webSocket = webSocket else {
                L.sockets.info("🔴🔴 Not connected. Did not sendMessage \(self.url)")
                return
            }
            let socketMessage = SocketMessage(text: text)
            self.outQueue.append(socketMessage)
            L.sockets.debug("🟠🟠🏎️🔌🔌 SEND \(self.url): \(text)")
            webSocket.send(text)
                .subscribe(Subscribers.Sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            self.wsq.async {
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
    
    
    
    func disconnect() {
        wsq.async { [weak self] in
            guard self?.webSocket != nil else { return }
            // You can stop the WebSocket subscription, disconnecting from remote server.
            //        pinger?.cancel()
            //        pingOnceSub?.cancel()
            self?.connection?.cancel()
        }
    }
}




final class EphemeralSocketPool: ObservableObject {
    
    static let shared = EphemeralSocketPool()
    
    private var sockets:[String : NewEphemeralClient] = [:]
    
    func addSocket(url:String) -> NewEphemeralClient {
        let urlLower = url.lowercased()
        removeAfterDelay(urlLower)
        
        if let socket = sockets[urlLower] {
            return socket
        }
        else {
            let urlURL:URL = URL(string: urlLower) ?? URL(string:"wss://localhost:123456/invalid_relay_url")!
            var request = URLRequest(url: urlURL)
            request.timeoutInterval = 15
            
            let client = NewWebSocket(url: url)
            
            let managedClient = NewEphemeralClient(url: urlLower, client: client)
            
            client.delegate = managedClient
            
            managedClient.connect()
            sockets[urlLower] = managedClient // TODO: Fix datarace: Swift access race in Nostur.EphemeralSocketPool.addSocket(url: Swift.String) -> Nostur.NewEphemeralClient at 0x146c1ae60
            return managedClient
        }
    }
    
    private func removeAfterDelay(_ url:String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(60)) { [weak self] in
            if let socket = self?.sockets.first(where: { (key: String, value: NewEphemeralClient) in
                key == url
            }) {
                L.sockets.info("Removing ephemeral relay \(url)")
                socket.value.disconnect()
                if (self?.sockets.keys.contains(url) ?? false) {
                    self?.sockets.removeValue(forKey: url)
                }
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
        let shortURL = URL(string: self.url)?.baseURL?.description ?? self.url
        DispatchQueue.main.async {
            sendNotification(.socketNotification, "Error: \(shortURL) \(error.localizedDescription)")
        }
        L.sockets.info("🏎️🏎️🔌🔴🔴 DISCONNECTED WITH ERROR \(self.url): \(error.localizedDescription)")
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
