//
//  Zaps.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/02/2023.
//

import Foundation
import CryptoKit
import NostrEssentials

func zapRequest(forPubkey pubkey: String, andEvent eventId: String? = nil, andATag aTag: String? = nil, withMessage message:String = "", relays: [String]) -> NEvent {
    var zapRequest = NEvent(content: message)
    zapRequest.kind = .zapRequest
    
    let pTag = NostrTag(["p", pubkey])
    zapRequest.tags.append(pTag)
    
    if let eventId {
        let eTag = NostrTag(["e", eventId])
        zapRequest.tags.append(eTag)
    }
    else if let aTag {
        let aTag = NostrTag(["a", aTag])
        zapRequest.tags.append(aTag)
    }
    
    let relaysTag = NostrTag(["relays"] + relays)
    zapRequest.tags.append(relaysTag)
    
    return zapRequest
}

func privateZapRequest(
    forPubkey pubkey: String,
    senderPrivateKey: String? = nil, // keep nil for anon zap
    senderPubkey: String, // needed to exclude client tag or not
    andEvent eventId: String? = nil,
    andATag aTag: String? = nil,
    withMessage message: String = "",
    relays: [String]
) -> NEvent? {
    let privateZapSenderKeys = if let senderPrivateKey {
        try? Keys(privateKeyHex: senderPrivateKey)
    }
    else {
        try? Keys.newKeys()
    }
    
    guard let privateZapSenderKeys else { return nil }
    
    var targetTags = [NostrTag(["p", pubkey])]
    if let eventId {
        targetTags.append(NostrTag(["e", eventId]))
    }
    else if let aTag {
        targetTags.append(NostrTag(["a", aTag]))
    }

    var privateZapEvent = NEvent(content: message)
    privateZapEvent.kind = .custom(9733)
    privateZapEvent.tags.append(contentsOf: targetTags)
    
    if (SettingsStore.shared.postUserAgentEnabled && !SettingsStore.shared.excludedUserAgentPubkeys.contains(senderPubkey)) {
        privateZapEvent.tags.append(NostrTag(["client", NIP89_APP_NAME, NIP89_APP_REFERENCE]))
    }
    
    guard let signedPrivateZapEvent = try? privateZapEvent.sign(privateZapSenderKeys) else { return nil }
#if DEBUG
    L.og.debug("⚡️⚡️ 9733: \(signedPrivateZapEvent.eventJson()) -[LOG]-")
#endif
    
    let targetIdForDeterministicKey = eventId ?? aTag ?? pubkey
    let zapRequestCreatedAt = NTimestamp(date: .now)
    let zapRequestKeys = if let senderPrivateKey {
        deterministicPrivateZapRequestKeys(
            senderPrivateKey: senderPrivateKey,
            targetId: targetIdForDeterministicKey,
            createdAt: zapRequestCreatedAt.timestamp
        )
    }
    else {
        try? Keys.newKeys()
    }
    
    guard let zapRequestKeys else { return nil }
    guard let encryptedPrivateZap = Keys.encryptDirectMessageContent(
        withPrivatekey: zapRequestKeys.privateKeyHex,
        pubkey: pubkey,
        content: signedPrivateZapEvent.eventJson()
    ) else { return nil }
    
    let components = encryptedPrivateZap.components(separatedBy: "?iv=")
    guard components.count == 2,
          let ciphertext = Data(base64Encoded: components[0]),
          let iv = Data(base64Encoded: components[1])
    else { return nil }
    
    let bech32 = Bech32()
    let encodedCiphertext = bech32.encode("pzap", values: ciphertext, eightToFive: true)
    let encodedIv = bech32.encode("iv", values: iv, eightToFive: true)
    
    var zapRequest = NEvent(content: "")
    zapRequest.kind = .zapRequest
    zapRequest.createdAt = zapRequestCreatedAt
    zapRequest.tags.append(contentsOf: targetTags)
    
    zapRequest.tags.append(NostrTag(["relays"] + relays))
    zapRequest.tags.append(NostrTag(["anon", "\(encodedCiphertext)_\(encodedIv)"]))
    return try? zapRequest.sign(zapRequestKeys)
}

private func deterministicPrivateZapRequestKeys(
    senderPrivateKey: String,
    targetId: String,
    createdAt: Int
) -> Keys? {
    let toHash = senderPrivateKey + targetId + String(createdAt)
    let hashed = SHA256.hash(data: Data(toHash.utf8))
    return try? Keys(privateKeyHex: String(bytes: hashed.bytes))
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


func naiveBolt11AmountDecoder(_ test: String) -> Double {
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


extension NEvent {
    // Homegrown bolt11 amount decoder because LightningDevKit is slow and don't know why
    // Also Homegrown parsing of serializedTags because EventTags.init slow...
    var naiveSats: Double {
        guard let bolt11 = bolt11() else { return 0.0 }
        return naiveBolt11AmountDecoder(bolt11)
    }
    
}
