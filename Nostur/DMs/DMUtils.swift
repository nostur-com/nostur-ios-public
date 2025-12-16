//
//  DMUtils.swift
//  Nostur
//
//  Created by Fabian Lachman on 16/12/2025.
//

import Foundation
import NostrEssentials

func getDMrelays(for pubkey: String) async -> Set<String> {
    let relays: Set<String> = await withBgContext { bgContext in
        if let dmRelaysEvent = Event.fetchEventsBy(pubkey: pubkey, andKind: 10050, context: bgContext).first {
            let relays = dmRelaysEvent.fastTags.filter { $0.0 == "relay" }
                .compactMap { $0.1 }
                .map { normalizeRelayUrl($0) }
            if !relays.isEmpty {
                return Set(relays)
            }
            return []
        }
        return []
    }
    return relays
}

func shouldShowUpgradeNotice(accountPubkey: String) async -> Bool {
    return await !hasDMrelays(pubkey: accountPubkey)
}

func hasDMrelays(pubkey: String) async -> Bool {
    let dmRelays = await getDMrelays(for: pubkey)
    if !dmRelays.isEmpty {
        return true
    }
    return false
}

func convertToHieroglyphs(text: String) -> String {
    let hieroglyphs: [Character] =  ["𓀀", "𓀁", "𓀂", "𓀃", "𓀄", "𓀅", "𓀆", "𓀇", "𓀈", "𓀉", "𓀊", "𓀋", "𓀌",
                                     "𓀍", "𓀎", "𓀏", "𓀐", "𓀑", "𓀒", "𓀓", "𓀔", "𓀕", "𓀖", "𓀗", "𓀘", "𓀙",
                                     "𓀚", "𓀛", "𓀜", "𓀝", "𓀞", "𓀟", "𓀠", "𓀡", "𓀢", "𓀣", "𓀤", "𓀥", "𓀦",
                                     "𓀧", "𓀨", "𓀩", "𓀪", "𓀫", "𓀬", "𓀭", "𓀮", "𓀯", "𓀰", "𓀱", "𓀲", "𓀳",
                                     "𓀴", "𓀵", "𓀶", "𓀷", "𓀸", "𓀹", "𓀺", "𓀻", "𓀼", "𓀽", "𓀾", "𓀿", "𓁀",
                                     "𓁁", "𓁂", "𓁃", "𓁄", "𓁅", "𓁆", "𓁇", "𓁈", "𓁉", "𓁊", "𓁋", "𓁌", "𓁍",
                                     "𓁎", "𓁏", "𓁐", "𓁑", "𓁒", "𓁓", "𓁔", "𓁕", "𓁖", "𓁗", "𓁘", "𓁙", "𓁚",
                                     "𓁛", "𓁜", "𓁝", "𓁞", "𓁟", "𓁠", "𓁡", "𓁢", "𓁣", "𓁤", "𓁥", "𓁦", "𓁧",
                                     "𓁨", "𓁩", "𓁪", "𓁫", "𓁬", "𓁭", "𓁮", "𓁯", "𓁰"]
    let outputLength = Int.random(in: 7..<20)
    var outputString = ""
    
    for _ in 0..<outputLength {
        let randomIndex = Int.random(in: 0..<hieroglyphs.count)
        outputString.append(hieroglyphs[randomIndex])
    }
    
    return outputString
}
