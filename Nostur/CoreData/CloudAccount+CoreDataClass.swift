//
//  CloudAccount+CoreDataClass.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/11/2023.
//
//

import Foundation
import CoreData

@objc(CloudAccount)
public class CloudAccount: NSManagedObject {
    var noPrivateKey = false
 
    public func getFollowingPFPs() -> [String: URL] {
        return Dictionary(grouping: follows) { contact in
            contact.pubkey
        }
        .compactMapValues({ contacts in
            guard let picture = contacts.first?.picture else { return nil }
            guard picture.prefix(7) != "http://" else { return nil }
            return URL(string: picture)
        })
    }
    
    public func getFollowingPublicKeys(includeBlocked:Bool = false) -> Set<String> {
        let withSelfIncluded = Set([publicKey]).union(followingPubkeys)
        if includeBlocked {
            return withSelfIncluded
        }
        let withoutBlocked = withSelfIncluded.subtracting(NRState.shared.blockedPubkeys)
        return withoutBlocked
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
