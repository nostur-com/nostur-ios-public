//
//  ZapperPubkeyVerificationQueue.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/05/2023.
//

import Foundation
import Combine
import CoreData

class ZapperPubkeyVerificationQueue {
    
    static let shared = ZapperPubkeyVerificationQueue()
    
    private var ctx:NSManagedObjectContext
    private var queuedZaps = Set<Event>() // Contains events only from background context
    private var delayedRemove = PassthroughSubject<Event, Never>()
    private var subscriptions = Set<AnyCancellable>()
    
    init() {
        ctx = bg()
        delayedRemove
            .sink { [weak self] event in
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(25)) {
                    self?.ctx.perform {
                        self?.queuedZaps.remove(event)
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    public func addZap(_ zap:Event, debugInfo:String? = "") {
        if zap.managedObjectContext == ctx {
            ctx.perform { [unowned self] in
                self.queuedZaps.insert(zap)
                self.removeZap(zap) // will remove after 25 seconds
            }
        }
        else {
            ctx.perform { [unowned self] in
                guard let privateZap = self.ctx.object(with: zap.objectID) as? Event else { return }
                self.queuedZaps.insert(privateZap)
                self.removeZap(zap) // will remove after 25 seconds
            }
        }
    }
    
    public func removeZap(_ zap:Event) {
        // Don't remove immediatly, give a few extra seconds, maybe needs to fetch more than 1 relation
        self.delayedRemove.send(zap)
    }
    
    public func getQueuedZaps() -> Set<Event> {
        return self.queuedZaps
    }
    
    public func removeAll() {
        ctx.perform {
            self.queuedZaps = Set<Event>()
        }
    }
}
