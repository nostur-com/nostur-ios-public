//
//  Account+CoreDataClass.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/01/2023.
//
//

import Foundation
import CoreData

extension Account {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Account> {
        return NSFetchRequest<Account>(entityName: "Account")
    }

    @NSManaged public var about: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var name: String
    @NSManaged public var display_name: String
    @NSManaged public var lud16: String
    @NSManaged public var lud06: String
    @NSManaged public var nip05: String
    @NSManaged public var picture: String
    @NSManaged public var banner: String
    @NSManaged public var publicKey: String
    @NSManaged public var id: UUID?
    @NSManaged public var follows: Set<Contact>?
    var follows_:Set<Contact> {
        follows ?? Set<Contact>()
    }
    @NSManaged public var privateNotes: Set<PrivateNote>?
    @NSManaged public var bookmarks: Set<Event>?
    @NSManaged public var mutedRootIds: String? // Serialized
    @NSManaged public var blockedPubkeys: String? // Serialized
    @NSManaged public var lastNotificationReceivedAt: Date?
    @NSManaged public var lastProfileReceivedAt: Date?
    
    @NSManaged public var isNC: Bool
    @NSManaged public var ncRelay: String
    
    var followingPublicKeys:Set<String> {
        get {
            let withSelfIncluded = Set([publicKey] + (follows ?? Set<Contact>()).map { $0.pubkey })
            let withoutBlocked = withSelfIncluded.subtracting(Set(blockedPubkeys_))
            return withoutBlocked
        }
    }
    
    var silentFollows:Set<String> {
        Set(follows_.filter { $0.privateFollow }.map { $0.pubkey })
    }
    
    static func fetchAccount(publicKey:String, context:NSManagedObjectContext) throws -> Account? {
        let request = NSFetchRequest<Account>(entityName: "Account")
        request.predicate = NSPredicate(format: "publicKey == %@", publicKey)
        request.fetchLimit = 1
        request.fetchBatchSize = 1
        return try context.fetch(request).first
    }
}

// MARK: Generated accessors for follows
extension Account {

    @objc(addFollowsObject:)
    @NSManaged public func addToFollows(_ value: Contact)

    @objc(removeFollowsObject:)
    @NSManaged public func removeFromFollows(_ value: Contact)

    @objc(addFollows:)
    @NSManaged public func addToFollows(_ values: NSSet)

    @objc(removeFollows:)
    @NSManaged public func removeFromFollows(_ values: NSSet)

}

// MARK: Generated accessors for bookmarks
extension Account {

    @objc(addBookmarksObject:)
    @NSManaged public func addToBookmarks(_ value: Event)

    @objc(removeBookmarksObject:)
    @NSManaged public func removeFromBookmarks(_ value: Event)

    @objc(addBookmarks:)
    @NSManaged public func addToBookmarks(_ values: NSSet)

    @objc(removeBookmarks:)
    @NSManaged public func removeFromBookmarks(_ values: NSSet)

}

// MARK: Generated accessors for private notes
extension Account {

    @objc(addPrivateNotesObject:)
    @NSManaged public func addToPrivateNotes(_ value: Event)

    @objc(removePrivateNotesObject:)
    @NSManaged public func removeFromPrivateNotes(_ value: Event)

    @objc(addPrivateNotes:)
    @NSManaged public func addToPrivateNotes(_ values: NSSet)

    @objc(removePrivateNotes:)
    @NSManaged public func removeFromPrivateNotes(_ values: NSSet)

    var privateNotes_:Set<PrivateNote> {
        get {
            guard privateNotes != nil else { return [] }
            return Set(privateNotes!)
        }
    }
}

extension Account : Identifiable {

    var npub:String { try! NIP19(prefix: "npub", hexString: publicKey).displayString }
    
    var privateKey:String? {
        get {
            if isNC {
                return NIP46SecretManager.shared.getSecret(account: self)
            }
            return AccountManager.shared.getPrivateKeyHex(pubkey: self.publicKey)
        }
        set(privateKeyHex) {
            guard privateKeyHex != nil else {
                AccountManager.shared.deletePrivateKey(forPublicKeyHex: self.publicKey)
                return
            }
            AccountManager.shared.storePrivateKey(privateKeyHex: privateKeyHex!, forPublicKeyHex: self.publicKey)
        }
    }
    
