//
//  LightningButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/02/2023.
//

import SwiftUI

struct LightningButton: View {
    
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var er:ExchangeRateModel

    var contact:Contact?
    var event:Event? = nil
    @State var isLoading = false
    
    @State var payAmountSelectorShown = false
    @State var min:UInt64 = 0
    @State var max:UInt64 = 5000000
    @State var callback = ""
    @State var supportsZap = false
    
    var body: some View {
        let _ = Self._printChanges()
        HStack {
            if isLoading {
                ProgressView()
                    .colorInvert()
            }
            else {
                Image(systemName: "bolt")
                if (er.bitcoinPrice != 0.0) {
                    let fiatPrice = String(format: "$%.02f",(Double(event!.zapTally) / 100000000 * Double(er.bitcoinPrice)))
                    
                    Text("\(fiatPrice)")
                }
                else {
                    Text("\(event!.zapTally.description) sats")
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard contact?.lud16 != nil && contact?.lud16 != "" else { return }
            buttonTapped()
        }
        .sheet(isPresented: $payAmountSelectorShown) {
            PaymentAmountSelector(contact: event?.contact, event: event, min: min, max: max, supportsZap: supportsZap, callback: callback)
        }
    }
    
    func buttonTapped() {
        guard ns.account?.privateKey != nil else { ns.readOnlyAccountSheetShown = true; return }
        guard contact?.lud16 != nil && contact?.lud16 != "" else { return }
        
        isLoading = true
        let lud16 = contact!.lud16!
        Task.detached(priority: .background) {
            do {
                let response = try await LUD16.getCallbackUrl(lud16: lud16)
                await MainActor.run {
                    // Make sure at least 1 sat, and not more than 2000000 sat (around $210)
                    min = ((response.minSendable ?? 1000) < 1000 ? 1000 : (response.minSendable ?? 1000)) / 1000
                    max = ((response.maxSendable ?? 100000000) > 100000000 ? 100000000 : (response.maxSendable ?? 100000000)) / 1000
                    if response.callback != nil {
                        callback = response.callback!
                        if (response.allowsNostr ?? false) && (response.nostrPubkey != nil) {
                            supportsZap = true
                            // Store zapper nostrPubkey on contact.zapperPubkey as cache
                            contact!.zapperPubkey = response.nostrPubkey!
                        }
                        payAmountSelectorShown = true
                        isLoading = false
                    }
                }
            }
            catch {
                print("🔴 problem in lnurlp")
                print(error)
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
            
            if (contact != nil) {
                LightningButton(contact: contact!)
            }
            
            Text("\n\n")
            
            if (contact != nil && event != nil) {
                LightningButton(contact: contact!, event: event!)
            }
            
        }
        .withPreviewEnvironment()
            
    }
}
