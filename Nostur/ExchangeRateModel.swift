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

    @Published var bitcoinPrice: Double = 0.0
    @Published private(set) var activeFiatCurrencyCode: String = "USD"
    @Published private(set) var supportedFiatCurrencyCodes: [String] = ["USD", "EUR"]

    static var deviceCurrencyCode: String {
        let currency = Locale.autoupdatingCurrent.currencyCode ?? "USD"
        return currency.uppercased()
    }

    private var pairCodeByFiatCurrency: [String: String] = [
        "USD": "XBTUSD",
        "EUR": "XBTEUR"
    ]

    private var setPriceSub: AnyCancellable?
    private var priceLoop = Timer.publish(every: 900, tolerance: 120, on: .main, in: .common)
        .autoconnect()
        .receive(on: RunLoop.main)
        .merge(with: Just(Date()))

    private init() {
        setPriceSub = priceLoop
            .sink { [weak self] _ in
                self?.refreshNow()
            }
    }

    func refreshNow() {
        Task.detached(priority: .low) { [weak self] in
            await self?.refreshBitcoinPrice()
        }
    }

    func formattedFiatValue(sats: Double, includeParentheses: Bool = false) -> String? {
        guard SettingsStore.shared.showFiat else { return nil }
        guard bitcoinPrice > 0 else { return nil }
        let fiatAmount = sats / 100_000_000 * bitcoinPrice
        return formatFiatValue(fiatAmount, includeParentheses: includeParentheses)
    }

    private func formatFiatValue(_ amount: Double, includeParentheses: Bool) -> String? {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.numberStyle = .currency
        formatter.currencyCode = activeFiatCurrencyCode
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2

        guard let value = formatter.string(from: NSNumber(value: amount)) else { return nil }
        return includeParentheses ? "(\(value))" : value
    }

    private func refreshBitcoinPrice() async {
        if let pairs = await fetchBitcoinFiatPairs(), !pairs.isEmpty {
            await MainActor.run {
                pairCodeByFiatCurrency = pairs
                supportedFiatCurrencyCodes = pairs.keys.sorted()
            }
        }

        let activeCode = resolveActiveFiatCurrencyCode(preferredCurrency: SettingsStore.shared.preferredFiatCurrency)

        guard let pairCode = pairCodeByFiatCurrency[activeCode]
            ?? pairCodeByFiatCurrency["USD"]
            ?? pairCodeByFiatCurrency.values.first
        else {
            return
        }

        guard let newPrice = await fetchBitcoinPrice(pairCode: pairCode) else { return }

        await MainActor.run {
            if newPrice != bitcoinPrice {
                bitcoinPrice = newPrice
            }
            activeFiatCurrencyCode = activeCode
        }
    }

    private func resolveActiveFiatCurrencyCode(preferredCurrency: String) -> String {
        let deviceCurrency = Self.deviceCurrencyCode
        let selectedCurrency = preferredCurrency == SettingsStore.deviceDefaultFiatCurrency
            ? deviceCurrency
            : preferredCurrency.uppercased()

        if pairCodeByFiatCurrency[selectedCurrency] != nil {
            return selectedCurrency
        }
        if pairCodeByFiatCurrency[deviceCurrency] != nil {
            return deviceCurrency
        }
        if pairCodeByFiatCurrency["USD"] != nil {
            return "USD"
        }
        return pairCodeByFiatCurrency.keys.first ?? "USD"
    }
}

private func fetchBitcoinPrice(pairCode: String) async -> Double? {
    guard let url = URL(string: "https://api.kraken.com/0/public/Ticker?pair=\(pairCode)") else { return nil }
    let request = URLRequest(url: url)

    do {
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(KrakenTickerResponse.self, from: data)
        guard let ticker = response.result.values.first,
              let lastTradePrice = ticker.c.first,
              let price = Double(lastTradePrice)
        else {
            return nil
        }
        return price
    }
    catch {
        L.og.debug("Could not get BTC price from Kraken for pair \(pairCode)")
        return nil
    }
}

private func fetchBitcoinFiatPairs() async -> [String: String]? {
    guard let url = URL(string: "https://api.kraken.com/0/public/AssetPairs") else { return nil }
    let request = URLRequest(url: url)

    do {
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(KrakenAssetPairsResponse.self, from: data)

        let fiatCurrencyCodes = Set(NSLocale.commonISOCurrencyCodes.map { $0.uppercased() })
        var pairCodeByFiatCurrency: [String: String] = [:]

        for assetPair in response.result.values {
            guard assetPair.base == "XXBT" || assetPair.base == "XBT" else { continue }
            guard let wsname = assetPair.wsname, wsname.hasPrefix("XBT/") else { continue }

            let fiatCode = String(wsname.split(separator: "/").last ?? "").uppercased()
            guard fiatCode.count == 3 else { continue }
            guard fiatCurrencyCodes.contains(fiatCode) else { continue }

            pairCodeByFiatCurrency[fiatCode] = assetPair.altname
        }

        if pairCodeByFiatCurrency.isEmpty {
            return nil
        }

        return pairCodeByFiatCurrency
    }
    catch {
        L.og.debug("Could not fetch BTC fiat pairs from Kraken")
        return nil
    }
}
