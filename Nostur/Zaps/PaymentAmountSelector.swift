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
    
    let SLIDER_MIN = 21.0
    let SLIDER_MAX = 2000000.0
    
    @State var sliderValue:Float = 0.0 // SATS (1000 SATS ~= 20 cent)
//    @State var amount:Float = 0.0 // SATS (1000 SATS ~= 20 cent)
    @State var exchangeRate:Double? = 0.0 // BTC 23167
    @State var fiatPrice = "" // $0.00
    @State var zapMessage = ""
    @Environment(\.dismiss) private var dismiss
    
    var amountS:Float {
        mapLinearToExponential(value: sliderValue, min: Float(SLIDER_MIN), max: Float(SLIDER_MAX), exponent: 7)
    }
    
    init(paymentInfo:PaymentInfo) {
        self.paymentInfo = paymentInfo
//        self.amount = Float(ss.defaultZapAmount) // SATS (1000 SATS ~= 20 cent)
    }
    
    func amountSelected(amount:Float, zapMessage:String) {
        guard paymentInfo.contact?.anyLud ?! true else { return }
        let pubkey = paymentInfo.contact!.pubkey
        let eventId = paymentInfo.nrPost?.id ?? nil
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
                    L.fetching.notice("problem fetching ln invoice / or signing zap request note. callback: \(paymentInfo.callback) \(error)")
                }
            }
        }
        else {
            Task {
                do {
                    let response = try await LUD16.getInvoice(url:paymentInfo.callback, amount:UInt64(amountS * 1000))
                    
                    if response.pr != nil {
                        await MainActor.run {
                            openURL(URL(string: "\(ss.defaultLightningWallet.scheme)\(response.pr!)")!)
                        }
                    }
                }
                catch {
                    L.fetching.notice("problem fetching ln invoice. callback:\(paymentInfo.callback) \(error)")
                }
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                HStack {
                    Text("Send sats:").font(.title2)
                    Text(ceil(Double(amountS)).clean).font(.title2)
                    Text("sats").font(.title2)
                    if (fiatPrice != "($0.00)") {
                        Text("\(fiatPrice)").font(.title2)
                    }
                }
                Slider(value: $sliderValue, in: Float(SLIDER_MIN)...Float(SLIDER_MAX)) {
                    
                } minimumValueLabel: {
                    Text("\(SLIDER_MIN.clean)")
                } maximumValueLabel: {
                    Text("\(SLIDER_MAX.clean)")
                }
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
                    amountSelected(amount:ceil(amountS), zapMessage:zapMessage)
                } label: {
                    Text("Pay").padding(10)
                        .foregroundColor(.white)
                        .frame(minWidth: 200)
                }.buttonStyle(.borderedProminent)
            }
            .onAppear {
                sliderValue = mapExponentialToLinear(value: Float(ss.defaultZapAmount) , min: Float(SLIDER_MIN), max: Float(SLIDER_MAX), exponent: 7)
                if (exchangeRate != nil) {
                    fiatPrice = String(format: "($%.02f)", (ceil(Double(amountS)) / 100000000 * exchangeRate!))
                }
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
                        fiatPrice = String(format: "($%.02f)", (ceil(Double(amountS)) / 100000000000 * exchangeRate!))
                    }
                    else {
                        fiatPrice = ""
                    }
       
                }
                catch {
                    print("could not get price from kraken")
                }
                
            }
            .onChange(of: amountS) { newAmountS in
                if (exchangeRate != nil) {
                    fiatPrice = String(format: "($%.02f)", (ceil(Double(newAmountS)) / 100000000 * exchangeRate!))
                }
            }
            .navigationTitle("Zap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(content: {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            })
        }
    }
    
}

struct PaymentAmountSelector_Previews: PreviewProvider {
    static var previews: some View {
        let paymentInfo = PaymentInfo(min: 21, max: 1000000, callback: "", supportsZap: true)
        PaymentAmountSelector(paymentInfo: paymentInfo)
            .withPreviewEnvironment()
    }
}

func mapLinearToExponential(value: Float, min: Float, max: Float, exponent: Float = 3) -> Float {
//    let exponent: Float = 3 // You can adjust this value to change the sensitivity

    let normalizedValue = (value - min) / (max - min)
    let exponentialValue = pow(normalizedValue, exponent)
    return min + (max - min) * exponentialValue
}

func mapExponentialToLinear(value: Float, min: Float, max: Float, exponent: Float = 3) -> Float {
    let normalizedValue = (value - min) / (max - min)
    let linearValue = pow(normalizedValue, 1/exponent)
    return min + (max - min) * linearValue
}

