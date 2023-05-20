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
                    print("🟢🟢 \(relayUrl): \(message.message)")
                case .OK:
                    print("\(relayUrl): \(message.message)")
                    if message.success ?? false {
                        if let id = message.id {
                            Event.updateRelays(id, relay: message.relay)
                        }
                    }
                case .NOTICE:
                    print("\(relayUrl): \(message.message)")
                case .EOSE:
                    // Keep these subscriptions open.
                    guard let subscriptionId = message.subscriptionId else { return }
                    if !["Following","Explore","Notifications","REALTIME-DETAIL"].contains(subscriptionId) && String(subscriptionId.prefix(5)) != "List-" {
                        // Send close message to this specific socket, not all.
                        client.sendMessage(ClientMessage.close(subscriptionId: subscriptionId))
                    }
                default:
                    if (message.type == .EVENT) {
                        guard let nEvent = message.event else { print("🔴🔴 uhh, where is nEvent "); return }
                        
                        let sameMessageInQueue = self.messageBucket.contains(where: {
                            $0.type == .EVENT && nEvent.id == $0.event?.id
                        })
                        if (sameMessageInQueue) {
                            return
                        }
                        else {
                            self.messageBucket.append(message)
                            Importer.shared.addedRelayMessage.send()
                        }
                    }
                }
            }
            catch RelayMessage.error.UNKNOWN_MESSAGE_TYPE {
                print("🟠 \(relayUrl) Unknown message type: \(text)")
            }
            catch RelayMessage.error.FAILED_TO_PARSE {
                print("🟠 \(relayUrl) Could not parse text received: \(text)")
            }
            catch RelayMessage.error.FAILED_TO_PARSE_EVENT {
                print("🟠 \(relayUrl) Could not parse EVENT: \(text)")
            }
            catch {
                print("🔴🔴 \(relayUrl) \(error)")
            }
        }
    }
}
