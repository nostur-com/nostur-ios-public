//
//  Zaps.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/02/2023.
//

import Foundation



func zapRequest(forPubkey pubkey: String, andEvent eventId: String? = nil, withMessage message:String = "", relays:[String]) -> NEvent {
    var zapRequest = NEvent(content:message)
    zapRequest.kind = .zapRequest
    
    let pTag = NEventTag(type: "p", otherInformation: pubkey)
    zapRequest.tags.append(pTag)
    
    if (eventId != nil) {
        let eTag = NEventTag(type: "e", otherInformation: eventId)
        zapRequest.tags.append(eTag)
    }
    
    let relaysTag = NEventTag(type: "relays", otherInformation: relays)
    zapRequest.tags.append(relaysTag)
    
    return zapRequest
}
