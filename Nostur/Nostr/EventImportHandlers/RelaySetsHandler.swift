//
//  RelaySetsHandler.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/12/2025.
//

import Foundation
import CoreData
import NostrEssentials

// Remove upgrade notice if we already have DM relays configures
func handleRelaySets(nEvent: NEvent, savedEvent: Event, context: NSManagedObjectContext) {
    guard nEvent.kind == .init(id: 10050) else { return }
    
    if nEvent.publicKey == AccountsState.shared.activeAccountPublicKey {
        Task { @MainActor in
            DMsVM.shared.showUpgradeNotice = false
        }
    }
    
}
