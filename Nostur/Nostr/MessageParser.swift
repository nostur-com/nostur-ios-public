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
    var parsedBucket = ActorQueue<RelayMessage>()
    
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
                        sp.sendMessage(ClientMessage(type: .CLOSE, message: ClientMessage.close(subscriptionId: message.subscriptionId!)))
                    }
                default:
                    if (message.type == .EVENT) {
                        
                        Task { [weak self] in
                            guard let self = self else { return }
                            
                            let queuedMessages:[RelayMessage] = await self.parsedBucket.all()
                            let sameMessageInQueue = queuedMessages.filter { $0.type == .EVENT }
                                .map { $0.event!.id }.firstIndex(of: message.event!.id )
                            if (sameMessageInQueue != nil) {
                                //                        print("🧜🧜 Message already in queue. skipped. \(message.event!.id)")
                                return
                            }
                            else {
                                await self.parsedBucket.enqueue(message) // Wrap in _ = Task {}?
                                
                                if (message.event?.kind == .textNote || message.event?.kind == .reaction) {
                                    
                                    if (message.subscriptionId == nil) {
                                        print("WHERE IS SUBSCRIPTION ID BRO")
                                        return
                                    }
                                    
                                    // TIMESTAMP TRACKING NOT COULD ENOUGH, BECAUSe NEED TO FETCH OLDER EVENTS SOMETIMES
                                    // MAYBE EXCLUDE FROM TRACKING BY SUBSCRIPTION ID.
                                    // DISABLE FOR NOW...
                                    // ----
                                    // don't remember if timestamp is in the future:
                                    if message.subscriptionId!.prefix(3) == "TL-" && message.event!.createdAt.timestamp > Int(Date().timeIntervalSince1970) {
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
