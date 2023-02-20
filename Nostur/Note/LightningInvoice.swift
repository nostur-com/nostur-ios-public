//
//  LightningInvoice.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/02/2023.
//

import SwiftUI
import LightningDevKit

struct KrakenApiResponse: Codable {
    
    //    https://api.kraken.com/0/public/Ticker?pair=XXBTZUSD
    //    {
    //        "result": {
    //            "XXBTZUSD": {
    //                "c": [
    //                    "21921.00000",
    //                    "0.00062338"
    //                ]
    //            }
    //        }
    //    }
    
    struct Result: Codable {
        struct XXBTZUSD: Codable {
            var c: [String]
        }
        var XXBTZUSD:XXBTZUSD
    }
    
    var result:Result
}

struct LightningInvoice: View {
    @Environment(\.openURL) var openURL
    
    var invoice:String
    @State var divider:Double = 1000 // 1000 = SATS, 100000000000 = BTC
    @State var fiatPrice = ""
    
    
    var pInvoice:Invoice? {
        get {
            if let pInvoice = Invoice.fromStr(s: invoice).getValue() {
                return pInvoice
            }
            return nil
        }
    }
    
    var isExpired:Bool {
        get {
            pInvoice?.isExpired() ?? false
        }
    }
    
    var body: some View {
        VStack {
            if (pInvoice != nil) {
                Text("Bitcoin Lightning Invoice ⚡️").font(.caption)
                Divider()
                Text("\(pInvoice!.amountMilliSatoshis() != nil ? (Double(pInvoice!.amountMilliSatoshis()!)/divider).clean.description : "any") \(divider == 1000 ? "sats" : "BTC") \(fiatPrice)")
                    .font(.title3).padding(.bottom, 10)
                    .onTapGesture {
                        divider = divider == 1000 ? 100000000000 : 1000
                    }
                Button {
                    openURL(URL(string: "lightning:\(invoice)")!)
                } label: { Text(isExpired ? "Expired" : "Pay").frame(minWidth: 150) }
                    .buttonStyle(.borderedProminent)
                    .cornerRadius(20)
                    .disabled(isExpired)
            }
            else {
                Text("Unable to decode lightning invoice")
            }
        }
        .padding(20)
        .background(LinearGradient(colors: isExpired ? [.gray, .black] : [.orange, .red],
                                   startPoint: .top,
                                   endPoint: .center).opacity(0.3))
        .cornerRadius(20)
        .task {
            guard let url = URL(string: "https://api.kraken.com/0/public/Ticker?pair=XXBTZUSD") else { return }
            let request = URLRequest(url: url)
            
            do {
                // Fetch the remote data.
                let (data, _) = try await URLSession.shared.data(for: request)
                
                // Decode data to a CatFact object.
                let response = try JSONDecoder().decode(KrakenApiResponse.self, from: data)
                
                // Return the fact string value.
                if pInvoice?.amountMilliSatoshis() != nil {
                    fiatPrice = String(format: "($%.02f)",(Double(pInvoice!.amountMilliSatoshis()!) / 100000000000 * Double(response.result.XXBTZUSD.c[0])!))
                }
            }
            catch {
                print("could not get price from kraken")
            }
        }
        
    }
}

func fetchBitcoinPrice() async -> Double? {
    guard let url = URL(string: "https://api.kraken.com/0/public/Ticker?pair=XXBTZUSD") else { return nil }
    let request = URLRequest(url: url)
    
    do {
        // Fetch the remote data.
        let (data, _) = try await URLSession.shared.data(for: request)
        
        // Decode data to a CatFact object.
        let response = try JSONDecoder().decode(KrakenApiResponse.self, from: data)
        
        // Return the fact string value.
        return Double(response.result.XXBTZUSD.c[0])
    }
    catch {
        print("could not get price from kraken")
        return nil
    }
}

struct LightningInvoice_Previews: PreviewProvider {
    static var previews: some View {
        let invoice = "lnbc469970n1p373e49pp5ey9mxfcy9k62clpjvqwsrju64p0378cll0mzehtccj2ulqnamkzqdqvw3jhxarfdenscqzpgxqyz5vqsp5m8zsyfs936f2vfkshvdfhntmr596079hwryr2r8dpr8ahy6hu6hq9qyyssqlcvvw6gmq09hwzw2kxfe03enc25plxzfmupxwx4xr8hddn972nzq7m0jf9sxenw23qg6nv55678nrnnr4fe3wkwm6pczmaxs0r7yftgqd6lgya"
        
        let event = { () -> Event in
            let event = PreviewFetcher.fetchEvent()
            event?.content = invoice
            return event!
        }()
        
        
        VStack {
            Text("Just the invoice:")
            LightningInvoice(invoice:invoice)
            
            Text("\n\n\n")
            
            Text("In a note")
            NoteRowView(event: event)
        }.padding(20)
            .withPreviewEnvironment()
        
    }
    
}
