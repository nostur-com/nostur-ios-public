//
//  NIP47.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/06/2023.
//

import Foundation

/// NIP-47 request: 23194
struct NWCRequest: Codable {
    let method:String // "pay_invoice", // method, string
    var params:NWCParams?
    
    struct NWCParams: Codable {
        var invoice:String? //  "lnbc50n1..." // command-related data
    }
}

/// NIP-47 response: 23195
struct NWCResponse: Codable {
    var result_type:String? // "pay_invoice", //indicates the structure of the result field. Field is required but alby doesn't have in case of error.
    var error:NWCResponseError? // object, non-null in case of error
    var result:NWCResponseResult?  // result, object. null in case of error.
    

    struct NWCResponseResult: Codable {
        var preimage:String? // "0123456789abcdef..." // command-related data
        var balance: Int? // 52410000,
        var max_amount: Int? // 2333000,
        var budget_renewal: String? // "weekly"
    }

    struct NWCResponseError: Codable {
        let code:String // "code": "UNAUTHORIZED", //string error code, see below
        let message:String // "message": "human readable error message"
    }
}
