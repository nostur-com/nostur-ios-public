//
//  ProfileLightningButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/02/2023.
//

import SwiftUI

struct ProfileLightningButton: View {
    @EnvironmentObject private var themes: Themes
    
    public var nrContact: NRContact?
    public var zapEtag: String?
    
    @State private var isLoading = false
    @State private var payAmountSelectorShown = false
    @State private var paymentInfo: PaymentInfo?
    
    var body: some View {
//        let _ = Self._printChanges()
        Button {
            buttonTapped()
        } label: {
            if isLoading {
                ProgressView()
                    .colorInvert()
            }
            else {
                Image(systemName: "bolt.fill")
            }
        }
        .buttonStyle(NosturButton())
//        .frame(width: 40, height: 30)
//        .font(.caption.weight(.heavy))
//        .background(themes.theme.background)
//        .cornerRadius(20)
//        .overlay {
//            RoundedRectangle(cornerRadius: 20)
//                .stroke(.gray, lineWidth: 1)
//        }
        .sheet(isPresented: $payAmountSelectorShown) {
            PaymentAmountSelector(paymentInfo: paymentInfo!)
                .environmentObject(themes)
                .presentationBackgroundCompat(themes.theme.listBackground)
        }
        .opacity((nrContact?.anyLud ?? false) ? 1 : 0)
    }
    
    private func buttonTapped() {
        guard isFullAccount() else { showReadOnlyMessage(); return }
        guard (nrContact?.anyLud ?? false) else { return }
        isLoading = true
        
        if let lud16 = nrContact!.lud16 {
            Task {
                do {
                    let response = try await LUD16.getCallbackUrl(lud16: lud16)
                    await MainActor.run {
                        var supportsZap = false
                        // Make sure at least 1 sat, and not more than 2000000 sat (around $210)
                        let min = ((response.minSendable ?? 1000) < 1000 ? 1000 : (response.minSendable ?? 1000)) / 1000
                        let max = ((response.maxSendable ?? 200000000) > 200000000 ? 200000000 : (response.maxSendable ?? 100000000)) / 1000
                        if response.callback != nil {
                            let callback = response.callback!
                            if (response.allowsNostr ?? false), let zapperPubkey = response.nostrPubkey, isValidPubkey(zapperPubkey) {
                                supportsZap = true
                                // Store zapper nostrPubkey on contact.zapperPubkey as cache
                                Contact.addZapperPubkey(contactPubkey: nrContact!.pubkey, zapperPubkey: zapperPubkey)
                                nrContact!.zapperPubkeys.insert(zapperPubkey)
                            }
                            paymentInfo = PaymentInfo(min: min, max: max, callback: callback, supportsZap: supportsZap, nrContact: nrContact, zapEtag: zapEtag)
                            payAmountSelectorShown = true
                            isLoading = false
                        }
                    }
                }
                catch {
                    L.fetching.error("🔴🔴🔴🔴 problem in lnurlp lud16 \(lud16) \(error)")
//                    print(error)
                }
            }
        }
        else if let lud06 = nrContact!.lud06 {
            Task {
                do {
                    let response = try await LUD16.getCallbackUrl(lud06: lud06)
                    await MainActor.run {
                        var supportsZap = false
                        // Make sure at least 1 sat, and not more than 2000000 sat (around $210)
                        let min = ((response.minSendable ?? 1000) < 1000 ? 1000 : (response.minSendable ?? 1000)) / 1000
                        let max = ((response.maxSendable ?? 200000000) > 200000000 ? 200000000 : (response.maxSendable ?? 200000000)) / 1000
                        if response.callback != nil {
                            let callback = response.callback!
                            if (response.allowsNostr ?? false), let zapperPubkey = response.nostrPubkey, isValidPubkey(zapperPubkey) {
                                supportsZap = true
                                // Store zapper nostrPubkey on contact.zapperPubkey as cache
                                Contact.addZapperPubkey(contactPubkey: nrContact!.pubkey, zapperPubkey: zapperPubkey)
                                nrContact!.zapperPubkeys.insert(zapperPubkey)
                            }
                            paymentInfo = PaymentInfo(min: min, max: max, callback: callback, supportsZap: supportsZap, nrContact: nrContact, zapEtag: zapEtag)
                            payAmountSelectorShown = true
                            isLoading = false
                        }
                    }
                }
                catch {
                    L.fetching.error("🔴🔴🔴🔴 problem in lnurlp lud06 \(lud06) \(error)")
                }
            }
        }
    }
}

struct ProfileLightningButton_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
        }) {
            PreviewFeed {
                if let nrContact = PreviewFetcher.fetchNRContact("9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e") {
                    ProfileLightningButton(nrContact: nrContact)
                }
            }
        }
    }
}
