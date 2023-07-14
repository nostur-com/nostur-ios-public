//
//  KrakenApiResponse.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/06/2023.
//

import Foundation

// TODO: Create settings toggle on/off and selection from usd/euro/fiat/etc
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
