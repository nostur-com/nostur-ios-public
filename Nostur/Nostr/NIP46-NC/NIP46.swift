//
//  NIP46.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/06/2023.
//

import Foundation

// https://github.com/nostr-protocol/nips/blob/master/46.md

/// NIP-46 request: 24133
struct NCRequest: Codable {
    let id:String // <random_string>,
    let method:String //  <one_of_the_methods>,
    let params:[String] //  [<anything>, <else>]
}

/// NIP-46 response: 24133
struct NCResponse: Codable {
    let id:String // <request_id>,
    var result:String? // <anything>,
    var error:String?  // <reason>
}
