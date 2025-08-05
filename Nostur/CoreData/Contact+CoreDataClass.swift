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
    func followsYou() -> Bool {
        guard let clEvent = clEvent else { return false }
        guard let accountPubkey = AccountsState.shared.loggedInAccount?.pubkey else { return false }
        return !clEvent.fastTags.filter { $0.0 == "p" && $0.1 == accountPubkey }.isEmpty
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


func withContact(pubkey: String, completion: @escaping (Contact) -> Void) {
    #if DEBUG
    shouldBeBg()
    #endif
    if let contact = Contact.fetchByPubkey(pubkey, context: bg()) {
        completion(contact)
    }
}
