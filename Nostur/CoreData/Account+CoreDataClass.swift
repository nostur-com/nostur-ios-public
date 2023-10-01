//
//  Account+CoreDataClass.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/01/2023.
//
//

import Foundation
import CoreData

public class Account: NSManagedObject {

    var noPrivateKey = false
 
    public func getFollowingPFPs() -> [String: URL] {
        return Dictionary(grouping: follows_) { contact in
            contact.pubkey
        }
        .compactMapValues({ contacts in
            guard let picture = contacts.first?.picture else { return nil }
            guard picture.prefix(7) != "http://" else { return nil }
            return URL(string: picture)
        })
    }
    
    public func getFollowingPublicKeys() -> Set<String> {
        let withSelfIncluded = Set([publicKey] + (follows ?? Set<Contact>()).map { $0.pubkey })
        let withoutBlocked = withSelfIncluded.subtracting(Set(blockedPubkeys_))
        return withoutBlocked
    }
    
    public func getSilentFollows() -> Set<String> {
        return Set(follows_.filter { $0.privateFollow }.map { $0.pubkey })
    }
    
    public func publishNewContactList() {
        guard let clEvent = try? AccountManager.createContactListEvent(account: self)
        else {
            L.og.error("🔴🔴 Could not create new clEvent")
            return
        }
        if self.isNC {
            NSecBunkerManager.shared.requestSignature(forEvent: clEvent, usingAccount: self, whenSigned: { signedEvent in
                _ = Unpublisher.shared.publishLast(signedEvent, ofType: .contactList)
            })
        }
        else {
            _ = Unpublisher.shared.publishLast(clEvent, ofType: .contactList)
        }
    }
}
