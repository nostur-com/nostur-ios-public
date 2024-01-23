//
//  Contact+CoreDataClass.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/01/2023.
//
//

import Foundation
import CoreData
import Combine

public class Contact: NSManagedObject {

    var zapState: ZapState?
    
    func followsYou() -> Bool {
        guard let clEvent = clEvent else { return false }
        let account = if Thread.isMainThread {
            NRState.shared.loggedInAccount?.account
        }
        else {
            NRState.shared.loggedInAccount?.bgAccount
        }
        guard let account = account else { return false }
        return !clEvent.fastTags.filter { $0.0 == "p" && $0.1 == account.publicKey }.isEmpty
    }
    
    var isPrivateFollow:Bool { // Not saved in DB (derived from account() + privateFollowingPubkeys
        get {
            account()?.privateFollowingPubkeys.contains(pubkey) ?? false
        }
        set {
            if newValue {
                account()?.privateFollowingPubkeys.insert(pubkey)
            }
            else {
                account()?.privateFollowingPubkeys.remove(pubkey)
            }
            
        }
    }
}

public typealias ZapEtag = String

extension Contact {
    func bgContact() -> Contact? {
        if Thread.isMainThread {
            L.og.info("🔴🔴🔴 toBG() should be in bg already, switching now but should fix code")
            return bg().performAndWait {
                return bg().object(with: self.objectID) as? Contact
            }
        }
        else {
            return bg().object(with: self.objectID) as? Contact
        }
    }
}
