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
 
    public func loadFollowingCache() -> [String: FollowCache] {
        return Dictionary(grouping: follows) { contact in
            contact.pubkey
        }
        .compactMapValues({ contacts in
            guard let contact = contacts.first else { return nil }
            let pfpURL: URL? = if let picture = contact.picture, picture.prefix(7) != "http://" {
                URL(string: picture)
            }
            else {
                nil
            }
            return FollowCache(
                anyName: contact.anyName,
                pfpURL: pfpURL,
                bgContact: contact)
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
    
    public func publishNewContactList(_ safeMode: Bool = false) {
        guard var clEvent = try? AccountManager.createContactListEvent(account: self)
        else {
            L.og.error("🔴🔴 Could not create new clEvent")
            return
        }
        
        if safeMode {
            clEvent.createdAt = NTimestamp(timestamp: Int((Date().timeIntervalSince1970 - (3600*24*7))))
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
    
    // Cache because:  20.00 ms    0.1%    10.00 ms                 CloudAccount.privateFollowingPubkeys.getter
    var followingPubkeysCache: Set<String> = []
    var privateFollowingPubkeysCache: Set<String> = []
}
