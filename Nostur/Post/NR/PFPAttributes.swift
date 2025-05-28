//
//  PFPAttributes.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/05/2025.
//

import SwiftUI
import Combine

class PFPAttributes: ObservableObject, Equatable, Identifiable {
    
    static func == (lhs: PFPAttributes, rhs: PFPAttributes) -> Bool {
        return lhs.pubkey == rhs.pubkey
    }
    
    @Published var contact: NRContact? = nil
    private var contactUpdatedSubscription: AnyCancellable?
    public let pubkey: String
    public var id: String { pubkey }
    
    public var anyName: String {
        contact?.anyName ?? String(pubkey.suffix(11))
    }
    
    public var pfpURL: URL? {
        contact?.pictureUrl
    }
        
    init(contact: NRContact? = nil, pubkey: String) {
        self.contact = contact
        self.pubkey = pubkey
        self.similarToPubkey = contact?.similarToPubkey
        
        if Thread.isMainThread {
            if contact == nil {
                bg().perform {
#if DEBUG
                    L.og.debug("🏓🏓 PFPAttributes.init NRContact.fetch()")
#endif
                    if let nrContact = NRContact.fetch(pubkey, context: bg()) {
                        Task { @MainActor in
                            if self.contact == nil {
                                self.contact = nrContact
                            }
                        }
                    }
                }
            }
        }
        
        if contact == nil {
            contactUpdatedSubscription = ViewUpdates.shared.contactUpdated
                .filter { pubkey == $0.0 }
                .sink(receiveValue: { [weak self] (_, contact) in
                    bg().perform {
                        let nrContact = NRContact.instance(of: contact.pubkey, contact: contact)
                        Task { @MainActor [weak self] in
                            withAnimation {
                                self?.contact = nrContact
                            }
                            self?.similarToPubkey = nrContact.similarToPubkey
                        }
                    }
                    self?.contactUpdatedSubscription?.cancel()
                    self?.contactUpdatedSubscription = nil
                })
        }
    }
    
    
    @Published var similarToPubkey: String? = nil
    private var didRunImposterCheck = false
    
    func runImposterCheck(_ nrContact: NRContact? = nil) {
        bg().perform { [weak self] in
            guard let self, let nrContact = (contact ?? nrContact) ?? NRContact.fetch(pubkey)
            else { return }
            
            // Make sure passed in nrContact is same .pubkey
            guard nrContact.pubkey == pubkey else { return }
            guard nrContact.couldBeImposter == -1 else {
                if nrContact.couldBeImposter == 1 {
                    Task { @MainActor in
                        self.similarToPubkey = nrContact.similarToPubkey
                    }
                }
                return
            }
            
            didRunImposterCheck = true
            ImposterChecker.shared.runImposterCheck(nrContact: nrContact) { imposterYes in
                Task { @MainActor in
                    self.similarToPubkey = imposterYes.similarToPubkey
                }
            }
        }
    }
}
