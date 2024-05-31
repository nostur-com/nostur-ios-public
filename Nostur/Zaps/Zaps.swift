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
    
    let pTag = NostrTag(["p", pubkey])
    zapRequest.tags.append(pTag)
    
    if (eventId != nil) {
        let eTag = NostrTag(["e", eventId!])
        zapRequest.tags.append(eTag)
    }
    
    let relaysTag = NostrTag(["relays"] + relays)
    zapRequest.tags.append(relaysTag)
    
    return zapRequest
}


extension Event {
    // Homegrown bolt11 amount decoder because LightningDevKit is slow and don't know why
    // Also Homegrown parsing of serializedTags because EventTags.init slow...
    var naiveSats: Double {
        guard let bolt11 = naiveBolt11() else { return 0.0 }
        return naiveBolt11AmountDecoder(bolt11)
    }
}


extension Contact {
    var anyLud:Bool {
        (lud16 != nil && lud16 != "") || (lud06 != nil && lud06 != "")
    }
}


func naiveBolt11AmountDecoder(_ test:String) -> Double {
    guard test.prefix(4) == "lnbc" else { return 0.0 }
    let noPrefix = test.dropFirst(4)
    
    let digitSet = CharacterSet.decimalDigits

    if let range = noPrefix.rangeOfCharacter(from: digitSet.inverted) {
        let nonDigitChar = noPrefix[range.lowerBound]
        guard ["m","u","n","p"].firstIndex(of: nonDigitChar) != nil else { return 0.0 }
        let nonDigitIndex = noPrefix.distance(from: noPrefix.startIndex, to: range.lowerBound)
        switch nonDigitChar {
                // 1 BTC = 100000000 SATS
                // 1 SAT = 1000 mSATS
            case "m":
                return (Double(noPrefix.prefix(nonDigitIndex)) ?? 0.0) * 100000
            case "u":
                return (Double(noPrefix.prefix(nonDigitIndex)) ?? 0.0) * 100
            case "n":
                return (Double(noPrefix.prefix(nonDigitIndex)) ?? 0.0) * 0.1
            case "p":
                // BOLT11: If the p multiplier is used the last decimal of amount MUST be 0.
                guard noPrefix.prefix(nonDigitIndex).suffix(1) == "0" else { return 0.0 }
                return (Double(noPrefix.prefix(nonDigitIndex)) ?? 0.0) * 0.0001
            default:
                return 0.0
        }
    }
    return 0.0
}
