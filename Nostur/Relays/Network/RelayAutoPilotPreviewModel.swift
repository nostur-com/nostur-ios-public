//
//  RelayAutoPilotPreviewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/01/2025.
//

import SwiftUI
import NostrEssentials

class RelayAutoPilotPreviewModel: ObservableObject {
    
    @Published var relays: [String] = []

    func runCheck(_ nEvent: NEvent) {
        
        let message = NosturClientMessage(
            clientMessage: NostrEssentials.ClientMessage(type: .EVENT, event: nEvent.toNostrEssentialsEvent()),
            relayType: .WRITE,
            nEvent: nEvent
        )
        
        guard let preferredRelays = ConnectionPool.shared.preferredRelays else {
            self.relays = []
#if DEBUG
            L.og.debug("🔴🔴 No .preferredRelays")
#endif
            return
        }
        
        if !preferredRelays.reachUserRelays.isEmpty {
            // don't send to p's if it is an event kind where p's have a different purpose than notification (eg kind:3)
            guard (message.clientMessage.event?.kind ?? 1) != 3 else { return }
            
            
            guard let messageString = message.clientMessage.json() else {
#if DEBUG
                L.og.debug("🔴🔴 No messageString")
#endif
                self.relays = []
                return
            }
                        
            let pTags: Set<String> = Set( message.clientMessage.event?.tags.filter { $0.type == "p" }.compactMap { $0.pubkey } ?? [] )
            guard !pTags.isEmpty else {
#if DEBUG
                L.og.debug("🔴🔴 No pTags")
#endif
                self.relays = []
                return
            }

            self.relays = Array(ConnectionPool.shared.previewOthersPreferredReadRelays(message.clientMessage, pubkeys: pTags))
        }
        else {
#if DEBUG
            L.og.debug("🔴🔴 No .reachUserRelays")
#endif
        }
    }
}
