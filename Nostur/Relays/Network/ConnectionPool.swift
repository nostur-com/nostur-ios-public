//
//  ConnectionPool.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/11/2023.
//

import Foundation
import Combine
import CoreData
import NostrEssentials

// // When resolving outbox relays, don't use relays that are widely known to be special purpose relays, not meant for finding events to (eg blastr)
let SPECIAL_PURPOSE_RELAYS: Set<String> = [
    "wss://nostr.mutinywallet.com",
    "wss://filter.nostr.wine",
    "wss://purplepag.es"
]

// Popular relays that are widely known, we can keep a list and choose to avoid these relays when finding content using Enhanced Relay Routing
// The skipTopRelays param of createRequestPlan() probably gives the same result so we might not need this
let POPULAR_RELAYS: Set<String> = [
    "wss://nos.lol",
    "wss://nostr.wine",
    "wss://relay.damus.io",
    "wss://relay.primal.net",
    "wss://relay.nostr.band"
]

public typealias CanonicalRelayUrl = String // lowercased, without trailing slash on root domain

public class ConnectionPool: ObservableObject {
    static public let shared = ConnectionPool()
    public var queue = DispatchQueue(label: "connection-pool", qos: .utility, attributes: .concurrent)
    
    // .connections should be read/mutated from connection context
    public var connections: [CanonicalRelayUrl: RelayConnection] = [:]
    
    // .ephemeralConnections should be read/mutated from main context
    private var ephemeralConnections: [CanonicalRelayUrl: RelayConnection] = [:]
    
    // .outboxConnections should be read/mutated from connection context
    private var outboxConnections: [CanonicalRelayUrl: RelayConnection] = [:]
    
    // for relays that always have zero (re)connected + 3 or more errors (TODO: need to finetune and better guess/retry)
    public var penaltybox: Set<CanonicalRelayUrl> = [] {
        didSet {
            self.reloadPreferredRelays()
        }
    }
    
    // .connectionStats should only be accessed from connection ConnectionPool.queue
    public var connectionStats: [CanonicalRelayUrl: RelayConnectionStats] = [:]
        
    @MainActor
    public var anyConnected: Bool = false
    
    public func updateAnyConnected() {
        queue.async { [unowned self] in
            let relayConnections = self.connections.values
            Task { @MainActor in
                if relayConnections.contains(where: { $0.isConnected }) {
                    if !self.anyConnected {
                        self.objectWillChange.send()
                        self.anyConnected = true
                    }
                }
                else if self.anyConnected {
                    self.objectWillChange.send()
                    self.anyConnected = false
                    
                    for connection in relayConnections {
                        self.queue.async { 
                            connection.resetExponentialBackOff()
                        }
                    }
                }
            }
        }
    }
    
    public var connectedCount: Int {
        connections.filter({ $0.value.isConnected }).count
    }
    
    public var ephemeralConnectedCount: Int {
        ephemeralConnections.filter({ $0.value.isConnected }).count
    }
    
    private var stayConnectedTimer: Timer?
    
