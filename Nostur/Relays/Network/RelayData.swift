//
//  RelayData.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/11/2023.
//

import Foundation
import NostrEssentials

// Struct to pass around and avoid all the multi threading NSManagedContext problems
public struct RelayData: Identifiable, Hashable, Equatable {
    public var id: String { url.lowercased() }
    
    // Consider below attributes as true if it contains the author pubkey or "APP".
    public var read: Bool
    public var write: Bool
    public var search: Bool
    public var auth: Bool // Allow AUTH response to this relay
    
    public var shouldConnect: Bool {
        return (read || write || search)
    }
    
    public var url: String
    
    public var excludedPubkeys: Set<String>
    
    
    mutating func setRead(_ value: Bool) {
        self.read = value
    }
    
    mutating func setWrite(_ value: Bool) {
        self.write = value
    }
    
    mutating func setSearch(_ value: Bool) {
        self.search = value
    }
    
    mutating func setAuth(_ value: Bool) {
        self.auth = value
    }
    
    mutating func setExcludedPubkeys(_ value: Set<String>) {
        self.excludedPubkeys = value
    }
    
    static func new(url: String, read: Bool, write: Bool, search: Bool, auth: Bool, excludedPubkeys: Set<String>) -> RelayData {
        let url = normalizeRelayUrl(url)

        return RelayData(read: read,
                         write: write,
                         search: search,
                         auth: auth,
                         url: url,
                         excludedPubkeys: excludedPubkeys
        )
    }
}

// For kind-10002
struct AccountRelayData: Codable, Identifiable, Hashable, Equatable {
    public var id: String { url }
    public var url: String // should be lowercased, without trailing slash
    public var read: Bool
    public var write: Bool
    
    init(url: String, read: Bool, write: Bool) {
        self.url = normalizeRelayUrl(url)
        self.read = read
        self.write = write
    }
    
    mutating func setRead(_ newValue:Bool) {
        self.read = newValue
    }
    
    mutating func setWrite(_ newValue:Bool) {
        self.write = newValue
    }
    
    mutating func setUrl(_ newValue:String) {
        self.url = normalizeRelayUrl(newValue)
    }
}
