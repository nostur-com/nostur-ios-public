//
//  NosturClientMessage.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/06/2024.
//

import Foundation
import NostrEssentials

// Original ClientMessage (from Nostur) has Nostur specific things. Generic ClientMessage from NostrEssentials is missing Nostur stuff
// This NosturClientMessage wraps generic NostrEssentials in NosturClientMessage so can reuse all the generic stuff and still make
// use of the Nostur specific stuff

public struct NosturClientMessage {
    
    public init(clientMessage: NostrEssentials.ClientMessage, onlyForNWCRelay: Bool = false, onlyForNCRelay: Bool = false, relayType: RelayType, message: String? = nil, nEvent: NEvent? = nil) {
        self.clientMessage = clientMessage
        self.onlyForNWCRelay = onlyForNWCRelay
        self.onlyForNCRelay = onlyForNCRelay
        self.relayType = relayType
        self._message = message // message usually for writing ["EVENT", {...}]
        self.nEvent = nEvent // Need this cause we can't use NostrEssentials.Event in .clientMessage (yet)
    }
    
    // Generic NostrEssentials ClientMessage
    public let clientMessage: NostrEssentials.ClientMessage // This one has [Filters] needed for Outbox stuff. Can't use ._message for that
    
    
    // Nostur specific stuff
    public var onlyForNWCRelay: Bool = false
    public var onlyForNCRelay: Bool = false
    public var relayType: RelayType
    public var _message: String? = nil // message usually for writing ["EVENT", {...}]
    public var nEvent: NEvent? = nil // Need to use this because Nostur doesn't use NostrEssentials.Event
    
    // Wrapping/Adapter stuff to make Nostur code work with NostrEssentals code
    public var message: String {
        if type == .EVENT, let nEvent = nEvent {
            return nEvent.wrappedEventJson()
        }
        return (_message ?? clientMessage.json()) ?? ""
    }
    
    public var type: NostrEssentials.ClientMessage.ClientMessageType {
        clientMessage.type
    }
    
    public enum RelayType {
        case READ
        case WRITE
        case SEARCH
        case SEARCH_ONLY // no .read
    }
    
    static func close(subscriptionId: String) -> String {
        return "[\"CLOSE\", \"\(subscriptionId)\"]"
    }
    
    static func event(event: NEvent) -> String {
        return "[\"EVENT\",\(event.eventJson())]"
    }
    
    static func auth(event: NEvent) -> String {
        return "[\"AUTH\",\(event.eventJson())]"
    }
}
