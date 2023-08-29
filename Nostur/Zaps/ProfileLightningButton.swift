//
//  ProfileLightningButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/02/2023.
//

import SwiftUI

struct ProfileLightningButton: View {
    @EnvironmentObject var theme:Theme
    var sp:SocketPool = .shared
    let er:ExchangeRateModel = .shared
    @EnvironmentObject var ns:NosturState
    
    var contact:Contact?
    
    @State var isLoading = false
    @State var payAmountSelectorShown = false
    @State var paymentInfo:PaymentInfo?
    
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
                Text("⚡️")
            }
        }
        .frame(width: 40, height: 30)
        .font(.caption.weight(.heavy))
        .background(theme.background)
        .cornerRadius(20)
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.gray, lineWidth: 1)
        }
        .sheet(isPresented: $payAmountSelectorShown) {
            PaymentAmountSelector(paymentInfo: paymentInfo!)
        }.opacity((contact?.anyLud ?? false) ? 1 : 0)
    }
    
    func buttonTapped() {
        guard ns.account?.privateKey != nil else { ns.readOnlyAccountSheetShown = true; return }
        guard (contact?.anyLud ?? false) else { return }
        isLoading = true
        
        if let lud16 = contact!.lud16 {
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
                            if (response.allowsNostr ?? false) && (response.nostrPubkey != nil) {
                                supportsZap = true
                                // Store zapper nostrPubkey on contact.zapperPubkey as cache
                                contact!.zapperPubkey = response.nostrPubkey!
                            }
                            paymentInfo = PaymentInfo(min: min, max: max, callback: callback, supportsZap: supportsZap, contact: contact)
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
        else if let lud06 = contact!.lud06 {
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
                            if (response.allowsNostr ?? false) && (response.nostrPubkey != nil) {
                                supportsZap = true
                                // Store zapper nostrPubkey on contact.zapperPubkey as cache
                                contact!.zapperPubkey = response.nostrPubkey!
                            }
                            paymentInfo = PaymentInfo(min: min, max: max, callback: callback, supportsZap: supportsZap, contact: contact)
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
            SmoothListMock {
                if let contact = PreviewFetcher.fetchContact("9be0be0e64d38a29a9cec9a5c8ef5d873c2bfa5362a4b558da5ff69bc3cbb81e") {
                    ProfileLightningButton(contact: contact)
                }
            }
        }
    }
}
