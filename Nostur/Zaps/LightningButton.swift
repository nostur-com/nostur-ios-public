//
//  LightningButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/02/2023.
//

import SwiftUI

struct LightningButton: View {
    let er:ExchangeRateModel = .shared // Not Observed for performance
    let ns:NosturState = .shared // Not Observed for performance
    var tally:Int64 // SATS (1000 SATS ~= 20 cent)
    var event:Event?
    @State var isLoading = false
    @State var paymentInfo:PaymentInfo? = nil
    @State var payAmountSelectorShown = false
    var body: some View {
        if isLoading {
            ProgressView()
                .colorInvert()
        }
        else {
            Group {
                Image(systemName: "bolt")
                if (er.bitcoinPrice != 0.0) {
                    let fiatPrice = String(format: "$%.02f",(Double(tally) / 100000000 * Double(er.bitcoinPrice)))
                    
                    Text("\(fiatPrice)").opacity(tally != 0 ? 1 : 0)
                }
                else {
                    Text("\(tally.formatNumber) sats").opacity(tally != 0 ? 1 : 0)
                }
            }
            .onTapGesture {
                guard event != nil else { return }
                isLoading = true
                buttonTapped()
            }
            .sheet(isPresented: $payAmountSelectorShown) {
                PaymentAmountSelector(paymentInfo:paymentInfo!)
            }
        }
    }
}

class PaymentInfo {
    var min:UInt64 = 0
    var max:UInt64 = 5000000
    var callback = ""
    var supportsZap = false
    var event:Event?
    var contact:Contact?
    
    init(min: UInt64, max: UInt64, callback: String = "", supportsZap: Bool = false, event:Event? = nil, contact:Contact? = nil) {
        self.min = min
        self.max = max
        self.callback = callback
        self.supportsZap = supportsZap
        self.event = event
        self.contact = contact
    }
}

extension LightningButton {
    func buttonTapped() {
        guard ns.account?.privateKey != nil else { ns.readOnlyAccountSheetShown = true; return }
        guard (event?.contact?.anyLud ?? false) else { return }
        isLoading = true
        
        
        if let lud16 = event!.contact!.lud16 {
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
                                event!.contact!.zapperPubkey = response.nostrPubkey!
                            }
                            paymentInfo = PaymentInfo(min: min, max: max, callback: callback, supportsZap: supportsZap, contact: event!.contact)
                            payAmountSelectorShown = true
                            isLoading = false
                        }
                    }
                }
                catch {
                    print("🔴🔴🔴🔴 problem in lnurlp")
                    print(error)
                }
            }
        }
        else if let lud06 = event!.contact!.lud06 {
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
                                event!.contact!.zapperPubkey = response.nostrPubkey!
                            }
                            paymentInfo = PaymentInfo(min: min, max: max, callback: callback, supportsZap: supportsZap, contact: event!.contact)
                            payAmountSelectorShown = true
                            isLoading = false
                        }
                    }
                }
                catch {
                    print("🔴🔴🔴🔴 problem in lnurlp")
                    print(error)
                }
            }
        }
    }
}

struct LightningButton_Previews: PreviewProvider {
    static var previews: some View {
        let pubkey = "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"
        let contact = PreviewFetcher.fetchContact(pubkey)

        let event = PreviewFetcher.fetchEvent("49635b590782cb1ab1580bd7e9d85ba586e6e99e48664bacf65e71821ae79df1")

        VStack {

//            if (contact != nil) {
//                LightningButton(contact: contact!)
//            }

            Text("\n\n")

            if (event != nil) {
                LightningButton(tally:event!.zapTally, event: event!)
            }

        }
        .withPreviewEnvironment()

    }
}
