//
//  ConnectionPool.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/11/2023.
//

import Foundation
import Combine
//import CombineWebSocket
import CoreData

public typealias CanonicalRelayUrl = String // lowercased, without trailing slash on root domain

public class ConnectionPool: ObservableObject {
    static public let shared = ConnectionPool()
    public var queue = DispatchQueue(label: "connection-pool", qos: .utility, attributes: .concurrent)
    
    // .connections should be read/mutated from main context
    public var connections:[CanonicalRelayUrl: RelayConnection] = [:]
    
    // .ephemeralConnections should be read/mutated from main context
    private var ephemeralConnections:[CanonicalRelayUrl: RelayConnection] = [:]
    
    public var anyConnected:Bool {
        connections.contains(where: { $0.value.isConnected })
    }
    
    private var stayConnectedTimer: Timer?
    
    @MainActor
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
    
    @MainActor
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
    
    @MainActor
    public func addNWCConnection(connectionId:String, url:String) -> RelayConnection  {
        if let existingConnection = connections[connectionId] {
            return existingConnection
        }
        else {
            let relayData = RelayData.new(url: url, read: true, write: true, search: false, excludedPubkeys: [])
            let newConnection = RelayConnection(relayData, isNWC: true, queue: queue)
            connections[connectionId] = newConnection
            return newConnection
        }
    }
    
    @MainActor
    public func addNCConnection(connectionId:String, url:String) -> RelayConnection {
        if let existingConnection = connections[connectionId] {
            return existingConnection
        }
        else {
            let relayData = RelayData.new(url: url, read: true, write: true, search: false, excludedPubkeys: [])
            let newConnection = RelayConnection(relayData, isNC: true, queue: queue)
            queue.async(flags: .barrier) { [weak self] in
                self?.connections[connectionId] = newConnection
            }
            return newConnection
        }
    }
    
