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
    @NSManaged public var display_name: String?
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

// MARK: Generated accessors for bookmarks
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
}
