//
//  ExchangeRateModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/03/2025.
//

import SwiftUI
import Combine

final class ExchangeRateModel: ObservableObject {
    static public let shared = ExchangeRateModel()
    
    private init() {
        setPriceSub = priceLoop
            .sink { _ in
                Task.detached(priority: .low) {
                    if let newPrice = await fetchBitcoinPrice() {
                        if (newPrice != ExchangeRateModel.shared.bitcoinPrice) {
                            Task { @MainActor in
                                ExchangeRateModel.shared.bitcoinPrice = newPrice
                            }
                        }
                    }
                }
            }
    }
    
    @Published var bitcoinPrice: Double = 0.0
    
    private var setPriceSub: AnyCancellable?
    private var priceLoop = Timer.publish(every: 900, tolerance: 120, on: .main, in: .common).autoconnect().receive(on: RunLoop.main)
        .merge(with: Just(Date()))
}


func fetchBitcoinPrice() async -> Double? {
    guard let url = URL(string: "https://api.kraken.com/0/public/Ticker?pair=XXBTZUSD") else { return nil }
    let request = URLRequest(url: url)
    
    do {
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(KrakenApiResponse.self, from: data)
        return Double(response.result.XXBTZUSD.c[0])
    }
    catch {
        L.og.debug("could not get price from kraken")
        return nil
    }
}
