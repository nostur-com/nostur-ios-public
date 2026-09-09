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
        var limit: Int?
        var offset: Int?
        var until: Int?
        var type: String?
        var invoice:String? //  "lnbc50n1..." // command-related data
    }
}

/// NIP-47 response: 23195
struct NWCResponse: Codable {
    var result_type:String? // "pay_invoice", //indicates the structure of the result field. Field is required but alby doesn't have in case of error.
    var error:NWCResponseError? // object, non-null in case of error
    var result:NWCResponseResult?  // result, object. null in case of error.
    

    struct NWCResponseResult: Codable {
        var transactions: [NWCTransaction]?
        var total_count: Int?
        var methods: [String]?
        var alias: String?
        var network: String?
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

/// Wallet amounts remain in millisatoshis until display. Optional fields vary by wallet.
struct NWCTransaction: Codable, Identifiable {
    var id: String { type + ":" + payment_hash }
    let type: String
    let payment_hash: String
    let amount: Int64
    let fees_paid: Int64?
    let created_at: Int64
    let settled_at: Int64?
    let expires_at: Int64?
    let state: String?
    let description: String?
    let invoice: String?
    var metadata: Metadata? = nil

    struct Metadata: Codable {
        var nostr: ZapRequest?
        struct ZapRequest: Codable {
            var kind: Int?
            var pubkey: String?
            var tags: [[String]]?
            var content: String?
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, payment_hash, amount, fees_paid, created_at, settled_at, expires_at, state, description, invoice, metadata
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        type = try values.decode(String.self, forKey: .type)
        payment_hash = try values.decode(String.self, forKey: .payment_hash)
        amount = try values.decode(Int64.self, forKey: .amount)
        created_at = try values.decode(Int64.self, forKey: .created_at)
        fees_paid = try values.decodeIfPresent(Int64.self, forKey: .fees_paid)
        settled_at = try values.decodeIfPresent(Int64.self, forKey: .settled_at)
        expires_at = try values.decodeIfPresent(Int64.self, forKey: .expires_at)
        state = try values.decodeIfPresent(String.self, forKey: .state)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        invoice = try values.decodeIfPresent(String.self, forKey: .invoice)
        // Wallet-specific metadata must not prevent otherwise valid history from loading.
        metadata = try? values.decodeIfPresent(Metadata.self, forKey: .metadata)
    }

    var zapRequest: Metadata.ZapRequest? {
        guard let request = metadata?.nostr,
              request.kind == nil || request.kind == 9734 else { return nil }
        return request
    }
    var zapPostId: String? { zapRequest?.tags?.first { $0.first == "e" && $0.count > 1 }?[1] }
    var zapContactPubkey: String? {
        type == "incoming" ? zapRequest?.pubkey : zapRequest?.tags?.first { $0.first == "p" && $0.count > 1 }?[1]
    }

    var title: String {
        if let description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return description
        }
        return type == "incoming" ? "Received payment" : "Sent payment"
    }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(created_at)) }
    static func formattedSats(_ msats: Int64) -> String {
        (Decimal(msats) / 1000).formatted(.number.precision(.fractionLength(0...3)))
    }
}
