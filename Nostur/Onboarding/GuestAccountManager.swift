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
    
    public func createGuestAccount() -> Account {
        if let account = try? Account.fetchAccount(publicKey: NosturState.GUEST_ACCOUNT_PUBKEY, context: context) {
            return account
        }
        return context.performAndWait {
            let account = Account(context: context)
            account.id = UUID()
            account.createdAt = Date()
            account.createdAt = Date()
//            account.display_name = "Nostur Rookie"
            account.name = "Nostur Guest Account"
            account.about = "Just trying things out"
            account.publicKey = NosturState.GUEST_ACCOUNT_PUBKEY
            try! context.save()
            NosturState.shared.loadAccounts()
            return account
        }
    }
}
