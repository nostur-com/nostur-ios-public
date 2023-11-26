//
//  CashuToken.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/11/2023.
//

import Foundation

struct CashuToken: Decodable {
    let token: [CashuMint]
    var memo: String?
    
    var totalAmount: Int {
        guard let mint = token.first else { return 0 }
        return mint.proofs.reduce(0, { $0 + $1.amount })
    }
    
    var mint: String? {
        guard let mint = token.first else { return nil }
        guard let url = URL(string: mint.mint), let host = url.host else { return nil }
        return host
    }
}

struct CashuMint: Decodable {
    let mint: String
    let proofs: [CashuProof]
}

struct CashuProof: Decodable {
    let id: String
    let amount: Int
    let secret: String
    let C: String
}
