//
//  MessageParser.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/01/2023.
//

import Foundation
import Collections
import NostrEssentials
import Combine

// Normal id here is event.id. In case of giftwrap/rumor, the id is giftwrap id, never use rumor id.
func updateEventCache(_ id: String, status: ProcessStatus, relays: String? = nil) {
    if let existing = Importer.shared.existingIds[id], let relays {
        let existingRelays = (existing.relays ?? "").split(separator: " ").map { String($0) }
        let newRelays = relays.split(separator: " ").map { String($0) }
        let uniqueRelays = Set(existingRelays + newRelays)
        if uniqueRelays.count > existingRelays.count {
            Importer.shared.existingIds[id] = EventState(status: status, relays: uniqueRelays.joined(separator: " "))
        }
        else {
            Importer.shared.existingIds[id] = EventState(status: status, relays: existing.relays)
        }
    }
    else {
        Importer.shared.existingIds[id] = EventState(status: status, relays: relays)
    }
}

class MessageParser {
    
    static let shared = MessageParser()

    // Subscriptions that will be kept open after EOSE (can also use prefix -OPEN-)
    static let ACTIVE_SUBSCRIPTIONS = Set(
        ["Following","Explore","Notifications","Notifications-A","REALTIME-DETAIL", "REALTIME-DETAIL-A", "REALTIME-DETAIL-22", "NWC", "NC", "LIVEEVENTS", "-DB-ROOMPRESENCE", "-DB-CHAT-"])
    
    private var bgQueue = bg()
    private var poolQueue = ConnectionPool.shared.queue
    public var messageBucket = Deque<NXRelayMessage>()
    public var priorityBucket = Deque<NXRelayMessage>()
    private var queuedMessageIds: Set<String> = []
    private var queuedPriorityIds: Set<String> = []
    private var messageRelaysByEventId: [String: Set<String>] = [:]
    private var priorityRelaysByEventId: [String: Set<String>] = [:]
    public var isSignatureVerificationEnabled = true
    
    public let tagSerializer: TagSerializer
    
    // (id, relay)
    public let okSub = PassthroughSubject<(id: String, relay: String), Never>()
    
    // if "OK" comes back, .updateRelays should update the rumor (.otherId), not the wrap
    public var pendingOkWrapIds: Set<String> = []
    
    // map OKs to rumor id, to update sent relays
    public var pendingOkWrapToRumorIdMap = [String: String]() // [wrapid : rumor id]
    
    init() {
        tagSerializer = TagSerializer.shared
        bgQueue.perform {
            self.isSignatureVerificationEnabled = SettingsStore.shared.isSignatureVerificationEnabled
        }
    }
    
