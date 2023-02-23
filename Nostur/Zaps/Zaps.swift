//
//  Zaps.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/02/2023.
//

import Foundation
import LightningDevKit


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


extension Event {
    var bolt11Invoice:Invoice? {
        get {
            guard let bolt11 = bolt11() else { return nil }
            if let pInvoice = Invoice.fromStr(s: bolt11).getValue() {
                return pInvoice
            }
            return nil
        }
    }
    
    // THE AMOUNT PAID
    var sats:Double {
        get {
            guard bolt11Invoice != nil else { return 0 }
            if (bolt11Invoice!.amountMilliSatoshis() != nil) {
                return Double(bolt11Invoice!.amountMilliSatoshis()!)/1000
            }
            return 0
        }
    }
}
