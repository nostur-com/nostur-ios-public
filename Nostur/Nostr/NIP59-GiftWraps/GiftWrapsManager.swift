//
//  GiftWrapsManager.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/11/2025.
//

import Foundation

import SwiftUI
import NostrEssentials
import Combine

// Partial Copy Paste from DMsVM
class GiftWrapsManager: ObservableObject {
    
    private var lastLocalGiftWrapTimestampAt: Int {
        get { UserDefaults.standard.integer(forKey: "last_local_giftwrap_timestamp") }
        set { UserDefaults.standard.setValue(newValue, forKey: "last_local_giftwrap_timestamp") }
    }
    
    private var accountPubkey: String
    @Published var ready = false
    @Published var ncNotSupported = false
       
    private var subscriptions = Set<AnyCancellable>()
    
    init(accountPubkey: String? = nil) {
        self.accountPubkey = accountPubkey ?? AccountsState.shared.activeAccountPublicKey
    }

    @MainActor
    public func load(force: Bool = false) async {
        guard force || !ready else { return }
        
        if let account = AccountsState.shared.accounts.first(where: { $0.publicKey == self.accountPubkey }) {
            ncNotSupported = account.isNC
        }
        
        if ncNotSupported {
            
            return
        }

        ready = true
        
        // 10050 is already fetched from DMsVM.shared so no need here
        // fetch since last timestamp minus 48 hours ago
        self.fetchGiftWraps()
    }
    
    private func fetchGiftWraps() {
        DMsVM.shared.fetchGiftWraps()
    }
    
    private var accountChangedSubscription: AnyCancellable?
    
    private func setupAccountChangedListener() {
        guard accountChangedSubscription == nil else { return }
        accountChangedSubscription = receiveNotification(.activeAccountChanged)
            .sink { [weak self] notification in
                Task { @MainActor in
                    let account = notification.object as! CloudAccount
                    await self?.reload(accountPubkey: account.publicKey)
                }
            }
    }
    
    @MainActor
    public func reload(accountPubkey: String) async {
        self.accountPubkey = accountPubkey
        await self.load(force: true)
    }

}
