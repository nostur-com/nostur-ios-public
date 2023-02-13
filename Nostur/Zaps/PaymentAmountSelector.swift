//
//  PaymentAmountSelector.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/02/2023.
//

import SwiftUI

struct PaymentAmountSelector: View {
    var min:UInt64
    var max:UInt64
    @State var amount:Float = 0.0
    @State var exchangeRate:Double? = 0.0
    @State var fiatPrice = ""
    @Environment(\.dismiss) private var dismiss
    
    var amountSelected: (Float) -> ()
    
    init(min: UInt64, max: UInt64, onAmountSelected: @escaping (Float) -> ()) {
        self.min = min
        self.max = max
        self.amountSelected = onAmountSelected
    }
    
    var body: some View {
        VStack {
            HStack {
                Text("Send sats:")
                Text(ceil(Double(amount)).clean)
                Text("sats")
                if (fiatPrice != "") {
                    Text("\(fiatPrice)")
                }
            }
            Slider(value: $amount, in: Float(min)...Float(max))
                .padding()
            Button {
                amountSelected(ceil(amount))
//                dismiss()
            } label: {
                Text("Pay").padding(10)
                    .frame(minWidth: 200)
            }.buttonStyle(.borderedProminent)
        }
        .onAppear {
            amount = Float(min)
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
        PaymentAmountSelector(min: 1000/1000, max: 1000000000/1000) { amount in
            print(amount)
        }
    }
}
