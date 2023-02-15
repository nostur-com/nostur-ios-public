//
//  LightningButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/02/2023.
//

import SwiftUI

struct LightningButton: View {
    
    @EnvironmentObject var sp:SocketPool
    @EnvironmentObject var ns:NosturState
    
    @Environment(\.openURL) var openURL
    var contact:Contact
    var event:Event? = nil
    @State var isLoading = false
    
    @State var payAmountSelectorShown = false
    @State var min:UInt64 = 0
    @State var max:UInt64 = 5000000
    @State var callback = ""
    @State var supportsZap = false
    
    var body: some View {
        if (contact.lud16 != nil && contact.lud16 != "") {
            
            if (event != nil) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .colorInvert()
                    }
                    else {
                        Image(systemName: "bolt")
                        Text(event!.zapTally.description)
                    }
                }
                .onTapGesture {
                    buttonTapped()
                }
                .sheet(isPresented: $payAmountSelectorShown) {
                    renderPaymentSelector()
                }
            }
            else {
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
                    renderPaymentSelector()
                }
            }
            
        }
        else {
            EmptyView()
        }
    }
    
    func buttonTapped() {
        isLoading = true
        let lud16 = contact.lud16!
        Task.detached(priority: .background) {
            do {
                let response = try await LUD16.getCallbackUrl(lud16: lud16)
                await MainActor.run {
                    // Make sure at least 1 sat, and not more than 2000000 sat (around $210)
                    min = ((response.minSendable ?? 1000) < 1000 ? 1000 : (response.minSendable ?? 1000)) / 1000
                    max = ((response.maxSendable ?? 1000000000) > 1000000000 ? 1000000000 : (response.maxSendable ?? 1000000000)) / 1000
                    if response.callback != nil {
                        callback = response.callback!
                        if (response.allowsNostr ?? false) && (response.nostrPubkey != nil) {
                            supportsZap = true
                            // Store zapper nostrPubkey on contact.zapperPubkey as cache
                            contact.zapperPubkey = response.nostrPubkey!
                        }
                        payAmountSelectorShown = true
                        isLoading = false
                    }
                }
            }
            catch {
                print("problem in lnurlp")
                print(error)
            }
        }
    }
    
    fileprivate func renderPaymentSelector() -> PaymentAmountSelector {
        return PaymentAmountSelector(min:min, max:max, supportsZap:supportsZap) { amount, zapMessage in
            
            let pubkey = contact.pubkey!
            let eventId = event?.id ?? nil
            let relays = sp.sockets.values
                .filter { $0.write }
                .map { $0.url }
            
            if (supportsZap) {
                Task.detached(priority: .background) {
                    do {
                        
                        let zapRequestNote = zapRequest(forPubkey: pubkey, andEvent: eventId, withMessage: zapMessage, relays: relays)
                        
                        let signedZapRequestNote = try await ns.signEvent(zapRequestNote)
                        
                        let response = try await LUD16.getInvoice(url:callback, amount:UInt64(amount * 1000), zapRequestNote: signedZapRequestNote)
                        
                        if response.pr != nil {
                            await MainActor.run {
                                openURL(URL(string: "lightning:\(response.pr!)")!)
                            }
                        }
                    }
                    catch {
                        print("problem fetching ln invoice / or signing zap request note")
                        print(error)
                    }
                }
            }
            else {
                Task.detached(priority: .background) {
                    do {
                        let response = try await LUD16.getInvoice(url:callback, amount:UInt64(amount * 1000))
                        
                        if response.pr != nil {
                            await MainActor.run {
                                openURL(URL(string: "lightning:\(response.pr!)")!)
                            }
                        }
                    }
                    catch {
                        print("problem fetching ln invoice")
                        print(error)
                    }
                }
            }
        }
    }
}

struct LightningButton_Previews: PreviewProvider {
    static var previews: some View {
        let pubkey = "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"
        let contact = PreviewFetcher.fetchContact(pubkey)!
        
        let event = PreviewFetcher.fetchEvent("49635b590782cb1ab1580bd7e9d85ba586e6e99e48664bacf65e71821ae79df1")!
        
        VStack {
            
            LightningButton(contact: contact)
            
            Text("\n\n")
            
            LightningButton(contact: contact, event: event)
            
        }
        .withPreviewEnvironment()
            
    }
}
