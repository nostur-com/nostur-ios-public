//
//  MessageParser.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/01/2023.
//

import Foundation
import Collections

class MessageParser {
    
    static let shared = MessageParser()

    private var context = DataProvider.shared().bg
    private var sp = SocketPool.shared
    public var messageBucket = Deque<RelayMessage>()
    
    func socketReceivedMessage(text:String, relayUrl:String, client:NewWebSocket) {
        self.context.perform { [unowned self] in
            do {
                let message = try RelayMessage.parseRelayMessage(text: text, relay: relayUrl, skipValidation: true)
                
                switch message.type {
                case .AUTH:
                    L.sockets.info("🟢🟢 \(relayUrl): \(message.message)")
                case .OK:
                    L.sockets.debug("\(relayUrl): \(message.message)")
                    if message.success ?? false {
                        if let id = message.id {
                            Event.updateRelays(id, relays: message.relays)
                        }
                    }
                case .NOTICE:
                    L.sockets.notice("\(relayUrl): \(message.message)")
                case .EOSE:
                    // Keep these subscriptions open.
                    guard let subscriptionId = message.subscriptionId else { return }
                    if !["Following","Explore","Notifications","REALTIME-DETAIL", "REALTIME-DETAIL-A", "NWC", "NC"].contains(subscriptionId) && String(subscriptionId.prefix(5)) != "List-" {
                        // Send close message to this specific socket, not all.
                        L.sockets.debug("🔌🔌 EOSE received. Sending CLOSE to \(client.url) for \(subscriptionId)")
                        client.sendMessage(ClientMessage.close(subscriptionId: subscriptionId))
                    }
                    else {
                        L.sockets.debug("🔌🔌 EOSE received. keeping OPEN. \(client.url) for \(subscriptionId)")
                    }
                default:
                    if (message.type == .EVENT) {
                        guard let nEvent = message.event else { L.sockets.info("🔴🔴 uhh, where is nEvent "); return }
                        
                        if nEvent.kind == .ncMessage {
                            // Don't save to database, just handle response directly
                            DispatchQueue.main.async {
                                sendNotification(.receivedMessage, message)
                            }
                            return
                        }
                        
                        if nEvent.kind == .nwcResponse {
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
                                        _ = PersistentNotification.createFailedNWCZap(pubkey: NosturState.shared.activeAccountPublicKey, message: message, context: context)
                                        L.og.info("⚡️ Created notification: Zap failed for [post](nostur:e:\(eventId)). \(error.message)")
                                        if let ev = try? Event.fetchEvent(id: eventId, context: DataProvider.shared().bg) {
                                            ev.zapState = .none
                                            ev.zapStateChanged.send(.none)
                                        }
                                    }
                                    else {
                                        let message = "Zap may have failed for [contact](nostur:p:\(awaitingZap.contact.pubkey)).\n\(error.message)"
                                        _ = PersistentNotification.createFailedNWCZap(pubkey: NosturState.shared.activeAccountPublicKey, message: message, context: context)
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
                                    return
                                }
                            }
                            else {
                                // HANDLE OLD BOLT11 INVOICE PAYMENT
                                if let error = nwcResponse.error {
                                    let message = "Failed to pay lightning invoice.\n\(error.message)"
                                    _ = PersistentNotification.createFailedLightningInvoice(pubkey: NosturState.shared.activeAccountPublicKey, message: message, context: context)
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
                                    return
                                }
                            }
                            L.og.info("⚡️ NWC response not handled: \(nEvent.eventJson()) ")
                            return
                        }
                        
                        
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
                            Importer.shared.existingIds[event.id] = .PARSED
                            Importer.shared.addedRelayMessage.send()
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
            catch {
                L.sockets.debug("🔴🔴 \(relayUrl) \(error)")
            }
        }
    }
}
