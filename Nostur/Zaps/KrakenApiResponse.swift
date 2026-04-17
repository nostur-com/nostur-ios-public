//
//  KrakenApiResponse.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/06/2023.
//

import Foundation

struct KrakenTickerResponse: Codable {
    struct Ticker: Codable {
        let c: [String]
    }

    let result: [String: Ticker]
}

struct KrakenAssetPairsResponse: Codable {
    struct AssetPair: Codable {
        let altname: String
        let wsname: String?
        let base: String
        let quote: String
    }

    let result: [String: AssetPair]
}

struct KrakenBitcoinFiatPair {
    let pairCode: String
    let fiatCode: String
}
