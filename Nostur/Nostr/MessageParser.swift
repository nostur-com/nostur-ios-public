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

    // Subscriptions that will be kept open after EOSE
    static let ACTIVE_SUBSCRIPTIONS = Set(["Following","Explore","Notifications","REALTIME-DETAIL", "REALTIME-DETAIL-A", "NWC", "NC", "LIVEEVENTS", "-DB-ROOMPRESENCE", "-DB-CHAT-"])
    
    private var bgQueue = bg()
    private var poolQueue = ConnectionPool.shared.queue
    public var messageBucket = Deque<RelayMessage>()
    public var priorityBucket = Deque<RelayMessage>()
    public var isSignatureVerificationEnabled = true
    
    public let tagSerializer: TagSerializer
    
    // (id, relay)
    public let okSub = PassthroughSubject<(String, String), Never>()
    
    
    init() {
        tagSerializer = TagSerializer.shared
        bgQueue.perform {
            self.isSignatureVerificationEnabled = SettingsStore.shared.isSignatureVerificationEnabled
        }
    }
    
    func socketReceivedMessage(text: String, relayUrl: String, client: RelayConnection) {
        bgQueue.perform { [unowned self] in
            do {
                let message = try RelayMessage.parseRelayMessage(text: text, relay: relayUrl)
                
                switch message.type {
                case .AUTH:
#if DEBUG
                    L.sockets.debug("🟢🟢 \(relayUrl): \(message.message)")
#endif
                    client.handleAuth(message.message)
                case .OK:
#if DEBUG
                    L.sockets.debug("\(relayUrl): \(message.message)")
#endif
                    if message.success ?? false {
                        if let id = message.id {
                            okSub.send((id, relayUrl))
                            Event.updateRelays(id, relays: message.relays, context: bgQueue)
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
                        
                        client.sendAuthResponse()
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
                    L.sockets.notice("\(relayUrl): \(message.message)")
                    #if DEBUG
                        DispatchQueue.main.async {
                            sendNotification(.anyStatus, (String(format:"Notice: %@: %@", relayUrl.replacingOccurrences(of: "wss://", with: ""), message.message), "RELAY_NOTICE"))
                        }
                    #endif
                    poolQueue.async(flags: .barrier) {
                        client.stats.addNoticeMessage(message.message)
                    }
                case .EOSE:
                    // Keep these subscriptions open.
                    guard let subscriptionId = message.subscriptionId else { return }
                    // TODO: Make generic -OPEN-, instead of "Following-" and "List-" etc..
                    if !Self.ACTIVE_SUBSCRIPTIONS.contains(subscriptionId) && String(subscriptionId.prefix(10)) != "Following-" && String(subscriptionId.prefix(5)) != "List-" && String(subscriptionId.prefix(9)) != "-DB-CHAT-" && String(subscriptionId.prefix(14)) != "-DB-1311-9735-" && String(subscriptionId.prefix(10)) != "LIVEEVENTS" {
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
                        guard let nEvent = message.event else { L.sockets.info("🔴🔴 uhh, where is nEvent "); return }
                        
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
            catch RelayMessage.error.NOT_IN_WOT {
#if DEBUG
                L.sockets.debug("🟠 \(relayUrl) Not in WoT, skipped: \(text)")
#endif
                ConnectionPool.shared.notInWoTcount += 1
            }
            catch RelayMessage.error.UNKNOWN_MESSAGE_TYPE {
#if DEBUG
                L.sockets.notice("🟠 \(relayUrl) Unknown message type: \(text)")
#endif
            }
            catch RelayMessage.error.FAILED_TO_PARSE {
#if DEBUG
                L.sockets.notice("🟠 \(relayUrl) Could not parse text received: \(text)")
#endif
            }
            catch RelayMessage.error.FAILED_TO_PARSE_EVENT {
#if DEBUG
                L.sockets.notice("🟠 \(relayUrl) Could not parse EVENT: \(text)")
#endif
            }
            catch RelayMessage.error.DUPLICATE_ALREADY_SAVED, RelayMessage.error.DUPLICATE_ALREADY_PARSED {
#if DEBUG
//                L.sockets.debug("🟡🟡 \(relayUrl) already SAVED/PARSED ")
#endif
            }
            catch RelayMessage.error.INVALID_SIGNATURE {
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
    
    func handleNoDbMessage(message: RelayMessage, nEvent: NEvent? = nil) throws {
        if let nEvent {
            guard try !self.isSignatureVerificationEnabled || nEvent.verified() else {
                throw RelayMessage.error.INVALID_SIGNATURE
            }
        }
        // Don't save to database, just handle response directly
        DispatchQueue.main.async {
            sendNotification(.receivedMessage, message)
        }
    }    
    
    func handleNWCResponse(message: RelayMessage, nEvent: NEvent) throws {
        guard try !self.isSignatureVerificationEnabled || nEvent.verified() else {
            throw RelayMessage.error.INVALID_SIGNATURE
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
                    NotificationsViewModel.shared.checkNeedsUpdate(notification)
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
                    let message = "Zap may have failed for [contact](nostur:p:\(awaitingZap.contact.pubkey)).\n\(error.message)"
                    let notification = PersistentNotification.createFailedNWCZap(pubkey: AccountsState.shared.activeAccountPublicKey, message: message, context: self.bgQueue)
                    NotificationsViewModel.shared.checkNeedsUpdate(notification)
#if DEBUG
                    L.og.info("⚡️ Created notification: Zap failed for [contact](nostur:p:\(awaitingZap.contact.pubkey)). \(error.message)")
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
                NotificationsViewModel.shared.checkNeedsUpdate(notification)
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
    
    func handleNWCInfoResponse(message: RelayMessage, nEvent: NEvent) throws {
        guard try !self.isSignatureVerificationEnabled || nEvent.verified() else {
            throw RelayMessage.error.INVALID_SIGNATURE
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
    
    func handlePrioMessage(message: RelayMessage, nEvent: NEvent, relayUrl: String) {
        let sameMessageInQueue = self.priorityBucket.first(where: {
             nEvent.id == $0.event?.id && $0.type == .EVENT
        })
        
        if let sameMessageInQueue {
            sameMessageInQueue.relays = sameMessageInQueue.relays + " " + message.relays
            return
        }
        else {
            self.priorityBucket.append(message)
            guard let event = message.event else { return }
            updateEventCache(event.id, status: .PARSED, relays: relayUrl)
            Importer.shared.addedPrioRelayMessage.send()
        }
    }
    
    
    
    // MARK: Goes to importer/db
    func handleNormalMessage(message: RelayMessage, nEvent: NEvent, relayUrl: String) {
        let sameMessageInQueue = self.messageBucket.first(where: { // TODO: Instruments: slow here...
             nEvent.id == $0.event?.id && $0.type == .EVENT
        })
        
        if let sameMessageInQueue {
            sameMessageInQueue.relays = sameMessageInQueue.relays + " " + message.relays
            return
        }
        else {
            self.messageBucket.append(message)
            guard let event = message.event else { return }
            updateEventCache(event.id, status: .PARSED, relays: relayUrl)
            Importer.shared.addedRelayMessage.send()
        }
    }
}
