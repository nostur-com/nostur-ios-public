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
                            Event.updateRelays(id, relay: message.relay)
                        }
                    }
                case .NOTICE:
                    L.sockets.notice("\(relayUrl): \(message.message)")
                case .EOSE:
                    // Keep these subscriptions open.
                    guard let subscriptionId = message.subscriptionId else { return }
                    if !["Following","Explore","Notifications","REALTIME-DETAIL","NWC", "NC"].contains(subscriptionId) && String(subscriptionId.prefix(5)) != "List-" {
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
                        
                        let sameMessageInQueue = self.messageBucket.contains(where: { // TODO: Instruments: slow here...
                             nEvent.id == $0.event?.id && $0.type == .EVENT
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
                L.sockets.notice("🟠 \(relayUrl) Unknown message type: \(text)")
            }
            catch RelayMessage.error.FAILED_TO_PARSE {
                L.sockets.notice("🟠 \(relayUrl) Could not parse text received: \(text)")
            }
            catch RelayMessage.error.FAILED_TO_PARSE_EVENT {
                L.sockets.notice("🟠 \(relayUrl) Could not parse EVENT: \(text)")
            }
            catch {
                L.sockets.error("🔴🔴 \(relayUrl) \(error)")
            }
        }
    }
}
