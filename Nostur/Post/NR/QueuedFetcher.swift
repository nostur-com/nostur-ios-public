//
//  QueuedFetcher.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/05/2023.
//

import Foundation
import Combine

class QueuedFetcher {
    static let shared = QueuedFetcher()
    
    var subscriptions = Set<AnyCancellable>()
    
    var pQueue = Set<String>()
    var idQueue = Set<String>()
    
    // TODO: finish recent cache - add recently tried queue, to not retry the same over and over..
    var recentPs = Set<String>()
    var recentIds = Set<String>()
    
    private var fetchSubject = PassthroughSubject<Void, Never>()
    private var enqueuePsubject = PassthroughSubject<String, Never>()
    private var dequeuePsubject = PassthroughSubject<String, Never>()
    private var enqueueIDsubject = PassthroughSubject<String, Never>()
    private var dequeueIDsubject = PassthroughSubject<String, Never>()
    private var ctx = bg()
    
    
    init() {
        enqueuePsubject.sink { [weak self] pTag in
            self?.pQueue.insert(pTag)
        }
        .store(in: &subscriptions)
        
        dequeuePsubject.sink { [weak self] pTag in
            self?.pQueue.remove(pTag)
        }
        .store(in: &subscriptions)
        
        enqueueIDsubject.sink { [weak self] eventId in
            self?.idQueue.insert(eventId)
        }
        .store(in: &subscriptions)
        
        dequeueIDsubject.sink { [weak self] eventId in
            self?.idQueue.remove(eventId)
        }
        .store(in: &subscriptions)
        
        fetchSubject
            .debounce(for: .seconds(0.05), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.ctx.perform {
                    guard let self else { return }
                    guard !self.pQueue.isEmpty || !self.idQueue.isEmpty else { return }
                    
                    if self.idQueue.isEmpty {
                        req(RM.getUserMetadata(pubkeys: Array(self.pQueue)))
                        self.pQueue.removeAll()
                    }
                    else if self.pQueue.isEmpty {
                        req(RM.getEvents(ids: Array(self.idQueue)))
                        self.idQueue.removeAll()
                    }
                    else {
                        // TODO COMBINE IN SINGLE REQUEST:
                        req(RM.getUserMetadata(pubkeys: Array(self.pQueue)))
                        req(RM.getEvents(ids: Array(self.idQueue)))
                        self.pQueue.removeAll()
                        self.idQueue.removeAll()
                    }
                }
        }
        .store(in: &subscriptions)
    }
    
    public func enqueue(pTag: String) {
        ctx.perform { [weak self] in
            self?.enqueuePsubject.send(pTag)
            self?.fetch()
        }
    }
    
    public func enqueue(pTags: [String]) {
        ctx.perform { [weak self] in
            guard !pTags.isEmpty else { return }
            pTags.forEach { pTag in
                self?.enqueuePsubject.send(pTag)
            }
            self?.fetch()
        }
    }
    
    public func enqueue(pTags: Set<String>) {
        guard !pTags.isEmpty else { return }
        ctx.perform { [weak self] in
            pTags.forEach { pTag in
                self?.enqueuePsubject.send(pTag)
            }
            self?.fetch()
        }
    }
    
    public func dequeue(pTag: String) {
        ctx.perform { [weak self] in
            self?.dequeuePsubject.send(pTag)
        }
    }
    
    public func dequeue(pTags: [String]) {
        ctx.perform { [weak self] in
            pTags.forEach { pTag in
                self?.dequeuePsubject.send(pTag)
            }
        }
    }
    
    public func dequeue(pTags: Set<String>) {
        ctx.perform { [weak self] in
            pTags.forEach { pTag in
                self?.dequeuePsubject.send(pTag)
            }
        }
    }
    
    public func enqueue(id: String) {
        ctx.perform { [weak self] in
            self?.enqueueIDsubject.send(id)
            self?.fetch()
        }
    }
    
    public func enqueue(ids: [String]) {
        guard !ids.isEmpty else { return }
        ctx.perform { [weak self] in
            ids.forEach { id in
                self?.enqueuePsubject.send(id)
            }
            self?.fetch()
        }
    }
    
    public func dequeue(id: String) {
        ctx.perform { [weak self] in
            self?.dequeueIDsubject.send(id)
        }
    }
    
    public func dequeue(ids: [String]) {
        ctx.perform { [weak self] in
            ids.forEach { id in
                self?.dequeueIDsubject.send(id)
            }
        }
    }
    
    private func fetch() {
        fetchSubject.send()
    }
}
