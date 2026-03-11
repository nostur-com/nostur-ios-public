//
//  NostrAccountEntity.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/03/2026.
//

import AppIntents
import Foundation

@available(iOS 16.0, macCatalyst 16.0, *)
struct NostrAccountEntity: AppEntity {
    
    // The stable identifier is the Nostr public key
    var id: String
    var name: String
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Nostr Account"
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
    
    static var defaultQuery = NostrAccountEntityQuery()
}

@available(iOS 16.0, macCatalyst 16.0, *)
struct NostrAccountEntityQuery: EntityQuery {
    
    // Look up specific accounts by their public key IDs
    func entities(for identifiers: [String]) async throws -> [NostrAccountEntity] {
        await MainActor.run {
            AccountsState.shared.fullAccounts
                .filter { identifiers.contains($0.publicKey) }
                .map { NostrAccountEntity(id: $0.publicKey, name: $0.anyName) }
        }
    }
    
    // Populate the picker with all full accounts
    func suggestedEntities() async throws -> [NostrAccountEntity] {
        await MainActor.run {
            AccountsState.shared.fullAccounts
                .map { NostrAccountEntity(id: $0.publicKey, name: $0.anyName) }
        }
    }
}
