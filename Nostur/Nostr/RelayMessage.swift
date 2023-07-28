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
        guard let relayMessage = try? decoder.decode(NMessage.self, from: dataFromString) else {
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
