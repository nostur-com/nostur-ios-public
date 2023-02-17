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
    
    func generateAccount(display_name:String = "", name:String = "", about:String = "", context: NSManagedObjectContext) -> Account {
        let newKeys = NKeys.newKeys()
        storeKeys(newKeys)
        
        //        print("Private key: \(privateKeyHex)") for testing. dont print this ever
        print("Public key: \(newKeys.publicKeyHex())")
        
        let account = context.performAndWait {
            let account = Account(context: context)
            account.id = UUID()
            account.createdAt = Date()
            account.display_name = display_name
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
    
    static func createMetadataEvent(account:Account) throws -> NEvent? {
        guard account.privateKey != nil else {
            throw "Account has no private key"
        }
        
        // create nostr .setMetadata event
        var setMetadataContent = NSetMetadata(name: account.name, display_name: account.display_name, about: account.about, picture: account.picture)
        if account.nip05 != "" { setMetadataContent.nip05 = account.nip05 }
        if account.lud16 != "" { setMetadataContent.lud16 = account.lud16 }
        if account.banner != "" { setMetadataContent.banner = account.banner }
        
        if (account.privateKey != nil) {
            do {
                let keys = try NKeys(privateKeyHex: account.privateKey!)
                
                var newKind0Event = NEvent(content: setMetadataContent)
                
                let newKind0EventSigned = try newKind0Event.sign(keys)
                
                print(newKind0EventSigned.eventJson())
                print(newKind0EventSigned.wrappedEventJson())
                
                return newKind0EventSigned
            }
            catch {
                print("🔴🔴🔴🔴 Could not sign/save/broadcast event 🔴🔴🔴🔴")
                return nil
            }
        }
        return nil
    }
    
    static func createContactListEvent(account:Account) throws -> NEvent? {
        guard account.privateKey != nil else {
            throw "Account has no private key"
        }
        
        
        if (account.privateKey != nil) {
            do {
                let keys = try NKeys(privateKeyHex: account.privateKey!)
                
                var newKind3Event = NEvent(content: "")
                newKind3Event.kind = .contactList
                
                for contact in Array(account.follows ?? Set<Contact>()) {
                    newKind3Event.tags.append(NEventTag(type: "p", otherInformation: contact.pubkey! ))
                }
                
                let newKind3EventSigned = try newKind3Event.sign(keys)
                
                print(newKind3EventSigned.eventJson())
                print(newKind3EventSigned.wrappedEventJson())
                
                return newKind3EventSigned
            }
            catch {
                print("🔴🔴🔴🔴 Could not sign/save/broadcast event 🔴🔴🔴🔴")
                return nil
            }
        }
        return nil
    }
}
