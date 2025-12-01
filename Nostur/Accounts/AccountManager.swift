//
//  AccountManager.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/02/2023.
//

import Foundation
import KeychainAccess
import CoreData
import NostrEssentials

class AccountManager {
    
    static let shared = AccountManager()
    
    func generateAccount(name: String = "", about: String = "", context: NSManagedObjectContext) -> CloudAccount? {
        guard let newKeys = try? Keys.newKeys() else {
            L.og.error("🔴🔴 Could not generate keys 🔴🔴")
            return nil
        }
        storeKeys(newKeys)
        
        let account = CloudAccount(context: context)
        account.createdAt = Date()
        account.name = name
        account.about = about
        account.publicKey = newKeys.publicKeyHex
        account.flagsSet = ["nostur_created", "full_account"] // need this to know if we can enable to follow button, normally we wait after we received contact list
        
        DataProvider.shared().saveToDiskNow(.viewContext)
        return account
    }
    
    func getPrivateKeyHex(pubkey: String, account: CloudAccount? = nil) -> String? {
        let keychain = Keychain(service: "nostur.com.Nostur")
            .synchronizable(true)
        do {
            let privateKeyHex = try keychain
                .get(pubkey)
            return privateKeyHex
        }
        catch Status.itemNotFound {
            account?.noPrivateKey = true
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
    
    func storeKeys(_ keys: Keys) {
        let keychain = Keychain(service: "nostur.com.Nostur")
            .synchronizable(true)
        do {
            try keychain
                .accessibility(.afterFirstUnlock)
                .set(keys.privateKeyHex, key: keys.publicKeyHex)
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
            L.og.debug("💾💾💾💾 Saved to disk / iCloud 💾💾💾💾")
        }
        catch {
            L.og.error("🔴🔴🔴🔴🔴 Could not wipe or delete account 🔴🔴🔴🔴🔴")
        }
    }
    
    @MainActor func cleanUp(for logoutAccountPubkey: String) {
        guard !logoutAccountPubkey.isEmpty else { return }
        
        let context = viewContext()
        
        // Delete following feeds
        let fr = NSFetchRequest<NSFetchRequestResult>(entityName: "CloudFeed")
        fr.predicate = NSPredicate(format: "accountPubkey == %@ AND type == \"following\"")
        let frBatchDelete = NSBatchDeleteRequest(fetchRequest: fr)
        frBatchDelete.resultType = .resultTypeCount
        
        if let result = try? context.execute(frBatchDelete) as? NSBatchDeleteResult {
            if let count = result.result as? Int, count > 0 {
#if DEBUG
                L.og.debug("🧹🧹🧹🧹 Deleted \(count) CloudFeeds")
#endif
            }
        }

        // Delete DM states
        let fr2 = NSFetchRequest<NSFetchRequestResult>(entityName: "CloudDMState")
        fr2.predicate = NSPredicate(format: "accountPubkey_ == %@")
        let frBatchDelete2 = NSBatchDeleteRequest(fetchRequest: fr2)
        frBatchDelete2.resultType = .resultTypeCount
        
        if let result2 = try? context.execute(frBatchDelete2) as? NSBatchDeleteResult {
            if let count = result2.result as? Int, count > 0 {
#if DEBUG
                L.og.debug("🧹🧹🧹🧹 Deleted \(count) CloudDMStates")
#endif
            }
        }
        
        // Cloud Tasks
        let fr3 = NSFetchRequest<NSFetchRequestResult>(entityName: "CloudDMState")
        fr3.predicate = NSPredicate(format: "accountPubkey_ == %@")
        let frBatchDelete3 = NSBatchDeleteRequest(fetchRequest: fr3)
        frBatchDelete3.resultType = .resultTypeCount
        
        if let result3 = try? context.execute(frBatchDelete3) as? NSBatchDeleteResult {
            if let count = result3.result as? Int, count > 0 {
#if DEBUG
                L.og.debug("🧹🧹🧹🧹 Deleted \(count) CloudTasks")
#endif
            }
        }
        
        // Delete WoT cache
        let fileManager = FileManager.default
        let cachesDirectory = try! fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let txtFilename = cachesDirectory.appendingPathComponent("web-of-trust-\(logoutAccountPubkey).txt")
        
        if fileManager.fileExists(atPath: txtFilename.path) {
            // Migrate from .txt to .bin
            do {
                try fileManager.removeItem(at: txtFilename)
#if DEBUG
                L.og.debug("🧹🧹🧹🧹 Deleted WoT cache web-of-trust-\(logoutAccountPubkey).txt")
#endif
            } catch { }
        }
    }
    
    static func createUserMetadataEvent(account: CloudAccount) -> NEvent? {
        guard account.privateKey != nil else { return nil }
        
        // Create nostr .setMetadata event
        var setMetadataContent = NSetMetadata(name: account.name, about: account.about, picture: account.picture)
        if account.nip05 != "" { setMetadataContent.nip05 = account.nip05 }
        if account.lud16 != "" { setMetadataContent.lud16 = account.lud16 }
        if account.lud06 != "" { setMetadataContent.lud06 = account.lud06 }
        if account.banner != "" { setMetadataContent.banner = account.banner }

        return try? account.signEvent(NEvent(content: setMetadataContent))
    }
    
    // kind:10002 relay metadata for new first time user created in app
    static func createRelayListMetadataEvent(account: CloudAccount) -> NEvent? {
        return try? account.signEvent(NEvent(
            kind: .relayList,
            tags: [
                NostrTag(["r", "wss://nostr.wine", "read"]),
                NostrTag(["r", "wss://nos.lol"]),
                NostrTag(["r", "wss://relay.damus.io", "write"])
            ]
        ))
    }
    
    static func createContactListEvent(account: CloudAccount) -> NEvent? {
        guard let ctx = account.managedObjectContext else {
            L.og.error("🔴🔴 createContactListEvent: account does not have managedObjectContext")
            return nil
        }
        guard account.privateKey != nil else { return nil }
        
        var newKind3Event = NEvent(kind: .contactList)

        // keep existing content if we have it. Should be ignored as per spec https://github.com/nostr-protocol/nips/blob/master/02.md
        // but some clients use it to store their stuff
        if let existingKind3 = Event.contactListEvents(byAuthorPubkey: account.publicKey, context: ctx)?.first {
            newKind3Event.content = existingKind3.content ?? ""
        }
        
        // add contacts
        for pubkey in account.followingPubkeys {
            newKind3Event.tags.append(NostrTag(["p", pubkey]))
        }
        
        // add hashtags
        for tag in account.followingHashtags {
            newKind3Event.tags.append(NostrTag(["t", tag]))
        }
        
        if account.isNC {
            newKind3Event.publicKey = account.publicKey
            newKind3Event = newKind3Event.withId()
            return newKind3Event
        }
        else {
            return try? account.signEvent(newKind3Event)
        }
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
        let keys = try Keys(privateKeyHex: pk)
        
        var newKind0Event = NEvent(content: setMetadataContent)
        
        if account.isNC {
            newKind0Event.publicKey = account.publicKey
            newKind0Event = newKind0Event.withId()
            
            NSecBunkerManager.shared.requestSignature(forEvent: newKind0Event, usingAccount: account, whenSigned: { signedEvent in
                L.og.debug("Going to publish \(signedEvent.wrappedEventJson())")
                let bgContext = bg()
                bgContext.perform {
                    _ = Event.saveEvent(event: signedEvent, context: bgContext)
                    Contact.saveOrUpdateContact(event: signedEvent, context: bgContext)
                    DataProvider.shared().saveToDiskNow(.bgContext)
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
                Contact.saveOrUpdateContact(event: signedEvent, context: bgContext)
                DataProvider.shared().saveToDiskNow(.bgContext)
            }
            // broadcast to relays
            Unpublisher.shared.publishNow(signedEvent)
        }
    }
    catch {
        L.og.error("🔴🔴🔴🔴 Could not sign/save/broadcast event 🔴🔴🔴🔴")
    }
}
