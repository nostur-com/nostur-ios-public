////
////  PFPAttributes.swift
////  Nostur
////
////  Created by Fabian Lachman on 28/05/2025.
////
//
//import SwiftUI
//import Combine
//
//class PFPAttributes: ObservableObject, Equatable, Identifiable {
//    
//    static func == (lhs: PFPAttributes, rhs: PFPAttributes) -> Bool {
//        return lhs.pubkey == rhs.pubkey
//    }
//    
//    @Published var contact: NRContact? = nil
//    private var contactUpdatedSubscription: AnyCancellable?
//    private var labelToggleSubscription: AnyCancellable?
//    public let pubkey: String
//    public var id: String { pubkey }
//    
//    public var anyName: String {
//        contact?.anyName ?? String(pubkey.suffix(11))
//    }
//    
//    public var pfpURL: URL? {
//        contact?.pictureUrl
//    }
//        
//    init(contact: NRContact? = nil, pubkey: String) {
//        self.contact = contact
//        self.pubkey = pubkey
//        self.similarToPubkey = contact?.similarToPubkey
//        
//        if self.similarToPubkey != nil {
//            self.didRunImposterCheck = true
//        }
//        
//        if Thread.isMainThread {
//            if contact == nil {
//                bg().perform {
//#if DEBUG
//                    L.og.debug("🏓🏓 PFPAttributes.init NRContact.fetch(): \(pubkey)")
//#endif
//                    if let nrContact = NRContact.fetch(pubkey, context: bg()) {
//                        Task { @MainActor in
//                            if self.contact == nil {
//                                self.contact = nrContact
//                                self.similarToPubkey = nrContact.similarToPubkey
//                                
//                                if self.similarToPubkey != nil {
//                                    self.didRunImposterCheck = true
//                                }
//                            }
//                        }
//                    }
//                }
//            }
//        }
//        
//        if contact == nil {
//            contactUpdatedSubscription = ViewUpdates.shared.contactUpdated
//                .filter { pubkey == $0.0 }
//                .sink(receiveValue: { [weak self] (_, contact) in
//                    bg().perform {
//                        let nrContact = NRContact.instance(of: contact.pubkey, contact: contact)
//                        Task { @MainActor [weak self] in
//                            withAnimation {
//                                self?.contact = nrContact
//                            }
//                            self?.similarToPubkey = nrContact.similarToPubkey
//                            if self?.similarToPubkey != nil {
//                                self?.didRunImposterCheck = true
//                            }
//                        }
//                    }
//                    self?.contactUpdatedSubscription?.cancel()
//                    self?.contactUpdatedSubscription = nil
//                })
//        }
//    }
//    
//    
//    @Published var similarToPubkey: String? = nil // {
////        didSet {
////            if similarToPubkey == nil { // After removing imposter label, add listener to toggle back on
////                labelToggleSubscription = contact?.similarToPubkey.publisher.sink { similarToPubkey in
////                    self.similarToPubkey = similarToPubkey
////                }
////            }
////        }
////    }
//    private var didRunImposterCheck = false
//    
//    func runImposterCheck(_ nrContact: NRContact? = nil) {
//        guard !didRunImposterCheck else { return }
//        bg().perform { [weak self] in
//            guard let didRunImposterCheck = self?.didRunImposterCheck, !didRunImposterCheck else { return }
//            guard let self, let nrContact = (contact ?? nrContact) ?? NRContact.fetch(pubkey)
//            else { return }
//            
//            // Make sure passed in nrContact is same .pubkey
//            guard nrContact.pubkey == pubkey else { return }
//            guard nrContact.couldBeImposter == -1 else {
//                if nrContact.couldBeImposter == 1 {
//                    Task { @MainActor in
//                        self.similarToPubkey = nrContact.similarToPubkey
//                        self.didRunImposterCheck = true
//                    }
//                }
//                return
//            }
//            
//            self.didRunImposterCheck = true
//            ImposterChecker.shared.runImposterCheck(nrContact: nrContact) { imposterYes in
//                Task { @MainActor in
//                    self.similarToPubkey = imposterYes.similarToPubkey
//                }
//            }
//        }
//    }
//}
