//
//  CouldBeImposterViewModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/02/2025.
//

import SwiftUI

class CouldBeImposterViewModel: ObservableObject {
    
    @Published var couldBeImposter: Bool = false
    
    @MainActor
    public func runCheck(_ nrContact: NRContact) {
        guard let la = AccountsState.shared.loggedInAccount else { return }
        guard la.account.publicKey != nrContact.pubkey else { return }
        guard !la.isFollowing(pubkey: nrContact.pubkey) else { return }
        if nrContact.couldBeImposter == 1 {
            self.couldBeImposter = true
            return
        }
        
        guard nrContact.couldBeImposter == -1 else { return }
        
        ImposterChecker.shared.runImposterCheck(nrContact: nrContact) { [weak self] imposterYes in
            self?.couldBeImposter = true
        }
    }
}
