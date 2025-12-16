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
