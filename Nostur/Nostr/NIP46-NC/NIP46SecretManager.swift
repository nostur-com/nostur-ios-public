//
//  NIP46SecretManager.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/06/2023.
//

import Foundation
import KeychainAccess
import NostrEssentials

/// Copy pasta from NIP47SecretManager, changed a bit for nostr connect
class NIP46SecretManager {
    
    static let shared = NIP46SecretManager()
    
    let SERVICE = "nc"
    
    // Store the new private key under the account public key, returns the new public key.
    // NOTE: This new key is a "session" key for NC. Not an account key
    func generateKeysForAccount(_ account: CloudAccount) throws -> String {
        let newKeys = try Keys.newKeys()
        if !hasSecret(account: account) { // don't override existing keys
            storeSecret(newKeys, account: account)
        }
        return newKeys.publicKeyHex
    }
    
    func getSecret(account: CloudAccount) -> String? {
        let keychain = Keychain(service: SERVICE)
            .synchronizable(true)
        do {
            let privateKeyHex = try keychain
                .get(account.ncRemoteSignerPubkey_ ?? account.publicKey) 
            return privateKeyHex
        }
        catch Status.itemNotFound {
            account.noPrivateKey = true
            return nil
        }
        catch {
            L.og.error("🔴🔴🔴 could not get key from keychain")
            return nil
        }
    }
    
    func hasSecret(account: CloudAccount) -> Bool {
        let keychain = Keychain(service: SERVICE)
            .synchronizable(true)
        do {
            let privateKeyHex = try keychain
                .get(account.ncRemoteSignerPubkey_ ?? account.publicKey)
            return privateKeyHex != nil
        } catch {
            return false
        }
    }
    
    func storeSecret(_ keys: Keys, account: CloudAccount) {
        let keychain = Keychain(service: SERVICE)
            .synchronizable(true)
        do {
            try keychain
                .accessibility(.afterFirstUnlock)
                .label("nostr connect")
                .set(keys.privateKeyHex, key: account.ncRemoteSignerPubkey_ ?? account.publicKey)
        } catch {
            L.og.error("🔴🔴🔴 could not store key in keychain")
        }
    }
    
    func deleteSecret(account: CloudAccount) {
        let keychain = Keychain(service: SERVICE)
            .synchronizable(true)
        do {
            try keychain.remove(account.ncRemoteSignerPubkey_ ?? account.publicKey)
        } catch {
            L.og.error("🔴🔴🔴 could not remove key from keychain")
        }
    }
}
