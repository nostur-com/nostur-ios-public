//
//  RelayMessage.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/07/2023.
//

import Foundation

// Messages received from relay EVENT/EOSE/NOTICE
class RelayMessage {
    
    enum type:String {
        case EVENT
        case NOTICE
        case EOSE
        case OK
        case AUTH
    }
    
    enum error:Error {
        case FAILED_TO_PARSE // Failed to parse raw websocket
        case UNKNOWN_MESSAGE_TYPE // NOT EVENT, NOTICE or EOSE
        case FAILED_TO_PARSE_EVENT // Could parse raw websocket but not event
        case DUPLICATE_ID // We already received this message (in cache, not db, db check is later)
    }
    
    var relays:String // space seperated relays
    var type:RelayMessage.type?
    var message:String
    var subscriptionId:String?
    var event:NEvent?
    
    var id:String?
    var success:Bool?
    
    init(relays:String, type: RelayMessage.type? = nil, message: String, subscriptionId: String? = nil,
         id:String? = nil, success:Bool? = nil, event:NEvent? = nil) {
        self.relays = relays
        self.type = type
        self.message = message
        self.subscriptionId = subscriptionId
        self.event = event
        
        self.id = id
        self.success = success
    }
    
    static func parseRelayMessage(text:String, relay:String, skipValidation:Bool = false) throws -> RelayMessage {
        guard let dataFromString = text.data(using: .utf8, allowLossyConversion: false) else {
            throw error.FAILED_TO_PARSE
        }
        
        guard text.prefix(7) != ###"["EOSE""### else {
            let decoder = JSONDecoder()
            guard let eose = try? decoder.decode(NMessage.self, from: dataFromString) else {
                throw error.FAILED_TO_PARSE
            }
            return RelayMessage(relays:relay, type: .EOSE, message: text, subscriptionId: eose.subscription)
        }
        
        guard text.prefix(7) != ###"["AUTH""### else {
            return RelayMessage(relays:relay, type: .AUTH, message: text)
        }
        
        guard text.prefix(9) != ###"["NOTICE""### else {
            return RelayMessage(relays:relay, type: .NOTICE, message: text)
        }
        
        guard text.prefix(5) != ###"["OK""### else {
            let decoder = JSONDecoder()
            guard let result = try? decoder.decode(CommandResult.self, from: dataFromString) else {
                throw error.FAILED_TO_PARSE
            }
            return RelayMessage(relays:relay, type: .OK, message: text, id:result.id, success:result.success)
        }
        
        guard text.prefix(8) == ###"["EVENT""### else {
            throw error.UNKNOWN_MESSAGE_TYPE
        }
        
        let decoder = JSONDecoder()
        
        // Try to get just the ID so if it is duplicate we don't parse whole event for nothing
        if let mMessage = try? decoder.decode(MinimalMessage.self, from: dataFromString) {
            if let eventState = Importer.shared.existingIds[mMessage.id] {

                if eventState == .SAVED {
                    Importer.shared.callbackSubscriptionIds.insert(mMessage.subscriptionId)
                    Importer.shared.sendReceivedNotification.send()
                    
                    // update from which relays an event id was received, or relay feeds won't work.
                    Event.updateRelays(mMessage.id, relays: relay)
                }
                
                if eventState == .PARSED {
                    let sameMessageInQueue = MessageParser.shared.messageBucket.first(where: {
                         mMessage.id == $0.event?.id && $0.type == .EVENT
                    })
                    
                    if let sameMessageInQueue {
                        sameMessageInQueue.relays = sameMessageInQueue.relays + " " + relay
                    }
                }
                
                // We should always notify if we received a contact list this session, to enable Follow button
                if mMessage.pubkey == NosturState.shared.activeAccountPublicKey && mMessage.kind == 3 { // To enable Follow button we need to have received a contact list
                    DispatchQueue.main.async {
                        FollowingGuardian.shared.didReceiveContactListThisSession = true
                    }
                }
                
                throw "error.DUPLICATE_ID \(Importer.shared.existingIds[mMessage.id] ?? .UNKNOWN)"
            }
            else {
                Importer.shared.existingIds[mMessage.id] = .RECEIVED
            }
        }
    
        guard var relayMessage = try? decoder.decode(NMessage.self, from: dataFromString) else {
            throw error.FAILED_TO_PARSE
        }

        guard let nEvent = relayMessage.event else {
            throw "WHERES THE PAYLOAD BRO"
        }
        
        guard try skipValidation || nEvent.verified() else {
            print("🟣\(relayMessage)")
            throw "🔴🔴🔴 NO VALID SIG 🔴🔴🔴 "
        }
        
        return RelayMessage(relays:relay, type: .EVENT, message: text, subscriptionId: relayMessage.subscription, event: nEvent)
    }
}

struct MinimalMessage: Decodable {
    var container:UnkeyedDecodingContainer
    
    let subscriptionId:String
    let id:String
    let kind:Int
    let pubkey:String
    var relays:String = ""

    init(from decoder: Decoder) throws {
        container = try decoder.unkeyedContainer()
        _ = try container.decode(String.self) // Discard "EVENT"
        subscriptionId = try container.decode(String.self) // for handling callbacks
        let minimalevent = try container.decode(MinimalEvent.self)
        id = minimalevent.id
        kind = minimalevent.kind
        pubkey = minimalevent.pubkey
    }
}

// Instead of full NEvent, this is a minimal one to reduce parsing of duplicate events
// We need:
// - id to check duplicates
// - kind + pubkey to know if we received our contact list this session
struct MinimalEvent: Decodable {
    let id:String
    let kind:Int
    let pubkey:String
}
