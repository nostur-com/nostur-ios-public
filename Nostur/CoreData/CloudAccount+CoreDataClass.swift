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
        var cache = Dictionary(grouping: follows) { contact in
            contact.pubkey
        }
        .compactMapValues({ contacts -> FollowCache? in
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
        
        // Always include entries for all accounts in AccountsState.accounts
        let missingAccountPubkeys = AccountsState.shared.bgAccountPubkeys.subtracting(cache.keys)
        if !missingAccountPubkeys.isEmpty {
            let bgContext = bg()
            let bgAccounts = CloudAccount.fetchAccounts(context: bgContext).filter { missingAccountPubkeys.contains($0.publicKey) }
            for bgAccount in bgAccounts {
                let pfpURL: URL? = if let picture = bgAccount.picture_, picture.prefix(7) != "http://" {
                    URL(string: picture)
                }
                else {
                    nil
                }
                cache[bgAccount.publicKey] = FollowCache(
                    anyName: bgAccount.anyName,
                    pfpURL: pfpURL,
                    bgContact: nil)
            }
            // For accounts with no CloudAccount record yet, add a minimal entry using the pubkey
            let foundPubkeys = Set(bgAccounts.map { $0.publicKey })
            for pubkey in missingAccountPubkeys.subtracting(foundPubkeys) {
                cache[pubkey] = FollowCache(anyName: pubkey, pfpURL: nil, bgContact: nil)
            }
        }
        
        return cache
    }
    
    public func getFollowingPublicKeys(includeBlocked: Bool = false) -> Set<String> {
        let withSelfIncluded = Set([publicKey]).union(followingPubkeys)
        if includeBlocked {
            return withSelfIncluded
        }
        let withoutBlocked = withSelfIncluded.subtracting(AppState.shared.bgAppState.blockedPubkeys)
        return withoutBlocked
    }
    
    public func publishNewContactList(_ safeMode: Bool = false) {
        guard var clEvent: NEvent = AccountManager.createContactListEvent(account: self)
        else {
            L.og.error("🔴🔴 Could not create new clEvent")
            return
        }
        
        if safeMode {
            clEvent.createdAt = NTimestamp(timestamp: Int((Date().timeIntervalSince1970 - (604800))))
        }
        
        if self.isNC {
            RemoteSignerManager.shared.requestSignature(forEvent: clEvent, usingAccount: self, whenSigned: { signedEvent in
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
    
    lazy var npub: String = { try! NIP19(prefix: "npub", hexString: publicKey).displayString }()
}
