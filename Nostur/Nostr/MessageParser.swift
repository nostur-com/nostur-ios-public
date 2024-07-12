//
//  MessageParser.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/01/2023.
//

import Foundation
import Collections

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

    // Subscriptions that will be kept open afte EOSE
    static let ACTIVE_SUBSCRIPTIONS = Set(["Following","Explore","Notifications","REALTIME-DETAIL", "REALTIME-DETAIL-A", "NWC", "NC"])
    
    private var bgQueue = bg()
    private var poolQueue = ConnectionPool.shared.queue
    public var messageBucket = Deque<RelayMessage>()
    public var priorityBucket = Deque<RelayMessage>()
    public var isSignatureVerificationEnabled = true
    
    public let tagSerializer: TagSerializer
    
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
                    L.sockets.info("🟢🟢 \(relayUrl): \(message.message)")
                    client.handleAuth(message.message)
                case .OK:
                    L.sockets.debug("\(relayUrl): \(message.message)")
                    if message.success ?? false {
                        if let id = message.id {
                            Event.updateRelays(id, relays: message.relays, context: bgQueue)
                        }
                    }
                case .CLOSED:
                    L.sockets.debug("\(relayUrl): \(message.message) \(message.subscriptionId ?? "") (CLOSED)")
                    if message.message.prefix(14) == "auth-required:" {
                        // Send auth response, but check first if its outbox relay, then remove from outbox relays
                        guard !client.isOutbox else {
                            DispatchQueue.main.async {
                                ConnectionPool.shared.removeOutboxConnection(relayUrl)
                                ConnectionPool.shared.queue.async(flags: .barrier) {
                                    guard SettingsStore.shared.enableOutboxRelays else { return }
                                    guard ConnectionPool.shared.canPutInPenaltyBox(relayUrl) else { return }
                                    ConnectionPool.shared.penaltybox.insert(relayUrl)
                                }
                            }
                            return
                        }
                        
                        client.sendAuthResponse()
                    }
                case .NOTICE:
                    L.sockets.notice("\(relayUrl): \(message.message)")
                    #if DEBUG
                        DispatchQueue.main.async {
                            sendNotification(.anyStatus, (String(format:"Notice: %@: %@", relayUrl.replacingOccurrences(of: "wss://", with: ""), message.message), "RELAY_NOTICE"))
                        }
                    #endif
                case .EOSE:
                    // Keep these subscriptions open.
                    guard let subscriptionId = message.subscriptionId else { return }
                    if !Self.ACTIVE_SUBSCRIPTIONS.contains(subscriptionId) && String(subscriptionId.prefix(5)) != "List-" {
                        // Send close message to this specific socket, not all.
                        #if DEBUG
                        L.sockets.debug("🔌🔌 EOSE received. Sending CLOSE to \(client.url) for \(subscriptionId)")
                        #endif
                        client.sendMessage(ClientMessage.close(subscriptionId: subscriptionId))
                    }
                    else {
                        #if DEBUG
                        L.sockets.debug("🔌🔌 EOSE received. keeping OPEN. \(client.url) for \(subscriptionId)")
                        #endif
                    }
                default:
                    if (message.type == .EVENT) {
                        guard let nEvent = message.event else { L.sockets.info("🔴🔴 uhh, where is nEvent "); return }
                        
                        if nEvent.kind == .ncMessage {
                            guard try !self.isSignatureVerificationEnabled || nEvent.verified() else {
                                throw RelayMessage.error.INVALID_SIGNATURE
                            }
                            // Don't save to database, just handle response directly
                            DispatchQueue.main.async {
                                sendNotification(.receivedMessage, message)
                            }
                            return
                        }
                        
                        if nEvent.kind == .nwcResponse {
                            guard try !self.isSignatureVerificationEnabled || nEvent.verified() else {
                                throw RelayMessage.error.INVALID_SIGNATURE
                            }
                            
                            let decoder = JSONDecoder()
                            guard let nwcConnection = Importer.shared.nwcConnection else { L.og.error("⚡️ NWC response but nwcConnection missing \(nEvent.eventJson())"); return }
                            guard let pk = nwcConnection.privateKey else { L.og.error("⚡️ NWC response but private key missing \(nEvent.eventJson())"); return }
                            guard let decrypted = NKeys.decryptDirectMessageContent(withPrivateKey: pk, pubkey: nEvent.publicKey, content: nEvent.content) else {
                                L.og.error("⚡️ Could not decrypt nwcResponse, \(nEvent.eventJson())")
                                return
                            }
                            guard let nwcResponse = try? decoder.decode(NWCResponse.self, from: decrypted.data(using: .utf8)!) else {
                                L.og.error("⚡️ Could not parse/decode nwcResponse, \(nEvent.eventJson()) - \(decrypted)")
                                return
                            }
                            if balanceResponseHandled(nwcResponse) {
                                return
                            }
                            guard let firstE = nEvent.eTags().first, let awaitingRequest = NWCRequestQueue.shared.getAwaitingRequest(byId: firstE) else {
                                L.og.error("⚡️ No matching nwc request for response, or e-tag missing, \(nEvent.eventJson()) - \(decrypted)")
                                return
                            }
                            if let awaitingZap = awaitingRequest.zap {
                                // HANDLE ZAPS
                                if let error = nwcResponse.error {
                                    L.og.info("⚡️ NWC response with error: \(error.code) - \(error.message)")
                                    if let eventId = awaitingZap.eventId {
                                        let message = "[Zap](nostur:e:\(eventId)) may have failed.\n\(error.message)"
                                        let notification = PersistentNotification.createFailedNWCZap(pubkey: NRState.shared.activeAccountPublicKey, message: message, context: self.bgQueue)
                                        NotificationsViewModel.shared.checkNeedsUpdate(notification)
                                        L.og.info("⚡️ Created notification: Zap failed for [post](nostur:e:\(eventId)). \(error.message)")
                                        if (SettingsStore.shared.nwcShowBalance) {
                                            nwcSendBalanceRequest()
                                        }
                                        if let ev = try? Event.fetchEvent(id: eventId, context: self.bgQueue) {
                                            ev.zapState = nil
                                        }
                                    }
                                    else {
                                        let message = "Zap may have failed for [contact](nostur:p:\(awaitingZap.contact.pubkey)).\n\(error.message)"
                                        let notification = PersistentNotification.createFailedNWCZap(pubkey: NRState.shared.activeAccountPublicKey, message: message, context: self.bgQueue)
                                        NotificationsViewModel.shared.checkNeedsUpdate(notification)
                                        L.og.info("⚡️ Created notification: Zap failed for [contact](nostur:p:\(awaitingZap.contact.pubkey)). \(error.message)")
                                    }
                                    NWCZapQueue.shared.removeZap(byId: awaitingZap.id)
                                    NWCRequestQueue.shared.removeRequest(byId: awaitingRequest.request.id)
                                    return
                                }
                                guard let result_type = nwcResponse.result_type, result_type == "pay_invoice" else {
                                    L.og.error("⚡️ Unknown or missing result_type, \(nwcResponse.result_type ?? "") - \(decrypted)")
                                    return
                                }
                                if let result = nwcResponse.result {
                                    L.og.info("⚡️ Zap success \(result.preimage ?? "-") - \(decrypted)")
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
                                    let notification = PersistentNotification.createFailedLightningInvoice(pubkey: NRState.shared.activeAccountPublicKey, message: message, context: self.bgQueue)
                                    NotificationsViewModel.shared.checkNeedsUpdate(notification)
                                    L.og.error("⚡️ Failed to pay lightning invoice. \(error.message)")
                                    NWCRequestQueue.shared.removeRequest(byId: awaitingRequest.request.id)
                                    return
                                }
                                guard let result_type = nwcResponse.result_type, result_type == "pay_invoice" else {
                                    L.og.error("⚡️ Unknown or missing result_type, \(nwcResponse.result_type ?? "") - \(decrypted)")
                                    return
                                }
                                if let result = nwcResponse.result {
                                    L.og.info("⚡️ Lighting Invoice Payment (Not Zap) success \(result.preimage ?? "-") - \(decrypted)")
                                    NWCRequestQueue.shared.removeRequest(byId: awaitingRequest.request.id)
                                    if (SettingsStore.shared.nwcShowBalance) {
                                        nwcSendBalanceRequest()
                                    }
                                    return
                                }
                            }
                            L.og.info("⚡️ NWC response not handled: \(nEvent.eventJson()) ")
                            return
                        }
                        
                        if let subscriptionId = message.subscriptionId, subscriptionId.prefix(5) == "prio-" {
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
                        else {
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
                }
            }
            catch RelayMessage.error.NOT_IN_WOT {
                L.sockets.debug("🟠 \(relayUrl) Not in WoT, skipped: \(text)")
            }
            catch RelayMessage.error.UNKNOWN_MESSAGE_TYPE {
                L.sockets.notice("🟠 \(relayUrl) Unknown message type: \(text)")
            }
            catch RelayMessage.error.FAILED_TO_PARSE {
                L.sockets.notice("🟠 \(relayUrl) Could not parse text received: \(text)")
            }
            catch RelayMessage.error.FAILED_TO_PARSE_EVENT {
                L.sockets.notice("🟠 \(relayUrl) Could not parse EVENT: \(text)")
            }
            catch RelayMessage.error.DUPLICATE_ALREADY_SAVED, RelayMessage.error.DUPLICATE_ALREADY_PARSED {
//                L.sockets.debug("🟡🟡 \(relayUrl) already SAVED/PARSED ")
            }
            catch RelayMessage.error.INVALID_SIGNATURE {
                L.sockets.notice("🔴🔴 \(relayUrl) invalid signature \(text)")
            }
            catch {
                L.sockets.info("🔴🔴 \(relayUrl) \(error)")
            }
        }        
    }
}
