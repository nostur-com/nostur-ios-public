//
//  GuestAccountManager.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/05/2023.
//

import Foundation
import CoreData

class GuestAccountManager {
    static let shared = GuestAccountManager()
    
    public func createGuestAccount(context: NSManagedObjectContext = context()) -> CloudAccount {
        if let account = try? CloudAccount.fetchAccount(publicKey: GUEST_ACCOUNT_PUBKEY, context: context) {
            return account
        }
        
        let account = CloudAccount(context: context)
        account.createdAt = Date()
        account.createdAt = Date()
        account.name = "Guest Account"
        account.about = "Just trying things out"
        account.publicKey = GUEST_ACCOUNT_PUBKEY
        
        return account
    }
}