    public func getConnection(_ id: String) async -> RelayConnection? {
        return await withCheckedContinuation { [unowned self] continuation in
            self.queue.async {
                if let existingConnection = self.connections[normalizeRelayUrl(id)] {
                    continuation.resume(returning: existingConnection)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    public func addConnection(_ relayData: RelayData, completion: ((RelayConnection) -> Void )? = nil) {
        let newConnection = RelayConnection(relayData, queue: queue)
        self.queue.async(flags: .barrier) { [unowned self] in
            if let conn = self.connections[relayData.id] {
                completion?(conn)
            }
            else {
                self.connections[relayData.id] = newConnection
                completion?(newConnection)
            }
        }
    }
    
    @MainActor
    public func addEphemeralConnection(_ relayData: RelayData) -> RelayConnection {
        if let existingConnection = ephemeralConnections[relayData.id] {
            L.og.debug("addEphemeralConnection: reusing existing \(relayData.id)")
            return existingConnection
        }
        else {
            let newConnection = RelayConnection(relayData, queue: queue)
            ephemeralConnections[relayData.id] = newConnection
            removeAfterDelay(relayData.id)
            L.og.debug("addEphemeralConnection: adding new connection \(relayData.id)")
            return newConnection
        }
    }
    
    // Same as addConnection() but should use from connection queue, not @MainActor
    public func addOutboxConnection(_ relayData: RelayData, completion: ((RelayConnection) -> Void )? = nil) {
        let newConnection = RelayConnection(relayData, isOutbox: true, queue: queue)
        self.queue.async(flags: .barrier) { [unowned self] in
            if let conn = self.outboxConnections[relayData.id] {
                if relayData.read && !conn.relayData.read {
                    conn.relayData.setRead(true)
                }
                if relayData.write && !conn.relayData.write {
                    conn.relayData.setWrite(true)
                }
                completion?(conn)
            }
            else {
                self.outboxConnections[relayData.id] = newConnection
                completion?(newConnection)
            }
        }
    }
    
    private var ourRelaySet: Set<String> {
        return Set(connections.filter { $0.value.relayData.shouldConnect }.map { $0.key })
    }
    
    // call from bg
    public func canPutInPenaltyBox(_ relayUrl: String) -> Bool {
        return !ourRelaySet.contains(relayUrl)
    }
    
    public func addNWCConnection(connectionId: String, url: String, completion: ((RelayConnection) -> Void )? = nil) {
        let relayData = RelayData.new(url: url, read: true, write: true, search: false, auth: false, excludedPubkeys: [])
        let newConnection = RelayConnection(relayData, isNWC: true, queue: queue)
        self.queue.async(flags: .barrier) { [unowned self] in
            if let conn = self.connections[connectionId] {
                completion?(conn)
            }
            else {
                self.connections[connectionId] = newConnection
                completion?(newConnection)
            }
        }
    }
    
    public func addNCConnection(connectionId: String, url: String, completion: ((RelayConnection) -> Void )? = nil) {
        let relayData = RelayData.new(url: url, read: true, write: true, search: false, auth: false, excludedPubkeys: [])
        let newConnection = RelayConnection(relayData, isNC: true, queue: queue)
        self.queue.async(flags: .barrier) { [unowned self] in
            if let conn = self.connections[connectionId] {
                completion?(conn)
            }
            else {
                self.connections[connectionId] = newConnection
                completion?(newConnection)
            }
        }
    }
    
    public func connectAll(resetExpBackOff: Bool = false) {
        #if DEBUG
        L.og.debug("ConnectionPool.shared.connectAll()")
        #endif
        
        queue.async { [unowned self] in
            for (_, connection) in self.connections {
                if (connection.isConnected) { continue }
                guard connection.relayData.shouldConnect else { return }
                guard !connection.isSocketConnected else { return }
                guard !connection.isSocketConnecting else { return }
                if resetExpBackOff {
                    connection.resetExponentialBackOff()
                }
                connection.connect()
            }
        }
        
        stayConnectedTimer?.invalidate()
        stayConnectedTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true, block: { [weak self] _ in
            if NetworkMonitor.shared.isConnected {
                if IS_CATALYST || !AppState.shared.appIsInBackground {
                    self?.stayConnectedPing()
                }
            }
        })
    }
    
    public func connectAllWrite() {
        queue.async { [unowned self] in
            for (_, connection) in self.connections {
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
        queue.async { [unowned self] in
            for (_, connection) in self.connections {
                guard connection.isConnected else { return }
                
                if let lastReceivedMessageAt = connection.lastMessageReceivedAt {
                    if Date.now.timeIntervalSince(lastReceivedMessageAt) >= 45 {
#if DEBUG
                        L.sockets.debug("PING: \(connection.url) Last message older that 45 seconds, sending ping -[LOG]-")
#endif
                        connection.ping()
                    }
                }
                else {
#if DEBUG
                    L.sockets.debug("\(connection.url) Last message = nil. (re)connecting.. connection.isSocketConnecting: \(connection.isSocketConnecting) ")
#endif
                    connection.connect()
                }
            }
        }
    }
    
    // Connect to relays selected for globalish feed, reuse existing connections
    @MainActor 
    func connectFeedRelays(relays: Set<RelayData>) {
        queue.async { [unowned self] in
            let existingConnections: Set<String> = Set(self.connections.keys)
        
            for relay in relays {
                guard !relay.url.isEmpty else { continue }
                
                if !existingConnections.contains(relay.id) {
                    // Add connection socket if we don't already have it from our normal connections
                    self.addConnection(relay) { newConnection in
                        newConnection.connect()
                    }
                }
                else {
                    if let existingConn = self.connections[relay.id], !existingConn.isConnected {
                        existingConn.connect()
                    }
                }
            }
        }
    }
    
    func removeConnection(_ relayId: String) {
        queue.async(flags: .barrier) { [unowned self] in
            if let connection = self.connections[relayId] {
                connection.disconnect()
                self.connections.removeValue(forKey: relayId)
            }
        }
    }
    
    func removeOutboxConnection(_ relayId: String) {
        queue.async(flags: .barrier) {
            if let connection = self.outboxConnections[relayId] {
                connection.disconnect()
                self.outboxConnections.removeValue(forKey: relayId)
            }
        }
    }
    
    @MainActor
    func disconnectAll() {
        L.og.debug("ConnectionPool.disconnectAll")
        stayConnectedTimer?.invalidate()
        stayConnectedTimer = nil
     
        queue.async { [unowned self] in
            for (_, connection) in self.connections {
                connection.disconnect()
            }
        }
    }
    
    @MainActor
    func disconnectAllAdditional() {
        L.og.debug("ConnectionPool.disconnectAllAdditional")
        
        queue.async {
            for (_, connection) in self.outboxConnections {
                connection.disconnect()
            }
        }
        
        for (_, connection) in ephemeralConnections {
            connection.disconnect()
        }
    }
    
    @MainActor
    func removeActiveAccountSubscriptions() {
        queue.async(flags: .barrier) { [unowned self] in
            for (_, connection) in connections {
                let subscriptionsToRemove: Set<String> = connection.nreqSubscriptions.filter({ sub in
                    return sub.starts(with: "Following-") || sub.starts(with: "List-") || sub.starts(with: "Notifications")
                })
                
                for sub in subscriptionsToRemove {
                    let closeFollowing = ClientMessage(type: .CLOSE, message: ClientMessage.close(subscriptionId: sub), relayType: .READ)
                    connection.sendMessage(closeFollowing.message)
                }
                connection.nreqSubscriptions.subtract(subscriptionsToRemove)
            }
            
            for (_, connection) in outboxConnections {
                let subscriptionsToRemove: Set<String> = connection.nreqSubscriptions.filter({ sub in
                    return sub.starts(with: "Following-") || sub.starts(with: "List-") || sub.starts(with: "Notifications")
                })
                
                for sub in subscriptionsToRemove {
                    let closeFollowing = ClientMessage(type: .CLOSE, message: ClientMessage.close(subscriptionId: sub), relayType: .READ)
                    connection.sendMessage(closeFollowing.message)
                }
                connection.nreqSubscriptions.subtract(subscriptionsToRemove)
            }
        }
    }
    
    @MainActor
    func allowNewFollowingSubscriptions() {
        // removes "Following" from the active subscriptions so when we try a new one when following keys has changed, it would be ignored because didn't pass !contains..
        queue.async(flags: .barrier) { [unowned self] in
            for (_, connection) in self.connections {
                let subscriptionsToRemove: Set<String> = connection.nreqSubscriptions.filter({ sub in
                    return sub.starts(with: "Following-")
                })
                connection.nreqSubscriptions.subtract(subscriptionsToRemove)
            }
            for (_, connection) in self.outboxConnections {
                let subscriptionsToRemove: Set<String> = connection.nreqSubscriptions.filter({ sub in
                    return sub.starts(with: "Following-")
                })
                connection.nreqSubscriptions.subtract(subscriptionsToRemove)
            }
        }
    }
    
    // TODO: NEED TO CHECK HOW WE HANDLE CLOSE PER CONNECTION WITH THE PREFERRED RELAYS....
    @MainActor
    func closeSubscription(_ subscriptionId: String) {
        queue.async(flags: .barrier) { [unowned self] in
            for (_, connection) in self.connections {
                if connection.nreqSubscriptions.contains(subscriptionId) {
                    L.lvm.info("Closing subscriptionId: \(subscriptionId) on \(connection.url)");
                    let closeSubscription = ClientMessage(type: .CLOSE, message: ClientMessage.close(subscriptionId: subscriptionId), relayType: .READ)
                    connection.sendMessage(closeSubscription.message)
                    connection.nreqSubscriptions.remove(subscriptionId)
                }
            }
            
            for (_, connection) in self.outboxConnections {
                if connection.nreqSubscriptions.contains(subscriptionId) {
                    L.lvm.info("Closing subscriptionId: \(subscriptionId) on outbox relay \(connection.url)");
                    let closeSubscription = ClientMessage(type: .CLOSE, message: ClientMessage.close(subscriptionId: subscriptionId), relayType: .READ)
                    connection.sendMessage(closeSubscription.message)
                    connection.nreqSubscriptions.remove(subscriptionId)
                }
            }
        }
    }
    
    @MainActor
    private func removeAfterDelay(_ url: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(35)) { [weak self] in
            if let (_ ,connection) = self?.ephemeralConnections.first(where: { (key: String, value: RelayConnection) in
                key == url
            }) {
                L.sockets.info("Removing ephemeral relay \(url)")
                connection.disconnect()
                if (self?.ephemeralConnections.keys.contains(url) ?? false) {
                    self?.ephemeralConnections.removeValue(forKey: url)
                }
            }
        }
    }
    
    // Can use from any context (will switch to connection queue)
    func sendMessage(_ message: NosturClientMessage, subscriptionId: String? = nil, relays: Set<RelayData> = [], accountPubkey: String? = nil) {
        #if DEBUG
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
                print("Canvas.sendMessage: \(message.clientMessage.type) \(message.message)")
                return
            }
        #endif
        
        queue.async(flags:. barrier) { [weak self] in
            self?.sendMessageAlreadyInQueue(message, subscriptionId: subscriptionId, relays: relays, accountPubkey: accountPubkey)
        }
    }
    
    // Only use when already in connection queue
    private func sendMessageAlreadyInQueue(_ message: NosturClientMessage, subscriptionId: String? = nil, relays: Set<RelayData> = [], accountPubkey: String? = nil) {
        #if DEBUG
        if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
            fatalError("Should only be called from inside queue.async { }")
        }
        #endif
        
        let limitToRelayIds = relays.map({ $0.id })
        
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
                
                guard connection.relayData.read || connection.relayData.write || limitToRelayIds.contains(connection.url) || (connection.relayData.search && message.relayType == .SEARCH) else {
                    // Skip if relay is not selected for reading or writing events. Or message and relay should be .SEARCH
                    continue
                }
                
                if message.type == .REQ { // REQ FOR ALL READ RELAYS
                    
                    if message.relayType == .READ && !limitToRelayIds.contains(connection.url) && !connection.relayData.read { continue }
                    if message.relayType == .SEARCH && !connection.relayData.search { continue }
                    if message.relayType == .SEARCH && connection.relayData.read { continue } // no need to lookup on relays that we already read from (Search/Lookup is always in addition to .READ)
                    
                    if (!connection.isSocketConnected) {
                        if (!connection.isSocketConnecting) {
                            connection.connect()
                        }
                        /// hmm don't continue with .sendMessage (or does it queue until connection??? not sure...)
                        //                        continue
                    }
                    // skip if we already have an active subscription
                    if subscriptionId != nil && connection.nreqSubscriptions.contains(subscriptionId!) { continue }
                    if (subscriptionId != nil) {
                        self.queue.async(flags: .barrier) { [weak connection] in
                            connection?.nreqSubscriptions.insert(subscriptionId!)
                        }
#if DEBUG
                        L.sockets.debug("⬇️⬇️ \(connection.url) .nreqSubscriptions.insert: \(subscriptionId!) - total subs: \(connection.nreqSubscriptions.count) onlyForNWC: \(message.onlyForNWCRelay) .isNWC: \(connection.isNWC) - onlyForNC: \(message.onlyForNCRelay) .isNC: \(connection.isNC)")
#endif
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
                    if let cmSubId = message.clientMessage.subscriptionId {
                        self.queue.async(flags: .barrier) { [weak connection] in
                            connection?.nreqSubscriptions.remove(cmSubId)
                        }
                    }
                    connection.sendMessage(message.message)
                }
                else if message.type == .EVENT {
                    let isRestrictedForThisRelay = (message.nEvent?.isRestricted ?? false) && limitToRelayIds.contains(connection.url)
                    if (message.relayType == .WRITE && !connection.relayData.write) && !isRestrictedForThisRelay { continue }
                    
                    if let accountPubkey = accountPubkey, connection.relayData.excludedPubkeys.contains(accountPubkey) {
                        L.sockets.info("sendMessage: \(accountPubkey) excluded from \(connection.url) - not publishing here isNC:\(connection.isNC.description) - isNWC: \(connection.isNWC.description) ")
                        continue
                    }
                    if (!connection.isSocketConnected) && (!connection.isSocketConnecting) {
                        connection.connect()
                    }
                    
                    if let nEvent = message.nEvent, connection.relayData.auth {
                        if connection.eventsThatMayNeedAuth.count > 10 {
                            connection.eventsThatMayNeedAuth = [:]
                        }
                        connection.eventsThatMayNeedAuth[nEvent.id] = message.message
                    }
                    
                    L.sockets.info("🚀🚀🚀 PUBLISHING TO \(connection.url): \(message.message)")
                    connection.sendMessage(message.message)
                }
            }
        }
        
        guard limitToRelayIds.isEmpty else { return } // REQ limited for specific relays are handled above, don't continue this in outbox stuff
        guard !SettingsStore.shared.lowDataMode else { return } // Don't continue with additional outbox relays on low data mode
        guard !message.onlyForNWCRelay && !message.onlyForNCRelay else { return } // also not NW or NWC
        
        // Additions for Outbox taken from nostr-essentials
        guard SettingsStore.shared.enableOutboxRelays, vpnGuardOK() else { return } // Check if Enhanced Relay Routing toggle is turned on
        guard let preferredRelays = self.preferredRelays else { return }
        
        // SEND REQ TO WHERE OTHERS WRITE (TO FIND THEIR POSTS, SO WE CAN READ)
        if message.type == .REQ && !preferredRelays.findEventsRelays.isEmpty {
            self.sendToOthersPreferredWriteRelays(message.clientMessage, subscriptionId: subscriptionId)
        }
        
        // SEND EVENT TO WHERE OTHERS READ (TO SEND REPLIES ETC SO THEY CAN READ IT)
        else if message.type == .EVENT && !preferredRelays.reachUserRelays.isEmpty {
            // don't send to p's if it is an event kind where p's have a different purpose than notification (eg kind:3)
            guard (message.clientMessage.event?.kind ?? 1) != 3 else { return }
            
            let pTags: Set<String> = Set( message.clientMessage.event?.tags.filter { $0.type == "p" }.compactMap { $0.pubkey } ?? [] )
            guard !pTags.isEmpty, let pubkey = message.clientMessage.event?.pubkey else { return }
            
            // don't use outbox if its not our message (maybe rebroadcast of existing reply/quote)
            guard AccountsState.shared.bgFullAccountPubkeys.contains(pubkey) else { return }
            
            self.sendToOthersPreferredReadRelays(message.clientMessage, pubkeys: pTags)
        }
    }
    
    @MainActor
    func sendEphemeralMessage(_ message: String, relay: String) {
        guard vpnGuardOK() else { L.sockets.debug("📡📡 No VPN: Connection cancelled (\(relay)"); return }
        let connection = addEphemeralConnection(RelayData.new(url: relay, read: true, write: false, search: true, auth: false, excludedPubkeys: []))
        if !connection.isConnected {
            connection.connect()
        }
        connection.sendMessage(message)
    }
    
    // -- MARK: Outbox code taken from nostr-essentials, because to generic there, need more Nostur specific wiring
    
    // Pubkeys grouped by relay url for finding events (.findEventsRelays) (their write relays)
    // and pubkeys grouped by relay url for publishing to reach them (.reachUserRelays) (their read relays)
    public var preferredRelays: PreferredRelays?
    
    private var maxPreferredRelays: Int = 50
    
    // Relays to find posts on relays not in our relay set
    public var findEventsConnections: [CanonicalRelayUrl: RelayConnection] = [:]
    
    // Relays to reach users on relays not in our relay set
    public var reachUsersConnections: [CanonicalRelayUrl: RelayConnection] = [:]
    
    private var _pubkeysByRelay: [String: Set<String>] = [:]
    
    public func setPreferredRelays(using kind10002s: [NostrEssentials.Event], maxPreferredRelays: Int = 50) {
        
        let cleanKind10002s = removeMisconfiguredKind10002s(kind10002s)
        
        self.preferredRelays = pubkeysByRelay(cleanKind10002s , ignoringRelays: SPECIAL_PURPOSE_RELAYS.union(POPULAR_RELAYS).union(self.penaltybox))
        self.kind10002s = cleanKind10002s
        // Set limit because to total relays will be derived from external events and can be abused
        self.maxPreferredRelays = maxPreferredRelays
    }
    
    private var kind10002s: [NostrEssentials.Event] = [] // cache here for easy reload after updating .penaltybox
    
    public func reloadPreferredRelays(kind10002s newerKind10002s: [NostrEssentials.Event]? = nil) {
        if let newerKind10002s { // Update with new kind 10002s
            let cleanKind10002s = removeMisconfiguredKind10002s(newerKind10002s) // remove garbage first
            self.preferredRelays = pubkeysByRelay(cleanKind10002s, ignoringRelays: SPECIAL_PURPOSE_RELAYS.union(POPULAR_RELAYS).union(self.penaltybox))
        }
        else { // no new kind 10002s, so probably update because new relays in penalty box
            self.preferredRelays = pubkeysByRelay(self.kind10002s, ignoringRelays: SPECIAL_PURPOSE_RELAYS.union(POPULAR_RELAYS).union(self.penaltybox))
        }
    }
    
    // SEND REQ TO WHERE OTHERS WRITE (TO FIND THEIR POSTS, SO WE CAN READ)
    private func sendToOthersPreferredWriteRelays(_ message: NostrEssentials.ClientMessage, subscriptionId: String? = nil) {
        guard let preferredRelays = self.preferredRelays else { return }
        
        let ourReadRelays: Set<String> = Set(connections.filter { $0.value.relayData.read }.map { $0.key })
        
        // Take pubkeys from first filter. Could be more and different but that wouldn't make sense for an outbox request.
        guard let filters = message.filters else { return }
        guard let pubkeys = filters.first?.authors else { return }
        
        // Outbox REQs should always be author based, so remove hashtags
        let filtersWithoutHashtags = if let subscriptionId, subscriptionId.starts(with: "Following-") {
            [filters
                .map { $0.withoutHashtags() } // Remove hashtags from existing query
                .first!] // Because its "Following" subscription, we know we only need the first Filter, the second filter will be hashtags. See LVM.fetchRealtimeSinceNow()
        } else {
            filters
                .filter { !$0.hasHashtags } // For any other query we always from hashtags from existing query (remove entire filter, not just hashtags
        }
        
        let plan: RequestPlan = createRequestPlan(pubkeys: pubkeys, reqFilters: filtersWithoutHashtags, ourReadRelays: ourReadRelays, preferredRelays: preferredRelays, skipTopRelays: 3)
        
        for req in plan.findEventsRequests
            .filter({ (relay: String, findEventsRequest: FindEventsRequest) in
                // Only requests that have .authors > 0
                // Requests can have multiple filters, we can count the authors on just the first one, all others should be the same (for THIS relay)
                findEventsRequest.pubkeys.count > 0
                
            })
            .sorted(by: {
                $0.value.pubkeys.count > $1.value.pubkeys.count
            })
            .prefix(self.maxPreferredRelays) // SANITY
        {
            if let conn = self.outboxConnections[req.key] {
                if !conn.relayData.read {
                    conn.relayData.setRead(true)
                }
                if !conn.isConnected {
                    conn.connect()
                }
                if subscriptionId != nil && conn.nreqSubscriptions.contains(subscriptionId!) { continue } // Skip if sub is already active
                if (subscriptionId != nil) {
                    conn.nreqSubscriptions.insert(subscriptionId!)
                }
                guard let message = NostrEssentials.ClientMessage(
                    type: .REQ,
                    subscriptionId: subscriptionId,
                    filters: req.value.filters
                ).json()
                else { return }
#if DEBUG
            L.sockets.debug("📤📤 Outbox 🟩 REQ (\(subscriptionId ?? "")) -- \(req.value.pubkeys.count): \(req.key) - \(req.value.filters.description) -[LOG]-")
#endif
                conn.sendMessage(message)
            }
            else {
                ConnectionPool.shared.addOutboxConnection(RelayData(read: true, write: false, search: false, auth: false, url: req.key, excludedPubkeys: [])) { connection in
                    if !connection.isConnected {
                        connection.connect()
                    }
                    
                    guard let message = NostrEssentials.ClientMessage(
                        type: .REQ,
                        subscriptionId: subscriptionId,
                        filters: req.value.filters
                    ).json()
                    else { return }
#if DEBUG
            L.sockets.debug("📤📤 Outbox 🟩 REQ (\(subscriptionId ?? "")) -- \(req.value.pubkeys.count): \(req.key) - \(req.value.filters.description) -[LOG]-")
#endif
                    connection.sendMessage(message)
                }
            }
        }
    }
    
    // SEND EVENT TO WHERE OTHERS READ (TO SEND REPLIES ETC SO THEY CAN READ IT)
    private func sendToOthersPreferredReadRelays(_ message: NostrEssentials.ClientMessage, pubkeys: Set<String>) {
        guard let preferredRelays = self.preferredRelays else { return }
        
        let ourWriteRelays: Set<String> = Set(connections.filter { $0.value.relayData.write }.map { $0.key })
        
        let plan: WritePlan = createWritePlan(pubkeys: pubkeys, ourWriteRelays: ourWriteRelays, preferredRelays: preferredRelays)
        
        for (relay, pubkeys) in plan.relays
            .filter({ (relay: String, pubkeys: Set<String>) in
                // Only relays that have .authors > 0
                pubkeys.count > 0
                
            })
            .sorted(by: {
                $0.value.count > $1.value.count
            }) {
            
            L.sockets.debug("📤📤 Outbox 🟩 SENDING EVENT -- \(relay): \(pubkeys.joined(separator: ","))")
            if let conn = self.outboxConnections[relay] {
                if !conn.relayData.write {
                    conn.relayData.setWrite(true)
                }
                if !conn.isConnected {
                    conn.connect()
                }
                guard let messageString = message.json() else { return }
                conn.sendMessage(messageString)
            }
            else {
                ConnectionPool.shared.addOutboxConnection(RelayData(read: false, write: true, search: false, auth: false, url: relay, excludedPubkeys: [])) { connection in
                    if !connection.isConnected {
                        connection.connect()
                    }
                    guard let messageString = message.json() else { return }
                    connection.sendMessage(messageString)
                }
            }
        }
    }
    
    // Copy-paste of sendToOthersPreferredReadRelays() but instead of sending will just return list or relay urls where it would send to
    public func previewOthersPreferredReadRelays(_ message: NostrEssentials.ClientMessage, pubkeys: Set<String>) -> Set<String> {
        guard let preferredRelays = self.preferredRelays else { return [] }
        
        let ourWriteRelays: Set<String> = Set(connections.filter { $0.value.relayData.write }.map { $0.key })
        
        let plan: WritePlan = createWritePlan(pubkeys: pubkeys, ourWriteRelays: ourWriteRelays, preferredRelays: preferredRelays)
        
        var relays = Set<String>()
        
        for (relay, pubkeys) in plan.relays
            .filter({ (relay: String, pubkeys: Set<String>) in
                // Only relays that have .authors > 0
                pubkeys.count > 0
                
            })
            .sorted(by: {
                $0.value.count > $1.value.count
            }) {
            
            relays.insert(relay)
        }
        
        return relays
    }
}

@MainActor func fetchEventFromRelayHint(_ eventId:String, fastTags: [FastTag]) {
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
    let text: String
}


// Check if a connection is allowed
func vpnGuardOK() -> Bool {
    // VPN check is disabled in settings, so always allow
    if (!SettingsStore.shared.enableVPNdetection) { return true }
    
    // VPN is detected so allow
    if NetworkMonitor.shared.vpnDetected { return true }
    
    // VPN is not detected, don't allow connection
    return false
}
