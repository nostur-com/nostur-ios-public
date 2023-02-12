//
//  AccountManager.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/02/2023.
//

import Foundation
import KeychainAccess
import CoreData

class AccountManager {
    
    static var shared = AccountManager()
    
    var keychain:Keychain
    
    init() {
        self.keychain = Keychain(service: "nostur.com.Nostur")
    }
    
    func generateAccount(name:String = "", about:String = "", context: NSManagedObjectContext) -> Account {
        let newKeys = NKeys.newKeys()
        storeKeys(newKeys)
        
        //        print("Private key: \(privateKeyHex)") for testing. dont print this ever
        print("Public key: \(newKeys.publicKeyHex())")
        
        let account = context.performAndWait {
            let account = Account(context: context)
            account.id = UUID()
            account.createdAt = Date()
            account.name = name
            account.about = about
            account.publicKey = newKeys.publicKeyHex()
            
            do {
                try context.save()
                return account
            } catch {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
        return account
    }
    
    
    func getPrivateKeyHex(pubkey:String) -> String? {
        do {
            let privateKeyHex = try self.keychain
                .get(pubkey)
            return privateKeyHex
        } catch let error {
            print("🔴🔴🔴 could not get key from keychain")
            print("🔴🔴🔴 \(error)")
            return nil
        }
    }
    
    func storeKeys(_ keys:NKeys) {
        do {
            try self.keychain
                .accessibility(.whenUnlocked)
                .set(keys.privateKeyHex(), key: keys.publicKeyHex())
        } catch let error {
            print("🔴🔴🔴 could not store key in keychain")
            print("🔴🔴🔴 \(error)")
        }
    }
    
    func storePrivateKey(privateKeyHex: String, forPublicKeyHex:String) {
        do {
            try self.keychain
                .accessibility(.whenUnlocked)
                .set(privateKeyHex, key: forPublicKeyHex)
        } catch let error {
            print("🔴🔴🔴 could not store key in keychain")
            print("🔴🔴🔴 \(error)")
        }
    }
    
    func deletePrivateKey(forPublicKeyHex: String) {
        do {
            try keychain.remove(forPublicKeyHex)
        } catch let error {
            print("🔴🔴🔴 could not remove key from keychain")
            print("🔴🔴🔴 \(error)")
        }
    }
}
