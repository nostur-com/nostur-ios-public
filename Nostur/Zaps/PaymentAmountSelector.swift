//
//  PaymentAmountSelector.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/02/2023.
//

import SwiftUI

struct PaymentAmountSelector: View {
    @EnvironmentObject var ns:NosturState
    @Environment(\.openURL) var openURL
    
    let ss:SettingsStore = .shared
    let sp:SocketPool = .shared
    let paymentInfo:PaymentInfo
    
    @State var amount:Float = 0.0 // SATS (1000 SATS ~= 20 cent)
    @State var exchangeRate:Double? = 0.0 // BTC 23167
    @State var fiatPrice = "" // $0.00
    @State var zapMessage = ""
    @Environment(\.dismiss) private var dismiss
    
    init(paymentInfo:PaymentInfo) {
        self.paymentInfo = paymentInfo
        self.amount = Float(ss.defaultZapAmount) // SATS (1000 SATS ~= 20 cent)
    }
    
    func amountSelected(amount:Float, zapMessage:String) {
        guard paymentInfo.contact?.lud16 != nil && paymentInfo.contact?.lud16 != "" else { return }
        let pubkey = paymentInfo.contact!.pubkey!
        let eventId = paymentInfo.event?.id ?? nil
        let relays = sp.sockets.values
            .filter { $0.write }
            .map { $0.url }
        
        if (paymentInfo.supportsZap) {
            Task {
                do {
                    
                    let zapRequestNote = zapRequest(forPubkey: pubkey, andEvent: eventId, withMessage: zapMessage, relays: relays)
                    
                    let signedZapRequestNote = try ns.signEvent(zapRequestNote)
                    
                    let response = try await LUD16.getInvoice(url:paymentInfo.callback, amount:UInt64(amount * 1000), zapRequestNote: signedZapRequestNote)
                    
                    if response.pr != nil {
                        await MainActor.run {
                            openURL(URL(string: "\(ss.defaultLightningWallet.scheme)\(response.pr!)")!)
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
                    let response = try await LUD16.getInvoice(url:paymentInfo.callback, amount:UInt64(amount * 1000))
                    
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
    
    var body: some View {
        VStack {
            if IS_IPAD {
                HStack {
                    Spacer()
                    Image(systemName: "xmark.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .padding(30)
                        .onTapGesture {
                            dismiss()
                        }
                }
            }
            HStack {
                Text("Send sats:").font(.title2)
                Text(ceil(Double(amount)).clean).font(.title2)
                Text("sats").font(.title2)
                if (fiatPrice != "") {
                    Text("\(fiatPrice)").font(.title2)
                }
            }
            Slider(value: $amount, in: Float(paymentInfo.min)...Float(paymentInfo.max))
                .padding()
            if (paymentInfo.supportsZap) {
                HStack(alignment: .center) {
                    TextField("Add public note (optional)", text: $zapMessage)
                        .multilineTextAlignment(.leading)
                        .lineLimit(5, reservesSpace: true)
                        .textFieldStyle(.roundedBorder)
                        .padding(20)
                        .frame(height: 100)
                        
                }
            }
            Button {
                amountSelected(amount:ceil(amount), zapMessage:zapMessage)
            } label: {
                Text("Pay").padding(10)
                    .foregroundColor(.white)
                    .frame(minWidth: 200)
            }.buttonStyle(.borderedProminent)
        }
        .onAppear {
            amount = Float(ss.defaultZapAmount)
        }
        .task {
            guard let url = URL(string: "https://api.kraken.com/0/public/Ticker?pair=XXBTZUSD") else { return }
            let request = URLRequest(url: url)
            
            do {
                // Fetch the remote data.
                let (data, _) = try await URLSession.shared.data(for: request)
                
                // Decode data to a CatFact object.
                let response = try JSONDecoder().decode(KrakenApiResponse.self, from: data)
                
                // Return the fact string value.
                
                exchangeRate = Double(response.result.XXBTZUSD.c[0])
                if (exchangeRate != nil) {
                    fiatPrice = String(format: "($%.02f)", (ceil(Double(amount)) / 100000000000 * exchangeRate!))
                }
                else {
                    fiatPrice = ""
                }
   
            }
            catch {
                print("could not get price from kraken")
            }
            
        }
        .onChange(of: amount) { newAmount in
            if (exchangeRate != nil) {
                fiatPrice = String(format: "($%.02f)", (ceil(Double(newAmount)) / 100000000 * exchangeRate!))
            }
        }
    }
    
}

struct PaymentAmountSelector_Previews: PreviewProvider {
    static var previews: some View {
        let paymentInfo = PaymentInfo(min: 1000, max: 50000000, callback: "", supportsZap: true)
        PaymentAmountSelector(paymentInfo: paymentInfo)
            .withPreviewEnvironment()
    }
}