    func socketReceivedMessage(text: String, relayUrl: String, client: RelayConnection) {
        bgQueue.perform { [unowned self] in
            do {
                let message = try nxParseRelayMessage(text: text, relay: relayUrl)
                
                switch message.type {
                case .AUTH:
#if DEBUG
                    L.sockets.debug("🟢🟢 \(relayUrl): \(message.message) (AUTH)")
#endif
                    client.handleAuth(message.message)
                case .OK:
#if DEBUG
                    L.sockets.debug("\(relayUrl): \(message.message) (OK)")
#endif
                    if message.success ?? false {
                        if let id = message.id {
                            // if "OK" comes back, .updateRelays should update the rumor (.otherId), not the wrap
                            if let rumorId = pendingOkWrapToRumorIdMap[id] {
                                Event.updateRelays(rumorId, relays: message.relays, isWrapId: false, context: bgQueue)
                                // Don't remove mapping immediately - same wrap may be sent to multiple relays
                                // Clean up after delay to allow all relay OKs to arrive
                                let wrapId = id
                                DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                                    self?.bgQueue.perform {
                                        self?.pendingOkWrapToRumorIdMap.removeValue(forKey: wrapId)
                                    }
                                }
                                okSub.send((id: rumorId, relay: relayUrl))
                            }
                            else if pendingOkWrapIds.contains(id) {
                                Event.updateRelays(id, relays: message.relays, isWrapId: true, context: bgQueue)
                                pendingOkWrapIds.remove(id)
                                okSub.send((id: id, relay: relayUrl))
                            }
                            else {
                                okSub.send((id: id, relay: relayUrl))
                                Event.updateRelays(id, relays: message.relays, context: bgQueue)
                            }
                        }
                    }
                    else if message.message.prefix(14) == "auth-required:", client.relayData.auth, let id = message.id {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            if let eventMessage = client.eventsThatMayNeedAuth[id] {
#if DEBUG
                                L.sockets.debug("🟢🟢 \(relayUrl): Trying again after auth-required")
#endif
                                client.sendMessage(eventMessage)
                            }
                        }
                    }
                case .CLOSED:
                    if let subscriptionId = message.subscriptionId {
                        client.completeReqSubscription(subscriptionId)
                    }
                    if message.message.prefix(14) == "auth-required:" {
#if DEBUG
                        L.sockets.debug("\(relayUrl): \(message.message) \(message.subscriptionId ?? "") (CLOSED) (auth-required)")
#endif
                        // Send auth response, but check first if its outbox relay, then remove from outbox relays
                        guard !client.isOutbox else {
                            DispatchQueue.main.async {
                                ConnectionPool.shared.removeOutboxConnection(relayUrl)
                                ConnectionPool.shared.queue.async(flags: .barrier) {
                                    guard SettingsStore.shared.enableOutboxRelays else { return }
                                    guard ConnectionPool.shared.canPutInPenaltyBox(relayUrl) else { return }
                                    ConnectionPool.shared.penaltybox.insert(relayUrl)
                                    client.stats.addNoticeMessage(message.message)
                                }
                            }
                            return
                        }
                        
                        client.authSubject.send()
                    }
                    else if message.message.prefix(13) == "rate-limited:" {
                        ConnectionPool.shared.queue.async(flags: .barrier) {
                            client.stats.addNoticeMessage(message.message)
                        }
                    }
                    else if message.message.prefix(8) == "invalid:" {
                        ConnectionPool.shared.queue.async(flags: .barrier) {
                            client.stats.addNoticeMessage(message.message)
                        }
                    }
                    else if message.message.prefix(8) == "blocked:" {
                        ConnectionPool.shared.queue.async(flags: .barrier) {
                            client.stats.addNoticeMessage(message.message)
                        }
                    }
                    else if message.message.prefix(4) == "pow:" {
                        ConnectionPool.shared.queue.async(flags: .barrier) {
                            client.stats.addNoticeMessage(message.message)
                        }
                    }
                    else if message.message.prefix(10) == "duplicate:" {
                        ConnectionPool.shared.queue.async(flags: .barrier) {
                            client.stats.addNoticeMessage(message.message)
                        }
                    }
                    else if message.message.prefix(6) == "error:" {
                        ConnectionPool.shared.queue.async(flags: .barrier) {
                            client.stats.addNoticeMessage(message.message)
                        }
                    }
                    else {
                        L.sockets.debug("\(relayUrl): \(message.message) \(message.subscriptionId ?? "") (CLOSED) -[LOG]-")
                    }
                case .NOTICE:
                    // handle ["NOTICE", "ping"] only Ditto Core does this??
                    if message.message == "ping" {
                        client.sendMessage(ClientMessage.close(subscriptionId: "pong")) // annoying
                    }
                    else {
                        L.sockets.notice("\(relayUrl): \(message.message)")
#if DEBUG
                        DispatchQueue.main.async {
                            sendNotification(.anyStatus, (String(format:"Notice: %@: %@", relayUrl.replacingOccurrences(of: "wss://", with: ""), message.message), "RELAY_NOTICE"))
                        }
#endif
                        poolQueue.async(flags: .barrier) {
                            client.stats.addNoticeMessage(message.message)
                        }
                    }
                case .EOSE:
                    // Keep these subscriptions open.
                    guard let subscriptionId = message.subscriptionId else { return }
                    client.completeReqSubscription(subscriptionId)
                    // TODO: Make generic -OPEN-, instead of "Following-" and "List-" etc..
                    if !Self.ACTIVE_SUBSCRIPTIONS
                        .contains(subscriptionId) && String(subscriptionId.prefix(6)) != "-OPEN-" && String(subscriptionId.prefix(10)) != "Following-" && String(subscriptionId.prefix(5)) != "List-"
                        && String(subscriptionId.prefix(9)) != "-DB-CHAT-" && String(subscriptionId.prefix(14)) != "-DB-1311-9735-"
                        && String(subscriptionId.prefix(10)) != "LIVEEVENTS" && String(subscriptionId.prefix(5)) != "LIVE-" {
                        // Send close message to this specific socket, not all.
#if DEBUG
                        L.sockets.debug("🔌🔌 \(relayUrl): EOSE received. Sending CLOSE to \(client.url) for \(subscriptionId) -[LOG]-")
#endif
                        client.sendMessage(ClientMessage.close(subscriptionId: subscriptionId))
                    }
                    else {
#if DEBUG
                        L.sockets.debug("🔌🔌 \(relayUrl): EOSE received. keeping OPEN. \(client.url) for \(subscriptionId) -[LOG]-")
#endif
                    }
                    if subscriptionId.prefix(4) == "-DB-" {
                        try handleNoDbMessage(message: message)
                    }
                default:
                    if (message.type == .EVENT) {
                        guard let nEvent = message.event else {
#if DEBUG
                            L.sockets.info("🔴🔴 uhh, where is nEvent ");
#endif
                            return
                        }
                        
                        // If a sub is prefixed with "-DB-" never hit db.
                        if let subscriptionId = message.subscriptionId, subscriptionId.prefix(4) == "-DB-", nEvent.kind != .zapNote {
                            try handleNoDbMessage(message: message, nEvent: nEvent)
                            return
                        }
                        
                        // Handle directly (not to db) or continue to importer
                        switch nEvent.kind {
                        case .ncMessage, .chatMessage, .custom(10312):
                            try handleNoDbMessage(message: message, nEvent: nEvent)
                        case .nwcInfo:
                            try handleNWCInfoResponse(message: message, nEvent: nEvent)
                        case .nwcResponse:
                            try handleNWCResponse(message: message, nEvent: nEvent)
                        default:
                            // Continue to importer (to db)
                            if let subscriptionId = message.subscriptionId, subscriptionId.prefix(5) == "prio-" {
                                handlePrioMessage(message: message, nEvent: nEvent, relayUrl: relayUrl)
                            }
                            else {
                                handleNormalMessage(message: message, nEvent: nEvent, relayUrl: relayUrl)
                            }
                        }
                       
                        
                        
                      
                    }
                }
            }
            catch NXRelayMessageError.NOT_IN_WOT {
#if DEBUG
                L.sockets.debug("🟠 \(relayUrl) Not in WoT, skipped: \(text) -[LOG]-")
#endif
                ConnectionPool.shared.notInWoTcount += 1
//                poolQueue.async(flags: .barrier) { // TODO: Track spam per relay?
//                    // client.stats.addNotInWoT...
//                }
            }
            catch NXRelayMessageError.UNKNOWN_MESSAGE_TYPE {
#if DEBUG
                L.sockets.notice("🟠 \(relayUrl) Unknown message type: \(text)")
#endif
            }
            catch NXRelayMessageError.FAILED_TO_PARSE {
#if DEBUG
                L.sockets.notice("🟠 \(relayUrl) Could not parse text received: \(text)")
#endif
            }
            catch NXRelayMessageError.FAILED_TO_PARSE_EVENT {
#if DEBUG
                L.sockets.notice("🟠 \(relayUrl) Could not parse EVENT: \(text)")
#endif
            }
            catch NXRelayMessageError.DUPLICATE_ALREADY_SAVED, NXRelayMessageError.DUPLICATE_ALREADY_PARSED {
#if DEBUG
//                L.sockets.debug("🟡🟡 \(relayUrl) already SAVED/PARSED ")
#endif
            }
            catch NXRelayMessageError.INVALID_SIGNATURE {
#if DEBUG
                L.sockets.notice("🔴🔴 \(relayUrl) invalid signature \(text)")
#endif
            }
            catch {
#if DEBUG
                L.sockets.info("🔴🔴 \(relayUrl) \(error)")
#endif
            }
        }        
    }
    
    // MARK: Handle directly without touching db
    
    func handleNoDbMessage(message: NXRelayMessage, nEvent: NEvent? = nil) throws {
        if let nEvent {
            guard try !self.isSignatureVerificationEnabled || nEvent.verified() else {
                throw NXRelayMessageError.INVALID_SIGNATURE
            }
        }
        // Don't save to database, just handle response directly
        DispatchQueue.main.async { // TODO: Need to check how to handle .receivedMessage in case of GiftWrap (so far not needed, yet)
            sendNotification(.receivedMessage, message)
        }
    }    
    
    func handleNWCResponse(message: NXRelayMessage, nEvent: NEvent) throws {
        guard try !self.isSignatureVerificationEnabled || nEvent.verified() else {
            throw NXRelayMessageError.INVALID_SIGNATURE
        }
        
        let decoder = JSONDecoder()
        guard let nwcConnection = Importer.shared.nwcConnection else {
#if DEBUG
            L.og.error("⚡️ NWC response but nwcConnection missing \(nEvent.eventJson())")
#endif
            return
        }
        guard let pk = nwcConnection.privateKey else {
#if DEBUG
            L.og.error("⚡️ NWC response but private key missing \(nEvent.eventJson())")
#endif
            return
        }
        guard let decrypted = Keys.decryptDirectMessageContent(withPrivateKey: pk, pubkey: nEvent.publicKey, content: nEvent.content) ?? Keys.decryptDirectMessageContent44(withPrivateKey: pk, pubkey: nEvent.publicKey, content: nEvent.content) else {
#if DEBUG
            L.og.error("⚡️ Could not decrypt nwcResponse, \(nEvent.eventJson())")
#endif
            return
        }
        guard let nwcResponse = try? decoder.decode(NWCResponse.self, from: decrypted.data(using: .utf8)!) else {
#if DEBUG
            L.og.error("⚡️ Could not parse/decode nwcResponse, \(nEvent.eventJson()) - \(decrypted)")
#endif
            return
        }
        if balanceResponseHandled(nwcResponse) {
            return
        }
        guard let firstE = nEvent.eTags().first, let awaitingRequest = NWCRequestQueue.shared.getAwaitingRequest(byId: firstE) else {
#if DEBUG
            L.og.error("⚡️ No matching nwc request for response, or e-tag missing, \(nEvent.eventJson()) - \(decrypted)")
#endif
            return
        }
        if let awaitingZap = awaitingRequest.zap {
            // HANDLE ZAPS
            if let error = nwcResponse.error {
#if DEBUG
                L.og.info("⚡️ NWC response with error: \(error.code) - \(error.message)")
#endif
                if let eventId = awaitingZap.eventId {
                    let message = "[Zap](nostur:e:\(eventId)) may have failed.\n\(error.message)"
                    let notification = PersistentNotification.createFailedNWCZap(pubkey: AccountsState.shared.activeAccountPublicKey, message: message, context: self.bgQueue)
                    FeedsCoordinator.shared.notificationNeedsUpdateSubject.send(
                        NeedsUpdateInfo(persistentNotification: notification)
                    )
#if DEBUG
                    L.og.info("⚡️ Created notification: Zap failed for [post](nostur:e:\(eventId)). \(error.message)")
#endif
                    if (SettingsStore.shared.nwcShowBalance) {
                        nwcSendBalanceRequest()
                    }
                    if let ev = Event.fetchEvent(id: eventId, context: self.bgQueue) {
                        ev.zapState = nil
                    }
                }
                else {
                    let message = "Zap may have failed for [contact](nostur:p:\(awaitingZap.nrContact.pubkey)).\n\(error.message)"
                    let notification = PersistentNotification.createFailedNWCZap(pubkey: AccountsState.shared.activeAccountPublicKey, message: message, context: self.bgQueue)
                    FeedsCoordinator.shared.notificationNeedsUpdateSubject.send(
                        NeedsUpdateInfo(persistentNotification: notification)
                    )
#if DEBUG
                    L.og.info("⚡️ Created notification: Zap failed for [contact](nostur:p:\(awaitingZap.nrContact.pubkey)). \(error.message)")
#endif
                }
                NWCZapQueue.shared.removeZap(byId: awaitingZap.id)
                NWCRequestQueue.shared.removeRequest(byId: awaitingRequest.request.id)
                return
            }
            guard let result_type = nwcResponse.result_type, result_type == "pay_invoice" else {
#if DEBUG
                L.og.error("⚡️ Unknown or missing result_type, \(nwcResponse.result_type ?? "") - \(decrypted)")
#endif
                return
            }
            if let result = nwcResponse.result {
#if DEBUG
                L.og.info("⚡️ Zap success \(result.preimage ?? "-") - \(decrypted)")
#endif
                NWCZapQueue.shared.removeZap(byId: awaitingZap.id)
                NWCRequestQueue.shared.removeRequest(byId: awaitingRequest.request.id)
                if (SettingsStore.shared.nwcShowBalance) {
                    nwcSendBalanceRequest()
                }
                return
            }
        }
        else {
            // HANDLE OLD BOLT11 INVOICE PAYMENT
            if let error = nwcResponse.error {
                let message = "Failed to pay lightning invoice.\n\(error.message)"
                let notification = PersistentNotification.createFailedLightningInvoice(pubkey: AccountsState.shared.activeAccountPublicKey, message: message, context: self.bgQueue)
                FeedsCoordinator.shared.notificationNeedsUpdateSubject.send(
                    NeedsUpdateInfo(persistentNotification: notification)
                )
#if DEBUG
                L.og.error("⚡️ Failed to pay lightning invoice. \(error.message)")
#endif
                NWCRequestQueue.shared.removeRequest(byId: awaitingRequest.request.id)
                return
            }
            guard let result_type = nwcResponse.result_type, result_type == "pay_invoice" else {
#if DEBUG
                L.og.error("⚡️ Unknown or missing result_type, \(nwcResponse.result_type ?? "") - \(decrypted)")
#endif
                return
            }
            if let result = nwcResponse.result {
#if DEBUG
                L.og.info("⚡️ Lighting Invoice Payment (Not Zap) success \(result.preimage ?? "-") - \(decrypted)")
#endif
                NWCRequestQueue.shared.removeRequest(byId: awaitingRequest.request.id)
                if (SettingsStore.shared.nwcShowBalance) {
                    nwcSendBalanceRequest()
                }
                return
            }
        }
#if DEBUG
        L.og.info("⚡️ NWC response not handled: \(nEvent.eventJson()) ")
#endif
    }
    
    func handleNWCInfoResponse(message: NXRelayMessage, nEvent: NEvent) throws {
        guard try !self.isSignatureVerificationEnabled || nEvent.verified() else {
            throw NXRelayMessageError.INVALID_SIGNATURE
        }
        
        guard let nwcConnection = Importer.shared.nwcConnection else { return }
        guard nEvent.publicKey == nwcConnection.walletPubkey else { return }
#if DEBUG
        L.og.debug("⚡️ Received 13194 info event, saving methods: \(nEvent.content)")
#endif
        nwcConnection.methods = nEvent.content
        DispatchQueue.main.async {
            sendNotification(.nwcInfoReceived, NWCInfoNotification(methods: nEvent.content))
        }
    }
    
    func handlePrioMessage(message: NXRelayMessage, nEvent: NEvent, relayUrl: String) {
        enqueuePrioMessage(message, eventId: nEvent.id, relayUrl: relayUrl)
    }
    
    
    
    // MARK: Goes to importer/db
    func handleNormalMessage(message: NXRelayMessage, nEvent: NEvent, relayUrl: String) {
        enqueueNormalMessage(message, eventId: nEvent.id, relayUrl: relayUrl)
    }
    
    var messageBucketCount: Int {
        messageBucket.count
    }
    
    var priorityBucketCount: Int {
        priorityBucket.count
    }
    
    func popFirstNormalMessage() -> NXRelayMessage? {
        guard var message = messageBucket.popFirst() else {
            return nil
        }
        
        if let eventId = message.event?.id {
            if let mergedRelays = mergedRelays(for: eventId, queuedRelaysByEventId: &messageRelaysByEventId) {
                message.relays = mergedRelays
            }
            queuedMessageIds.remove(eventId)
        }
        return message
    }
    
    func popFirstPrioMessage() -> NXRelayMessage? {
        guard var message = priorityBucket.popFirst() else {
            return nil
        }
        
        if let eventId = message.event?.id {
            if let mergedRelays = mergedRelays(for: eventId, queuedRelaysByEventId: &priorityRelaysByEventId) {
                message.relays = mergedRelays
            }
            queuedPriorityIds.remove(eventId)
        }
        return message
    }
    
    func mergeRelaysForParsedDuplicate(eventId: String, relay: String) {
        var merged = false
        
        if queuedMessageIds.contains(eventId) {
            messageRelaysByEventId[eventId, default: []].insert(relay)
            merged = true
        }
        
        if queuedPriorityIds.contains(eventId) {
            priorityRelaysByEventId[eventId, default: []].insert(relay)
            merged = true
        }
        
        if merged {
            updateEventCache(eventId, status: .PARSED, relays: relay)
        }
    }
    
    private func enqueueNormalMessage(_ message: NXRelayMessage, eventId: String, relayUrl: String) {
        let relaySet = relaySetFromString(message.relays)
        if queuedMessageIds.contains(eventId) {
            messageRelaysByEventId[eventId, default: []].formUnion(relaySet)
            updateEventCache(eventId, status: .PARSED, relays: relayUrl)
            return
        }
        
        messageBucket.append(message)
        queuedMessageIds.insert(eventId)
        messageRelaysByEventId[eventId] = relaySet
        updateEventCache(eventId, status: .PARSED, relays: relayUrl)
        Importer.shared.addedRelayMessage.send()
    }
    
    private func enqueuePrioMessage(_ message: NXRelayMessage, eventId: String, relayUrl: String) {
        let relaySet = relaySetFromString(message.relays)
        if queuedPriorityIds.contains(eventId) {
            priorityRelaysByEventId[eventId, default: []].formUnion(relaySet)
            updateEventCache(eventId, status: .PARSED, relays: relayUrl)
            return
        }
        
        priorityBucket.append(message)
        queuedPriorityIds.insert(eventId)
        priorityRelaysByEventId[eventId] = relaySet
        updateEventCache(eventId, status: .PARSED, relays: relayUrl)
        Importer.shared.addedPrioRelayMessage.send()
    }
    
    private func relaySetFromString(_ relays: String) -> Set<String> {
        Set(relays.split(separator: " ").map { String($0) })
    }
    
    private func mergedRelays(for eventId: String, queuedRelaysByEventId: inout [String: Set<String>]) -> String? {
        guard let relays = queuedRelaysByEventId.removeValue(forKey: eventId), !relays.isEmpty else {
            return nil
        }
        return relays.joined(separator: " ")
    }
}
