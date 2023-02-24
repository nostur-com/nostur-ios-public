//
//  ProfileLightningButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/02/2023.
//

import SwiftUI

struct ProfileLightningButton: View {
    var sp:SocketPool = .shared
    @EnvironmentObject var er:ExchangeRateModel
    @EnvironmentObject var ns:NosturState
    
    var contact:Contact?
    
    @State var isLoading = false
    @State var payAmountSelectorShown = false
    @State var min:UInt64 = 0
    @State var max:UInt64 = 5000000
    @State var callback = ""
    @State var supportsZap = false
    
    var body: some View {
        let _ = Self._printChanges()
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
        .background(Color("BackgroundColor"))
        .cornerRadius(20)
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.gray, lineWidth: 1)
        }
        .sheet(isPresented: $payAmountSelectorShown) {
            PaymentAmountSelector(contact: contact, min: min, max: max, supportsZap: supportsZap, callback: callback)
        }.opacity(contact?.lud16 == nil || contact?.lud16 == "" ? 0 : 1)
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

struct ProfileLightningButton_Previews: PreviewProvider {
    static var previews: some View {
        ProfileLightningButton()
    }
}