    public func connectAll() {
        for (_, connection) in self.connections {
            queue.async {
                guard connection.relayData.shouldConnect else { return }
                guard !connection.isSocketConnected else { return }
                connection.connect()
            }
        }
        
        
        stayConnectedTimer?.invalidate()
        stayConnectedTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true, block: { [weak self] _ in
            if NetworkMonitor.shared.isConnected {
                if IS_CATALYST || !NRState.shared.appIsInBackground {
                    self?.stayConnectedPing()
                }
            }
        })
    }
    
    public func connectAllWrite() {
        for (_, connection) in self.connections {
            queue.async {
                guard connection.relayData.write else { return }
                guard !connection.isSocketConnected else { return }
                connection.connect()
            }
        }
        
        stayConnectedTimer?.invalidate()
        stayConnectedTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true, block: { [weak self] _ in
            self?.stayConnectedPing()
        })
    }
    
    private func stayConnectedPing() {
        for (_, connection) in self.connections {
            queue.async { [weak connection] in
                guard let connection, connection.relayData.shouldConnect else { return }
                guard !connection.isNWC else { return }
                guard !connection.isNC else { return }
                
                if let lastReceivedMessageAt = connection.lastMessageReceivedAt {
                    if Date.now.timeIntervalSince(lastReceivedMessageAt) >= 45 {
                        L.sockets.debug("PING: \(connection.url) Last message older that 45 seconds, sending ping")
                        connection.ping()
                    }
                }
                else {
                    L.sockets.debug("\(connection.url) Last message = nil. (re)connecting.. connection.isSocketConnecting: \(connection.isSocketConnecting) ")
                    connection.connect()
                }
            }
        }
    }
    
    // Connect to relays selected for globalish feed, reuse existing connections
    @MainActor 
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
            queue.async {
                if !connection.isConnected {
                    connection.connect()
                }
            }
        }
    }
    
    @MainActor
    func connectionByUrl(_ url:String) -> RelayConnection? {
        let relayConnection = connections.filter { relayId, relayConnection in
            relayConnection.url == url.lowercased()
        }.first?.value
        return relayConnection
    }
    
    // For view?
    @MainActor
    func isUrlConnected(_ url:String) -> Bool {
        let relayConnection = connections.filter { relayId, relayConnection in
            relayConnection.url == url.lowercased()
        }.first?.value
        guard relayConnection != nil else {
            return false
        }
        return relayConnection!.isConnected
    }
    
    @MainActor
    func removeConnection(_ relayId: String) {
        if let connection = connections[relayId] {
            connection.disconnect()
            connections.removeValue(forKey: relayId)
        }
    }
    
    @MainActor
    func disconnectAll() {
        L.og.debug("ConnectionPool.disconnectAll")
        stayConnectedTimer?.invalidate()
        stayConnectedTimer = nil
        
        for (_, connection) in connections {
            connection.disconnect()
        }
    }
    
    @MainActor
    func ping() {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            print("ping")
            return
        }
        
        for (_, connection) in connections {
            queue.async { [weak connection] in
                guard connection?.relayData.shouldConnect ?? false else { return }
                connection?.ping()
            }
        }
    }
    
    @MainActor
    func removeActiveAccountSubscriptions() {
        for (_, connection) in connections {
            let closeFollowing = ClientMessage(type: .CLOSE, message: ClientMessage.close(subscriptionId: "Following"), relayType: .READ)
            connection.sendMessage(closeFollowing.message)
            let closeNotifications = ClientMessage(type: .CLOSE, message: ClientMessage.close(subscriptionId: "Notifications"), relayType: .READ)
            connection.sendMessage(closeNotifications.message)
            
            queue.async { [weak self, weak connection] in
                guard let connection, let self else { return }
                if !connection.nreqSubscriptions.isDisjoint(with: Set(["Following", "Notifications"])) {
                    self.queue.async(flags: .barrier) { [weak connection] in
                        connection?.nreqSubscriptions.subtract(Set(["Following", "Notifications"]))
                    }
                }
            }
        }
    }
    
    @MainActor
    func allowNewFollowingSubscriptions() {
        // removes "Following" from the active subscriptions so when we try a new one when following keys has changed, it would be ignored because didn't pass !contains..
        for (_, connection) in self.connections {
            self.queue.async { [weak self, weak connection] in
                guard let connection else { return }
                if connection.nreqSubscriptions.contains("Following") {
                    self?.queue.async(flags: .barrier) { [weak connection] in
                        connection?.nreqSubscriptions.remove("Following")
                    }
                }
            }
        }
    }
    
    @MainActor
    func closeSubscription(_ subscriptionId:String) {
        queue.async { [weak self] in
            guard let self else { return }
            for (_, connection) in self.connections {
                guard connection.isSocketConnected else { continue }
                
                if connection.nreqSubscriptions.contains(subscriptionId) {
                    L.lvm.info("Closing subscriptions for .relays - subscriptionId: \(subscriptionId)");
                    let closeSubscription = ClientMessage(type: .CLOSE, message: ClientMessage.close(subscriptionId: subscriptionId), relayType: .READ)
                    connection.sendMessage(closeSubscription.message)
                    self.queue.async(flags: .barrier) { [weak connection] in
                        connection?.nreqSubscriptions.remove(subscriptionId)
                    }
                }
            }
        }
    }
    
    @MainActor
    private func removeAfterDelay(_ url:String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(35)) { [weak self] in
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
    
    
    func sendMessage(_ message:ClientMessage, subscriptionId:String? = nil, relays:Set<RelayData> = [], accountPubkey:String? = nil) {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            print("Canvas.sendMessage: \(message.type) \(message.message)")
            return
        }

        let limitToRelayIds = relays.map({ $0.id })
        
        queue.async { [weak self] in
            guard let self = self else { return }
            for (_, connection) in self.connections {
                if connection.isNWC || connection.isNC { // Logic for N(W)C relay is a bit different, no read/write difference
                    if connection.isNWC && !message.onlyForNWCRelay { continue }
                    if connection.isNC && !message.onlyForNCRelay { continue }
                    
                    if message.type == .REQ {
                        if (!connection.isSocketConnected) {
                            if (!connection.isSocketConnecting) {
                                L.og.debug("⚡️ sendMessage \(subscriptionId ?? ""): not connected yet, connecting to N(W)C relay \(connection.url)")
                                connection.connect()
                            }
                        }
                        // For NWC we just replace active subscriptions, else doesn't work
                        connection.sendMessage(message.message)
                    }
                    else if message.type == .CLOSE {
                        if (!connection.isSocketConnected) && (!connection.isSocketConnecting) {
                            continue
                        }
                        L.sockets.debug("🔚🔚 CLOSE: \(message.message)")
                        connection.sendMessage(message.message)
                    }
                    else if message.type == .EVENT {
                        
                        if message.relayType == .WRITE && !connection.relayData.write { continue }
//                        if message.relayType == .DM && !connection.relayData.shouldDM(for: message.accountPubkey) { continue } // TODO: THIS ONE NEEDS TO BE AT AUTH
                        
                        if let accountPubkey = accountPubkey, connection.relayData.excludedPubkeys.contains(accountPubkey) {
                            L.sockets.debug("sendMessage: \(accountPubkey) excluded from \(connection.url) - not publishing here isNC:\(connection.isNC.description) - isNWC: \(connection.isNWC.description)")
                            continue
                        }
                        if (!connection.isSocketConnected) && (!connection.isSocketConnecting) {
                            connection.connect()
                        }
                        L.sockets.debug("🚀🚀🚀 PUBLISHING TO \(connection.url): \(message.message)")
                        connection.sendMessage(message.message)
                    }
                }
                
                else {
                    if message.onlyForNWCRelay || message.onlyForNCRelay { continue }
                    guard limitToRelayIds.isEmpty || limitToRelayIds.contains(connection.url) else { continue }
                    
                    guard connection.relayData.read || connection.relayData.write || limitToRelayIds.contains(connection.url) else {
                        // Skip if relay is not selected for reading or writing events
                        continue
                    }
                    
                    if message.type == .REQ { // REQ FOR ALL READ RELAYS
                        
                        if message.relayType == .READ && !limitToRelayIds.contains(connection.url) && !connection.relayData.read { continue }
                        if message.relayType == .SEARCH && !connection.relayData.search { continue }
                        
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
                            self.queue.async(flags: .barrier) { [weak connection] in
                                connection?.nreqSubscriptions.insert(subscriptionId!)
                            }
                            L.sockets.info("⬇️⬇️ ADDED SUBSCRIPTION  \(connection.url): \(subscriptionId!) - total subs: \(connection.nreqSubscriptions.count) onlyForNWC: \(message.onlyForNWCRelay) .isNWC: \(connection.isNWC) - onlyForNC: \(message.onlyForNCRelay) .isNC: \(connection.isNC)")
                        }
                        connection.sendMessage(message.message)
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
                    else if message.type == .EVENT {
                        if message.relayType == .WRITE && !connection.relayData.write { continue }
                        
                        if let accountPubkey = accountPubkey, connection.relayData.excludedPubkeys.contains(accountPubkey) {
                            L.sockets.info("sendMessage: \(accountPubkey) excluded from \(connection.url) - not publishing here isNC:\(connection.isNC.description) - isNWC: \(connection.isNWC.description) ")
                            continue
                        }
                        if (!connection.isSocketConnected) && (!connection.isSocketConnecting) {
                            connection.connect()
                        }
                        L.sockets.info("🚀🚀🚀 PUBLISHING TO \(connection.url): \(message.message)")
                        connection.sendMessage(message.message)
                    }
                }
            }
        }
    }
    
    @MainActor
    func sendEphemeralMessage(_ message:String, relay:String) {
        let connection = addEphemeralConnection(RelayData.new(url: relay, read: true, write: false, search: true, excludedPubkeys: []))
        connection.connect(andSend: message)
    }
}

@MainActor func fetchEventFromRelayHint(_ eventId:String, fastTags:[(String, String, String?, String?)]) {
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




struct SocketMessage {
    let id = UUID()
    let text:String
}
