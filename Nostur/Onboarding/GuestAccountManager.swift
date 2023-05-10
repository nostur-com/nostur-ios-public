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
    
    public func createGuestAccount() {
        guard (try? Account.fetchAccount(publicKey: NosturState.GUEST_ACCOUNT_PUBKEY, context: context)) == nil else { return }
        context.performAndWait {
            let account = Account(context: context)
            account.id = UUID()
            account.createdAt = Date()
            account.createdAt = Date()
            account.display_name = "Nostur Rookie"
            account.name = "NosturRookie"
            account.about = "Just trying things out"
            account.publicKey = NosturState.GUEST_ACCOUNT_PUBKEY
            try! context.save()
        }
    }
}
