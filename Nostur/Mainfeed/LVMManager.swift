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
    var listVMs:[LVM] = []
    
    var subscriptions:Set<AnyCancellable> = []
    
    init() {
        restoreSubscriptionsSubject
            .debounce(for: .seconds(0.2), scheduler: RunLoop.main)
            .throttle(for: .seconds(10.0), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.listVMs.forEach { lvm in
                    lvm.restoreSubscription()
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
    
    func followingLVM(forAccount account:Account) -> LVM {
        if let lvm = listVMs.first(where: { $0.pubkey == account.publicKey && $0.id == "Following" }) {
            return lvm
        }
        L.lvm.info("⭐️ New LVM for: \(account.publicKey) - \(account.name) - following: \(account.followingPublicKeys.count)")
        let lvm = LVM(type: .pubkeys, pubkey: account.publicKey, pubkeys: account.followingPublicKeys, listId: "Following", name: account.name)
        listVMs.append(lvm)
        return lvm
    }
    func exploreLVM() -> LVM {
        if let lvm = listVMs.first(where: { $0.id == "Explore" }) {
            return lvm
        }
        let lvm = LVM(type: .pubkeys, pubkeys: NosturState.shared.explorePubkeys, listId: "Explore", name: "Explore")
        listVMs.append(lvm)
        return lvm
    }
    func listLVM(forList list:NosturList) -> LVM {
        if let lvm = listVMs.first(where: { $0.id == list.subscriptionId }) {
            return lvm
        }
        let lvm = list.type == LVM.ListType.relays.rawValue
            ? LVM(type: .relays, pubkeys: [], listId: list.subscriptionId, name: list.name_, relays: list.relays_, wotEnabled: list.wotEnabled)
            : LVM(type: .pubkeys, pubkeys: Set(list.contacts_.map { $0.pubkey }), listId: list.subscriptionId, name: list.name_)
        
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
