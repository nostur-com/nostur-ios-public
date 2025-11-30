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

class GiftWrapsManager: ObservableObject {
    
    private var lastLocalGiftWrapTimestampAt: Int {
        get { UserDefaults.standard.integer(forKey: "last_local_giftwrap_timestamp") }
        set { UserDefaults.standard.setValue(newValue, forKey: "last_local_giftwrap_timestamp") }
    }
    
    private var accountPubkey: String
    private var didLoad = false
       
    private var subscriptions = Set<AnyCancellable>()
    
    init(accountPubkey: String) {
        self.accountPubkey = accountPubkey
    }

    public func load() {


        didLoad = true
    }
     
    public func processGiftWrap(_ event: Event) {
        // Should already be kind 1059 here, with our acountPubkey as recipient (p tag)
        guard event.pTags().contains(where: { $0 == self.accountPubkey }) else { return }
        
        // Decrypt the seal
        
    }
    
    private func monthsAgoRange(_ months:Int) -> (since: Int, until: Int) {
        return (
            since: NTimestamp(date: Date().addingTimeInterval(Double(months + 1) * -2_592_000)).timestamp,
            until: NTimestamp(date: Date().addingTimeInterval(Double(months) * -2_592_000)).timestamp
        )
    }
    
    @Published var scanningMonthsAgo = 0
    
    public func rescanForMissingDMs(_ monthsAgo: Int) {
        guard scanningMonthsAgo == 0 else { return }
        
        for i in 0...monthsAgo {
            let ago = monthsAgoRange(monthsAgo - i)
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(5 * i)) { [weak self] in
                guard let self else { return }
                self.scanningMonthsAgo = i+1 == (monthsAgo + 1) ? 0 : i+1
                
                if let message = CM(
                    type: .REQ,
                    filters: [
                        Filters(kinds: [1059], tagFilter: TagFilter(tag: "p", values: [accountPubkey]), since: ago.since, until: ago.until)
                    ]
                ).json() {
                    req(message)
                }
            }
        }
    }
}