    var nsec:String? {
        get {
            guard self.privateKey != nil else { return nil }
            guard let nsec = try? NIP19(prefix: "nsec", hexString: self.privateKey!).displayString else {
                return nil
            }
            return nsec
        }
    }
    
    
    // For when adding read only accounts, prefill with kind.0 info from relays (FROM CACHE)
    static func preFillReadOnlyAccountInfo(account:Account, context:NSManagedObjectContext, forceOverwrite:Bool = false) {
        
        guard let kind0 = Event.setMetaDataEvents(byAuthorPubkey: account.publicKey, context: context)?.first else {
            return
        }
        
        let decoder = JSONDecoder()
        guard let metaData = try? decoder.decode(NSetMetadata.self, from: kind0.content!.data(using: .utf8, allowLossyConversion: false)!) else {
            return
        }

        if (account.privateKey == nil || forceOverwrite) { // Don't overwrite non-read-only accounts
            account.objectWillChange.send()
//            account.display_name = metaData.display_name ?? ""
            account.name = metaData.name ?? ""
            account.about = metaData.about ?? ""
            account.picture = metaData.picture ?? ""
            account.banner = metaData.banner ?? ""
            account.nip05 = metaData.nip05 ?? ""
            account.lud16 = metaData.lud16 ?? ""
            account.lud06 = metaData.lud06 ?? ""
        }
    }
    
    // For when adding read only accounts, prefill with kind.0 info from relays (NEW EVENT FROM IMPORTER)
    static func preFillReadOnlyAccountInfo(event:NEvent, context:NSManagedObjectContext, forceOverwrite:Bool = false) {
        
        let decoder = JSONDecoder()
        guard let metaData = try? decoder.decode(NSetMetadata.self, from: event.content.data(using: .utf8, allowLossyConversion: false)!) else {
            return
        }
        
        let fr = Account.fetchRequest()
        fr.predicate = NSPredicate(format: "publicKey = %@", event.publicKey)
        if let account = try? context.fetch(fr).first {
            if (account.privateKey == nil || forceOverwrite == true) { // Don't overwrite non-read-only accounts
                account.objectWillChange.send()
//                account.display_name = metaData.display_name ?? ""
                account.name = metaData.name ?? ""
                account.about = metaData.about ?? ""
                account.picture = metaData.picture ?? ""
                account.banner = metaData.banner ?? ""
                account.nip05 = metaData.nip05 ?? ""
                account.lud16 = metaData.lud16 ?? ""
                account.lud06 = metaData.lud06 ?? ""
            }
        }
    }
    
    // For when adding read only accounts, prefill with kind.3 info from relays (FROM CACHE)
    static func preFillReadOnlyAccountFollowing(account:Account, context:NSManagedObjectContext) {
        
        guard let kind3 = Event.contactListEvents(byAuthorPubkey: account.publicKey, context: context)?.first else {
            return
        }
        
        let contacts = Contact.ensureContactsCreated(event: kind3.toNEvent(), context: context, limit:999)
        
        // if read only account, import follows. Or pendingFirstContactsFetch
        if (!contacts.isEmpty) {
//            account.objectWillChange.send()
            for contact in contacts {
                account.addToFollows(contact)
            }
        }
    }
    
    var mutedRootIds_:[String] {
        get {
            guard mutedRootIds != nil else { return [] }
            let decoder = JSONDecoder()
            guard let ids = try? decoder.decode([String].self, from: Data(mutedRootIds!.utf8)) else { return [] }
            return ids
        }
        set {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            if let idsSerialized = try? encoder.encode(newValue) {
                objectWillChange.send()
                mutedRootIds = String(data: idsSerialized, encoding: .utf8)
            }
        }
    }
    
    var blockedPubkeys_:[String] {
        get {
            guard blockedPubkeys != nil else { return [] }
            let decoder = JSONDecoder()
            guard let ids = try? decoder.decode([String].self, from: Data(blockedPubkeys!.utf8)) else { return [] }
            return ids
        }
        set {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            if let idsSerialized = try? encoder.encode(newValue) {
                objectWillChange.send()
                blockedPubkeys = String(data: idsSerialized, encoding: .utf8)
            }
        }
    }
    
    func toBG() -> Account? {
        DataProvider.shared().bg.object(with: self.objectID) as? Account
    }
}
