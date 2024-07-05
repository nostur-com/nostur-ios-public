//
//  RelayConnectionStats.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/07/2024.
//

import Foundation

public class RelayConnectionStats: Identifiable {
    public let id: String // should be relay url
    
    public var errors: Int = 0
    public var messages: Int = 0
    public var connected: Int = 0
    
    public var lastErrorMessages: [String] = []
    
    // Pubkeys actually received from this relay
    public var receivedPubkeys: Set<String> = []
    
    init(id: String) {
        self.id = id
    }
    
    public func addErrorMessage(_ message: String) {
        lastErrorMessages = Array(([String(format: "%@: %@", Date().ISO8601Format(), message)] + lastErrorMessages).prefix(10))
    }
}

func updateConnectionStats(receivedPubkey pubkey: String, fromRelay relay: String) {
    // Only track pubkey we follow
    guard NRState.shared.loggedInAccount?.followingPublicKeys.contains(pubkey) ?? false else { return }
    ConnectionPool.shared.queue.async(flags: .barrier) {
        guard let relayStats = ConnectionPool.shared.connectionStats[relay] else { return }
        relayStats.receivedPubkeys.insert(pubkey)
    }
}
