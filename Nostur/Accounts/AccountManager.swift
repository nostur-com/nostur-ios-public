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
    
    func generateAccount(name:String = "", about:String = "", context: NSManagedObjectContext) -> CloudAccount {
        let newKeys = NKeys.newKeys()
        storeKeys(newKeys)
        
        let account = CloudAccount(context: context)
        account.createdAt = Date()
        account.name = name
        account.about = about
        account.publicKey = newKeys.publicKeyHex()
        account.flagsSet = ["nostur_created", "full_account"] // need this to know if we can enable to follow button, normally we wait after we received contact list
        
        try! context.save()
        return account
    }
    
    func getPrivateKeyHex(pubkey: String, account: CloudAccount) -> String? {
        let keychain = Keychain(service: "nostur.com.Nostur")
            .synchronizable(true)
        do {
            let privateKeyHex = try keychain
                .get(pubkey)
            return privateKeyHex
        }
        catch Status.itemNotFound {
            account.noPrivateKey = true
            return nil
        }
        catch {
            return nil
        }
    }
    
    func hasPrivateKey(pubkey:String) -> Bool {
        let keychain = Keychain(service: "nostur.com.Nostur")
            .synchronizable(true)
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
            .synchronizable(true)
        do {
            try keychain
                .accessibility(.afterFirstUnlock)
                .set(keys.privateKeyHex(), key: keys.publicKeyHex())
        } catch {
            L.og.error("🔴🔴🔴 could not store key in keychain")
        }
    }
    
    func storePrivateKey(privateKeyHex: String, forPublicKeyHex:String) {
        let keychain = Keychain(service: "nostur.com.Nostur")
            .synchronizable(true)
        do {
            try keychain
                .accessibility(.afterFirstUnlock)
                .set(privateKeyHex, key: forPublicKeyHex)
        } catch {
            L.og.error("🔴🔴🔴 could not store key in keychain")
        }
    }
    
    func deletePrivateKey(forPublicKeyHex: String) {
        let keychain = Keychain(service: "nostur.com.Nostur")
            .synchronizable(true)
        do {
            try keychain.remove(forPublicKeyHex)
        } catch {
            L.og.error("🔴🔴🔴 could not remove key from keychain")
        }
    }
    
    // Wipes kind 0 and 3, publishes wiped events. Deletes key from keychain, account from db
    @MainActor func wipeAccount(_ account: CloudAccount) {
        guard let pk = account.privateKey else { return }
    
        let metaData = NSetMetadata(name: "ACCOUNT_DELETED", display_name: "ACCOUNT_DELETED", about: "", picture: "", banner: "", nip05: "", lud16: "", lud06: "")

        // wipe kind 0
        var newKind0Event = NEvent(content: metaData)
        newKind0Event.kind = .setMetadata
        
        // wipe kind 3
        var newKind3Event = NEvent(content: "")
        newKind3Event.kind = .contactList

        do {
            if (account.picture.prefix(30) == "https://profilepics.nostur.com") || (account.banner.prefix(30) == "https://profilepics.nostur.com") {
//                print("Sending delete PFP and BANNER request")
                deletePFPandBanner(pk: pk, pubkey: account.publicKey)
            }
            
            if account.isNC {
                newKind0Event.publicKey = account.publicKey
                newKind0Event = newKind0Event.withId()
                NSecBunkerManager.shared.requestSignature(forEvent: newKind0Event, usingAccount: account, whenSigned: { signedEvent in
                    Unpublisher.shared.publishNow(signedEvent)
                })
                
                newKind3Event.publicKey = account.publicKey
                newKind3Event = newKind3Event.withId()
                NSecBunkerManager.shared.requestSignature(forEvent: newKind3Event, usingAccount: account, whenSigned: { signedEvent in
                    Unpublisher.shared.publishNow(signedEvent)
                })
            }
            else {
                let newKind0EventSigned = try account.signEvent(newKind0Event)
                let newKind3EventSigned = try account.signEvent(newKind3Event)
                
                Unpublisher.shared.publishNow(newKind0EventSigned)
                Unpublisher.shared.publishNow(newKind3EventSigned)
            }
            
            // delete key from keychain
            deletePrivateKey(forPublicKeyHex: account.publicKey)
            
            // delete account
            
            DataProvider.shared().viewContext.delete(account)
            try DataProvider.shared().viewContext.save()         
        }
        catch {
            L.og.error("🔴🔴🔴🔴🔴 Could not wipe or delete account 🔴🔴🔴🔴🔴")
        }
    }
    
    static func createMetadataEvent(account: CloudAccount) throws -> NEvent? {
        guard account.privateKey != nil else {
            throw "Account has no private key"
        }
        
        // create nostr .setMetadata event
        var setMetadataContent = NSetMetadata(name: account.name, about: account.about, picture: account.picture)
        if account.nip05 != "" { setMetadataContent.nip05 = account.nip05 }
        if account.lud16 != "" { setMetadataContent.lud16 = account.lud16 }
        if account.lud06 != "" { setMetadataContent.lud06 = account.lud06 }
        if account.banner != "" { setMetadataContent.banner = account.banner }
        
        if (account.privateKey != nil) {
            do {
                let keys = try NKeys(privateKeyHex: account.privateKey!)
                
                var newKind0Event = NEvent(content: setMetadataContent)
                
                let newKind0EventSigned = try newKind0Event.sign(keys)
                
//                print(newKind0EventSigned.eventJson())
//                print(newKind0EventSigned.wrappedEventJson())
                
                return newKind0EventSigned
            }
            catch {
                L.og.error("🔴🔴🔴🔴 Could not sign/save/broadcast event 🔴🔴🔴🔴")
                return nil
            }
        }
        return nil
    }
    
    static func createContactListEvent(account:CloudAccount) throws -> NEvent? {
        guard let ctx = account.managedObjectContext else {
            L.og.error("🔴🔴 createContactListEvent: account does not have managedObjectContext??")
            return nil
        }
        guard account.privateKey != nil else {
            throw "Account has no private key"
        }
        
        if (account.privateKey != nil) {
            do {
                let keys = try NKeys(privateKeyHex: account.privateKey!)
                
                var newKind3Event = NEvent(content: "")
                newKind3Event.kind = .contactList
                
                // keep existing content if we have it. Should be ignored as per spec https://github.com/nostr-protocol/nips/blob/master/02.md
                // but some clients use it to store their stuff
                if let existingKind3 = Event.contactListEvents(byAuthorPubkey: account.publicKey, context: ctx)?.first {
                    newKind3Event.content = existingKind3.content ?? ""
                }
                
                for pubkey in account.followingPubkeys {
                    newKind3Event.tags.append(NostrTag(["p", pubkey]))
                }
                
                for tag in account.followingHashtags {
                    newKind3Event.tags.append(NostrTag(["t", tag]))
                }
                
                if account.isNC {
                    newKind3Event.publicKey = account.publicKey
                    newKind3Event = newKind3Event.withId()
                    return newKind3Event
                }
                else {
                    let newKind3EventSigned = try newKind3Event.sign(keys)
                    
                    return newKind3EventSigned
                }
            }
            catch {
                L.og.error("🔴🔴🔴🔴 Could not sign/save/broadcast event 🔴🔴🔴🔴")
                return nil
            }
        }
        return nil
    }
}


