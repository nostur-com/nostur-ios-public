//
//  LVMManager.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/04/2023.
//

import Foundation
import Combine

class LVMManager {
    static let shared = LVMManager()
    var listVMs: [LVM] = []
    
    var subscriptions: Set<AnyCancellable> = []
    
    init() {
        restoreSubscriptionsSubject
            .debounce(for: .seconds(0.2), scheduler: RunLoop.main)
            .throttle(for: .seconds(10.0), scheduler: RunLoop.main, latest: false)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.listVMs.forEach { lvm in
                    Task { @MainActor in
                        lvm.restoreSubscription()
                    }
                }
            }
            .store(in: &subscriptions)
        
        stopSubscriptionsSubject
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.listVMs.forEach { lvm in
                    lvm.stopSubscription()
                }
            }
            .store(in: &subscriptions)
    }
    
    func followingLVM(forAccount account: CloudAccount, isDeck: Bool = false) -> LVM {
        if let lvm = listVMs.first(where: { $0.pubkey == account.publicKey && $0.id == "Following" }) {
            return lvm
        }
        L.lvm.info("⭐️ New LVM for: \(account.publicKey) - \(account.name) - following: \(account.getFollowingPublicKeys(includeBlocked: false).count)")
        let lvm = LVM(type: .pubkeys, pubkey: account.publicKey, pubkeys: account.getFollowingPublicKeys(includeBlocked: false), listId: "Following", name: account.name, isDeck: isDeck)
        listVMs.append(lvm)
        return lvm
    }
    func exploreLVM(isDeck: Bool = false) -> LVM {
        if let lvm = listVMs.first(where: { $0.id == "Explore" }) {
            return lvm
        }
        
        let explorePubkeys: Set<String> =
            if let account = NRState.shared.loggedInAccount?.account {
                Set([account.publicKey] + NRState.shared.rawExplorePubkeys).subtracting(NRState.shared.blockedPubkeys)
            }
            else {
                NRState.shared.rawExplorePubkeys
            }
        
        let lvm = LVM(type: .pubkeys, pubkeys: explorePubkeys, listId: "Explore", name: "Explore", isDeck: isDeck)
        listVMs.append(lvm)
        return lvm
    }
    func listLVM(forList list: CloudFeed, isDeck: Bool = false) -> LVM {
        if let lvm = listVMs.first(where: { $0.id == list.subscriptionId }) {
            return lvm
        }
        let lvm = list.type == LVM.ListType.relays.rawValue
        ? LVM(type: .relays, pubkeys: [], listId: list.subscriptionId, name: list.name_, relays: list.relays_, wotEnabled: list.wotEnabled, isDeck: isDeck)
        : LVM(type: .pubkeys, pubkeys: Set((list.pubkeys ?? "").components(separatedBy: " ")), listId: list.subscriptionId, name: list.name_, isDeck: isDeck)
        
        listVMs.append(lvm)
        return lvm
    }
    
    var restoreSubscriptionsSubject = PassthroughSubject<Void, Never>()
    var stopSubscriptionsSubject = PassthroughSubject<Void, Never>()
    
    func restoreSubscriptions() {
        restoreSubscriptionsSubject.send()
    }
    func stopSubscriptions() {
        stopSubscriptionsSubject.send()
    }
}
