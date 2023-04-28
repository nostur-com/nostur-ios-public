//
//  MessageParser.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/01/2023.
//

import Foundation

class MessageParser {
    
    static let shared = MessageParser()

    var sp = SocketPool.shared
    var messageBucket = MessageBucket()
    
    func socketReceivedMessage(text:String, relayUrl:String) {
        do {
            //            ThreadWarning.which("socketReceivedMessage")
            // Validation is CPU intensive. Moved it to Importer right before save step
            // so we dont waste cpu on duplicates etc
            guard let message = try? RelayMessage.parseRelayMessage(text: text, relay: relayUrl, skipValidation: true) else {
                print("🚒🚒🚒 \(relayUrl) could not parse message. or verify sig: \(text)")
                throw "could not parse message. or verify sig"
            }
            
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
                    if !["Following","Explore","Notifications"].contains(subscriptionId) && String(subscriptionId.prefix(5)) != "List-" {
                        sp.sendMessage(ClientMessage(type: .CLOSE, message: ClientMessage.close(subscriptionId: subscriptionId)))
                    }
                default:
                    if (message.type == .EVENT) {
                        guard let nEvent = message.event else { print("🔴🔴 uhh, where is nEvent "); return }
                        
                        Task { [weak self] in
                            guard let self = self else { return }
                            
                            let queuedMessages:[RelayMessage] = self.messageBucket.all()
                            let sameMessageInQueue = queuedMessages
                                .filter { $0.type == .EVENT }
                                .compactMap { $0.event?.id }
                                .firstIndex(of: nEvent.id )
                            if (sameMessageInQueue != nil) {
                                // print("🧜🧜 Message already in queue. skipped. \(message.event!.id)")
                                return
                            }
                            else {
                                self.messageBucket.addMessage(message)
                                
                                if (nEvent.kind == .textNote || nEvent.kind == .reaction) {
                                    
                                    if (message.subscriptionId == nil) {
                                        print("WHERE IS SUBSCRIPTION ID BRO")
                                        return
                                    }
                                    
                                    // TIMESTAMP TRACKING NOT COULD ENOUGH, BECAUSE  NEED TO FETCH OLDER EVENTS SOMETIMES
                                    // MAYBE EXCLUDE FROM TRACKING BY SUBSCRIPTION ID.
                                    // DISABLE FOR NOW...
                                    // ----
                                    // don't remember if timestamp is in the future:
                                    guard let subscriptionId = message.subscriptionId else { return }
                                    if subscriptionId.prefix(3) == "TL-" && nEvent.createdAt.timestamp > Int(Date().timeIntervalSince1970) {
                                        return
                                    }
                                }
                            }
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