func publishMetadataEvent(_ account: CloudAccount) throws {
    guard let pk = account.privateKey else {
        throw "Account has no private key"
    }
    
    // create nostr .setMetadata event
    var setMetadataContent = NSetMetadata(name: account.name, about: account.about, picture: account.picture)
    
    setMetadataContent.nip05 = account.nip05 != "" ? account.nip05 : nil
    setMetadataContent.lud16 = account.lud16 != "" ? account.lud16 : nil
    setMetadataContent.lud06 = account.lud06 != "" ? account.lud06 : nil
    setMetadataContent.banner = account.banner != "" ? account.banner : nil
    
    //        if account.display_name != "" { setMetadataContent.display_name = account.display_name }
    
    do {
        let keys = try NKeys(privateKeyHex: pk)
        
        var newKind0Event = NEvent(content: setMetadataContent)
        
        if account.isNC {
            newKind0Event.publicKey = account.publicKey
            newKind0Event = newKind0Event.withId()
            
            NSecBunkerManager.shared.requestSignature(forEvent: newKind0Event, usingAccount: account, whenSigned: { signedEvent in
                L.og.debug("Going to publish \(signedEvent.wrappedEventJson())")
                let bgContext = bg()
                bgContext.perform {
                    _ = Event.saveEvent(event: signedEvent, context: bgContext)
                    Contact.saveOrUpdateContact(event: signedEvent)
                    DataProvider.shared().bgSave()
                }
                // broadcast to relays
                Unpublisher.shared.publishNow(signedEvent)
            })
        }
        else {
            guard let signedEvent = try? newKind0Event.sign(keys) else {
                L.og.error("🔴🔴🔴🔴🔴 COULD NOT SIGN EVENT 🔴🔴🔴🔴🔴")
                return
            }
            L.og.debug("Going to publish \(signedEvent.wrappedEventJson())")
            let bgContext = bg()
            bgContext.perform {
                _ = Event.saveEvent(event: signedEvent, context: bgContext)
                Contact.saveOrUpdateContact(event: signedEvent)
                DataProvider.shared().bgSave()
            }
            // broadcast to relays
            Unpublisher.shared.publishNow(signedEvent)
        }
    }
    catch {
        L.og.error("🔴🔴🔴🔴 Could not sign/save/broadcast event 🔴🔴🔴🔴")
    }
}
