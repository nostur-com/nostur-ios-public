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
        let keychain = Keychain(service: "nostur.com.Nostur")
        do {
            let privateKeyHex = try keychain
                .get(pubkey)
            return privateKeyHex
        } catch let error {
            print("🔴🔴🔴 could not get key from keychain")
            print("🔴🔴🔴 \(error)")
            return nil
        }
    }
    
    func hasPrivateKey(pubkey:String) -> Bool {
        let keychain = Keychain(service: "nostur.com.Nostur")
        do {
            let privateKeyHex = try keychain
                .get(pubkey)
            return privateKeyHex != nil
        } catch {
            return false
        }
    }
    
    func storeKeys(_ keys:NKeys) {
        let keychain = Keychain(service: "nostur.com.Nostur")
        do {
            try keychain
                .accessibility(.whenUnlocked)
                .set(keys.privateKeyHex(), key: keys.publicKeyHex())
        } catch let error {
            print("🔴🔴🔴 could not store key in keychain")
            print("🔴🔴🔴 \(error)")
        }
    }
    
    func storePrivateKey(privateKeyHex: String, forPublicKeyHex:String) {
        let keychain = Keychain(service: "nostur.com.Nostur")
        do {
            try keychain
                .accessibility(.whenUnlocked)
                .set(privateKeyHex, key: forPublicKeyHex)
        } catch let error {
            print("🔴🔴🔴 could not store key in keychain")
            print("🔴🔴🔴 \(error)")
        }
    }
    
    func deletePrivateKey(forPublicKeyHex: String) {
        let keychain = Keychain(service: "nostur.com.Nostur")
        do {
            try keychain.remove(forPublicKeyHex)
        } catch let error {
            print("🔴🔴🔴 could not remove key from keychain")
            print("🔴🔴🔴 \(error)")
        }
    }
    
    // Wipes kind 0 and 3, publishes wiped events. Deletes key fron keychain, account from db
    func wipeAccount(_ account:Account) {
        guard let pk = account.privateKey else { return }
    
        let metaData = NSetMetadata(name: "ACCOUNT_DELETED", display_name: "ACCOUNT_DELETED", about: "", picture: "", banner: "", nip05: "", lud16: "", lud06: "")

        // wipe kind 0
        var newKind0Event = NEvent(content: metaData)
        newKind0Event.kind = .setMetadata
        
        // wipe kind 3
        var newKind3Event = NEvent(content: "")
        newKind3Event.kind = .contactList

        do {
            let keys = try NKeys(privateKeyHex: pk)
            let newKind0EventSigned = try newKind0Event.sign(keys)
            let newKind3EventSigned = try newKind3Event.sign(keys)

            Unpublisher.shared.publishNow(newKind0EventSigned)
            Unpublisher.shared.publishNow(newKind3EventSigned)
            
            // delete key from keychain
            deletePrivateKey(forPublicKeyHex: account.publicKey)
            
            // delete account
            let accounts = NosturState.shared.accounts
            if (accounts.count < 1) {
                NosturState.shared.onBoardingIsShown = true
                sendNotification(.clearNavigation)
                NosturState.shared.setAccount(account: nil)
                DataProvider.shared().viewContext.delete(account)
            }
            else {
                DataProvider.shared().viewContext.delete(account)
                NosturState.shared.setAccount(account: accounts.first)
            }
            try DataProvider.shared().viewContext.save()
        }
        catch {
            print("🔴🔴🔴🔴🔴 Could not wipe or delete account 🔴🔴🔴🔴🔴")
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
        if account.lud06 != "" { setMetadataContent.lud06 = account.lud06 }
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
                
                // keep existing content if we have it. Should be ignored as per spec https://github.com/nostr-protocol/nips/blob/master/02.md
                // but some clients use it to store their garbage
                if let existingKind3 = Event.contactListEvents(byAuthorPubkey: account.publicKey, context: DataProvider.shared().viewContext)?.first {
                    newKind3Event.content = existingKind3.content ?? ""
                }
                
                for contact in (Array(account.follows ?? Set<Contact>()).filter { $0.privateFollow == false } ) {
                    newKind3Event.tags.append(NEventTag(type: "p", otherInformation: contact.pubkey ))
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
