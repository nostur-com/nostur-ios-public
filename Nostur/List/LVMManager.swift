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
            .sink { [weak self] _ in
                guard let self = self else { return }
                
                self.listVMs.forEach { lvm in
                    lvm.restoreSubscription()
                }
            }
            .store(in: &subscriptions)
        
        
        receiveNotification(.activeAccountChanged)
            .sink { [weak self] notification in
                guard let self = self else { return }
                guard let account = notification.object as? Account else { return }
                self.listVMs.removeAll(where: { $0.pubkey != account.publicKey })
            }
            .store(in: &subscriptions)
        
//        receiveNotification(.followersChanged)
//            .sink { notification in
//                guard let account = notification.object as? Account else { return }
//                self.listVMs.removeAll(where: { $0.pubkey == account.publicKey })
//            }
//            .store(in: &subscriptions)
    }
    
    func followingLVM(forAccount account:Account) -> LVM {
        if let lvm = listVMs.first(where: { $0.pubkey == account.publicKey && $0.listId == "Following" }) {
            return lvm
        }
        let lvm = LVM(pubkey: account.publicKey, pubkeys: account.followingPublicKeys, listId: "Following")
        listVMs.append(lvm)
        return lvm
    }
    func exploreLVM(forAccount account:Account) -> LVM {
        if let lvm = listVMs.first(where: { $0.pubkey == account.publicKey && $0.listId == "Explore" }) {
            return lvm
        }
        let lvm = LVM(pubkey: account.publicKey, pubkeys: NosturState.shared.explorePubkeys, listId: "Explore")
        listVMs.append(lvm)
        return lvm
    }
    func listLVM(forAccount account:Account, andList list:NosturList) -> LVM {
        if let lvm = listVMs.first(where: { $0.pubkey == account.publicKey && $0.subscriptionId == list.subscriptionId }) {
            return lvm
        }
        let lvm = LVM(pubkey: account.publicKey, pubkeys: Set(list.contacts_.map { $0.pubkey }), listId: list.subscriptionId)
        listVMs.append(lvm)
        return lvm
    }
    
    var restoreSubscriptionsSubject = PassthroughSubject<Void, Never>()
    
    func restoreSubscriptions() {
        restoreSubscriptionsSubject.send()
    }
}
