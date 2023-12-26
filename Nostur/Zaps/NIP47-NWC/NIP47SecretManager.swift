//
//  NIP47SecretManager.swift
//  Nostur
//
//  Created by Fabian Lachman on 02/06/2023.
//

import Foundation
import KeychainAccess

/// Copy pasta from AccountManager, changed a bit and use background context
class NIP47SecretManager {
    
    static let shared = NIP47SecretManager()
    
    let SERVICE = "nwc"
    
    // Store the new private key under the connectionId key, returns the new public key.
    func generateKeysForConnection(_ connection:NWCConnection) -> String {
        let newKeys = NKeys.newKeys()
        if !hasSecret(connectionId: connection.connectionId) { // don't override existing keys
            storeSecret(newKeys, connectionId: connection.connectionId)
        }
        return newKeys.publicKeyHex()
    }
    
    func getSecret(connectionId:String) -> String? {
        let keychain = Keychain(service: SERVICE)
            .synchronizable(true)
        do {
            let privateKeyHex = try keychain
                .get(connectionId)
            return privateKeyHex
        } catch {
            L.og.error("🔴🔴🔴 could not get key from keychain")
            return nil
        }
    }
    
    func hasSecret(connectionId:String) -> Bool {
        let keychain = Keychain(service: SERVICE)
            .synchronizable(true)
        do {
            let privateKeyHex = try keychain
                .get(connectionId)
            return privateKeyHex != nil
        } catch {
            return false
        }
    }
    
    func storeSecret(_ keys:NKeys, connectionId:String) {
        let keychain = Keychain(service: SERVICE)
            .synchronizable(true)
        do {
            try keychain
                .accessibility(.afterFirstUnlock)
                .label("nostr wallet connect")
                .set(keys.privateKeyHex(), key: connectionId)
        } catch {
            L.og.error("🔴🔴🔴 could not store key in keychain")
        }
    }
    
    func deleteSecret(connectionId: String) {
        let keychain = Keychain(service: SERVICE)
            .synchronizable(true)
        do {
            try keychain.remove(connectionId)
        } catch {
            L.og.error("🔴🔴🔴 could not remove key from keychain")
        }
    }
}
