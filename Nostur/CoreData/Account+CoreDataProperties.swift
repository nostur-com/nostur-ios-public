//
//  Account+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/01/2023.
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
    @NSManaged public var nip05: String
    @NSManaged public var picture: String
    @NSManaged public var banner: String
    @NSManaged public var publicKey: String?
    @NSManaged public var id: UUID?
    @NSManaged public var follows: Set<Contact>?
    @NSManaged public var bookmarks: Set<Event>?
    @NSManaged public var blockedContacts: Set<Contact>?
    
    @NSManaged public var likes: Set<Event>?
    @NSManaged public var reposts: Set<Event>?
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

// MARK: Generated accessors for blockedContacts
extension Account {

    @objc(addBlockedContactsObject:)
    @NSManaged public func addToBlockedContacts(_ value: Contact)

    @objc(removeBlockedContactsObject:)
    @NSManaged public func removeFromBlockedContacts(_ value: Contact)

    @objc(addBlockedContacts:)
    @NSManaged public func addToBlockedContacts(_ values: NSSet)

    @objc(removeBlockedContacts:)
    @NSManaged public func removeFromBlockedContacts(_ values: NSSet)

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

// MARK: Generated accessors for likes
extension Account {

    @objc(addLikesObject:)
    @NSManaged public func addToLikes(_ value: Event)

    @objc(removeLikeObject:)
    @NSManaged public func removeFromLikes(_ value: Event)

    @objc(addLikes:)
    @NSManaged public func addToLikes(_ values: NSSet)

    @objc(removeLikes:)
    @NSManaged public func removeFromLikes(_ values: NSSet)

}

// MARK: Generated accessors for reposts
extension Account {

    @objc(addRepostsObject:)
    @NSManaged public func addToReposts(_ value: Event)

    @objc(removeRepostObject:)
    @NSManaged public func removeFromReposts(_ value: Event)

    @objc(addReposts:)
    @NSManaged public func addToReposts(_ values: NSSet)

    @objc(removeReposts:)
    @NSManaged public func removeFromReposts(_ values: NSSet)

}

extension Account : Identifiable {

    var npub:String {
        get {
            publicKey != nil ? try! NIP19(prefix: "npub", hexString: publicKey!).displayString : "?"
        }
    }
    
    var privateKey:String? {
        get {
            guard self.publicKey != nil else { return nil }
            return AccountManager.shared.getPrivateKeyHex(pubkey: self.publicKey!)
        }
        set(privateKeyHex) {
            guard privateKeyHex != nil, self.publicKey != nil else {
                if (self.publicKey != nil) {
                    AccountManager.shared.deletePrivateKey(forPublicKeyHex: self.publicKey!)
                }
                return
            }
            if (self.publicKey != nil) { // TODO: Store public key based on private?
                AccountManager.shared.storePrivateKey(privateKeyHex: privateKeyHex!, forPublicKeyHex: self.publicKey!)
            }
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
    static func preFillReadOnlyAccountInfo(account:Account, context:NSManagedObjectContext) {
        
        guard let kind0 = Event.setMetaDataEvents(byAuthorPubkey: account.publicKey!, context: context)?.first else {
            return
        }
        
        let decoder = JSONDecoder()
        guard let metaData = try? decoder.decode(NSetMetadata.self, from: kind0.content!.data(using: .utf8, allowLossyConversion: false)!) else {
            return
        }

        if (account.privateKey == nil) { // Don't overwrite non-read-only accounts
            account.objectWillChange.send()
            account.display_name = metaData.display_name ?? ""
            account.name = metaData.name ?? ""
            account.about = metaData.about ?? ""
            account.picture = metaData.picture ?? ""
            account.banner = metaData.banner ?? ""
            account.nip05 = metaData.nip05 ?? ""
            account.lud16 = metaData.lud16 ?? ""
        }
    }
    
    // For when adding read only accounts, prefill with kind.0 info from relays (NEW EVENT FROM IMPORTER)
    static func preFillReadOnlyAccountInfo(event:NEvent, context:NSManagedObjectContext) {
        
        let decoder = JSONDecoder()
        guard let metaData = try? decoder.decode(NSetMetadata.self, from: event.content.data(using: .utf8, allowLossyConversion: false)!) else {
            return
        }
        
        let fr = Account.fetchRequest()
        fr.predicate = NSPredicate(format: "publicKey = %@", event.publicKey)
        if let account = try? context.fetch(fr).first {
            if (account.privateKey == nil) { // Don't overwrite non-read-only accounts
                account.objectWillChange.send()
                account.display_name = metaData.display_name ?? ""
                account.name = metaData.name ?? ""
                account.about = metaData.about ?? ""
                account.picture = metaData.picture ?? ""
                account.banner = metaData.banner ?? ""
                account.nip05 = metaData.nip05 ?? ""
                account.lud16 = metaData.lud16 ?? ""
            }
        }
    }
    
    // For when adding read only accounts, prefill with kind.3 info from relays (FROM CACHE)
    static func preFillReadOnlyAccountFollowing(account:Account, context:NSManagedObjectContext) {
        
        guard let kind3 = Event.contactListEvents(byAuthorPubkey: account.publicKey!, context: context)?.first else {
            return
        }
        
        let contacts = Contact.ensureContactsCreated(event: kind3.toNEvent(), context: context)
        
        // if read only account, import follows
        if (account.privateKey == nil && contacts.count > 0) {
//            account.objectWillChange.send()
            for contact in contacts {
                account.addToFollows(contact)
            }
        }
    }
    
    // For when adding read only accounts, prefill with kind.0 info from relays (NEW EVENT FROM IMPORTER)
    static func preFillReadOnlyAccountFollowing(event:NEvent, context:NSManagedObjectContext) {
        
        let fr = Account.fetchRequest()
        fr.predicate = NSPredicate(format: "publicKey == %@", event.publicKey)
        if let account = try? context.fetch(fr).first {
            
            let contacts = Contact.ensureContactsCreated(event: event, context: context)

            if (account.privateKey == nil && contacts.count > 0) {
                
                // Also prefetch all metadata
                let pubkeys = contacts.map { $0.pubkey! }
                SocketPool.shared.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkeys: pubkeys)))
                account.objectWillChange.send()
                for contact in contacts {
                    account.addToFollows(contact)
                }
            }
        }
    }
    
}
