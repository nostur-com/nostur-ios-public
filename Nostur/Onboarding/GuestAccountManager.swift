//
//  GuestAccountManager.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/05/2023.
//

import Foundation

class GuestAccountManager {
    static let shared = GuestAccountManager()
    
    private var context = DataProvider.shared().viewContext
    
    public func createGuestAccount() -> CloudAccount {
        if let account = try? CloudAccount.fetchAccount(publicKey: GUEST_ACCOUNT_PUBKEY, context: context) {
            return account
        }
        return context.performAndWait {
            let account = CloudAccount(context: context)
            account.createdAt = Date()
            account.createdAt = Date()
//            account.display_name = "Nostur Rookie"
            account.name = "Guest Account"
            account.about = "Just trying things out"
            account.publicKey = GUEST_ACCOUNT_PUBKEY
            try! context.save()
            return account
        }
    }
}
